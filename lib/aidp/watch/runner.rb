# frozen_string_literal: true

require "tty-prompt"
require_relative "feedback_collector"
require_relative "github_state_extractor"
require_relative "round_robin_scheduler"
require_relative "work_item"
require_relative "worktree_cleanup_job"
require_relative "worktree_reconciler"

module Aidp
  module Watch
    # Coordinates the watch mode loop: monitors issues, handles plan/build
    # triggers, and keeps running until interrupted.
    class Runner
      include Aidp::MessageDisplay

      DEFAULT_INTERVAL = 30

      # Expose for testability
      attr_reader :post_detection_comments
      attr_writer :last_update_check

      def initialize(issues_url:, interval: DEFAULT_INTERVAL, provider_name: nil, gh_available: nil, project_dir: Dir.pwd, once: false, use_workstreams: true, prompt: TTY::Prompt.new, safety_config: {}, force: false, verbose: false, quiet: false)
        @prompt = prompt
        @interval = interval
        @once = once
        @project_dir = project_dir
        @force = force
        @verbose = verbose
        @quiet = quiet
        @provider_name = provider_name
        @safety_config = safety_config

        owner, repo = RepositoryClient.parse_issues_url(issues_url)
        @repository_client = RepositoryClient.new(owner: owner, repo: repo, gh_available: gh_available)
        @safety_checker = RepositorySafetyChecker.new(
          repository_client: @repository_client,
          config: safety_config
        )
        @state_store = StateStore.new(project_dir: project_dir, repository: "#{owner}/#{repo}")
        @state_extractor = GitHubStateExtractor.new(repository_client: @repository_client)

        # Extract label configuration from safety_config (it's actually the full watch config)
        label_config = safety_config[:labels] || safety_config["labels"] || {}

        # Extract detection comment configuration (issue #280)
        # Enabled by default, can be disabled in config
        @post_detection_comments = if safety_config.key?(:post_detection_comments)
          safety_config[:post_detection_comments]
        elsif safety_config.key?("post_detection_comments")
          safety_config["post_detection_comments"]
        else
          true # Enabled by default
        end

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
        @auto_processor = AutoProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          build_processor: @build_processor,
          label_config: label_config,
          verbose: verbose
        )

        # Initialize auto-update coordinator
        @auto_update_coordinator = Aidp::AutoUpdate.coordinator(project_dir: project_dir)
        @last_update_check = nil
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
        @auto_pr_processor = AutoPrProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          review_processor: @review_processor,
          ci_fix_processor: @ci_fix_processor,
          label_config: label_config,
          verbose: verbose
        )
        @change_request_processor = ChangeRequestProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          provider_name: provider_name,
          project_dir: project_dir,
          label_config: label_config,
          change_request_config: safety_config[:pr_change_requests] || safety_config["pr_change_requests"] || {},
          safety_config: safety_config[:safety] || safety_config["safety"] || {},
          verbose: verbose
        )

        @feedback_collector = FeedbackCollector.new(
          repository_client: @repository_client,
          state_store: @state_store,
          project_dir: project_dir
        )

        # Initialize worktree cleanup job (issue #367)
        cleanup_config = Aidp::Config.worktree_cleanup_config(project_dir)
        @worktree_cleanup_job = WorktreeCleanupJob.new(
          project_dir: project_dir,
          config: cleanup_config
        )

        # Initialize worktree reconciler for dirty worktree handling
        reconciler_config = safety_config[:worktree_reconciliation] || safety_config["worktree_reconciliation"] || {}
        @worktree_reconciler = WorktreeReconciler.new(
          project_dir: project_dir,
          repository_client: @repository_client,
          build_processor: @build_processor,
          state_store: @state_store,
          config: reconciler_config
        )
        @last_reconcile_at = nil

        # Initialize round-robin scheduler (issue #434)
        @round_robin_scheduler = RoundRobinScheduler.new(
          state_store: @state_store
        )
        @needs_input_label = label_config[:needs_input] || label_config["needs_input"] || "aidp-needs-input"
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
        # Collect all work items and refresh the scheduler queue
        work_items = collect_all_work_items
        @round_robin_scheduler.refresh_queue(work_items)

        # Get paused items (aidp-needs-input label)
        paused_numbers = fetch_paused_item_numbers

        # Log queue status
        stats = @round_robin_scheduler.stats
        Aidp.log_debug("watch_runner", "round_robin.queue_status",
          total: stats[:total],
          by_processor: stats[:by_processor],
          paused_count: paused_numbers.size)

        # Process one work item using round-robin
        if @round_robin_scheduler.work?(paused_numbers: paused_numbers)
          process_next_work_item(paused_numbers: paused_numbers)
        else
          Aidp.log_debug("watch_runner", "round_robin.no_work",
            queue_size: stats[:total], paused_count: paused_numbers.size)
        end

        # Run maintenance tasks (these run every cycle regardless)
        check_for_updates_if_due
        collect_feedback
        process_worktree_cleanup
        process_worktree_reconciliation
      end

      # Process the next work item from the round-robin queue.
      # @param paused_numbers [Array<Integer>] Numbers of paused items to skip
      def process_next_work_item(paused_numbers:)
        item = @round_robin_scheduler.next_item(paused_numbers: paused_numbers)
        return unless item

        Aidp.log_info("watch_runner", "round_robin.processing",
          key: item.key, number: item.number, processor_type: item.processor_type)

        # Dispatch to appropriate processor - returns true if item was actually processed
        was_processed = dispatch_work_item(item)

        # Only mark as processed if work was actually done (not skipped), so skipped
        # items remain in the queue and will be re-checked on the next cycle.
        @round_robin_scheduler.mark_processed(item) if was_processed
      rescue => e
        Aidp.log_error("watch_runner", "round_robin.process_failed",
          key: item&.key, error: e.message, error_class: e.class.name)
        # Mark as processed on error to prevent infinite retry loops within the same
        # rotation. Unlike authorization/build_completed skips (which return false to
        # allow immediate retry since their state may change), errors are assumed to be
        # transient issues that will resolve by the next full queue refresh cycle.
        # The item will be re-added to the queue on the next refresh if still active.
        @round_robin_scheduler.mark_processed(item) if item
      end

      # Dispatch a work item to its appropriate processor.
      #
      # Design note: Items skipped due to authorization or build_completed checks
      # return false and are NOT marked as processed. This means they will be
      # re-checked on the next cycle. This is intentional because:
      # - Authorization: An author could be added to the allowlist between cycles
      # - Build completed: New commits could be pushed, requiring more work
      #
      # The trade-off is some redundant API calls, but this ensures we don't
      # permanently skip items whose state could change.
      #
      # @param item [WorkItem] The work item to process
      # @return [Boolean] True if item was actually processed, false if skipped
      def dispatch_work_item(item)
        detailed = fetch_detailed_item(item)
        return false unless detailed

        # Check authorization
        unless @safety_checker.should_process_issue?(detailed, enforce: false)
          Aidp.log_debug("watch_runner", "round_robin.skip_unauthorized",
            key: item.key, author: detailed[:author])
          return false
        end

        # Post detection comment if not already posted
        post_detection_comment_for_item(item, detailed)

        # Dispatch to processor
        case item.processor_type
        when :plan
          @plan_processor.process(detailed)
        when :build
          # Check build completion at dispatch time (moved from collection for API efficiency)
          if @state_extractor.build_completed?(detailed)
            Aidp.log_debug("watch_runner", "round_robin.skip_build_completed",
              key: item.key, number: item.number)
            return false
          end
          @build_processor.process(detailed)
        when :auto_issue
          @auto_processor.process(detailed)
        when :review
          @review_processor.process(detailed)
        when :ci_fix
          @ci_fix_processor.process(detailed)
        when :auto_pr
          @auto_pr_processor.process(detailed)
        when :change_request
          @change_request_processor.process(detailed)
        else
          Aidp.log_warn("watch_runner", "round_robin.unknown_processor",
            processor_type: item.processor_type)
          return false
        end

        true # Item was processed
      rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
        Aidp.log_warn("watch_runner", "round_robin.unauthorized_author",
          key: item.key, error: e.message)
        false
      end

      # Fetch detailed issue or PR data for a work item.
      # @param item [WorkItem] Work item to fetch details for
      # @return [Hash, nil] Detailed item data or nil on error
      def fetch_detailed_item(item)
        if item.issue?
          @repository_client.fetch_issue(item.number)
        else
          @repository_client.fetch_pull_request(item.number)
        end
      rescue => e
        Aidp.log_error("watch_runner", "round_robin.fetch_failed",
          key: item.key, error: e.message)
        nil
      end

      # Post detection comment for a work item if not already posted.
      # @param item [WorkItem] Work item
      # @param detailed [Hash] Detailed issue/PR data
      def post_detection_comment_for_item(item, detailed)
        return unless @post_detection_comments
        return if @state_extractor.detection_comment_posted?(detailed, item.label)

        post_detection_comment(
          item_type: item.item_type,
          number: item.number,
          label: item.label
        )
      end

      # Collect all work items from all processors.
      # @return [Array<WorkItem>] List of all work items
      def collect_all_work_items
        items = []

        items.concat(collect_plan_work_items)
        items.concat(collect_build_work_items)
        items.concat(collect_auto_issue_work_items)
        items.concat(collect_review_work_items)
        items.concat(collect_ci_fix_work_items)
        items.concat(collect_auto_pr_work_items)
        items.concat(collect_change_request_work_items)

        Aidp.log_debug("watch_runner", "collect_all_work_items.complete",
          total: items.size)

        items
      end

      # Collect work items for plan triggers.
      # @return [Array<WorkItem>]
      def collect_plan_work_items
        label = @plan_processor.plan_label
        issues = @repository_client.list_issues(labels: [label], state: "open")

        issues.filter_map do |issue|
          next unless issue_has_label?(issue, label)

          WorkItem.new(
            number: issue[:number],
            item_type: :issue,
            processor_type: :plan,
            label: label,
            data: issue
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_plan_items_failed", error: e.message)
        []
      end

      # Collect work items for build triggers.
      # @return [Array<WorkItem>]
      def collect_build_work_items
        label = @build_processor.build_label
        issues = @repository_client.list_issues(labels: [label], state: "open")

        issues.filter_map do |issue|
          next unless issue_has_label?(issue, label)

          # Note: build_completed check moved to dispatch phase to avoid
          # API calls during collection (addresses rate limiting concerns)
          WorkItem.new(
            number: issue[:number],
            item_type: :issue,
            processor_type: :build,
            label: label,
            data: issue
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_build_items_failed", error: e.message)
        []
      end

      # Collect work items for auto issue triggers.
      # @return [Array<WorkItem>]
      def collect_auto_issue_work_items
        label = @auto_processor.auto_label
        issues = @repository_client.list_issues(labels: [label], state: "open")

        issues.filter_map do |issue|
          next unless issue_has_label?(issue, label)

          WorkItem.new(
            number: issue[:number],
            item_type: :issue,
            processor_type: :auto_issue,
            label: label,
            data: issue
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_auto_issue_items_failed", error: e.message)
        []
      end

      # Collect work items for review triggers.
      # @return [Array<WorkItem>]
      def collect_review_work_items
        label = @review_processor.review_label
        prs = @repository_client.list_pull_requests(labels: [label], state: "open")

        prs.filter_map do |pr|
          next unless pr_has_label?(pr, label)

          WorkItem.new(
            number: pr[:number],
            item_type: :pr,
            processor_type: :review,
            label: label,
            data: pr
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_review_items_failed", error: e.message)
        []
      end

      # Collect work items for CI fix triggers.
      # @return [Array<WorkItem>]
      def collect_ci_fix_work_items
        label = @ci_fix_processor.ci_fix_label
        prs = @repository_client.list_pull_requests(labels: [label], state: "open")

        prs.filter_map do |pr|
          next unless pr_has_label?(pr, label)

          WorkItem.new(
            number: pr[:number],
            item_type: :pr,
            processor_type: :ci_fix,
            label: label,
            data: pr
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_ci_fix_items_failed", error: e.message)
        []
      end

      # Collect work items for auto PR triggers.
      # @return [Array<WorkItem>]
      def collect_auto_pr_work_items
        label = @auto_pr_processor.auto_label
        prs = @repository_client.list_pull_requests(labels: [label], state: "open")

        prs.filter_map do |pr|
          next unless pr_has_label?(pr, label)

          WorkItem.new(
            number: pr[:number],
            item_type: :pr,
            processor_type: :auto_pr,
            label: label,
            data: pr
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_auto_pr_items_failed", error: e.message)
        []
      end

      # Collect work items for change request triggers.
      # @return [Array<WorkItem>]
      def collect_change_request_work_items
        label = @change_request_processor.change_request_label
        prs = @repository_client.list_pull_requests(labels: [label], state: "open")

        prs.filter_map do |pr|
          next unless pr_has_label?(pr, label)

          WorkItem.new(
            number: pr[:number],
            item_type: :pr,
            processor_type: :change_request,
            label: label,
            data: pr
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "collect_change_request_items_failed", error: e.message)
        []
      end

      # Fetch the numbers of all paused items (with aidp-needs-input label).
      # @return [Array<Integer>] Issue/PR numbers that are paused
      def fetch_paused_item_numbers
        issues = @repository_client.list_issues(labels: [@needs_input_label], state: "open")
        prs = @repository_client.list_pull_requests(labels: [@needs_input_label], state: "open")

        paused = issues.map { |i| i[:number] } + prs.map { |p| p[:number] }

        Aidp.log_debug("watch_runner", "fetch_paused_items",
          count: paused.size, numbers: paused)

        paused
      rescue => e
        Aidp.log_error("watch_runner", "fetch_paused_items_failed", error: e.message)
        []
      end

      def issue_has_label?(issue, label)
        Array(issue[:labels]).any? do |issue_label|
          name = (issue_label.is_a?(Hash) ? issue_label["name"] : issue_label.to_s)
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

        @last_update_check = Time.now
        update_check = @auto_update_coordinator.check_for_update

        if update_check.should_update?
          display_message("🔄 Update available: #{update_check.current_version} → #{update_check.available_version}",
            type: :highlight)

          # Prefer hot reloading if available (Zeitwerk enabled with reloading)
          if @auto_update_coordinator.hot_reload_available?
            perform_hot_reload(update_check)
          else
            # Fall back to checkpoint + exit approach
            display_message("   Saving checkpoint and initiating update...", type: :muted)
            initiate_update(update_check)
            # Never returns - exits with code 75
          end
        end
      rescue Aidp::AutoUpdate::UpdateLoopError => e
        # Restart loop detected - disable auto-update
        display_message("⚠️  Auto-update disabled: #{e.message}", type: :error)
        Aidp.log_error("watch_runner", "update_loop_detected", error: e.message)
      rescue Aidp::AutoUpdate::UpdateError => e
        # Non-fatal update error - log and continue
        Aidp.log_error("watch_runner", "update_check_failed", error: e.message)
      end

      # Perform hot code reload without restarting
      # @param update_check [Aidp::AutoUpdate::UpdateCheck] Update check result
      def perform_hot_reload(update_check)
        display_message("   Performing hot code reload (no restart needed)...", type: :muted)

        if @auto_update_coordinator.hot_reload_update(update_check)
          display_message("✨ Hot reload complete! Now running #{Aidp::VERSION}", type: :success)
          Aidp.log_info("watch_runner", "hot_reload_success",
            version: Aidp::VERSION)
        else
          display_message("⚠️  Hot reload skipped (no update needed)", type: :muted)
        end
      rescue Aidp::AutoUpdate::UpdateError => e
        display_message("⚠️  Hot reload failed: #{e.message}", type: :warning)
        display_message("   Falling back to checkpoint + restart...", type: :muted)
        # Fall back to cold restart
        initiate_update(update_check)
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

      # Post detection comment to GitHub when aidp picks up a labeled item (issue #280)
      # @param item_type [Symbol] Type of item (:issue or :pr)
      # @param number [Integer] Issue or PR number
      # @param label [String] Label that triggered detection
      def post_detection_comment(item_type:, number:, label:)
        return unless @post_detection_comments

        # Check if we've already posted a detection comment for this item/label combination
        detection_key = "#{item_type}_#{number}_#{label}"
        return if @state_store.detection_comment_posted?(detection_key)

        timestamp = Time.now.utc.iso8601
        item_name = (item_type == :pr) ? "PR" : "issue"

        comment_body = "aidp detected `#{label}` at #{timestamp} and is working on it"

        begin
          @repository_client.post_comment(number, comment_body)
          @state_store.record_detection_comment(detection_key, timestamp: timestamp)

          Aidp.log_info("watch_runner", "detection_comment_posted",
            item_type: item_type,
            number: number,
            label: label,
            timestamp: timestamp)

          display_message("💬 Posted detection comment for #{item_name} ##{number}", type: :info) if @verbose
        rescue => e
          # Don't fail processing if comment posting fails - just log it
          Aidp.log_warn("watch_runner", "detection_comment_failed",
            item_type: item_type,
            number: number,
            label: label,
            error: e.message)
        end
      end

      def pr_has_label?(pr, label)
        Array(pr[:labels]).any? do |pr_label|
          name = (pr_label.is_a?(Hash) ? pr_label["name"] : pr_label.to_s)
          name.casecmp(label).zero?
        end
      end

      # Collect feedback from reactions on tracked comments
      def collect_feedback
        new_evaluations = @feedback_collector.collect_feedback
        return if new_evaluations.empty?

        Aidp.log_info("watch_runner", "feedback_collected",
          count: new_evaluations.size,
          evaluations: new_evaluations.map { |e| {id: e[:id], rating: e[:rating]} })

        display_message("📊 Collected #{new_evaluations.size} new feedback evaluation(s)", type: :info) if @verbose
      rescue => e
        Aidp.log_error("watch_runner", "feedback_collection_failed", error: e.message)
        display_message("⚠️  Feedback collection failed: #{e.message}", type: :warn) if @verbose
      end

      # Process worktree cleanup if due (issue #367)
      # Runs periodically based on configured frequency (daily/weekly)
      def process_worktree_cleanup
        return unless @worktree_cleanup_job.enabled?

        last_cleanup = @state_store.last_worktree_cleanup
        return unless @worktree_cleanup_job.cleanup_due?(last_cleanup)

        Aidp.log_debug("watch_runner", "worktree_cleanup.checking",
          last_cleanup: last_cleanup&.iso8601,
          frequency: @worktree_cleanup_job.cleanup_interval_seconds)

        result = @worktree_cleanup_job.execute

        @state_store.record_worktree_cleanup(
          cleaned: result[:cleaned],
          skipped: result[:skipped],
          errors: result[:errors]
        )

        if result[:cleaned] > 0 || @verbose
          display_message("🧹 Worktree cleanup: #{result[:cleaned]} cleaned, #{result[:skipped]} skipped",
            type: :info)
        end
      rescue => e
        Aidp.log_error("watch_runner", "worktree_cleanup_failed", error: e.message)
        display_message("⚠️  Worktree cleanup failed: #{e.message}", type: :warn) if @verbose
      end

      # Process worktree reconciliation for dirty worktrees
      # Resumes interrupted work or reconciles merged PRs
      def process_worktree_reconciliation
        return unless @worktree_reconciler.enabled?
        return unless @worktree_reconciler.reconciliation_due?(@last_reconcile_at)

        Aidp.log_debug("watch_runner", "worktree_reconciliation.checking",
          last_reconcile: @last_reconcile_at&.iso8601)

        result = @worktree_reconciler.execute
        @last_reconcile_at = Time.now

        total_actions = result[:resumed] + result[:reconciled] + result[:cleaned]
        if total_actions > 0 || @verbose
          display_message(
            "🔄 Worktree reconciliation: #{result[:resumed]} resumed, " \
            "#{result[:reconciled]} reconciled, #{result[:cleaned]} cleaned",
            type: :info
          )
        end
      rescue => e
        Aidp.log_error("watch_runner", "worktree_reconciliation_failed", error: e.message)
        display_message("⚠️  Worktree reconciliation failed: #{e.message}", type: :warn) if @verbose
      end
    end
  end
end
