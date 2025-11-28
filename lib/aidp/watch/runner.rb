# frozen_string_literal: true

require "tty-prompt"

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
        process_auto_issue_triggers
        check_for_updates_if_due
        process_review_triggers
        process_ci_fix_triggers
        process_auto_pr_triggers
        process_change_request_triggers
      end

      def process_plan_triggers
        plan_label = @plan_processor.plan_label
        begin
          issues = @repository_client.list_issues(labels: [plan_label], state: "open")
        rescue => e
          Aidp.log_error("watch_runner", "plan_poll_failed", label: plan_label, error: e.message)
          return # Skip this cycle, continue watch loop
        end
        Aidp.log_debug("watch_runner", "plan_poll", label: plan_label, total: issues.size)
        issues.each do |issue|
          unless issue_has_label?(issue, plan_label)
            Aidp.log_debug("watch_runner", "plan_skip_label_mismatch", issue: issue[:number], labels: issue[:labels])
            next
          end

          begin
            detailed = @repository_client.fetch_issue(issue[:number])
          rescue => e
            Aidp.log_error("watch_runner", "fetch_issue_failed", issue: issue[:number], error: e.message)
            next # Skip this issue, continue with others
          end

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "plan_skip_in_progress", issue: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "plan_skip_unauthorized_author", issue: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, plan_label)
            post_detection_comment(item_type: :issue, number: detailed[:number], label: plan_label)
          end

          Aidp.log_debug("watch_runner", "plan_process", issue: detailed[:number])
          @plan_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
        end
      end

      def process_build_triggers
        build_label = @build_processor.build_label
        begin
          issues = @repository_client.list_issues(labels: [build_label], state: "open")
        rescue => e
          Aidp.log_error("watch_runner", "build_poll_failed", label: build_label, error: e.message)
          return # Skip this cycle, continue watch loop
        end
        Aidp.log_debug("watch_runner", "build_poll", label: build_label, total: issues.size)
        issues.each do |issue|
          detailed = nil
          in_progress_added = false

          begin
            unless issue_has_label?(issue, build_label)
              Aidp.log_debug("watch_runner", "build_skip_label_mismatch", issue: issue[:number], labels: issue[:labels])
              next
            end

            begin
              detailed = @repository_client.fetch_issue(issue[:number])
            rescue => e
              Aidp.log_error("watch_runner", "fetch_issue_failed", issue: issue[:number], error: e.message)
              next # Skip this issue, continue with others
            end

            # Check if already completed (via GitHub comments)
            if @state_extractor.build_completed?(detailed)
              Aidp.log_debug("watch_runner", "build_skip_completed", issue: detailed[:number])
              next
            end

            # Check if already in progress by another instance
            if @state_extractor.in_progress?(detailed)
              Aidp.log_debug("watch_runner", "build_skip_in_progress", issue: detailed[:number])
              next
            end

            # Check author authorization before processing
            unless @safety_checker.should_process_issue?(detailed, enforce: false)
              Aidp.log_debug("watch_runner", "build_skip_unauthorized_author", issue: detailed[:number], author: detailed[:author])
              next
            end

            # Check if detection comment already posted (deduplication)
            unless @state_extractor.detection_comment_posted?(detailed, build_label)
              post_detection_comment(item_type: :issue, number: detailed[:number], label: build_label)
            end

            # Add in-progress label before processing
            @repository_client.add_labels(detailed[:number], GitHubStateExtractor::IN_PROGRESS_LABEL)
            in_progress_added = true

            Aidp.log_debug("watch_runner", "build_process", issue: detailed[:number])
            @build_processor.process(detailed)
          rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
            Aidp.log_warn("watch_runner", "unauthorized issue author", issue: issue[:number], error: e.message)
          ensure
            # Remove in-progress label when done (only if we added it)
            if in_progress_added && detailed
              begin
                @repository_client.remove_labels(detailed[:number], GitHubStateExtractor::IN_PROGRESS_LABEL)
              rescue => e
                Aidp.log_warn("watch_runner", "failed_to_remove_in_progress_label", issue: detailed[:number], error: e.message)
              end
            end
          end
        end
      end

      def process_auto_issue_triggers
        auto_label = @auto_processor.auto_label
        begin
          issues = @repository_client.list_issues(labels: [auto_label], state: "open")
        rescue => e
          Aidp.log_error("watch_runner", "auto_issue_poll_failed", label: auto_label, error: e.message)
          return
        end

        Aidp.log_debug("watch_runner", "auto_issue_poll", label: auto_label, total: issues.size)

        issues.each do |issue|
          unless issue_has_label?(issue, auto_label)
            Aidp.log_debug("watch_runner", "auto_issue_skip_label_mismatch", issue: issue[:number], labels: issue[:labels])
            next
          end

          begin
            detailed = @repository_client.fetch_issue(issue[:number])
          rescue => e
            Aidp.log_error("watch_runner", "auto_issue_fetch_failed", issue: issue[:number], error: e.message)
            next
          end

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "auto_issue_skip_in_progress", issue: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "auto_issue_skip_unauthorized_author", issue: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, auto_label)
            post_detection_comment(item_type: :issue, number: detailed[:number], label: auto_label)
          end

          Aidp.log_debug("watch_runner", "auto_issue_process", issue: detailed[:number])
          @auto_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized_issue_author_auto", issue: issue[:number], error: e.message)
        end
      end

      def process_review_triggers
        review_label = @review_processor.review_label
        begin
          prs = @repository_client.list_pull_requests(labels: [review_label], state: "open")
        rescue => e
          Aidp.log_error("watch_runner", "review_poll_failed", label: review_label, error: e.message)
          return # Skip this cycle, continue watch loop
        end
        Aidp.log_debug("watch_runner", "review_poll", label: review_label, total: prs.size)
        prs.each do |pr|
          unless pr_has_label?(pr, review_label)
            Aidp.log_debug("watch_runner", "review_skip_label_mismatch", pr: pr[:number], labels: pr[:labels])
            next
          end

          begin
            detailed = @repository_client.fetch_pull_request(pr[:number])
          rescue => e
            Aidp.log_error("watch_runner", "fetch_pr_failed", pr: pr[:number], error: e.message)
            next # Skip this PR, continue with others
          end

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "review_skip_in_progress", pr: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "review_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, review_label)
            post_detection_comment(item_type: :pr, number: detailed[:number], label: review_label)
          end

          Aidp.log_debug("watch_runner", "review_process", pr: detailed[:number])
          @review_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized PR author", pr: pr[:number], error: e.message)
        end
      end

      def process_auto_pr_triggers
        auto_label = @auto_pr_processor.auto_label
        prs = @repository_client.list_pull_requests(labels: [auto_label], state: "open")
        Aidp.log_debug("watch_runner", "auto_pr_poll", label: auto_label, total: prs.size)

        prs.each do |pr|
          unless pr_has_label?(pr, auto_label)
            Aidp.log_debug("watch_runner", "auto_pr_skip_label_mismatch", pr: pr[:number], labels: pr[:labels])
            next
          end

          detailed = @repository_client.fetch_pull_request(pr[:number])

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "auto_pr_skip_in_progress", pr: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "auto_pr_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, auto_label)
            post_detection_comment(item_type: :pr, number: detailed[:number], label: auto_label)
          end

          Aidp.log_debug("watch_runner", "auto_pr_process", pr: detailed[:number])
          @auto_pr_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized_pr_author_auto", pr: pr[:number], error: e.message)
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

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "ci_fix_skip_in_progress", pr: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "ci_fix_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, ci_fix_label)
            post_detection_comment(item_type: :pr, number: detailed[:number], label: ci_fix_label)
          end

          Aidp.log_debug("watch_runner", "ci_fix_process", pr: detailed[:number])
          @ci_fix_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized PR author", pr: pr[:number], error: e.message)
        end
      end

      def process_change_request_triggers
        change_request_label = @change_request_processor.change_request_label
        prs = @repository_client.list_pull_requests(labels: [change_request_label], state: "open")
        Aidp.log_debug("watch_runner", "change_request_poll", label: change_request_label, total: prs.size)
        prs.each do |pr|
          unless pr_has_label?(pr, change_request_label)
            Aidp.log_debug("watch_runner", "change_request_skip_label_mismatch", pr: pr[:number], labels: pr[:labels])
            next
          end

          detailed = @repository_client.fetch_pull_request(pr[:number])

          # Check if already in progress by another instance
          if @state_extractor.in_progress?(detailed)
            Aidp.log_debug("watch_runner", "change_request_skip_in_progress", pr: detailed[:number])
            next
          end

          # Check author authorization before processing
          unless @safety_checker.should_process_issue?(detailed, enforce: false)
            Aidp.log_debug("watch_runner", "change_request_skip_unauthorized_author", pr: detailed[:number], author: detailed[:author])
            next
          end

          # Check if detection comment already posted (deduplication)
          unless @state_extractor.detection_comment_posted?(detailed, change_request_label)
            post_detection_comment(item_type: :pr, number: detailed[:number], label: change_request_label)
          end

          Aidp.log_debug("watch_runner", "change_request_process", pr: detailed[:number])
          @change_request_processor.process(detailed)
        rescue RepositorySafetyChecker::UnauthorizedAuthorError => e
          Aidp.log_warn("watch_runner", "unauthorized PR author", pr: pr[:number], error: e.message)
        end
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
          display_message("🔄 Update available: #{update_check.current_version} → #{update_check.available_version}", type: :highlight)

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
    end
  end
end
