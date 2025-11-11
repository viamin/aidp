# frozen_string_literal: true

require "tty-prompt"

require_relative "../message_display"
require_relative "repository_client"
require_relative "repository_safety_checker"
require_relative "state_store"
require_relative "plan_generator"
require_relative "plan_processor"
require_relative "build_processor"
require_relative "../auto_update"

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
        @provider_name = provider_name
        @safety_config = safety_config

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

        # Initialize auto-update coordinator
        @auto_update_coordinator = Aidp::AutoUpdate.coordinator(project_dir: project_dir)
        @last_update_check = nil
      end

      def start
        # Check for and restore from checkpoint (after auto-update)
        restore_from_checkpoint_if_exists

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
        check_for_updates_if_due
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

      def issue_has_label?(issue, label)
        Array(issue[:labels]).any? do |issue_label|
          name = issue_label.is_a?(Hash) ? issue_label["name"] : issue_label.to_s
          name.casecmp(label).zero?
        end
      end

      # Restore from checkpoint if one exists (after auto-update)
      def restore_from_checkpoint_if_exists
        return unless @auto_update_coordinator.policy.enabled

        checkpoint = @auto_update_coordinator.restore_from_checkpoint
        return unless checkpoint

        # Checkpoint exists and was successfully restored
        display_message("✨ Restored from checkpoint after update to v#{Aidp::VERSION}", type: :success)

        # Override instance variables with checkpoint state
        if checkpoint.watch_mode? && checkpoint.watch_state
          @interval = checkpoint.watch_state[:interval] || @interval
          Aidp.log_info("watch_runner", "checkpoint_restored",
            checkpoint_id: checkpoint.checkpoint_id,
            interval: @interval)
        end
      rescue => e
        # Log but don't fail - continue with fresh start
        Aidp.log_error("watch_runner", "checkpoint_restore_failed",
          error: e.message)
        display_message("⚠️  Checkpoint restore failed, starting fresh: #{e.message}", type: :warning)
      end

      # Check for updates at appropriate intervals
      def check_for_updates_if_due
        return unless @auto_update_coordinator.policy.enabled
        return unless time_for_update_check?

        update_check = @auto_update_coordinator.check_for_update

        if update_check.should_update?
          display_message("🔄 Update available: #{update_check.current_version} → #{update_check.available_version}", type: :highlight)
          display_message("   Saving checkpoint and initiating update...", type: :muted)

          initiate_update(update_check)
          # Never returns - exits with code 75
        end
      rescue Aidp::AutoUpdate::UpdateLoopError => e
        # Restart loop detected - disable auto-update
        display_message("⚠️  Auto-update disabled: #{e.message}", type: :error)
        Aidp.log_error("watch_runner", "update_loop_detected", error: e.message)
      rescue Aidp::AutoUpdate::UpdateError => e
        # Non-fatal update error - log and continue
        Aidp.log_error("watch_runner", "update_check_failed", error: e.message)
      end

      # Determine if it's time to check for updates
      # @return [Boolean]
      def time_for_update_check?
        return true if @last_update_check.nil?

        elapsed = Time.now - @last_update_check
        elapsed >= @auto_update_coordinator.policy.check_interval_seconds
      end

      # Initiate update process: capture state, create checkpoint, exit
      # @param update_check [Aidp::AutoUpdate::UpdateCheck] Update check result
      def initiate_update(update_check)
        current_state = capture_current_state

        # This will exit with code 75 if successful
        @auto_update_coordinator.initiate_update(current_state)
      end

      # Capture current watch mode state for checkpoint
      # @return [Hash] Current state
      def capture_current_state
        {
          mode: "watch",
          watch_state: {
            repository: @repository_client.full_repo,
            interval: @interval,
            provider_name: @provider_name,
            persona: nil,
            safety_config: @safety_config,
            worktree_context: capture_worktree_context,
            state_store_snapshot: @state_store.send(:state).dup
          }
        }
      end

      # Capture git worktree context
      # @return [Hash] Worktree information
      def capture_worktree_context
        return {} unless system("git rev-parse --git-dir > /dev/null 2>&1")

        {
          branch: `git rev-parse --abbrev-ref HEAD`.strip,
          commit_sha: `git rev-parse HEAD`.strip,
          remote_url: `git config --get remote.origin.url`.strip
        }
      rescue => e
        Aidp.log_debug("watch_runner", "worktree_context_unavailable", error: e.message)
        {}
      end
    end
  end
end
