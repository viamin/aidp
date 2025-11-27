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
          allow_large_pr_worktree_bypass: true # Default to always using worktree for large PRs
        }.merge(symbolize_keys(change_request_config))

        # Load safety configuration
        @safety_config = safety_config
        @author_allowlist = Array(@safety_config[:author_allowlist] || @safety_config["author_allowlist"])
      end

      def process(pr)
        number = pr[:number]

        unless @config[:enabled]
          display_message("ℹ️  PR change requests are disabled in configuration. Skipping PR ##{number}.", type: :muted)
          return
        end

        # Check clarification round limit
        existing_data = @state_store.change_request_data(number)
        if existing_data && existing_data["clarification_count"].to_i >= MAX_CLARIFICATION_ROUNDS
          display_message("⚠️  Max clarification rounds (#{MAX_CLARIFICATION_ROUNDS}) reached for PR ##{number}. Skipping.", type: :warn)
          post_max_rounds_comment(pr)
          return
        end

        display_message("📝 Processing change request for PR ##{number} (#{pr[:title]})", type: :info)

        # Fetch PR details
        pr_data = @repository_client.fetch_pull_request(number)
        comments = @repository_client.fetch_pr_comments(number)

        # Filter comments from authorized users
        authorized_comments = filter_authorized_comments(comments, pr_data)

        if authorized_comments.empty?
          display_message("ℹ️  No authorized comments found for PR ##{number}. Skipping.", type: :muted)
          return
        end

        # If max_diff_size is set, attempt to fetch and check diff
        # But bypass restriction for worktree-based workflows
        diff = @repository_client.fetch_pull_request_diff(number)
        diff_size = diff.lines.count

        # Check if we want to use the worktree bypass
        use_worktree_bypass = @config[:allow_large_pr_worktree_bypass] || @config[:allow_large_pr_worktree_bypass].nil?

        if diff_size > @config[:max_diff_size] && !use_worktree_bypass
          display_message("⚠️  PR ##{number} diff too large (#{diff_size} lines > #{@config[:max_diff_size]}). Skipping.", type: :warn)
          post_diff_too_large_comment(pr, diff_size)
          return
        end

        # Log the diff size for observability
        Aidp.log_debug("change_request_processor", "PR diff size", number: number, size: diff_size, max_allowed: @config[:max_diff_size], worktree_bypass: use_worktree_bypass)

        # Analyze change requests
        analysis_result = analyze_change_requests(pr_data: pr_data, comments: authorized_comments, diff: diff)

        if analysis_result[:needs_clarification]
          handle_clarification_needed(pr: pr_data, analysis: analysis_result)
        elsif analysis_result[:can_implement]
          implement_changes(pr: pr_data, analysis: analysis_result, diff: diff)
        else
          handle_cannot_implement(pr: pr_data, analysis: analysis_result)
        end
      rescue => e
        display_message("❌ Change request processing failed: #{e.message}", type: :error)
        Aidp.log_error("change_request_processor", "Change request failed", pr: pr[:number], error: e.message, backtrace: e.backtrace&.first(10))

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

        {
          can_implement: parsed["can_implement"],
          needs_clarification: parsed["needs_clarification"],
          clarifying_questions: parsed["clarifying_questions"] || [],
          reason: parsed["reason"],
          changes: parsed["changes"] || []
        }
      rescue JSON::ParserError => e
        Aidp.log_error("change_request_processor", "Failed to parse AI response", error: e.message, content: content)
        {can_implement: false, needs_clarification: false, reason: "Failed to parse AI analysis"}
      rescue => e
        Aidp.log_error("change_request_processor", "AI analysis failed", error: e.message)
        {can_implement: false, needs_clarification: false, reason: "AI analysis error: #{e.message}"}
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
        head_ref = pr_data[:head_ref]
        pr_number = pr_data[:number]

        worktree_path = resolve_worktree_for_pr(pr_data)

        Dir.chdir(worktree_path) do
          run_git(%w[fetch origin], allow_failure: true)
          run_git(["checkout", head_ref])
          run_git(%w[pull --ff-only], allow_failure: true)
        end

        @project_dir = worktree_path

        Aidp.log_debug("change_request_processor", "Checked out PR branch", branch: head_ref, worktree: worktree_path)
        display_message("🌿 Using worktree for PR ##{pr_number}: #{head_ref}", type: :info)
      end

      def resolve_worktree_for_pr(pr_data)
        head_ref = pr_data[:head_ref]
        pr_number = pr_data[:number]

        existing = Aidp::Worktree.find_by_branch(branch: head_ref, project_dir: @project_dir)

        if existing && existing[:active]
          display_message("🔄 Using existing worktree for branch: #{head_ref}", type: :info)
          Aidp.log_debug("change_request_processor", "worktree_reused", pr_number: pr_number, branch: head_ref, path: existing[:path])
          return existing[:path]
        end

        issue_worktree = find_issue_worktree_for_pr(pr_data)
        return issue_worktree if issue_worktree

        create_worktree_for_pr(pr_data)
      end

      def find_issue_worktree_for_pr(pr_data)
        pr_number = pr_data[:number]
        linked_issue_numbers = extract_issue_numbers_from_pr(pr_data)

        build_match = @state_store.find_build_by_pr(pr_number)
        linked_issue_numbers << build_match[:issue_number] if build_match
        linked_issue_numbers = linked_issue_numbers.compact.uniq

        linked_issue_numbers.each do |issue_number|
          workstream = @state_store.workstream_for_issue(issue_number)
          next unless workstream

          slug = workstream[:workstream]
          branch = workstream[:branch]

          if slug
            info = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
            if info && info[:active]
              Aidp.log_debug("change_request_processor", "issue_worktree_reused", pr_number: pr_number, issue_number: issue_number, branch: branch, path: info[:path])
              display_message("🔄 Reusing worktree #{slug} for issue ##{issue_number} (PR ##{pr_number})", type: :info)
              return info[:path]
            end
          end

          if branch
            existing = Aidp::Worktree.find_by_branch(branch: branch, project_dir: @project_dir)
            if existing && existing[:active]
              Aidp.log_debug("change_request_processor", "issue_branch_worktree_reused", pr_number: pr_number, issue_number: issue_number, branch: branch, path: existing[:path])
              display_message("🔄 Reusing branch worktree for issue ##{issue_number}: #{branch}", type: :info)
              return existing[:path]
            end
          end
        end

        nil
      end

      def extract_issue_numbers_from_pr(pr_data)
        body = pr_data[:body].to_s
        issue_matches = body.scan(/(?:Fixes|Resolves|Closes)\s+#(\d+)/i).flatten

        issue_matches.map { |num| num.to_i }.uniq
      end

      def create_worktree_for_pr(pr_data)
        head_ref = pr_data[:head_ref]
        pr_number = pr_data[:number]

        # Configure slug and worktree strategy
        slug = pr_data.fetch(:worktree_slug, "pr-#{pr_number}-change-requests")
        strategy = @config.fetch(:worktree_strategy, "auto")

        display_message("🌿 Preparing worktree for PR ##{pr_number}: #{head_ref} (Strategy: #{strategy})", type: :info)

        # Pre-create setup: fetch latest refs
        Dir.chdir(@project_dir) do
          run_git(%w[fetch origin], allow_failure: true)
        end

        # Worktree creation strategy
        worktree_path =
          case strategy
          when "always_create"
            create_fresh_worktree(pr_data, slug)
          when "reuse_only"
            find_existing_worktree(pr_data, slug)
          else # 'auto' or default
            find_existing_worktree(pr_data, slug) || create_fresh_worktree(pr_data, slug)
          end

        Aidp.log_debug(
          "change_request_processor",
          "worktree_resolved",
          pr_number: pr_number,
          branch: head_ref,
          path: worktree_path,
          strategy: strategy
        )

        display_message("✅ Worktree available at #{worktree_path}", type: :success)
        worktree_path
      rescue => e
        Aidp.log_error(
          "change_request_processor",
          "worktree_creation_failed",
          pr_number: pr_number,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        )
        display_message("❌ Failed to create worktree: #{e.message}", type: :error)
        raise
      end

      private

      def find_existing_worktree(pr_data, slug)
        head_ref = pr_data[:head_ref]
        pr_number = pr_data[:number]

        # First check for existing worktree by branch
        existing = Aidp::Worktree.find_by_branch(branch: head_ref, project_dir: @project_dir)
        return existing[:path] if existing && existing[:active]

        # If no branch-specific worktree, look for PR-specific worktree
        pr_worktrees = Aidp::Worktree.list(project_dir: @project_dir)
        pr_specific_worktree = pr_worktrees.find do |w|
          w[:slug]&.include?("pr-#{pr_number}")
        end

        pr_specific_worktree ? pr_specific_worktree[:path] : nil
      end

      def create_fresh_worktree(pr_data, slug)
        head_ref = pr_data[:head_ref]
        pr_number = pr_data[:number]

        Aidp.log_debug(
          "change_request_processor",
          "creating_new_worktree",
          pr_number: pr_number,
          branch: head_ref,
          slug: slug
        )

        result = Aidp::Worktree.create(
          slug: slug,
          project_dir: @project_dir,
          branch: head_ref,
          base_branch: pr_data[:base_ref]
        )

        result[:path]
      end

      def apply_changes(changes)
        changes.each do |change|
          file_path = File.join(@project_dir, change["file"])

          case change["action"]
          when "create", "edit"
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, change["content"])
            display_message("  ✓ #{change["action"]} #{change["file"]}", type: :muted) if @verbose
            Aidp.log_debug("change_request_processor", "Applied change", action: change["action"], file: change["file"])
          when "delete"
            File.delete(file_path) if File.exist?(file_path)
            display_message("  ✓ Deleted #{change["file"]}", type: :muted) if @verbose
            Aidp.log_debug("change_request_processor", "Deleted file", file: change["file"])
          else
            display_message("  ⚠️  Unknown action: #{change["action"]} for #{change["file"]}", type: :warn)
            Aidp.log_warn("change_request_processor", "Unknown change action", action: change["action"], file: change["file"])
          end
        end
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
          # Check if there are changes
          status_output = run_git(%w[status --porcelain])
          if status_output.strip.empty?
            display_message("ℹ️  No changes to commit after applying changes.", type: :muted)
            return false
          end

          # Stage all changes
          run_git(%w[add -A])

          # Create commit
          commit_message = build_commit_message(pr_data, analysis)
          run_git(["commit", "-m", commit_message])

          display_message("💾 Created commit: #{commit_message.lines.first.strip}", type: :info)
          Aidp.log_debug("change_request_processor", "Created commit", pr: pr_data[:number])

          # Push to origin
          head_ref = pr_data[:head_ref]
          run_git(["push", "origin", head_ref])

          display_message("⬆️  Pushed changes to #{head_ref}", type: :success)
          Aidp.log_info("change_request_processor", "Pushed changes", pr: pr_data[:number], branch: head_ref)
          true
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
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ⚠️  PR diff is too large for default change requests.

          **Current size:** #{diff_size} lines
          **Maximum allowed:** #{@config[:max_diff_size]} lines

          For large PRs, you have several options:
          1. Enable worktree-based large PR handling:
             Set `allow_large_pr_worktree_bypass: true` in your `aidp.yml`
          2. Break the PR into smaller chunks
          3. Implement changes manually
          4. Increase `max_diff_size` in your configuration

          The worktree bypass allows processing large PRs by working directly in the branch
          instead of using diff-based changes.
        COMMENT

        begin
          @repository_client.post_comment(pr[:number], comment)
          @repository_client.remove_labels(pr[:number], @change_request_label)
        rescue
          nil
        end
      end

      def run_git(args, allow_failure: false)
        stdout, stderr, status = Open3.capture3("git", *Array(args))
        raise "git #{args.join(" ")} failed: #{stderr.strip}" unless status.success? || allow_failure
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

      def symbolize_keys(hash)
        return {} unless hash

        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end
    end
  end
end
