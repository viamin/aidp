# frozen_string_literal: true

require "open3"
require "time"
require "fileutils"

require_relative "../message_display"
require_relative "../execute/prompt_manager"
require_relative "../harness/runner"
require_relative "../harness/state_manager"
require_relative "../worktree"
require_relative "../execute/progress"

module Aidp
  module Watch
    # Handles the aidp-build trigger by running the autonomous work loop, creating
    # a branch/PR, and posting completion status back to GitHub.
    class BuildProcessor
      include Aidp::MessageDisplay

      DEFAULT_BUILD_LABEL = "aidp-build"
      DEFAULT_NEEDS_INPUT_LABEL = "aidp-needs-input"
      IMPLEMENTATION_STEP = "16_IMPLEMENTATION"

      attr_reader :build_label, :needs_input_label

      def initialize(repository_client:, state_store:, project_dir: Dir.pwd, use_workstreams: true, verbose: false, label_config: {})
        @repository_client = repository_client
        @state_store = state_store
        @project_dir = project_dir
        @use_workstreams = use_workstreams
        @verbose = verbose

        # Load label configuration
        @build_label = label_config[:build_trigger] || label_config["build_trigger"] || DEFAULT_BUILD_LABEL
        @needs_input_label = label_config[:needs_input] || label_config["needs_input"] || DEFAULT_NEEDS_INPUT_LABEL
      end

      def process(issue)
        number = issue[:number]
        display_message("🛠️  Starting implementation for issue ##{number}", type: :info)

        plan_data = ensure_plan_data(number)
        return unless plan_data

        slug = workstream_slug_for(issue)
        branch_name = branch_name_for(issue)
        @state_store.record_build_status(number, status: "running", details: {branch: branch_name, workstream: slug, started_at: Time.now.utc.iso8601})

        ensure_git_repo!
        base_branch = detect_base_branch

        if @use_workstreams
          workstream_path = setup_workstream(slug: slug, branch_name: branch_name, base_branch: base_branch)
          working_dir = workstream_path
        else
          checkout_branch(base_branch, branch_name)
          working_dir = @project_dir
        end

        sync_local_aidp_config(working_dir)

        prompt_content = build_prompt(issue: issue, plan_data: plan_data)
        write_prompt(prompt_content, working_dir: working_dir)

        user_input = build_user_input(issue: issue, plan_data: plan_data)
        result = run_harness(user_input: user_input, working_dir: working_dir)

        if result[:status] == "completed"
          handle_success(issue: issue, slug: slug, branch_name: branch_name, base_branch: base_branch, plan_data: plan_data, working_dir: working_dir)
        elsif result[:status] == "needs_clarification"
          handle_clarification_request(issue: issue, slug: slug, result: result)
        elsif result[:reason] == :completion_criteria
          handle_incomplete_criteria(issue: issue, slug: slug, branch_name: branch_name, working_dir: working_dir, metadata: result[:failure_metadata])
        else
          handle_failure(issue: issue, slug: slug, result: result)
        end
      rescue => e
        # Don't re-raise - handle gracefully for fix-forward pattern
        display_message("❌ Implementation failed with exception: #{e.message}", type: :error)
        Aidp.log_error(
          "build_processor",
          "Implementation failed with exception",
          issue: issue[:number],
          error: e.message,
          error_class: e.class.name,
          backtrace: e.backtrace&.first(10)
        )

        # Record failure state internally but DON'T post error to GitHub
        # (per issue #280 - error messages should never appear on issues)
        @state_store.record_build_status(
          issue[:number],
          status: "error",
          details: {
            error: e.message,
            error_class: e.class.name,
            workstream: slug,
            timestamp: Time.now.utc.iso8601
          }
        )

        # Note: We intentionally DON'T re-raise here to allow watch mode to continue
        # The error has been logged and recorded internally
      end

      private

      def ensure_plan_data(number)
        data = @state_store.plan_data(number)
        unless data
          display_message("⚠️  No recorded plan for issue ##{number}. Skipping build trigger.", type: :warn)
        end
        data
      end

      def ensure_git_repo!
        Dir.chdir(@project_dir) do
          stdout, stderr, status = Open3.capture3("git", "rev-parse", "--is-inside-work-tree")
          raise "Not a git repository: #{stderr.strip}" unless status.success? && stdout.strip == "true"
        end
      end

      def detect_base_branch
        Dir.chdir(@project_dir) do
          stdout, _stderr, status = Open3.capture3("git", "symbolic-ref", "refs/remotes/origin/HEAD")
          if status.success?
            ref = stdout.strip
            return ref.split("/").last if ref.include?("/")
          end

          %w[main master trunk].find do |candidate|
            _out, _err, branch_status = Open3.capture3("git", "rev-parse", "--verify", candidate)
            branch_status.success?
          end || "main"
        end
      end

      def checkout_branch(base_branch, branch_name)
        Dir.chdir(@project_dir) do
          run_git(%w[fetch origin], allow_failure: true)
          run_git(["checkout", base_branch])
          run_git(%w[pull --ff-only], allow_failure: true)
          run_git(["checkout", "-B", branch_name])
        end
        display_message("🌿 Checked out #{branch_name}", type: :info)
      end

      def workstream_slug_for(issue)
        slug = issue[:title].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
        "issue-#{issue[:number]}-#{slug[0, 32]}"
      end

      def branch_name_for(issue)
        "aidp/#{workstream_slug_for(issue)}"
      end

      def setup_workstream(slug:, branch_name:, base_branch:)
        # Check if workstream already exists
        existing = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
        if existing
          display_message("🔄 Reusing existing workstream: #{slug}", type: :info)
          Dir.chdir(existing[:path]) do
            run_git(["checkout", existing[:branch]])
            run_git(%w[pull --ff-only], allow_failure: true)
          end
          return existing[:path]
        end

        # Create new workstream
        display_message("🌿 Creating workstream: #{slug}", type: :info)
        result = Aidp::Worktree.create(
          slug: slug,
          project_dir: @project_dir,
          branch: branch_name,
          base_branch: base_branch
        )

        worktree_path = worktree_path_from_result(result)
        display_message("✅ Workstream created at #{worktree_path}", type: :success)
        worktree_path
      end

      def cleanup_workstream(slug)
        return unless slug

        display_message("🧹 Cleaning up workstream: #{slug}", type: :info)
        result = Aidp::Worktree.remove(slug: slug, project_dir: @project_dir, delete_branch: true)
        removed = (result == true) || (result.respond_to?(:[]) && result[:success])
        if removed
          display_message("✅ Workstream removed", type: :success)
        else
          display_message("⚠️  Failed to remove workstream: #{result[:message]}", type: :warn)
        end
      rescue => e
        display_message("⚠️  Error cleaning up workstream: #{e.message}", type: :warn)
      end

      def build_prompt(issue:, plan_data:)
        lines = []
        lines << "# Implementation Contract for Issue ##{issue[:number]}"
        lines << ""
        lines << "## Summary"
        lines << plan_value(plan_data, "summary").to_s.strip
        lines << ""
        lines << "## Tasks"
        Array(plan_value(plan_data, "tasks")).each do |task|
          lines << "- [ ] #{task}"
        end
        lines << "" unless Array(plan_value(plan_data, "tasks")).empty?
        lines << "## Clarifying Answers / Notes"
        lines << clarifications_from_comments(issue[:comments], plan_data)
        lines << ""
        lines << "## Original Issue Body"
        lines << issue[:body].to_s
        lines.join("\n")
      end

      def clarifications_from_comments(comments, plan_data)
        return "_No additional context provided._" if comments.nil? || comments.empty?

        comment_hint = plan_value(plan_data, "comment_hint")
        relevant = comments.reject do |comment|
          body = comment["body"].to_s
          comment_hint && body.start_with?(comment_hint)
        end

        return "_No follow-up responses yet._" if relevant.empty?

        relevant.map do |comment|
          author = comment["author"] || "unknown"
          created = comment["createdAt"] ? Time.parse(comment["createdAt"]).utc.iso8601 : "unknown"
          body = strip_archived_plans(comment["body"])
          "### #{author} (#{created})\n#{body}"
        end.join("\n\n")
      rescue
        "_Unable to parse comment thread._"
      end

      def strip_archived_plans(content)
        return content unless content

        # Remove all archived plan sections (wrapped in HTML comments)
        result = content.dup

        # Remove archived plan blocks
        # Safe string-based approach to avoid ReDoS vulnerabilities
        start_prefix = "<!-- ARCHIVED_PLAN_START"
        end_marker = "<!-- ARCHIVED_PLAN_END -->"

        loop do
          # Find the start of an archived plan block (may have attributes after ARCHIVED_PLAN_START)
          start_idx = result.index(start_prefix)
          break unless start_idx

          # Find the closing --> of the start marker
          start_marker_end = result.index("-->", start_idx)
          break unless start_marker_end

          # Find the corresponding end marker
          end_idx = result.index(end_marker, start_marker_end)
          break unless end_idx

          # Remove the entire block including markers
          result = result[0...start_idx] + result[(end_idx + end_marker.length)..]
        end

        # Remove HTML-commented sections from active plan
        # Keep the content between START and END markers, but strip the markers themselves
        # This preserves the current plan while removing archived content
        result = result.gsub(/<!-- (PLAN_SUMMARY_START|PLAN_TASKS_START|CLARIFYING_QUESTIONS_START) -->/, "")
        result = result.gsub(/<!-- (PLAN_SUMMARY_END|PLAN_TASKS_END|CLARIFYING_QUESTIONS_END) -->/, "")

        # Clean up any extra blank lines
        result.gsub(/\n{3,}/, "\n\n").strip
      end

      def write_prompt(content, working_dir: @project_dir)
        prompt_manager = Aidp::Execute::PromptManager.new(working_dir)
        prompt_manager.write(content, step_name: IMPLEMENTATION_STEP)
        display_message("📝 Wrote PROMPT.md with implementation contract", type: :info)

        if @verbose
          display_message("\n--- Implementation Prompt ---", type: :muted)
          display_message(content.strip, type: :muted)
          display_message("--- End Prompt ---\n", type: :muted)
        end
      end

      def build_user_input(issue:, plan_data:)
        tasks = Array(plan_value(plan_data, "tasks"))
        user_input = {
          "Implementation Contract" => plan_value(plan_data, "summary").to_s,
          "Tasks" => tasks.map { |task| "- #{task}" }.join("\n"),
          "Issue URL" => issue[:url]
        }.delete_if { |_k, v| v.nil? || v.empty? }

        if @verbose
          display_message("\n--- User Input for Harness ---", type: :muted)
          user_input.each do |key, value|
            display_message("#{key}:", type: :muted)
            display_message(value, type: :muted)
            display_message("", type: :muted)
          end
          display_message("--- End User Input ---\n", type: :muted)
        end

        user_input
      end

      def run_harness(user_input:, working_dir: @project_dir)
        reset_work_loop_state(working_dir)

        Aidp.log_info(
          "build_processor",
          "starting_harness",
          issue_dir: working_dir,
          workflow_type: :watch_mode,
          selected_steps: [IMPLEMENTATION_STEP]
        )

        options = {
          selected_steps: [IMPLEMENTATION_STEP],
          workflow_type: :watch_mode,
          user_input: user_input,
          non_interactive: true
        }

        display_message("🚀 Running harness in execute mode...", type: :info) if @verbose

        runner = Aidp::Harness::Runner.new(working_dir, :execute, options)
        result = runner.run

        if @verbose
          display_message("\n--- Harness Result ---", type: :muted)
          display_message("Status: #{result[:status]}", type: :muted)
          display_message("Message: #{result[:message]}", type: :muted) if result[:message]
          if result[:error]
            display_message("Error: #{result[:error]}", type: :muted)
            display_message("Error Details: #{result[:error_details]}", type: :muted) if result[:error_details]
          end
          display_message("--- End Result ---\n", type: :muted)
        end

        Aidp.log_info(
          "build_processor",
          "harness_result",
          status: result[:status],
          message: result[:message],
          error: result[:error],
          error_class: result[:error_class]
        )

        # Log errors to aidp.log
        if result[:status] == "error"
          error_msg = result[:message] || "Unknown error"
          error_details = {
            status: result[:status],
            message: error_msg,
            error: result[:error]&.to_s,
            error_class: result[:error]&.class&.name,
            backtrace: result[:backtrace]&.first(5)
          }.compact
          Aidp.log_error("build_processor", "Harness execution failed", **error_details)
        end

        result
      end

      def reset_work_loop_state(working_dir)
        state_manager = Aidp::Harness::StateManager.new(working_dir, :execute)
        state_manager.clear_state
        Aidp::Execute::Progress.new(working_dir).reset
      rescue => e
        display_message("⚠️  Failed to reset work loop state before execution: #{e.message}", type: :warn)
        Aidp.log_warn("build_processor", "failed_to_reset_work_loop_state", error: e.message, working_dir: working_dir)
      end

      def enqueue_decider_followup(target_dir)
        work_loop_dir = File.join(target_dir, ".aidp", "work_loop")
        FileUtils.mkdir_p(work_loop_dir)
        request_path = File.join(work_loop_dir, "initial_units.txt")
        File.open(request_path, "a") { |file| file.puts("decide_whats_next") }
        Aidp.log_info("build_processor", "scheduled_decider_followup", request_path: request_path)
      rescue => e
        Aidp.log_warn("build_processor", "failed_to_schedule_decider", error: e.message)
      end

      def sync_local_aidp_config(target_dir)
        return if target_dir.nil? || target_dir == @project_dir

        source_config = File.join(@project_dir, ".aidp", "aidp.yml")
        return unless File.exist?(source_config)

        target_config = File.join(target_dir, ".aidp", "aidp.yml")
        FileUtils.mkdir_p(File.dirname(target_config))

        # Only copy when target missing or differs
        if !File.exist?(target_config) || File.read(source_config, encoding: "UTF-8") != File.read(target_config, encoding: "UTF-8")
          FileUtils.cp(source_config, target_config)
        end
      rescue => e
        display_message("⚠️  Failed to sync AIDP config to workstream: #{e.message}", type: :warn)
      end

      def worktree_path_from_result(result)
        return result if result.is_a?(String)

        path = result[:path] || result["path"]
        return path if path

        message = result[:message] || "unknown error"
        raise "Failed to create workstream: #{message}"
      end

      def handle_success(issue:, slug:, branch_name:, base_branch:, plan_data:, working_dir:)
        changes_committed = stage_and_commit(issue, working_dir: working_dir)

        unless changes_committed
          handle_no_changes(issue: issue, slug: slug, branch_name: branch_name, working_dir: working_dir)
          return
        end

        # Check if PR should be created based on VCS preferences
        # For watch mode, default to creating PRs (set to false to disable)
        vcs_config = config_dig(:work_loop, :version_control) || {}
        auto_create_pr = config_value(vcs_config, :auto_create_pr, true)

        pr_url = if !changes_committed
          Aidp.log_info(
            "build_processor",
            "skipping_pr_no_commits",
            issue: issue[:number],
            branch: branch_name,
            working_dir: working_dir
          )
          display_message("ℹ️  Skipping PR creation because there are no commits on #{branch_name}.", type: :muted)
          nil
        elsif auto_create_pr
          Aidp.log_info(
            "build_processor",
            "creating_pull_request",
            issue: issue[:number],
            branch: branch_name,
            base_branch: base_branch,
            working_dir: working_dir
          )
          create_pull_request(issue: issue, branch_name: branch_name, base_branch: base_branch, working_dir: working_dir)
        else
          display_message("ℹ️  Skipping PR creation (disabled in VCS preferences)", type: :muted)
          nil
        end

        # Fetch the user who added the most recent label
        label_actor = @repository_client.most_recent_label_actor(issue[:number])

        workstream_note = @use_workstreams ? "\n- Workstream: `#{slug}`" : ""
        pr_line = pr_url ? "\n- Pull Request: #{pr_url}" : ""
        actor_tag = label_actor ? "cc @#{label_actor}\n\n" : ""

        comment = <<~COMMENT
          ✅ Implementation complete for ##{issue[:number]}.

          #{actor_tag}- Branch: `#{branch_name}`#{workstream_note}#{pr_line}

          Summary:
          #{plan_value(plan_data, "summary")}
        COMMENT

        @repository_client.post_comment(issue[:number], comment)
        @state_store.record_build_status(
          issue[:number],
          status: "completed",
          details: {branch: branch_name, workstream: slug, pr_url: pr_url}
        )
        display_message("🎉 Posted completion comment for issue ##{issue[:number]}", type: :success)

        # Remove build label after successful completion
        begin
          @repository_client.remove_labels(issue[:number], @build_label)
          display_message("🏷️  Removed '#{@build_label}' label after completion", type: :info)
        rescue => e
          display_message("⚠️  Failed to remove build label: #{e.message}", type: :warn)
          # Don't fail the process if label removal fails
        end

        # Keep workstream for review - don't auto-cleanup on success
        if @use_workstreams
          display_message("ℹ️  Workstream #{slug} preserved for review. Remove with: aidp ws rm #{slug}", type: :muted)
        end
      end

      def handle_clarification_request(issue:, slug:, result:)
        questions = result[:clarification_questions] || []
        workstream_note = @use_workstreams ? " The workstream `#{slug}` has been preserved." : " The branch has been preserved."

        # Fetch the user who added the most recent label
        label_actor = @repository_client.most_recent_label_actor(issue[:number])

        # Build comment with questions
        comment_parts = []
        comment_parts << "❓ Implementation needs clarification for ##{issue[:number]}."
        comment_parts << ""

        # Tag the label actor if available
        if label_actor
          comment_parts << "cc @#{label_actor}"
          comment_parts << ""
        end

        comment_parts << "The AI agent needs additional information to proceed with implementation:"
        comment_parts << ""
        questions.each_with_index do |question, index|
          comment_parts << "#{index + 1}. #{question}"
        end
        comment_parts << ""
        comment_parts << "**Next Steps**: Please reply with answers to the questions above. Once resolved, remove the `#{@needs_input_label}` label and add the `#{@build_label}` label to resume implementation."
        comment_parts << ""
        comment_parts << workstream_note.to_s

        comment = comment_parts.join("\n")
        @repository_client.post_comment(issue[:number], comment)

        # Update labels: remove build trigger, add needs input
        begin
          @repository_client.replace_labels(
            issue[:number],
            old_labels: [@build_label],
            new_labels: [@needs_input_label]
          )
          display_message("🏷️  Updated labels: removed '#{@build_label}', added '#{@needs_input_label}' (needs clarification)", type: :info)
        rescue => e
          display_message("⚠️  Failed to update labels for issue ##{issue[:number]}: #{e.message}", type: :warn)
        end

        @state_store.record_build_status(
          issue[:number],
          status: "needs_clarification",
          details: {questions: questions, workstream: slug}
        )
        display_message("💬 Posted clarification request for issue ##{issue[:number]}", type: :success)
      end

      def handle_failure(issue:, slug:, result:)
        message = result[:message] || "Unknown failure"
        error_info = result[:error] || result[:error_details]
        workstream_note = @use_workstreams ? " The workstream `#{slug}` has been left intact for debugging." : " The branch has been left intact for debugging."

        # Build detailed error message for the comment
        error_details_section = if error_info
          "\nError: #{error_info}"
        else
          ""
        end

        comment = <<~COMMENT
          ❌ Implementation attempt for ##{issue[:number]} failed.

          Status: #{result[:status]}
          Details: #{message}#{error_details_section}

          Please review the repository for partial changes.#{workstream_note}
        COMMENT
        @repository_client.post_comment(issue[:number], comment)

        # Log the failure with full details
        Aidp.log_error(
          "build_processor",
          "Build failed for issue ##{issue[:number]}",
          status: result[:status],
          message: message,
          error: error_info&.to_s,
          workstream: slug
        )

        @state_store.record_build_status(
          issue[:number],
          status: "failed",
          details: {message: message, error: error_info&.to_s, workstream: slug}
        )
        display_message("⚠️  Build failure recorded for issue ##{issue[:number]}", type: :warn)
      end

      def handle_no_changes(issue:, slug:, branch_name:, working_dir:)
        location_note = if @use_workstreams
          "The workstream `#{slug}` has been preserved for review."
        else
          "Branch `#{branch_name}` remains checked out for inspection."
        end

        @state_store.record_build_status(
          issue[:number],
          status: "no_changes",
          details: {branch: branch_name, workstream: slug}
        )

        Aidp.log_warn(
          "build_processor",
          "noop_build_result",
          issue: issue[:number],
          branch: branch_name,
          workstream: slug
        )

        display_message("⚠️  Implementation produced no changes; labels remain untouched. #{location_note}", type: :warn)
        enqueue_decider_followup(working_dir)
      end

      def handle_incomplete_criteria(issue:, slug:, branch_name:, working_dir:, metadata:)
        display_message("⚠️  Completion criteria unmet; scheduling additional fix-forward iteration.", type: :warn)
        enqueue_decider_followup(working_dir)

        @state_store.record_build_status(
          issue[:number],
          status: "pending_fix_forward",
          details: {branch: branch_name, workstream: slug, criteria: metadata}
        )

        Aidp.log_info(
          "build_processor",
          "pending_fix_forward",
          issue: issue[:number],
          branch: branch_name,
          workstream: slug,
          criteria: metadata
        )
      end

      def stage_and_commit(issue, working_dir: @project_dir)
        commit_created = false

        Dir.chdir(working_dir) do
          status_output = run_git(%w[status --porcelain])
          if status_output.strip.empty?
            display_message("ℹ️  No file changes detected after work loop.", type: :muted)
            Aidp.log_info("build_processor", "no_changes_after_work_loop", issue: issue[:number], working_dir: working_dir)
            return commit_created
          end

          changed_entries = status_output.lines.map(&:strip).reject(&:empty?)
          Aidp.log_info(
            "build_processor",
            "changes_detected_after_work_loop",
            issue: issue[:number],
            working_dir: working_dir,
            changed_file_count: changed_entries.length,
            changed_files_sample: changed_entries.first(10)
          )

          run_git(%w[add -A])
          commit_message = build_commit_message(issue)
          run_git(["commit", "-m", commit_message])
          display_message("💾 Created commit: #{commit_message.lines.first.strip}", type: :info)
          Aidp.log_info(
            "build_processor",
            "commit_created",
            working_dir: working_dir,
            issue: issue[:number],
            commit_summary: commit_message.lines.first.strip
          )

          # Push the branch to remote
          current_branch = run_git(%w[branch --show-current]).strip
          run_git(["push", "-u", "origin", current_branch])
          display_message("⬆️  Pushed branch '#{current_branch}' to remote", type: :info)
          Aidp.log_info("build_processor", "branch_pushed", branch: current_branch, working_dir: working_dir)
          commit_created = true
        end

        commit_created
      end

      def build_commit_message(issue)
        vcs_config = config_dig(:work_loop, :version_control) || {}

        # Base message components
        issue_ref = "##{issue[:number]}"
        title = issue[:title]

        # Determine commit prefix based on configuration
        prefix = if config_value(vcs_config, :conventional_commits)
          commit_style = config_value(vcs_config, :commit_style, "default")
          emoji = (commit_style == "emoji") ? "✨ " : ""
          scope = (commit_style == "angular") ? "(implementation)" : ""
          "#{emoji}feat#{scope}: "
        else
          ""
        end

        # Build main message
        main_message = "#{prefix}implement #{issue_ref} #{title}"

        # Add co-author attribution if configured
        if config_value(vcs_config, :co_author_ai, true)
          provider_name = detect_current_provider || "AI Agent"
          co_author = "\n\nCo-authored-by: #{provider_name} <ai@aidp.dev>"
          main_message + co_author
        else
          main_message
        end
      end

      def detect_current_provider
        # Attempt to detect which provider is being used
        # This is a best-effort detection
        config_manager = Aidp::Harness::ConfigManager.new(@project_dir)
        default_provider = config_manager.config.dig(:harness, :default_provider)
        default_provider&.capitalize
      rescue
        nil
      end

      def config
        @config ||= begin
          config_manager = Aidp::Harness::ConfigManager.new(@project_dir)
          config_manager.config || {}
        rescue => e
          Aidp.log_error("build_processor", "config_load_exception", project_dir: @project_dir, error: e.message, backtrace: e.backtrace&.first(5))
          {}
        end
      end

      # Helper to safely dig into config with both string and symbol keys
      def config_dig(*keys)
        value = config
        keys.each do |key|
          return nil unless value.is_a?(Hash)
          # Try both symbol and string versions of the key
          value = value[key] || value[key.to_s] || value[key.to_sym]
          return nil if value.nil?
        end
        value
      end

      # Helper to get config value with both string and symbol key support
      def config_value(hash, key, default = nil)
        return default unless hash.is_a?(Hash)
        # Check each key variation explicitly to handle false/nil values correctly
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)
        return hash[key.to_sym] if hash.key?(key.to_sym)
        default
      end

      def create_pull_request(issue:, branch_name:, base_branch:, working_dir: @project_dir)
        title = "aidp: Resolve ##{issue[:number]} - #{issue[:title]}"
        test_summary = gather_test_summary(working_dir: working_dir)
        body = <<~BODY
          Fixes ##{issue[:number]}

          ## Summary
          - Automated resolution for ##{issue[:number]}

          ## Testing
          #{test_summary}
        BODY

        # Determine if PR should be draft based on VCS preferences
        vcs_config = config_dig(:work_loop, :version_control) || {}
        pr_strategy = config_value(vcs_config, :pr_strategy, "draft")
        draft = (pr_strategy == "draft")

        # Fetch the user who added the most recent label to assign the PR
        label_actor = @repository_client.most_recent_label_actor(issue[:number])
        assignee = label_actor || issue[:author]

        Aidp.log_info(
          "build_processor",
          "assigning_pr",
          issue: issue[:number],
          assignee: assignee,
          label_actor: label_actor,
          fallback_to_author: label_actor.nil?
        )

        Aidp.log_debug(
          "build_processor",
          "attempting_pr_creation",
          issue: issue[:number],
          branch_name: branch_name,
          base_branch: base_branch,
          draft: draft,
          assignee: assignee,
          gh_available: @repository_client.gh_available?
        )

        output = @repository_client.create_pull_request(
          title: title,
          body: body,
          head: branch_name,
          base: base_branch,
          issue_number: issue[:number],
          draft: draft,
          assignee: assignee
        )

        pr_url = extract_pr_url(output)
        Aidp.log_info(
          "build_processor",
          "pull_request_created",
          issue: issue[:number],
          branch: branch_name,
          base_branch: base_branch,
          pr_url: pr_url,
          assignee: assignee
        )
        pr_url
      rescue => e
        Aidp.log_error(
          "build_processor",
          "pr_creation_failed",
          issue: issue[:number],
          branch_name: branch_name,
          base_branch: base_branch,
          error: e.message,
          error_class: e.class.name,
          gh_available: @repository_client.gh_available?
        )
        display_message("⚠️  Failed to create pull request: #{e.message}", type: :warn)
        nil
      end

      def gather_test_summary(working_dir: @project_dir)
        Dir.chdir(working_dir) do
          log_path = File.join(".aidp", "logs", "test_runner.log")
          return "- Fix-forward harness executed; refer to #{log_path}" unless File.exist?(log_path)

          recent = File.readlines(log_path, encoding: "UTF-8").last(20).map(&:strip).reject(&:empty?)
          if recent.empty?
            "- Fix-forward harness executed successfully."
          else
            "- Recent test output:\n" + recent.map { |line| "  - #{line}" }.join("\n")
          end
        end
      rescue
        "- Fix-forward harness extracted successfully."
      end

      def extract_pr_url(output)
        output.to_s.split("\n").reverse.find { |line| line.include?("http") } || output
      end

      def run_git(args, allow_failure: false)
        stdout, stderr, status = Open3.capture3("git", *Array(args))
        raise "git #{args.join(" ")} failed: #{stderr.strip}" unless status.success? || allow_failure
        stdout
      end

      def plan_value(plan_data, key)
        return nil unless plan_data

        symbol_key = key.to_sym
        string_key = key.to_s
        plan_data[symbol_key] || plan_data[string_key]
      end
    end
  end
end
