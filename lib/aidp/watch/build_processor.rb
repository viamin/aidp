# frozen_string_literal: true

require "open3"
require "time"
require "fileutils"

require_relative "../message_display"
require_relative "../execute/prompt_manager"
require_relative "../harness/runner"
require_relative "../worktree"

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
        else
          handle_failure(issue: issue, slug: slug, result: result)
        end
      rescue => e
        display_message("❌ Implementation failed: #{e.message}", type: :error)
        Aidp.log_error(
          "build_processor",
          "Implementation failed with exception",
          issue: issue[:number],
          error: e.message,
          error_class: e.class.name,
          backtrace: e.backtrace&.first(10)
        )
        @state_store.record_build_status(
          issue[:number],
          status: "failed",
          details: {error: e.message, error_class: e.class.name, backtrace: e.backtrace&.first(3)}
        )
        cleanup_workstream(slug) if @use_workstreams && slug
        raise
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
          "### #{author} (#{created})\n#{comment["body"]}"
        end.join("\n\n")
      rescue
        "_Unable to parse comment thread._"
      end

      def write_prompt(content, working_dir: @project_dir)
        prompt_manager = Aidp::Execute::PromptManager.new(working_dir)
        prompt_manager.write(content)
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
        options = {
          selected_steps: [IMPLEMENTATION_STEP],
          workflow_type: :watch_mode,
          user_input: user_input
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

      def sync_local_aidp_config(target_dir)
        return if target_dir.nil? || target_dir == @project_dir

        source_config = File.join(@project_dir, ".aidp", "aidp.yml")
        return unless File.exist?(source_config)

        target_config = File.join(target_dir, ".aidp", "aidp.yml")
        FileUtils.mkdir_p(File.dirname(target_config))

        # Only copy when target missing or differs
        if !File.exist?(target_config) || File.read(source_config) != File.read(target_config)
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
        stage_and_commit(issue, working_dir: working_dir)

        # Check if PR should be created based on VCS preferences
        # For watch mode, default to creating PRs (set to false to disable)
        vcs_config = config.dig(:work_loop, :version_control) || {}
        auto_create_pr = vcs_config.fetch(:auto_create_pr, true)

        pr_url = if auto_create_pr
          create_pull_request(issue: issue, branch_name: branch_name, base_branch: base_branch, working_dir: working_dir)
        else
          display_message("ℹ️  Skipping PR creation (disabled in VCS preferences)", type: :muted)
          nil
        end

        workstream_note = @use_workstreams ? "\n- Workstream: `#{slug}`" : ""
        pr_line = pr_url ? "\n- Pull Request: #{pr_url}" : ""

        comment = <<~COMMENT
          ✅ Implementation complete for ##{issue[:number]}.
          - Branch: `#{branch_name}`#{workstream_note}#{pr_line}

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

        # Build comment with questions
        comment_parts = []
        comment_parts << "❓ Implementation needs clarification for ##{issue[:number]}."
        comment_parts << ""
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

      def stage_and_commit(issue, working_dir: @project_dir)
        Dir.chdir(working_dir) do
          status_output = run_git(%w[status --porcelain])
          if status_output.strip.empty?
            display_message("ℹ️  No file changes detected after work loop.", type: :muted)
            return
          end

          run_git(%w[add -A])
          commit_message = build_commit_message(issue)
          run_git(["commit", "-m", commit_message])
          display_message("💾 Created commit: #{commit_message.lines.first.strip}", type: :info)
        end
      end

      def build_commit_message(issue)
        vcs_config = config.dig(:work_loop, :version_control) || {}

        # Base message components
        issue_ref = "##{issue[:number]}"
        title = issue[:title]

        # Determine commit prefix based on configuration
        prefix = if vcs_config[:conventional_commits]
          commit_style = vcs_config[:commit_style] || "default"
          emoji = (commit_style == "emoji") ? "✨ " : ""
          scope = (commit_style == "angular") ? "(implementation)" : ""
          "#{emoji}feat#{scope}: "
        else
          ""
        end

        # Build main message
        main_message = "#{prefix}implement #{issue_ref} #{title}"

        # Add co-author attribution if configured
        if vcs_config.fetch(:co_author_ai, true)
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
        rescue
          {}
        end
      end

      def create_pull_request(issue:, branch_name:, base_branch:, working_dir: @project_dir)
        title = "aidp: Resolve ##{issue[:number]} - #{issue[:title]}"
        test_summary = gather_test_summary(working_dir: working_dir)
        body = <<~BODY
          ## Summary
          - Automated resolution for ##{issue[:number]}

          ## Testing
          #{test_summary}
        BODY

        # Determine if PR should be draft based on VCS preferences
        vcs_config = config.dig(:work_loop, :version_control) || {}
        pr_strategy = vcs_config[:pr_strategy] || "draft"
        draft = (pr_strategy == "draft")

        # Assign PR to the issue author
        assignee = issue[:author]

        output = @repository_client.create_pull_request(
          title: title,
          body: body,
          head: branch_name,
          base: base_branch,
          issue_number: issue[:number],
          draft: draft,
          assignee: assignee
        )

        extract_pr_url(output)
      end

      def gather_test_summary(working_dir: @project_dir)
        Dir.chdir(working_dir) do
          log_path = File.join(".aidp", "logs", "test_runner.log")
          return "- Fix-forward harness executed; refer to #{log_path}" unless File.exist?(log_path)

          recent = File.readlines(log_path).last(20).map(&:strip).reject(&:empty?)
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
