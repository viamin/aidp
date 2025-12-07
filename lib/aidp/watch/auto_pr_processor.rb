# frozen_string_literal: true

require_relative "../message_display"
require_relative "github_state_extractor"

module Aidp
  module Watch
    # Handles the aidp-auto label on PRs by chaining review and CI-fix flows
    # until the PR is ready for human review.
    #
    # Completion criteria:
    # - Automated review completed (or already processed)
    # - CI passing (success or skipped states accepted)
    # - Iteration cap not exceeded (default: 20)
    #
    # When complete:
    # - Converts draft PR to ready for review
    # - Requests the label-adder as reviewer
    # - Posts completion comment
    # - Removes aidp-auto label
    class AutoPrProcessor
      include Aidp::MessageDisplay

      DEFAULT_AUTO_LABEL = "aidp-auto"
      DEFAULT_ITERATION_CAP = 20
      PASSING_CI_STATES = %w[success skipped].freeze

      def initialize(repository_client:, state_store:, review_processor:, ci_fix_processor:,
        label_config: {}, iteration_cap: nil, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @review_processor = review_processor
        @ci_fix_processor = ci_fix_processor
        @state_extractor = GitHubStateExtractor.new(repository_client: repository_client)
        @verbose = verbose
        @auto_label = label_config[:auto_trigger] || label_config["auto_trigger"] || DEFAULT_AUTO_LABEL
        @iteration_cap = iteration_cap || DEFAULT_ITERATION_CAP
      end

      def process(pr)
        number = pr[:number]
        Aidp.log_debug("auto_pr_processor", "process_started", pr: number, title: pr[:title])
        display_message("🤖 Running autonomous review/CI loop for PR ##{number}", type: :info)

        # Record this iteration
        iteration = @state_store.record_auto_pr_iteration(number)
        Aidp.log_debug("auto_pr_processor", "iteration_recorded", pr: number, iteration: iteration, cap: @iteration_cap)

        # Check iteration cap
        if iteration > @iteration_cap
          Aidp.log_warn("auto_pr_processor", "iteration_cap_reached",
            pr: number, iteration: iteration, cap: @iteration_cap)
          display_message("⚠️  PR ##{number} reached iteration cap (#{@iteration_cap}), marking ready", type: :warn)
          finalize_pr(pr_number: number, reason: :iteration_cap_reached)
          return
        end

        # Run review and CI fix flows. Each processor is responsible for its own guards.
        @review_processor.process(pr)
        @ci_fix_processor.process(pr)

        finalize_if_ready(pr_number: number)
      rescue => e
        Aidp.log_error("auto_pr_processor", "process_failed", pr: pr[:number], error: e.message, error_class: e.class.name)
        display_message("❌ aidp-auto failed on PR ##{pr[:number]}: #{e.message}", type: :error)
      end

      attr_reader :auto_label, :iteration_cap

      private

      def finalize_if_ready(pr_number:)
        pr_data = @repository_client.fetch_pull_request(pr_number)
        ci_status = @repository_client.fetch_ci_status(pr_number)

        review_done = @state_extractor.review_completed?(pr_data) || @state_store.review_processed?(pr_number)
        ci_passing = ci_state_passing?(ci_status)

        Aidp.log_debug("auto_pr_processor", "completion_check",
          pr: pr_number,
          review_done: review_done,
          ci_state: ci_status[:state],
          ci_passing: ci_passing)

        return unless review_done && ci_passing

        finalize_pr(pr_number: pr_number, reason: :completion_criteria_met)
      end

      # Check if CI state indicates passing (success or skipped)
      # @param ci_status [Hash] CI status from repository_client
      # @return [Boolean] True if CI is considered passing
      def ci_state_passing?(ci_status)
        state = ci_status[:state]

        # Direct state match
        return true if PASSING_CI_STATES.include?(state)

        # Check individual checks - all must be success or skipped
        checks = ci_status[:checks] || []
        return false if checks.empty?

        checks.all? do |check|
          conclusion = check[:conclusion]
          PASSING_CI_STATES.include?(conclusion)
        end
      end

      def finalize_pr(pr_number:, reason:)
        Aidp.log_info("auto_pr_processor", "finalizing_pr",
          pr: pr_number, reason: reason)

        # Convert draft to ready if needed
        convert_draft_to_ready(pr_number)

        # Request reviewer (label-adder)
        request_label_adder_as_reviewer(pr_number)

        # Post completion comment
        post_completion_comment(pr_number, reason: reason)

        # Remove auto label
        remove_auto_label(pr_number)

        # Mark as completed in state store
        @state_store.complete_auto_pr(pr_number, reason: reason.to_s)

        display_message("✅ PR ##{pr_number} ready for human review", type: :success)
      end

      def convert_draft_to_ready(pr_number)
        pr_data = @repository_client.fetch_pull_request(pr_number)

        # Check if PR is a draft (gh returns isDraft in the data)
        # The normalize methods don't include draft status, so we need to check via API
        # For now, attempt the conversion and let it fail gracefully if already ready
        success = @repository_client.mark_pr_ready_for_review(pr_number)
        if success
          display_message("📋 Converted PR ##{pr_number} from draft to ready", type: :info)
        else
          Aidp.log_debug("auto_pr_processor", "draft_conversion_skipped",
            pr: pr_number, message: "PR may already be ready for review")
        end
      rescue => e
        Aidp.log_warn("auto_pr_processor", "draft_conversion_failed",
          pr: pr_number, error: e.message)
      end

      def request_label_adder_as_reviewer(pr_number)
        label_actor = @repository_client.most_recent_pr_label_actor(pr_number)

        unless label_actor
          Aidp.log_debug("auto_pr_processor", "no_label_actor_found", pr: pr_number)
          return
        end

        success = @repository_client.request_reviewers(pr_number, reviewers: [label_actor])
        if success
          display_message("👤 Requested @#{label_actor} as reviewer on PR ##{pr_number}", type: :info)
        else
          Aidp.log_warn("auto_pr_processor", "reviewer_request_failed",
            pr: pr_number, reviewer: label_actor)
        end
      rescue => e
        Aidp.log_warn("auto_pr_processor", "reviewer_request_exception",
          pr: pr_number, error: e.message)
      end

      def post_completion_comment(pr_number, reason:)
        iteration = @state_store.auto_pr_iteration_count(pr_number)

        reason_text = case reason
        when :iteration_cap_reached
          "Iteration cap (#{@iteration_cap}) reached"
        when :completion_criteria_met
          "All completion criteria met"
        else
          "Processing complete"
        end

        comment = <<~COMMENT
          ## 🤖 aidp-auto

          #{reason_text} after #{iteration} iteration(s).

          - Automated review completed
          - CI is passing (success/skipped)

          Marking this PR ready for human review and removing the `#{@auto_label}` label.
        COMMENT

        @repository_client.post_comment(pr_number, comment)
        display_message("💬 Posted aidp-auto completion comment on PR ##{pr_number}", type: :success)
      rescue => e
        Aidp.log_warn("auto_pr_processor", "comment_failed", pr: pr_number, error: e.message)
      end

      def remove_auto_label(pr_number)
        @repository_client.remove_labels(pr_number, @auto_label)
        display_message("🏷️  Removed '#{@auto_label}' from PR ##{pr_number}", type: :info)
      rescue => e
        Aidp.log_warn("auto_pr_processor", "remove_label_failed", pr: pr_number, error: e.message)
      end
    end
  end
end
