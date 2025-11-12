# frozen_string_literal: true

require "tty-prompt"

require_relative "../message_display"
require_relative "repository_client"
require_relative "repository_safety_checker"
require_relative "state_store"
require_relative "plan_generator"
require_relative "plan_processor"
require_relative "build_processor"
require_relative "review_processor"
require_relative "ci_fix_processor"

module Aidp
  module Watch
    # Coordinates the watch mode loop: monitors issues, handles plan/build
    # triggers, and keeps running until interrupted.
    class Runner
      include Aidp::MessageDisplay

      DEFAULT_INTERVAL = 30

      def initialize(issues_url:, interval: DEFAULT_INTERVAL, provider_name: nil, gh_available: nil, project_dir: Dir.pwd, once: false, use_workstreams: true, prompt: TTY::Prompt.new, safety_config: {}, force: false, verbose: false)
        @prompt = prompt
        @interval = interval
        @once = once
        @project_dir = project_dir
        @force = force
        @verbose = verbose

        owner, repo = RepositoryClient.parse_issues_url(issues_url)
        @repository_client = RepositoryClient.new(owner: owner, repo: repo, gh_available: gh_available)
        @safety_checker = RepositorySafetyChecker.new(
          repository_client: @repository_client,
          config: safety_config
        )
        @state_store = StateStore.new(project_dir: project_dir, repository: "#{owner}/#{repo}")

        # Extract label configuration from safety_config (it's actually the full watch config)
        label_config = safety_config[:labels] || safety_config["labels"] || {}

        @plan_processor = PlanProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          plan_generator: PlanGenerator.new(provider_name: provider_name, verbose: verbose),
          label_config: label_config
        )
        @build_processor = BuildProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          project_dir: project_dir,
          use_workstreams: use_workstreams,
          verbose: verbose,
          label_config: label_config
        )
        @review_processor = ReviewProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          provider_name: provider_name,
          project_dir: project_dir,
          label_config: label_config,
          verbose: verbose
        )
        @ci_fix_processor = CiFixProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          provider_name: provider_name,
          project_dir: project_dir,
          label_config: label_config,
          verbose: verbose
        )
      end

      def start
        # Validate safety requirements before starting
        @safety_checker.validate_watch_mode_safety!(force: @force)

        Aidp.log_info(
          "watch_runner",
          "watch_mode_started",
          repo: @repository_client.full_repo,
          interval: @interval,
          once: @once,
          use_workstreams: @use_workstreams,
          verbose: @verbose
        )

        display_message("👀 Watch mode enabled for #{@repository_client.full_repo}", type: :highlight)
        display_message("Polling every #{@interval} seconds. Press Ctrl+C to stop.", type: :muted)

        loop do
          Aidp.log_debug("watch_runner", "poll_cycle.begin", repo: @repository_client.full_repo, interval: @interval)
          process_cycle
          Aidp.log_debug("watch_runner", "poll_cycle.complete", once: @once, next_poll_in: @once ? nil : @interval)
          break if @once
          Aidp.log_debug("watch_runner", "poll_cycle.sleep", seconds: @interval)
          sleep @interval
        end
      rescue Interrupt
        display_message("\n⏹️  Watch mode interrupted by user", type: :warning)
      rescue RepositorySafetyChecker::UnsafeRepositoryError => e
        display_message("\n#{e.message}", type: :error)
        raise
      end

      private

      def process_cycle
        process_plan_triggers
        process_build_triggers
        process_review_triggers
        process_ci_fix_triggers
      end

      def process_plan_triggers
        plan_label = @plan_processor.plan_label
        issues = @repository_client.list_issues(labels: [plan_label], state: "open")
        Aidp.log_debug("watch_runner", "plan_poll", label: plan_label, total: issues.size)
        issues.each do |issue|
          unless issue_has_label?(issue, plan_label)
            Aidp.log_debug("watch_runner", "plan_skip_label_mismatch", issue: issue[:number], labels: issue[:labels])
            next
          end

          detailed = @repository_client.fetch_issue(issue[:number])

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "plan_skip_unauthorized_author", issue: detailed[:number], author: detailed[:author])
            next
          end

          Aidp.log_debug("watch_runner", "plan_process", issue: detailed[:number])
          @plan_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
        end
      end

      def process_build_triggers
        build_label = @build_processor.build_label
        issues = @repository_client.list_issues(labels: [build_label], state: "open")
        Aidp.log_debug("watch_runner", "build_poll", label: build_label, total: issues.size)
        issues.each do |issue|
          unless issue_has_label?(issue, build_label)
            Aidp.log_debug("watch_runner", "build_skip_label_mismatch", issue: issue[:number], labels: issue[:labels])
            next
          end

          status = @state_store.build_status(issue[:number])
          if status["status"] == "completed"
            Aidp.log_debug("watch_runner", "build_skip_completed", issue: issue[:number])
            next
          end

          detailed = @repository_client.fetch_issue(issue[:number])

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "build_skip_unauthorized_author", issue: detailed[:number], author: detailed[:author])
            next
          end

          Aidp.log_debug("watch_runner", "build_process", issue: detailed[:number])
          @build_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
        end
      end

      def process_review_triggers
        review_label = @review_processor.review_label
        prs = @repository_client.list_pull_requests(labels: [review_label], state: "open")
        Aidp.log_debug("watch_runner", "review_poll", label: review_label, total: prs.size)
        prs.each do |pr|
          unless pr_has_label?(pr, review_label)
            Aidp.log_debug("watch_runner", "review_skip_label_mismatch", pr: pr[:number], labels: pr[:labels])
            next
          end

          detailed = @repository_client.fetch_pull_request(pr[:number])

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "review_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          Aidp.log_debug("watch_runner", "review_process", pr: detailed[:number])
          @review_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized PR author", pr: pr[:number], error: e.message)
        end
      end

      def process_ci_fix_triggers
        ci_fix_label = @ci_fix_processor.ci_fix_label
        prs = @repository_client.list_pull_requests(labels: [ci_fix_label], state: "open")
        Aidp.log_debug("watch_runner", "ci_fix_poll", label: ci_fix_label, total: prs.size)
        prs.each do |pr|
          unless pr_has_label?(pr, ci_fix_label)
            Aidp.log_debug("watch_runner", "ci_fix_skip_label_mismatch", pr: pr[:number], labels: pr[:labels])
            next
          end

          detailed = @repository_client.fetch_pull_request(pr[:number])

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "ci_fix_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          Aidp.log_debug("watch_runner", "ci_fix_process", pr: detailed[:number])
          @ci_fix_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized PR author", pr: pr[:number], error: e.message)
        end
      end

      def issue_has_label?(issue, label)
        Array(issue[:labels]).any? do |issue_label|
          name = issue_label.is_a?(Hash) ? issue_label["name"] : issue_label.to_s
          name.casecmp(label).zero?
        end
      end

      def pr_has_label?(pr, label)
        Array(pr[:labels]).any? do |pr_label|
          name = pr_label.is_a?(Hash) ? pr_label["name"] : pr_label.to_s
          name.casecmp(label).zero?
        end
      end
    end
  end
end
