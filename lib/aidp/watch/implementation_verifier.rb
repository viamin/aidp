# frozen_string_literal: true

require "open3"
require_relative "../harness/ai_decision_engine"
require_relative "../message_display"

module Aidp
  module Watch
    # Verifies that implementation fully addresses issue requirements using ZFC
    # before allowing PR creation in watch mode build workflow
    class ImplementationVerifier
      include Aidp::MessageDisplay

      def initialize(repository_client:, project_dir:, ai_decision_engine: nil)
        @repository_client = repository_client
        @project_dir = project_dir
        @ai_decision_engine = ai_decision_engine || build_default_ai_decision_engine
      end

      # Verify implementation against issue requirements
      # Returns: { verified: true/false, reason: String, missing_items: Array }
      #
      # FIX for issue #391: Enhanced verification to require substantive code changes
      # Rejects implementations that only contain documentation changes
      def verify(issue:, working_dir:)
        Aidp.log_debug("implementation_verifier", "starting_verification", issue: issue[:number], working_dir: working_dir)

        display_message("🔍 Verifying implementation completeness...", type: :info)

        # Gather verification inputs
        issue_requirements = extract_issue_requirements(issue)
        implementation_changes = extract_implementation_changes(working_dir)

        # FIX for issue #391: Check for substantive changes before ZFC verification
        substantive_check = verify_substantive_changes(implementation_changes, working_dir)
        unless substantive_check[:has_substantive_changes]
          Aidp.log_warn(
            "implementation_verifier",
            "no_substantive_changes",
            issue: issue[:number],
            reason: substantive_check[:reason]
          )

          return {
            verified: false,
            reason: substantive_check[:reason],
            missing_items: ["Substantive code changes required - only documentation/config changes detected"],
            additional_work: ["Implement the actual code changes described in the issue"]
          }
        end

        # Use ZFC to verify completeness
        result = perform_zfc_verification(
          issue_number: issue[:number],
          issue_requirements: issue_requirements,
          implementation_changes: implementation_changes
        )

        Aidp.log_info(
          "implementation_verifier",
          "verification_complete",
          issue: issue[:number],
          verified: result[:verified],
          reason: result[:reason]
        )

        result
      end

      private

      def extract_issue_requirements(issue)
        # Collect full issue context including comments for plan
        requirements = {
          title: issue[:title],
          body: issue[:body] || "",
          comments: []
        }

        # Extract relevant comments (include plan comments and user responses)
        issue[:comments]&.each do |comment|
          requirements[:comments] << {
            author: comment["author"] || comment[:author],
            body: comment["body"] || comment[:body],
            created_at: comment["createdAt"] || comment[:createdAt]
          }
        end

        requirements
      end

      def extract_implementation_changes(working_dir)
        Dir.chdir(working_dir) do
          # Get the base branch to compare against
          base_branch = detect_base_branch

          # Get diff from base branch
          diff_output, _stderr, status = Open3.capture3("git", "diff", "#{base_branch}...HEAD")

          unless status.success?
            Aidp.log_warn("implementation_verifier", "git_diff_failed", working_dir: working_dir)
            return {
              diff: "",
              files_changed: "Unable to extract changes: git diff failed"
            }
          end

          # Get list of changed files with stats
          files_output, _stderr, files_status = Open3.capture3("git", "diff", "--stat", "#{base_branch}...HEAD")

          changes = {
            diff: diff_output,
            files_changed: files_status.success? ? files_output : "Unable to get file list"
          }

          Aidp.log_debug(
            "implementation_verifier",
            "extracted_changes",
            working_dir: working_dir,
            base_branch: base_branch,
            diff_size: diff_output.bytesize,
            files_changed_count: files_output.lines.count
          )

          changes
        end
      rescue => e
        Aidp.log_error("implementation_verifier", "extract_changes_failed", error: e.message, working_dir: working_dir)
        {error: "Failed to extract changes: #{e.message}"}
      end

      def detect_base_branch
        stdout, _stderr, status = Open3.capture3("git", "symbolic-ref", "refs/remotes/origin/HEAD")
        if status.success?
          ref = stdout.strip
          return ref.split("/").last if ref.include?("/")
        end

        # Fallback to common branch names
        %w[main master trunk].find do |candidate|
          _out, _err, branch_status = Open3.capture3("git", "rev-parse", "--verify", candidate)
          branch_status.success?
        end || "main"
      end

      # FIX for issue #391: Verify that implementation includes substantive code changes
      # Rejects changes that only include documentation, config, or non-code files
      # Note: If no files changed, we defer to ZFC verification (which handles empty implementations)
      def verify_substantive_changes(implementation_changes, working_dir)
        files_changed = implementation_changes[:files_changed] || ""
        diff = implementation_changes[:diff] || ""

        # Extract file names from the files changed summary
        changed_files = extract_changed_file_names(files_changed)

        Aidp.log_debug("implementation_verifier", "checking_substantive_changes",
          total_files: changed_files.size,
          files: changed_files.take(10))

        # No changes at all - defer to ZFC verification for proper handling
        # ZFC will determine if an empty implementation is valid for the issue
        if changed_files.empty?
          Aidp.log_debug("implementation_verifier", "no_files_changed_deferring_to_zfc")
          return {
            has_substantive_changes: true,  # Allow ZFC to make the determination
            reason: "No files changed - deferring to ZFC verification"
          }
        end

        # Categorize files
        code_files = []
        test_files = []
        doc_files = []
        config_files = []
        other_files = []

        changed_files.each do |file|
          case file
          when /\.(rb|py|js|ts|jsx|tsx|go|rs|java|kt|swift|c|cpp|h|hpp|cs)$/i
            if /(_spec|_test|\.spec|\.test|\/spec\/|\/test\/)/i.match?(file)
              test_files << file
            else
              code_files << file
            end
          # Only clearly documentation files - not .txt which could be anything
          when /\.(md|rst|adoc|rdoc)$/i, /^README/i, /^CHANGELOG/i, /^LICENSE/i
            doc_files << file
          when /\.(yml|yaml|json|toml|ini|env|config)$/i, /\.gitignore$/, /Gemfile/, /package\.json/
            config_files << file
          else
            other_files << file
          end
        end

        Aidp.log_debug("implementation_verifier", "file_categorization",
          code_files: code_files.size,
          test_files: test_files.size,
          doc_files: doc_files.size,
          config_files: config_files.size,
          other_files: other_files.size)

        # Check if there are substantive code changes
        # Substantive means: actual code files changed, not just docs/config
        # Note: "other" files (unknown extensions) are allowed through to ZFC for proper evaluation
        if code_files.empty? && test_files.empty? && other_files.empty?
          if doc_files.any? && config_files.empty?
            return {
              has_substantive_changes: false,
              reason: "Only documentation files were changed (#{doc_files.join(", ")}). " \
                     "Implementation requires code changes."
            }
          elsif config_files.any? && doc_files.empty?
            return {
              has_substantive_changes: false,
              reason: "Only configuration files were changed (#{config_files.join(", ")}). " \
                     "Implementation requires code changes."
            }
          elsif doc_files.any? || config_files.any?
            return {
              has_substantive_changes: false,
              reason: "Only documentation and configuration files were changed. " \
                     "Implementation requires code changes."
            }
          end
        end

        # If only test files changed, that's potentially valid for test-related issues
        # but we should flag it for issues that require implementation
        if code_files.empty? && test_files.any?
          # This is acceptable but worth noting
          Aidp.log_debug("implementation_verifier", "only_test_files_changed",
            test_files: test_files)
        end

        # Check diff size - very small diffs might be insignificant
        if diff.bytesize < 100 && code_files.any?
          return {
            has_substantive_changes: false,
            reason: "Code changes are too minimal (#{diff.bytesize} bytes). " \
                   "Please implement the required functionality fully."
          }
        end

        {
          has_substantive_changes: true,
          reason: "Found #{code_files.size} code files and #{test_files.size} test files changed"
        }
      end

      def extract_changed_file_names(files_changed_summary)
        return [] if files_changed_summary.nil? || files_changed_summary.empty?

        # Parse git diff --stat output format:
        # lib/aidp/foo.rb | 10 +++++-----
        # docs/README.md  |  3 +++
        files_changed_summary.lines.map do |line|
          # Extract filename from diff --stat format
          match = line.match(/^\s*([^\s|]+)\s*\|/)
          match ? match[1].strip : nil
        end.compact.reject(&:empty?)
      end

      def perform_zfc_verification(issue_number:, issue_requirements:, implementation_changes:)
        # Check if AI decision engine is available
        unless @ai_decision_engine
          Aidp.log_error(
            "implementation_verifier",
            "ai_decision_engine_not_available",
            issue: issue_number
          )
          return {
            verified: false,
            reason: "AI decision engine not available for verification",
            missing_items: ["Unable to verify - AI decision engine initialization failed"],
            additional_work: []
          }
        end

        prompt = build_verification_prompt(issue_number, issue_requirements, implementation_changes)

        schema = {
          type: "object",
          properties: {
            fully_implemented: {
              type: "boolean",
              description: "True if the implementation fully addresses all issue requirements"
            },
            reasoning: {
              type: "string",
              description: "Detailed explanation of the verification decision"
            },
            missing_requirements: {
              type: "array",
              items: {type: "string"},
              description: "List of specific requirements from the issue that are not yet implemented (empty if fully_implemented is true)"
            },
            additional_work_needed: {
              type: "array",
              items: {type: "string"},
              description: "List of specific tasks needed to complete the implementation (empty if fully_implemented is true)"
            }
          },
          required: ["fully_implemented", "reasoning", "missing_requirements", "additional_work_needed"]
        }

        # Use AIDecisionEngine with custom prompt
        # We use a custom decision type since this is a one-off verification
        decision = @ai_decision_engine.decide(
          :implementation_verification,
          context: {prompt: prompt},
          schema: schema,
          tier: :mini,
          cache_ttl: nil # Don't cache verification results as they're context-specific
        )

        # Convert AI decision to verification result
        {
          verified: decision[:fully_implemented],
          reason: decision[:reasoning],
          missing_items: decision[:missing_requirements] || [],
          additional_work: decision[:additional_work_needed] || []
        }
      rescue => e
        Aidp.log_error(
          "implementation_verifier",
          "zfc_verification_failed",
          issue: issue_number,
          error: e.message,
          error_class: e.class.name
        )

        # On error, fail safe by marking as not verified
        {
          verified: false,
          reason: "Verification failed due to error: #{e.message}",
          missing_items: ["Unable to verify due to technical error"],
          additional_work: []
        }
      end

      def build_verification_prompt(issue_number, issue_requirements, implementation_changes)
        <<~PROMPT
          You are verifying that an implementation fully addresses the requirements specified in a GitHub issue.

          ## Task
          Compare the issue requirements with the actual implementation changes and determine if the implementation is complete.

          ## Issue ##{issue_number} Requirements

          ### Title
          #{issue_requirements[:title]}

          ### Description
          #{issue_requirements[:body]}

          ### Discussion Thread / Plan
          #{format_comments(issue_requirements[:comments])}

          ## Implementation Changes

          ### Files Changed
          #{implementation_changes[:files_changed]}

          ### Code Changes (Diff)
          #{truncate_diff(implementation_changes[:diff])}

          ## Verification Criteria

          1. **All explicit requirements** from the issue description must be addressed
          2. **All tasks from the plan** (if present in comments) must be completed
          3. **Code changes must be substantive** - not just documentation or planning files
          4. **Test requirements** are NOT part of this verification (handled separately)
          5. **Quality/style requirements** are NOT part of this verification (handled by linters)

          ## Your Decision

          Determine if the implementation FULLY addresses the issue requirements. Be thorough but fair:
          - If all requirements are met, mark as fully_implemented = true
          - If any requirements are missing or incomplete, mark as fully_implemented = false and list them
          - Focus on FUNCTIONAL requirements, not code quality or style
        PROMPT
      end

      def format_comments(comments)
        return "_No discussion thread_" if comments.nil? || comments.empty?

        comments.map do |comment|
          author = comment[:author] || "unknown"
          timestamp = comment[:created_at] || "unknown"
          body = comment[:body] || ""

          "### #{author} (#{timestamp})\n#{body}"
        end.join("\n\n")
      end

      def truncate_diff(diff)
        return "_No changes detected_" if diff.nil? || diff.empty?

        max_size = 15_000 # ~15KB to stay within token limits
        if diff.bytesize > max_size
          truncated = diff.byteslice(0, max_size)
          "#{truncated}\n\n[... diff truncated, showing first #{max_size} bytes of #{diff.bytesize} total ...]"
        else
          diff
        end
      end

      def build_default_ai_decision_engine
        # Load config and create AI decision engine
        config = Aidp::Harness::Configuration.new(@project_dir)

        Aidp::Harness::AIDecisionEngine.new(config)
      rescue => e
        Aidp.log_warn(
          "implementation_verifier",
          "failed_to_create_ai_decision_engine",
          error: e.message,
          project_dir: @project_dir
        )
        # Return nil and fail verification gracefully
        nil
      end
    end
  end
end
