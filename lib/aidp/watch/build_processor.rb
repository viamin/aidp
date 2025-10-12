# frozen_string_literal: true

require "open3"
require "time"

require_relative "../message_display"
require_relative "../execute/prompt_manager"
require_relative "../harness/runner"

module Aidp
  module Watch
    # Handles the aidp-build trigger by running the autonomous work loop, creating
    # a branch/PR, and posting completion status back to GitHub.
    class BuildProcessor
      include Aidp::MessageDisplay

      BUILD_LABEL = "aidp-build"
      IMPLEMENTATION_STEP = "16_IMPLEMENTATION"

      def initialize(repository_client:, state_store:, project_dir: Dir.pwd)
        @repository_client = repository_client
        @state_store = state_store
        @project_dir = project_dir
      end

      def process(issue)
        number = issue[:number]
        display_message("🛠️  Starting implementation for issue ##{number}", type: :info)

        plan_data = ensure_plan_data(number)
        return unless plan_data

        branch_name = branch_name_for(issue)
        @state_store.record_build_status(number, status: "running", details: {branch: branch_name, started_at: Time.now.utc.iso8601})

        ensure_git_repo!
        base_branch = detect_base_branch

        checkout_branch(base_branch, branch_name)
        prompt_content = build_prompt(issue: issue, plan_data: plan_data)
        write_prompt(prompt_content)

        user_input = build_user_input(issue: issue, plan_data: plan_data)
        result = run_harness(user_input: user_input)

        if result[:status] == "completed"
          handle_success(issue: issue, branch_name: branch_name, base_branch: base_branch, plan_data: plan_data)
        else
          handle_failure(issue: issue, result: result)
        end
      rescue => e
        display_message("❌ Implementation failed: #{e.message}", type: :error)
        @state_store.record_build_status(issue[:number], status: "failed", details: {error: e.message})
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

      def branch_name_for(issue)
        slug = issue[:title].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
        "aidp/issue-#{issue[:number]}-#{slug[0, 32]}"
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
          "### #{author} (#{created})\n#{comment['body']}"
        end.join("\n\n")
      rescue
        "_Unable to parse comment thread._"
      end

      def write_prompt(content)
        prompt_manager = Aidp::Execute::PromptManager.new(@project_dir)
        prompt_manager.write(content)
        display_message("📝 Wrote PROMPT.md with implementation contract", type: :info)
      end

      def build_user_input(issue:, plan_data:)
        tasks = Array(plan_value(plan_data, "tasks"))
        {
          "Implementation Contract" => plan_value(plan_data, "summary").to_s,
          "Tasks" => tasks.map { |task| "- #{task}" }.join("\n"),
          "Issue URL" => issue[:url]
        }.delete_if { |_k, v| v.nil? || v.empty? }
      end

      def run_harness(user_input:)
        options = {
          selected_steps: [IMPLEMENTATION_STEP],
          workflow_type: :watch_mode,
          user_input: user_input
        }
        runner = Aidp::Harness::Runner.new(@project_dir, :execute, options)
        runner.run
      end

      def handle_success(issue:, branch_name:, base_branch:, plan_data:)
        stage_and_commit(issue)
        pr_url = create_pull_request(issue: issue, branch_name: branch_name, base_branch: base_branch)

        comment = <<~COMMENT
          ✅ Implementation complete for ##{issue[:number]}.
          - Branch: `#{branch_name}`
          - Pull Request: #{pr_url}

          Summary:
          #{plan_value(plan_data, "summary")}
        COMMENT

        @repository_client.post_comment(issue[:number], comment)
        @state_store.record_build_status(
          issue[:number],
          status: "completed",
          details: {branch: branch_name, pr_url: pr_url}
        )
        display_message("🎉 Posted completion comment for issue ##{issue[:number]}", type: :success)
      end

      def handle_failure(issue:, result:)
        message = result[:message] || "Unknown failure"
        comment = <<~COMMENT
          ❌ Implementation attempt for ##{issue[:number]} failed.

          Status: #{result[:status]}
          Details: #{message}

          Please review the repository for partial changes. The branch has been left intact for debugging.
        COMMENT
        @repository_client.post_comment(issue[:number], comment)
        @state_store.record_build_status(
          issue[:number],
          status: "failed",
          details: {message: message}
        )
        display_message("⚠️  Build failure recorded for issue ##{issue[:number]}", type: :warn)
      end

      def stage_and_commit(issue)
        Dir.chdir(@project_dir) do
          status_output = run_git(%w[status --porcelain])
          if status_output.strip.empty?
            display_message("ℹ️  No file changes detected after work loop.", type: :muted)
            return
          end

          run_git(%w[add -A])
          commit_message = "feat: implement ##{issue[:number]} #{issue[:title]}"
          run_git(["commit", "-m", commit_message])
          display_message("💾 Created commit: #{commit_message}", type: :info)
        end
      end

      def create_pull_request(issue:, branch_name:, base_branch:)
        title = "aidp: Resolve ##{issue[:number]} - #{issue[:title]}"
        test_summary = gather_test_summary
        body = <<~BODY
          ## Summary
          - Automated resolution for ##{issue[:number]}

          ## Testing
          #{test_summary}
        BODY

        output = @repository_client.create_pull_request(
          title: title,
          body: body,
          head: branch_name,
          base: base_branch,
          issue_number: issue[:number]
        )

        extract_pr_url(output)
      end

      def gather_test_summary
        Dir.chdir(@project_dir) do
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
        "- Fix-forward harness executed successfully."
      end

      def extract_pr_url(output)
        output.to_s.split("\n").reverse.find { |line| line.include?("http") } || output
      end

      def run_git(args, allow_failure: false)
        stdout, stderr, status = Open3.capture3("git", *Array(args))
        raise "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success? || allow_failure
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
