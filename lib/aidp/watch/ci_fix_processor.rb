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

module Aidp
  module Watch
    # Handles the aidp-fix-ci label trigger by analyzing CI failures
    # and automatically fixing them with commits pushed to the PR branch.
    class CiFixProcessor
      include Aidp::MessageDisplay

      # Default label names
      DEFAULT_CI_FIX_LABEL = "aidp-fix-ci"

      COMMENT_HEADER = "## 🤖 AIDP CI Fix"
      MAX_FIX_ATTEMPTS = 3

      attr_reader :ci_fix_label

      def initialize(repository_client:, state_store:, provider_name: nil, project_dir: Dir.pwd, label_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @provider_name = provider_name
        @project_dir = project_dir
        @verbose = verbose

        # Load label configuration
        @ci_fix_label = label_config[:ci_fix_trigger] || label_config["ci_fix_trigger"] || DEFAULT_CI_FIX_LABEL
      end

      def process(pr)
        number = pr[:number]

        # Check if already processed successfully
        if @state_store.ci_fix_completed?(number)
          display_message("ℹ️  CI fix for PR ##{number} already completed. Skipping.", type: :muted)
          return
        end

        display_message("🔧 Analyzing CI failures for PR ##{number} (#{pr[:title]})", type: :info)

        # Fetch PR details
        pr_data = @repository_client.fetch_pull_request(number)
        ci_status = @repository_client.fetch_ci_status(number)

        # Check if there are failures
        if ci_status[:state] == "success"
          display_message("✅ CI is passing for PR ##{number}. No fixes needed.", type: :success)
          post_success_comment(pr_data)
          @state_store.record_ci_fix(number, {status: "no_failures", timestamp: Time.now.utc.iso8601})
          begin
            @repository_client.remove_labels(number, @ci_fix_label)
          rescue StandardError
            nil
          end
          return
        end

        if ci_status[:state] == "pending"
          display_message("⏳ CI is still running for PR ##{number}. Skipping for now.", type: :muted)
          return
        end

        # Get failed checks
        failed_checks = ci_status[:checks].select { |check| check[:conclusion] == "failure" }

        if failed_checks.empty?
          display_message("⚠️  No specific failed checks found for PR ##{number}.", type: :warn)
          return
        end

        display_message("Found #{failed_checks.length} failed check(s):", type: :info)
        failed_checks.each do |check|
          display_message("  - #{check[:name]}", type: :muted)
        end

        # Analyze failures and generate fixes
        fix_result = analyze_and_fix(pr_data: pr_data, ci_status: ci_status, failed_checks: failed_checks)

        # Log the fix attempt
        log_ci_fix(number, fix_result)

        if fix_result[:success]
          handle_success(pr: pr_data, fix_result: fix_result)
        else
          handle_failure(pr: pr_data, fix_result: fix_result)
        end
      rescue => e
        display_message("❌ CI fix failed: #{e.message}", type: :error)
        Aidp.log_error("ci_fix_processor", "CI fix failed", pr: pr[:number], error: e.message, backtrace: e.backtrace&.first(10))

        # Post error comment
        error_comment = <<~COMMENT
          #{COMMENT_HEADER}

          ❌ Automated CI fix failed: #{e.message}

          Please investigate the CI failures manually or retry by re-adding the `#{@ci_fix_label}` label.
        COMMENT
        begin
          @repository_client.post_comment(pr[:number], error_comment)
        rescue StandardError
          nil
        end
      end

      private

      def analyze_and_fix(pr_data:, ci_status:, failed_checks:)
        # Fetch logs for failed checks (if available)
        failure_details = failed_checks.map do |check|
          {
            name: check[:name],
            conclusion: check[:conclusion],
            output: check[:output],
            details_url: check[:details_url]
          }
        end

        # Use AI to analyze failures and propose fixes
        analysis = analyze_failures_with_ai(pr_data: pr_data, failures: failure_details)

        if analysis[:can_fix]
          # Checkout the PR branch and apply fixes
          checkout_pr_branch(pr_data)

          # Apply the proposed fixes
          apply_fixes(analysis[:fixes])

          # Commit and push
          if commit_and_push(pr_data, analysis)
            {success: true, analysis: analysis, commit_created: true}
          else
            {success: false, analysis: analysis, reason: "No changes to commit"}
          end
        else
          {success: false, analysis: analysis, reason: analysis[:reason] || "Cannot automatically fix"}
        end
      rescue => e
        {success: false, error: e.message, backtrace: e.backtrace&.first(5)}
      end

      def analyze_failures_with_ai(pr_data:, failures:)
        provider_name = @provider_name || detect_default_provider
        provider = Aidp::ProviderManager.get_provider(provider_name, use_harness: false)

        user_prompt = build_ci_analysis_prompt(pr_data: pr_data, failures: failures)
        full_prompt = "#{ci_fix_system_prompt}\n\n#{user_prompt}"

        response = provider.send_message(prompt: full_prompt)
        content = response.to_s.strip

        # Extract JSON from response (handle code fences)
        json_content = extract_json(content)

        # Parse JSON response
        parsed = JSON.parse(json_content)

        {
          can_fix: parsed["can_fix"],
          reason: parsed["reason"],
          root_causes: parsed["root_causes"] || [],
          fixes: parsed["fixes"] || []
        }
      rescue JSON::ParserError => e
        Aidp.log_error("ci_fix_processor", "Failed to parse AI response", error: e.message, content: content)
        {can_fix: false, reason: "Failed to parse AI analysis"}
      rescue => e
        Aidp.log_error("ci_fix_processor", "AI analysis failed", error: e.message)
        {can_fix: false, reason: "AI analysis error: #{e.message}"}
      end

      def ci_fix_system_prompt
        <<~PROMPT
          You are an expert CI/CD troubleshooter. Your task is to analyze CI failures and propose fixes.

          Analyze the provided CI failure information and respond in JSON format:
          {
            "can_fix": true/false,
            "reason": "Brief explanation of why you can or cannot fix this",
            "root_causes": ["List of identified root causes"],
            "fixes": [
              {
                "file": "path/to/file",
                "action": "edit|create|delete",
                "content": "Full file content after fix (for create/edit)",
                "description": "What this fix does"
              }
            ]
          }

          Only propose fixes if you are confident they will resolve the issue.
          Common CI failures you can fix:
          - Linting errors (formatting, style violations)
          - Simple test failures (typos, missing imports, incorrect assertions)
          - Dependency issues (missing packages in manifest)
          - Configuration errors (incorrect paths, missing env vars)

          DO NOT attempt to fix:
          - Complex logic errors requiring domain knowledge
          - Failing integration tests that may indicate real bugs
          - Security scan failures
          - Performance regression issues
        PROMPT
      end

      def build_ci_analysis_prompt(pr_data:, failures:)
        <<~PROMPT
          Analyze these CI failures for PR ##{pr_data[:number]}: #{pr_data[:title]}

          **PR Description:**
          #{pr_data[:body]}

          **Failed Checks:**
          #{failures.map { |f| "- #{f[:name]}: #{f[:conclusion]}\n  Output: #{f[:output].inspect}" }.join("\n")}

          Please analyze these failures and propose fixes if possible.
        PROMPT
      end

      def detect_default_provider
        config_manager = Aidp::Harness::ConfigManager.new(@project_dir)
        config_manager.default_provider || "anthropic"
      rescue
        "anthropic"
      end

      def extract_json(text)
        # Try to extract JSON from code fences or find JSON object
        # Use non-greedy matching to avoid ReDoS
        return text if text.start_with?("{") && text.end_with?("}")

        # Match code fence with non-greedy quantifier
        if text =~ /```json\s*(\{.*?\})\s*```/m
          return $1
        end

        # Find JSON object with non-greedy quantifier
        json_match = text.match(/\{.*?\}/m)
        json_match ? json_match[0] : text
      end

      def checkout_pr_branch(pr_data)
        head_ref = pr_data[:head_ref]

        Dir.chdir(@project_dir) do
          # Fetch latest
          run_git(%w[fetch origin])

          # Checkout the PR branch
          run_git(["checkout", head_ref])

          # Pull latest changes
          run_git(%w[pull --ff-only], allow_failure: true)
        end

        display_message("🌿 Checked out branch: #{head_ref}", type: :info)
      end

      def apply_fixes(fixes)
        fixes.each do |fix|
          file_path = File.join(@project_dir, fix["file"])

          case fix["action"]
          when "create", "edit"
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, fix["content"])
            display_message("  ✓ #{fix["action"]} #{fix["file"]}", type: :muted) if @verbose
          when "delete"
            File.delete(file_path) if File.exist?(file_path)
            display_message("  ✓ Deleted #{fix["file"]}", type: :muted) if @verbose
          else
            display_message("  ⚠️  Unknown action: #{fix["action"]} for #{fix["file"]}", type: :warn)
          end
        end
      end

      def commit_and_push(pr_data, analysis)
        Dir.chdir(@project_dir) do
          # Check if there are changes
          status_output = run_git(%w[status --porcelain])
          if status_output.strip.empty?
            display_message("ℹ️  No changes to commit after applying fixes.", type: :muted)
            return false
          end

          # Stage all changes
          run_git(%w[add -A])

          # Create commit
          commit_message = build_commit_message(pr_data, analysis)
          run_git(["commit", "-m", commit_message])

          display_message("💾 Created commit: #{commit_message.lines.first.strip}", type: :info)

          # Push to origin
          head_ref = pr_data[:head_ref]
          run_git(["push", "origin", head_ref])

          display_message("⬆️  Pushed fixes to #{head_ref}", type: :success)
          true
        end
      end

      def build_commit_message(pr_data, analysis)
        root_causes = analysis[:root_causes] || []
        fixes_description = analysis[:fixes]&.map { |f| f["description"] }&.join(", ") || "CI failures"

        message = "fix: resolve CI failures for PR ##{pr_data[:number]}\n\n"
        message += "Root causes:\n"
        root_causes.each { |cause| message += "- #{cause}\n" }
        message += "\nFixes: #{fixes_description}\n"
        message += "\nCo-authored-by: AIDP CI Fixer <ai@aidp.dev>"

        message
      end

      def handle_success(pr:, fix_result:)
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ✅ Successfully analyzed and fixed CI failures!

          **Root Causes:**
          #{fix_result[:analysis][:root_causes].map { |c| "- #{c}" }.join("\n")}

          **Applied Fixes:**
          #{fix_result[:analysis][:fixes].map { |f| "- #{f["file"]}: #{f["description"]}" }.join("\n")}

          The fixes have been committed and pushed to this PR. CI should re-run automatically.
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_ci_fix(pr[:number], {
          status: "completed",
          timestamp: Time.now.utc.iso8601,
          root_causes: fix_result[:analysis][:root_causes],
          fixes_count: fix_result[:analysis][:fixes].length
        })

        display_message("🎉 Posted success comment for PR ##{pr[:number]}", type: :success)

        # Remove label after successful fix
        begin
          @repository_client.remove_labels(pr[:number], @ci_fix_label)
          display_message("🏷️  Removed '#{@ci_fix_label}' label after successful fix", type: :info)
        rescue => e
          display_message("⚠️  Failed to remove CI fix label: #{e.message}", type: :warn)
        end
      end

      def handle_failure(pr:, fix_result:)
        reason = fix_result[:reason] || fix_result[:error] || "Unknown error"

        analysis_section = if fix_result[:analysis]
          "**Analysis:**\n#{fix_result[:analysis][:root_causes]&.map { |c| "- #{c}" }&.join("\n")}"
        else
          ""
        end

        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ⚠️  Could not automatically fix CI failures.

          **Reason:** #{reason}

          #{analysis_section}

          Please review the CI failures manually. You may need to:
          1. Check the full CI logs for more context
          2. Run tests locally to reproduce the issue
          3. Consult with your team if the failures indicate a deeper problem

          You can retry the automated fix by re-adding the `#{@ci_fix_label}` label after making changes.
        COMMENT

        @repository_client.post_comment(pr[:number], comment)
        @state_store.record_ci_fix(pr[:number], {
          status: "failed",
          timestamp: Time.now.utc.iso8601,
          reason: reason
        })

        display_message("⚠️  Posted failure comment for PR ##{pr[:number]}", type: :warn)
      end

      def post_success_comment(pr_data)
        comment = <<~COMMENT
          #{COMMENT_HEADER}

          ✅ CI is already passing! No fixes needed.

          All checks are green for this PR.
        COMMENT

        @repository_client.post_comment(pr_data[:number], comment)
      end

      def run_git(args, allow_failure: false)
        stdout, stderr, status = Open3.capture3("git", *Array(args))
        raise "git #{args.join(" ")} failed: #{stderr.strip}" unless status.success? || allow_failure
        stdout
      end

      def log_ci_fix(pr_number, fix_result)
        log_dir = File.join(@project_dir, ".aidp", "logs", "pr_reviews")
        FileUtils.mkdir_p(log_dir)

        log_file = File.join(log_dir, "ci_fix_#{pr_number}_#{Time.now.utc.strftime("%Y%m%d_%H%M%S")}.json")

        log_data = {
          pr_number: pr_number,
          timestamp: Time.now.utc.iso8601,
          success: fix_result[:success],
          analysis: fix_result[:analysis],
          error: fix_result[:error]
        }

        File.write(log_file, JSON.pretty_generate(log_data))
        display_message("📝 CI fix log saved to #{log_file}", type: :muted) if @verbose
      rescue => e
        display_message("⚠️  Failed to save CI fix log: #{e.message}", type: :warn)
      end
    end
  end
end
