# frozen_string_literal: true

require "tty-prompt"

require_relative "../message_display"
require_relative "repository_client"
require_relative "repository_safety_checker"
require_relative "state_store"
require_relative "plan_generator"
require_relative "plan_processor"
require_relative "build_processor"

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
      end

      def start
        # Validate safety requirements before starting
        @safety_checker.validate_watch_mode_safety!(force: @force)

        display_message("👀 Watch mode enabled for #{@repository_client.full_repo}", type: :highlight)
        display_message("Polling every #{@interval} seconds. Press Ctrl+C to stop.", type: :muted)

        loop do
          process_cycle
          break if @once
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
      end

      def process_plan_triggers
        plan_label = @plan_processor.plan_label
        issues = @repository_client.list_issues(labels: [plan_label], state: "open")
        issues.each do |issue|
          next unless issue_has_label?(issue, plan_label)

          detailed = @repository_client.fetch_issue(issue[:number])

          # Check author authorization before processing
          next unless @safety_checker.should_process_issue?(detailed, enforce: false)

          @plan_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
        end
      end

      def process_build_triggers
        build_label = @build_processor.build_label
        issues = @repository_client.list_issues(labels: [build_label], state: "open")
        issues.each do |issue|
          next unless issue_has_label?(issue, build_label)

          status = @state_store.build_status(issue[:number])
          next if status["status"] == "completed"

          detailed = @repository_client.fetch_issue(issue[:number])

          # Check author authorization before processing
          next unless @safety_checker.should_process_issue?(detailed, enforce: false)

          @build_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
        end
      end

      def issue_has_label?(issue, label)
        Array(issue[:labels]).any? do |issue_label|
          name = issue_label.is_a?(Hash) ? issue_label["name"] : issue_label.to_s
          name.casecmp(label).zero?
        end
      end
    end
  end
end
