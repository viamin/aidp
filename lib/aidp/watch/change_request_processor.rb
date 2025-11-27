# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"
require "time"

require_relative "../message_display"
require_relative "../provider_manager"
require_relative "../harness/config_manager"
require_relative "../execute/prompt_manager"
require_relative "../harness/runner"
require_relative "../harness/state_manager"
require_relative "../harness/test_runner"
require_relative "../worktree"
require_relative "../pr_worktree_manager"
require_relative "../worktree_branch_manager"
require_relative "github_state_extractor"
require_relative "implementation_verifier"

module Aidp
  module Watch
    # Handles the aidp-request-changes label trigger by analyzing PR comments
    # and automatically implementing the requested changes.
    class ChangeRequestProcessor
      include Aidp::MessageDisplay

      # Default label names
      DEFAULT_CHANGE_REQUEST_LABEL = "aidp-request-changes"
      DEFAULT_NEEDS_INPUT_LABEL = "aidp-needs-input"

      COMMENT_HEADER = "## 🤖 AIDP Change Request"
      MAX_CLARIFICATION_ROUNDS = 3

      attr_reader :change_request_label, :needs_input_label

      def initialize(repository_client:, state_store:, provider_name: nil, project_dir: Dir.pwd, label_config: {}, change_request_config: {}, safety_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @state_extractor = GitHubStateExtractor.new(repository_client: repository_client)
        @provider_name = provider_name
        @project_dir = project_dir
        @verbose = verbose

        # Initialize worktree managers
        @pr_worktree_manager = Aidp::PrWorktreeManager.new(project_dir: project_dir)
        @worktree_branch_manager = Aidp::WorktreeBranchManager.new(project_dir: project_dir)

        # Initialize verifier
        @verifier = ImplementationVerifier.new(
          repository_client: repository_client,
          project_dir: project_dir
        )

        # Load label configuration
        @change_request_label = label_config[:change_request_trigger] || label_config["change_request_trigger"] || DEFAULT_CHANGE_REQUEST_LABEL
        @needs_input_label = label_config[:needs_input] || label_config["needs_input"] || DEFAULT_NEEDS_INPUT_LABEL

        # Load change request configuration
        @config = {
          enabled: true,
          allow_multi_file_edits: true,
          run_tests_before_push: true,
          commit_message_prefix: "aidp: pr-change",
          require_comment_reference: true,
          max_diff_size: 2000,
          large_pr_strategy: "create_worktree", # Options: create_worktree, manual, skip
          worktree_strategy: "auto", # Options: auto, always_create, reuse_only
          worktree_max_age: 7 * 24 * 60 * 60, # 7 days in seconds
          worktree_cleanup_on_success: true,
          worktree_cleanup_on_failure: false
        }.merge(symbolize_keys(change_request_config))

        # Log the configuration, especially the large PR strategy
        Aidp.log_debug(
          "change_request_processor", "Initialized with config",
          max_diff_size: @config[:max_diff_size],
          large_pr_strategy: @config[:large_pr_strategy],
          run_tests_before_push: @config[:run_tests_before_push],
          enabled: @config[:enabled],
          worktree_strategy: @config[:worktree_strategy],
          worktree_max_age: @config[:worktree_max_age],
          worktree_cleanup_on_success: @config[:worktree_cleanup_on_success],
          worktree_cleanup_on_failure: @config[:worktree_cleanup_on_failure]
        )

        # Load safety configuration
        @safety_config = safety_config
        @author_allowlist = Array(@safety_config[:author_allowlist] || @safety_config["author_allowlist"])
      end

      def process(pr)
        number = pr[:number]

        Aidp.log_debug(
          "change_request_processor", "Starting change request processing",
          pr_number: number, pr_title: pr[:title]
        )

        unless @config[:enabled]
          display_message(
            "ℹ️  PR change requests are disabled in configuration. Skipping PR ##{number}.",
            type: :muted
          )
          return
        end

        # Check clarification round limit
        existing_data = @state_store.change_request_data(number)
        if existing_data && existing_data["clarification_count"].to_i >= MAX_CLARIFICATION_ROUNDS
          display_message(
            "⚠️  Max clarification rounds (#{MAX_CLARIFICATION_ROUNDS}) reached for PR ##{number}. Skipping.",
            type: :warn
          )
          post_max_rounds_comment(pr)
          return
        end

        display_message(
          "📝 Processing change request for PR ##{number} (#{pr[:title]})",
          type: :info
        )

        # Fetch PR details
        pr_data = @repository_client.fetch_pull_request(number)
        comments = @repository_client.fetch_pr_comments(number)

        # Filter comments from authorized users
        authorized_comments = filter_authorized_comments(comments, pr_data)

        if authorized_comments.empty?
          display_message(
            "ℹ️  No authorized comments found for PR ##{number}. Skipping.",
            type: :muted
          )
          return
        end

        # Fetch diff to check size with enhanced strategy
        diff = @repository_client.fetch_pull_request_diff(number)
        diff_size = diff.lines.count

        # Enhanced diff size and worktree handling
        large_pr = diff_size > @config[:max_diff_size]

        if large_pr
          # Comprehensive logging for large PR detection
          Aidp.log_debug(
            "change_request_processor", "Large PR detected",
            pr_number: number,
            diff_size: diff_size,
            max_diff_size: @config[:max_diff_size],
            large_pr_strategy: @config[:large_pr_strategy]
          )

          display_message(
            "⚠️  Large PR detected - applying enhanced worktree handling strategy.",
            type: :info
          )

          # Handle different strategies for large PRs
          case @config[:large_pr_strategy]
          when "skip"
            Aidp.log_debug(
              "change_request_processor", "Skipping large PR processing",
              pr_number: number
            )
            post_diff_too_large_comment(pr_data, diff_size)
            return
          when "manual"
            post_diff_too_large_comment(pr_data, diff_size)
            display_message("❌ Change request processing failed: Large PR requires manual processing. See comment for details.", type: :error)
            @state_store.record_change_request(pr_data[:number], {
              status: "manual_processing_required",
              timestamp: Time.now.utc.iso8601,
              diff_size: diff_size,
              max_diff_size: @config[:max_diff_size]
            })
            raise "Large PR requires manual processing. See comment for details."
          when "create_worktree"
            # Use our enhanced WorktreeBranchManager to handle PR worktrees
            begin
              # Get PR branch information
              head_ref = @worktree_branch_manager.get_pr_branch(number)

              # Check if a PR-specific worktree already exists
              Aidp.log_debug(
                "change_request_processor", "Checking for existing PR worktree",
                pr_number: number,
                head_branch: head_ref
              )

              # Try to find existing worktree first
              existing_worktree = @worktree_branch_manager.find_worktree(
                branch: head_ref,
                pr_number: number
              )

              # Create new worktree if none exists
              if existing_worktree.nil?
                Aidp.log_info(
                  "change_request_processor", "Creating PR-specific worktree",
                  pr_number: number,
                  head_branch: head_ref,
                  base_branch: pr_data[:base_ref],
                  strategy: "create_worktree"
                )

                # Use find_or_create_pr_worktree for PR-specific handling
                @worktree_branch_manager.find_or_create_pr_worktree(
                  pr_number: number,
                  head_branch: head_ref,
                  base_branch: pr_data[:base_ref]
                )
              else
                Aidp.log_debug(
                  "change_request_processor", "Using existing PR worktree",
                  pr_number: number,
                  worktree_path: existing_worktree
                )
              end
            rescue => e
              Aidp.log_error(
                "change_request_processor", "Large PR worktree handling failed",
                pr_number: number,
                error: e.message,
                strategy: @config[:large_pr_strategy]
              )

              # Fallback error handling
              post_diff_too_large_comment(pr_data, diff_size)
              raise "Failed to handle large PR: #{e.message}"
            end
          else
            # Default fallback
            Aidp.log_warn(
              "change_request_processor", "Unknown large_pr_strategy",
              strategy: @config[:large_pr_strategy],
              fallback: "skip"
            )
            post_diff_too_large_comment(pr_data, diff_size)
            return
          end

          # Provide additional context via debug log
          Aidp.log_info(
            "change_request_processor", "Large PR worktree strategy applied",
            pr_number: number,
            diff_size: diff_size,
            max_diff_size: @config[:max_diff_size],
            strategy: @config[:large_pr_strategy]
          )
        end

        # Analyze change requests
        analysis_result = analyze_change_requests(
          pr_data: pr_data,
          comments: authorized_comments,
          diff: diff
        )

        if analysis_result[:needs_clarification]
          handle_clarification_needed(pr: pr_data, analysis: analysis_result)
        elsif analysis_result[:can_implement]
          implement_changes(pr: pr_data, analysis: analysis_result, diff: diff)
        else
          handle_cannot_implement(pr: pr_data, analysis: analysis_result)
        end
      rescue => e
        display_message(
          "❌ Change request processing failed: #{e.message}",
          type: :error
        )
        Aidp.log_error(
          "change_request_processor", "Change request failed",
          pr: pr[:number],
          error: e.message,
          backtrace: e.backtrace&.first(10),
          error_class: e.class.name
        )

        # Record failure state internally but DON'T post error to GitHub
        # (per issue #280 - error messages should never appear on issues)
        @state_store.record_change_request(pr[:number], {
          status: "error",
          error: e.message,
          error_class: e.class.name,
          timestamp: Time.now.utc.iso8601
        })
      end

      private

      def filter_authorized_comments(comments, pr_data)
        # If allowlist is empty (for private repos), consider PR author and all commenters
        # For public repos, enforce allowlist
        if @author_allowlist.empty?
          # Private repo: trust all comments from PR participants
          comments
        else
          # Public repo: only allow comments from allowlisted users
          comments.select do |comment|
            author = comment[:author]
            @author_allowlist.include?(author)
          end
        end
      end

      def analyze_change_requests(pr_data:, comments:, diff:)
        provider_name = @provider_name || detect_default_provider
        provider = Aidp::ProviderManager.get_provider(provider_name)

        user_prompt = build_analysis_prompt(pr_data: pr_data, comments: comments, diff: diff)
        full_prompt = "#{change_request_system_prompt}\n\n#{user_prompt}"

        Aidp.log_debug("change_request_processor", "Analyzing change requests", pr: pr_data[:number], comments_count: comments.length)

        response = provider.send_message(prompt: full_prompt)
        content = response.to_s.strip

        # Extract JSON from response
        json_content = extract_json(content)

        # Parse JSON response
        parsed = JSON.parse(json_content)

        # Additional structured analysis
        result = {
          can_implement: parsed["can_implement"],
          needs_clarification: parsed["needs_clarification"],
          clarifying_questions: parsed["clarifying_questions"] || [],
          reason: parsed["reason"],
          changes: []
        }

        # Enhanced change parsing
        begin
          result[:changes] = parse_ai_changes(
            {changes: parsed["changes"]},
            pr_data,
            comments
          )
        rescue => e
          Aidp.log_warn("change_request_processor", "Change parsing failed",
            pr_number: pr_data[:number],
            error: e.message)
        end

        Aidp.log_debug("change_request_processor", "Change request analysis result",
          pr_number: pr_data[:number],
          can_implement: result[:can_implement],
          needs_clarification: result[:needs_clarification],
          changes_count: result[:changes].length)

        result
      rescue JSON::ParserError => e
        Aidp.log_error("change_request_processor", "Failed to parse AI response", error: e.message, content: content)
        {can_implement: false, needs_clarification: false, reason: "Failed to parse AI analysis", changes: []}
      rescue => e
        Aidp.log_error("change_request_processor", "AI analysis failed", error: e.message)
        {can_implement: false, needs_clarification: false, reason: "AI analysis error: #{e.message}", changes: []}
      end

      def change_request_system_prompt
        <<~PROMPT
          You are an expert software engineer analyzing change requests from PR comments.

          Your task is to:
          1. Read all comments and understand what changes are being requested
          2. Weight newer comments higher than older ones
          3. If multiple approved commenters request different things, consider the most recent request
          4. Determine if you can confidently implement the requested changes

          Respond in JSON format:
          {
            "can_implement": true/false,
            "needs_clarification": true/false,
            "clarifying_questions": ["Question 1?", "Question 2?"],
            "reason": "Brief explanation of your decision",
            "changes": [
              {
                "file": "path/to/file",
                "action": "edit|create|delete",
                "content": "Full file content after change (for create/edit)",
                "description": "What this change does",
                "line_start": 10,
                "line_end": 20
              }
            ]
          }

          Set "can_implement" to true ONLY if:
          - The requested changes are clear and unambiguous
          - You understand the codebase context from the PR diff
          - The changes are technically feasible
          - You can provide complete, correct implementations

          Set "needs_clarification" to true if:
          - Multiple conflicting requests exist
          - The request is vague or incomplete
          - You need more context to implement correctly
          - There are unclear technical requirements

          For "changes", provide the complete file content after applying the requested modifications.
          Support multi-file edits by including multiple change objects.

          DO NOT attempt to implement if:
          - The request requires domain knowledge you don't have
          - The changes could introduce security vulnerabilities
          - The request is too complex for automated implementation
          - You're not confident the changes are correct
        PROMPT
      end

      def build_analysis_prompt(pr_data:, comments:, diff:)
        # Sort comments by creation time, newest first
        sorted_comments = comments.sort_by { |c| c[:created_at] }.reverse

        comments_text = sorted_comments.map do |comment|
          "**#{comment[:author]}** (#{comment[:created_at]}):\n#{comment[:body]}"
        end.join("\n\n---\n\n")

        <<~PROMPT
          Analyze these change requests for PR ##{pr_data[:number]}: #{pr_data[:title]}

          **PR Description:**
          #{pr_data[:body]}

          **Current PR Diff:**
          ```diff
          #{diff}
          ```

          **Comments (newest first):**
          #{comments_text}

          Please analyze what changes are being requested and determine if you can implement them.
        PROMPT
      end

      def implement_changes(pr:, analysis:, diff:)
        display_message("🔨 Implementing requested changes for PR ##{pr[:number]}", type: :info)

        # Checkout PR branch
        checkout_pr_branch(pr)

        # Apply changes
        apply_changes(analysis[:changes])

        # Run tests if configured
        if @config[:run_tests_before_push]
          test_result = run_tests_and_linters
          unless test_result[:success]
            handle_test_failure(pr: pr, analysis: analysis, test_result: test_result)
            return
          end
        end

        # Check if PR is linked to an issue - if so, verify implementation completeness
        issue_number = @state_extractor.extract_linked_issue(pr[:body])
        if issue_number
          display_message("🔗 Found linked issue ##{issue_number} - verifying implementation...", type: :info)

          begin
            issue = @repository_client.fetch_issue(issue_number)
            verification_result = @verifier.verify(issue: issue, working_dir: @project_dir)

            unless verification_result[:verified]
              handle_incomplete_implementation(pr: pr, analysis: analysis, verification_result: verification_result)
              return
            end

            display_message("✅ Implementation verified complete", type: :success)
          rescue => e
            display_message("⚠️  Verification check failed: #{e.message}", type: :warn)
            Aidp.log_error("change_request_processor", "Verification failed", pr: pr[:number], error: e.message)
            # Continue with commit/push even if verification fails
          end
        end

        # Commit and push
        if commit_and_push(pr, analysis)
          handle_success(pr: pr, analysis: analysis)
        else
          handle_no_changes(pr: pr, analysis: analysis)
        end
      end

      def checkout_pr_branch(pr_data)
        pr_number = pr_data[:number]
        base_branch = pr_data[:base_ref]

        Aidp.log_debug(
          "change_request_processor", "Starting PR branch checkout process",
          pr_number: pr_number,
          base_branch: base_branch,
          project_dir: @project_dir
        )

        # Get PR branch information
        head_ref = @worktree_branch_manager.get_pr_branch(pr_number)

        begin
          # Advanced worktree strategy with more detailed lookup
          existing_worktree = @worktree_branch_manager.find_worktree(
            branch: head_ref,
            pr_number: pr_number
          )

          # Logging: Detailed worktree search strategy
          log_worktree_strategy = {
            pr_number: pr_number,
            head_branch: head_ref,
            existing_worktree: !!existing_worktree,
            worktree_creation_strategy: @config.fetch(:worktree_strategy, "auto")
          }

          # Enhanced logging for worktree preparation
          Aidp.log_info(
            "change_request_processor", "Preparing PR worktree",
            **log_worktree_strategy
          )

          # Worktree creation or reuse strategy
          case @config.fetch(:worktree_strategy, "auto")
          when "always_create"
            # Force new worktree creation, useful for complex/large PRs
            Aidp.log_info("change_request_processor", "Forcing new worktree creation", pr: pr_number)
            existing_worktree = nil
          when "reuse_only"
            # Use only existing worktrees, error if not found
            unless existing_worktree
              raise "No existing worktree found for PR ##{pr_number}"
            end
          else # "auto" or default
            # Existing default behavior: find or create
          end

          # Use the enhanced find_or_create_pr_worktree method for PR-specific worktree handling
          worktree_path = @worktree_branch_manager.find_or_create_pr_worktree(
            pr_number: pr_number,
            head_branch: head_ref,
            base_branch: base_branch
          )

          # Detailed logging of worktree path and strategy
          Aidp.log_debug(
            "change_request_processor", "PR worktree determined",
            worktree_path: worktree_path,
            creation_strategy: existing_worktree ? "reused" : "created",
            pr_number: pr_number
          )

          display_message("🔄 Using PR-specific worktree for branch: #{head_ref}", type: :info)

          # Update project directory to use the worktree
          @project_dir = worktree_path

          # Ensure the branch is up-to-date with remote
          Dir.chdir(@project_dir) do
            run_git(["fetch", "origin", base_branch], allow_failure: true)
            run_git(["fetch", "origin", head_ref], allow_failure: true)

            # Checkout branch with more detailed tracking
            checkout_result = run_git(["checkout", head_ref])

            # Pull with fast-forward preference for cleaner history
            pull_result = run_git(
              ["pull", "--ff-only", "origin", head_ref],
              allow_failure: true
            )

            # Enhanced branch state logging
            Aidp.log_info(
              "change_request_processor", "Branch synchronization complete",
              pr_number: pr_number,
              checkout_status: checkout_result.strip,
              pull_status: pull_result.strip,
              current_branch: run_git(["rev-parse", "--abbrev-ref", "HEAD"]).strip
            )
          end

          # Additional validation and logging
          worktree_details = {
            path: worktree_path,
            branch: head_ref,
            base_branch: base_branch,
            pr_number: pr_number,
            timestamp: Time.now.utc.iso8601
          }

          Aidp.log_debug(
            "change_request_processor", "Validated PR worktree",
            **worktree_details
          )

          worktree_path
        rescue => e
          Aidp.log_error(
            "change_request_processor", "Critical worktree preparation failure",
            pr_number: pr_number,
            base_branch: base_branch,
            head_branch: head_ref,
            error: e.message,
            error_class: e.class.name,
            backtrace: e.backtrace.first(10)
          )

          # Provide detailed error handling and recovery
          handle_worktree_error(pr_data, e)
        end
      end

      def handle_worktree_error(pr_data, error)
        # Log the detailed error
        Aidp.log_error(
          "change_request_processor", "Worktree preparation critical error",
          pr_number: pr_data[:number],
          error_message: error.message,
          error_class: error.class.name
        )

        # Post a comment to GitHub about the failure
        comment_body = <<~COMMENT
          #{COMMENT_HEADER}

          ❌ Automated worktree preparation failed for this pull request.

          **Error Details:**
          ```
          #{error.message}
          ```

          **Possible Actions:**
          1. Review the PR branch and its configuration
          2. Check if the base repository is accessible
          3. Try re-adding the `#{@change_request_label}` label

          This may require manual intervention or administrative access.
        COMMENT

        begin
          @repository_client.post_comment(pr_data[:number], comment_body)

          # Optionally remove or modify the label to indicate a problem
          @repository_client.replace_labels(
            pr_data[:number],
            old_labels: [@change_request_label],
            new_labels: ["aidp-worktree-error"]
          )
        rescue => comment_error
          Aidp.log_warn(
            "change_request_processor", "Failed to post error comment",
            pr_number: pr_data[:number],
            error: comment_error.message
          )
        end

        # Re-raise the original error to halt processing
        raise error
      end

      private

      def apply_changes(changes)
        # Validate we're in a worktree for enhanced change handling
        in_worktree = @project_dir.include?(".worktrees")

        Aidp.log_debug("change_request_processor", "Starting change application",
          total_changes: changes.length,
          in_worktree: in_worktree,
          working_dir: @project_dir)

        # Track overall change application results
        results = {
          total_changes: changes.length,
          successful_changes: 0,
          failed_changes: 0,
          skipped_changes: 0,
          errors: [],
          worktree_context: in_worktree
        }

        # Enhanced change application with worktree context awareness
        changes.each_with_index do |change, index|
          file_path = change["file"].start_with?(@project_dir) ? change["file"] : File.join(@project_dir, change["file"])

          Aidp.log_debug("change_request_processor", "Preparing to apply change",
            index: index + 1,
            total: changes.length,
            action: change["action"],
            file: change["file"],
            content_length: change["content"]&.length || 0,
            in_worktree: in_worktree)

          begin
            case change["action"]
            when "create", "edit"
              # Enhanced file change strategy with worktree awareness
              unless change["content"]
                results[:skipped_changes] += 1
                Aidp.log_warn("change_request_processor", "Skipping change with empty content",
                  file: change["file"], action: change["action"], in_worktree: in_worktree)
                next
              end

              # Enhanced directory creation with worktree validation
              target_directory = File.dirname(file_path)
              unless File.directory?(target_directory)
                FileUtils.mkdir_p(target_directory)
                Aidp.log_debug("change_request_processor", "Created directory structure",
                  directory: target_directory, in_worktree: in_worktree)
              end

              # Preserve file permissions if file already exists
              old_permissions = File.exist?(file_path) ? File.stat(file_path).mode : 0o644

              # Enhanced content writing with validation
              File.write(file_path, change["content"])
              File.chmod(old_permissions, file_path)

              # Validate file was written correctly
              unless File.exist?(file_path) && File.readable?(file_path)
                raise "File creation validation failed"
              end

              display_message("  ✓ #{change["action"]} #{change["file"]}", type: :muted) if @verbose
              Aidp.log_debug("change_request_processor", "Applied file change",
                action: change["action"],
                file: change["file"],
                content_preview: change["content"]&.slice(0, 100),
                file_size: File.size(file_path),
                original_source_comments: change["source_comment_urls"],
                in_worktree: in_worktree)

              results[:successful_changes] += 1

            when "delete"
              # Enhanced delete strategy with worktree context
              if File.exist?(file_path)
                # Additional validation for worktree safety
                if in_worktree
                  canonical_path = File.expand_path(file_path)
                  worktree_canonical = File.expand_path(@project_dir)
                  unless canonical_path.start_with?(worktree_canonical)
                    raise SecurityError, "Attempted to delete file outside worktree"
                  end
                end

                File.delete(file_path)
                display_message("  ✓ Deleted #{change["file"]}", type: :muted) if @verbose
                Aidp.log_debug("change_request_processor", "Deleted file",
                  file: change["file"],
                  original_source_comments: change["source_comment_urls"],
                  in_worktree: in_worktree)
                results[:successful_changes] += 1
              else
                results[:skipped_changes] += 1
                Aidp.log_warn("change_request_processor", "File to delete does not exist",
                  file: change["file"], in_worktree: in_worktree)
              end

            else
              results[:skipped_changes] += 1
              error_msg = "Unknown change action: #{change["action"]}"
              display_message("  ⚠️  #{error_msg} for #{change["file"]}", type: :warn)

              results[:errors] << {
                file: change["file"],
                action: change["action"],
                error: error_msg,
                worktree_context: in_worktree
              }

              Aidp.log_warn("change_request_processor", "Unhandled change action",
                action: change["action"],
                file: change["file"],
                in_worktree: in_worktree)
            end
          rescue SecurityError => e
            results[:failed_changes] += 1
            error_details = {
              file: change["file"],
              action: change["action"],
              error: e.message,
              error_type: "security_violation",
              worktree_context: in_worktree
            }

            results[:errors] << error_details

            Aidp.log_error("change_request_processor", "Security violation during change application",
              **error_details)

            display_message("  🔒 Security error applying change to #{change["file"]}: #{e.message}", type: :error)
          rescue => e
            results[:failed_changes] += 1
            error_details = {
              file: change["file"],
              action: change["action"],
              error: e.message,
              backtrace: e.backtrace&.first(3),
              worktree_context: in_worktree
            }

            results[:errors] << error_details

            Aidp.log_error("change_request_processor", "Change application failed",
              **error_details)

            display_message("  ❌ Failed to apply change to #{change["file"]}: #{e.message}", type: :error)
          end
        end

        # Enhanced logging of overall change application results
        Aidp.log_info("change_request_processor", "Change application summary",
          total_changes: results[:total_changes],
          successful_changes: results[:successful_changes],
          skipped_changes: results[:skipped_changes],
          failed_changes: results[:failed_changes],
          errors_count: results[:errors].length,
          success_rate: (results[:successful_changes].to_f / results[:total_changes] * 100).round(2),
          in_worktree: in_worktree,
          working_directory: @project_dir)

        # Additional worktree-specific logging
        if in_worktree && results[:successful_changes] > 0
          Aidp.log_info("change_request_processor", "Worktree changes applied successfully",
            worktree_path: @project_dir,
            files_modified: results[:successful_changes])
        end

        # Return enhanced results for potential additional handling
        results
      end

      def run_tests_and_linters
        display_message("🧪 Running tests and linters...", type: :info)

        config_manager = Aidp::Harness::ConfigManager.new(@project_dir)
        config = config_manager.config || {}

        test_runner = Aidp::Harness::TestRunner.new(@project_dir, config)

        # Run linters first
        lint_result = test_runner.run_linters
        if lint_result && !lint_result[:passed]
          return {success: false, stage: "lint", output: lint_result[:output]}
        end

        # Run tests
        test_result = test_runner.run_tests
        if test_result && !test_result[:passed]
          return {success: false, stage: "test", output: test_result[:output]}
        end

        {success: true}
      rescue => e
        Aidp.log_error("change_request_processor", "Test/lint execution failed", error: e.message)
        {success: false, stage: "unknown", error: e.message}
      end

      def commit_and_push(pr_data, analysis)
        Dir.chdir(@project_dir) do
          # Validate we're in a worktree
          unless @project_dir.include?(".worktrees")
            Aidp.log_error(
              "change_request_processor", "Invalid project directory for commit_and_push",
              pr_number: pr_data[:number],
              project_dir: @project_dir
            )
            return false
          end

          begin
            # Check for changes
            status_result = run_git(%w[status --porcelain])
            return false if status_result.strip.empty?

            modified_files = status_result.split("\n").map { |l| l.strip.split(" ", 2).last }

            # Stage all changes
            run_git(%w[add -A])
            Aidp.log_debug("change_request_processor", "Staged changes",
              pr_number: pr_data[:number],
              staged_files: modified_files)

            # Create commit
            commit_message = build_commit_message(pr_data, analysis)
            commit_result = run_git(["commit", "-m", commit_message])
            first_line = commit_message.lines.first.strip
            Aidp.log_info(
              "change_request_processor", "Created commit",
              pr: pr_data[:number],
              commit_message: first_line,
              files_changed: modified_files,
              commit_result: commit_result.strip
            )
            display_message("💾 Created commit: #{first_line}", type: :info)

            # Push changes
            head_ref = pr_data[:head_ref]
            begin
              push_result = run_git(["push", "origin", head_ref], allow_failure: false)
              Aidp.log_info("change_request_processor", "Pushed changes",
                pr: pr_data[:number],
                branch: head_ref,
                push_result: push_result.strip)
              display_message("⬆️  Pushed changes to #{head_ref}", type: :success)
              return true
            rescue => push_error
              # Push failed, but commit was successful
              Aidp.log_warn("change_request_processor", "Push failed, but commit was successful",
                pr_number: pr_data[:number],
                error: push_error.message)

              # Post a detailed comment about the push failure
              comment_body = <<~COMMENT
                #{COMMENT_HEADER}

                ⚠️ Automated changes were committed successfully, but pushing to the branch failed.

                **Error Details:**
                ```
                #{push_error.message}
                ```

                **Suggested Actions:**
                1. Check branch permissions
                2. Verify remote repository configuration
                3. Manually push the changes
                4. Contact repository administrator
              COMMENT

              begin
                @repository_client.post_comment(pr_data[:number], comment_body)
              rescue => comment_error
                Aidp.log_warn("change_request_processor", "Failed to post push error comment",
                  pr_number: pr_data[:number],
                  error: comment_error.message)
              end

              return false
            end
          rescue => error
            # Catch any other unexpected errors during the entire process
            Aidp.log_error(
              "change_request_processor", "Unexpected error in commit_and_push",
              pr_number: pr_data[:number],
              error: error.message,
              backtrace: error.backtrace.first(5)
            )
            return false
          end
        end
      end

      def build_commit_message(pr_data, analysis)
        prefix = @config[:commit_message_prefix]
        changes_summary = analysis[:changes]&.map { |c| c["description"] }&.join(", ")
        changes_summary = "requested changes" if changes_summary.nil? || changes_summary.empty?

        message = "#{prefix}: #{changes_summary}\n\n"
        message += "Implements change request from PR ##{pr_data[:number]} review comments.\n"
        message += "\nReason: #{analysis[:reason]}\n" if analysis[:reason]
        message += "\nCo-authored-by: AIDP Change Request Processor <ai@aidp.dev>"

        message
      end

      def handle_success(pr:, analysis:)
        changes_list = analysis[:changes].map do |c|
          "- **#{c["file"]}**: #{c["description"]}"
        end.join("\n")

        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ✅ Successfully implemented requested changes!

          **Changes Applied:**
          #{changes_list}

          The changes have been committed and pushed to this PR.
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_change_request(pr[:number], {
          status: "completed",
          timestamp: Time.now.utc.iso8601,
          changes_applied: analysis[:changes].length,
          commits: 1
        })

        display_message("🎉 Posted success comment for PR ##{pr[:number]}", type: :success)
        Aidp.log_info("change_request_processor", "Change request completed", pr: pr[:number], changes: analysis[:changes].length)

        # Remove label after successful implementation
        begin
          @repository_client.remove_labels(pr[:number], @change_request_label)
          display_message("🏷️  Removed '#{@change_request_label}' label after successful implementation", type: :info)
        rescue => e
          display_message("⚠️  Failed to remove change request label: #{e.message}", type: :warn)
        end
      end

      def handle_no_changes(pr:, analysis:)
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ℹ️  Analysis completed but no changes were needed.

          **Reason:** #{analysis[:reason] || "The requested changes may already be applied or no modifications were necessary."}

          If you believe changes should be made, please clarify the request and re-add the `#{@change_request_label}` label.
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_change_request(pr[:number], {
          status: "no_changes",
          timestamp: Time.now.utc.iso8601,
          reason: analysis[:reason]
        })

        display_message("ℹ️  Posted no-changes comment for PR ##{pr[:number]}", type: :info)

        # Remove label
        begin
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue
          nil
        end
      end

      def handle_incomplete_implementation(pr:, analysis:, verification_result:)
        display_message("⚠️  Implementation incomplete; creating follow-up tasks.", type: :warn)

        # Create tasks for missing requirements
        if verification_result[:additional_work] && !verification_result[:additional_work].empty?
          create_follow_up_tasks(@project_dir, verification_result[:additional_work])
        end

        # Record state but do not post a separate comment
        # (verification details will be included in the next summary comment)
        @state_store.record_change_request(pr[:number], {
          status: "incomplete_implementation",
          timestamp: Time.now.utc.iso8601,
          verification_reasons: verification_result[:reasons],
          missing_items: verification_result[:missing_items],
          additional_work: verification_result[:additional_work]
        })

        display_message("📝 Recorded incomplete implementation status for PR ##{pr[:number]}", type: :info)

        # Keep the label so the work loop continues (do NOT remove it)
        Aidp.log_info(
          "change_request_processor",
          "incomplete_implementation",
          pr: pr[:number],
          missing_items: verification_result[:missing_items],
          additional_work: verification_result[:additional_work]
        )
      end

      def create_follow_up_tasks(working_dir, additional_work)
        return if additional_work.nil? || additional_work.empty?

        tasklist_file = File.join(working_dir, ".aidp", "tasklist.jsonl")
        FileUtils.mkdir_p(File.dirname(tasklist_file))

        require_relative "../execute/persistent_tasklist"
        tasklist = Aidp::Execute::PersistentTasklist.new(working_dir)

        additional_work.each do |task_description|
          tasklist.create(
            description: task_description,
            priority: :high,
            source: "verification"
          )
        end

        display_message("📝 Created #{additional_work.length} follow-up task(s) for continued work", type: :info)

        Aidp.log_info(
          "change_request_processor",
          "created_follow_up_tasks",
          task_count: additional_work.length,
          working_dir: working_dir
        )
      rescue => e
        display_message("⚠️  Failed to create follow-up tasks: #{e.message}", type: :warn)
        Aidp.log_error(
          "change_request_processor",
          "failed_to_create_follow_up_tasks",
          error: e.message,
          backtrace: e.backtrace&.first(5)
        )
      end

      def handle_clarification_needed(pr:, analysis:)
        existing_data = @state_store.change_request_data(pr[:number])
        clarification_count = (existing_data&.dig("clarification_count") || 0) + 1

        questions_list = analysis[:clarifying_questions].map.with_index(1) do |q, i|
          "#{i}. #{q}"
        end.join("\n")

        comment = <<~COMMENT
          #{COMMENT_HEADER}

          🤔 I need clarification to implement the requested changes.

          **Questions:**
          #{questions_list}

          **Reason:** #{analysis[:reason]}

          Please respond to these questions in a comment, then re-apply the `#{@change_request_label}` label.

          _(Clarification round #{clarification_count} of #{MAX_CLARIFICATION_ROUNDS})_
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_change_request(pr[:number], {
          status: "needs_clarification",
          timestamp: Time.now.utc.iso8601,
          clarification_count: clarification_count,
          reason: analysis[:reason]
        })

        display_message("🤔 Posted clarification request for PR ##{pr[:number]}", type: :info)
        Aidp.log_info("change_request_processor", "Clarification needed", pr: pr[:number], round: clarification_count)

        # Replace label with needs-input label
        begin
          @repository_client.replace_labels(pr[:number], old_labels: [@change_request_label], new_labels: [@needs_input_label])
          display_message("🏷️  Replaced '#{@change_request_label}' with '#{@needs_input_label}' label", type: :info)
        rescue => e
          display_message("⚠️  Failed to update labels: #{e.message}", type: :warn)
        end
      end

      def handle_cannot_implement(pr:, analysis:)
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ⚠️  Cannot automatically implement the requested changes.

          **Reason:** #{analysis[:reason] || "The request is too complex or unclear for automated implementation."}

          Please consider:
          1. Breaking down the request into smaller, more specific changes
          2. Providing additional context or examples
          3. Implementing the changes manually

          You can retry by re-adding the `#{@change_request_label}` label with clarified instructions.
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_change_request(pr[:number], {
          status: "cannot_implement",
          timestamp: Time.now.utc.iso8601,
          reason: analysis[:reason]
        })

        display_message("⚠️  Posted cannot-implement comment for PR ##{pr[:number]}", type: :warn)
        Aidp.log_info("change_request_processor", "Cannot implement", pr: pr[:number], reason: analysis[:reason])

        # Remove label
        begin
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue
          nil
        end
      end

      def handle_test_failure(pr:, analysis:, test_result:)
        stage = test_result[:stage]
        output = test_result[:output] || test_result[:error] || "Unknown error"

        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ❌ Changes were applied but #{stage} failed.

          **#{stage.capitalize} Output:**
          ```
          #{output.lines.first(50).join}
          ```

          Using fix-forward strategy: the changes have been committed but not pushed.
          Please review the #{stage} failures and either:
          1. Fix the issues manually
          2. Provide additional context in a comment and re-add the `#{@change_request_label}` label
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_change_request(pr[:number], {
          status: "test_failed",
          timestamp: Time.now.utc.iso8601,
          reason: "#{stage} failed after applying changes",
          changes_applied: analysis[:changes].length
        })

        display_message("❌ Posted test failure comment for PR ##{pr[:number]}", type: :error)
        Aidp.log_error("change_request_processor", "Test/lint failure", pr: pr[:number], stage: stage)

        # Remove label
        begin
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue
          nil
        end
      end

      def post_max_rounds_comment(pr)
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ⛔ Maximum clarification rounds (#{MAX_CLARIFICATION_ROUNDS}) reached.

          Unable to proceed with automated implementation. Please consider:
          1. Implementing the changes manually
          2. Creating a new, more specific change request
          3. Providing all necessary context upfront

          To reset and try again, remove the current state and re-add the `#{@change_request_label}` label.
        COMMENT

        begin
          @repository_client.post_comment(pr[:number], comment)
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue
          nil
        end
      end

      def post_diff_too_large_comment(pr, diff_size)
        # Configure handling based on repository/project config
        handling_strategy = case @config[:large_pr_strategy]
        when "create_worktree"
          "Creating a dedicated git worktree"
        when "manual"
          "Requiring manual intervention"
        else
          "Skipping processing"
        end

        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ⚠️  PR diff is too large for standard automated change requests.

          **Current size:** #{diff_size} lines
          **Maximum allowed:** #{@config[:max_diff_size]} lines
          **Handling strategy:** #{handling_strategy}

          Options:
          1. Break the PR into smaller chunks
          2. Implement changes manually
          3. Increase `max_diff_size` in your `aidp.yml` configuration
          4. Configure `large_pr_strategy` to customize processing
        COMMENT

        Aidp.log_debug(
          "change_request_processor", "Large PR detected",
          pr_number: pr[:number],
          diff_size: diff_size,
          max_diff_size: @config[:max_diff_size],
          strategy: handling_strategy
        )

        begin
          @repository_client.post_comment(pr[:number], comment)
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue => e
          Aidp.log_warn(
            "change_request_processor", "Failed to post large PR comment",
            pr_number: pr[:number],
            error: e.message
          )
        end
      end

      def run_git(args, allow_failure: false)
        args_array = Array(args)
        stdout, stderr, status = Open3.capture3("git", *args_array)
        raise "git #{args_array.join(" ")} failed: #{stderr.strip}" unless status.success? || allow_failure
        stdout
      end

      def detect_default_provider
        config_manager = Aidp::Harness::ConfigManager.new(@project_dir)
        config_manager.default_provider || "anthropic"
      rescue
        "anthropic"
      end

      def extract_json(text)
        # Try to extract JSON from code fences or find JSON object
        return text if text.start_with?("{") && text.end_with?("}")

        # Extract from code fence
        fence_start = text.index("```json")
        if fence_start
          json_start = text.index("{", fence_start)
          fence_end = text.index("```", fence_start + 7)
          if json_start && fence_end && json_start < fence_end
            json_end = text.rindex("}", fence_end - 1)
            return text[json_start..json_end] if json_end && json_end > json_start
          end
        end

        # Find JSON object
        first_brace = text.index("{")
        last_brace = text.rindex("}")
        if first_brace && last_brace && last_brace > first_brace
          text[first_brace..last_brace]
        else
          text
        end
      end

      def parse_ai_changes(ai_response, pr_data, comments)
        changes = ai_response[:changes] || []

        # Log raw changes for debugging
        Aidp.log_debug(
          "change_request_processor", "Extracted changes",
          pr_number: pr_data[:number],
          changes_count: changes.length
        )

        # Validate and sanitize changes
        validated_changes = changes.map do |change|
          # Sanitize file path
          file_path = change["file"].to_s.gsub(%r{^/|\.\.}, "")
          file_path = File.join(@project_dir, file_path) unless file_path.start_with?(@project_dir)

          # Validate change structure
          {
            "file" => file_path,
            "action" => %w[create edit delete].include?(change["action"]) ? change["action"] : "edit",
            "content" => change["content"].to_s,
            "description" => change["description"].to_s.slice(0, 500), # Limit description length
            "line_start" => change["line_start"]&.to_i,
            "line_end" => change["line_end"]&.to_i
          }
        end.select do |change|
          # Filter out invalid or empty changes
          change["file"].present? &&
            (change["action"] == "delete" || change["content"].present?)
        end

        # Add source reference for traceability
        validated_changes.each do |change|
          change["source_comment_urls"] = comments
            .select { |c| c[:body].include?(change["description"]) }
            .map { |c| c[:url] }
        end

        Aidp.log_debug(
          "change_request_processor", "Validated changes",
          pr_number: pr_data[:number],
          validated_changes_count: validated_changes.length
        )

        validated_changes
      end

      def symbolize_keys(hash)
        return {} unless hash

        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end
    end
  end
end
