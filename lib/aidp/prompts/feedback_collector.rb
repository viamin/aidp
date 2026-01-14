# frozen_string_literal: true

require_relative "../database/repositories/prompt_feedback_repository"
require_relative "template_version_manager"

module Aidp
  module Prompts
    # Collects and stores feedback about prompt effectiveness
    #
    # Tracks:
    # - Prompt template usage
    # - Completion outcomes (success/failure)
    # - Iteration counts
    # - User reactions
    # - Suggested improvements
    #
    # The collected feedback can be used for:
    # - AGD pattern: Generating improved prompts based on feedback
    # - Analytics: Understanding which prompts work well
    # - Evolution: Automatic prompt improvement over time
    #
    # Per issue #402: Integrates with TemplateVersionManager to:
    # - Record positive votes (count but don't alter templates)
    # - Record negative votes (trigger AGD for new template variants)
    #
    # @example Record feedback
    #   collector = FeedbackCollector.new(project_dir: Dir.pwd)
    #   collector.record(
    #     template_id: "decision_engine/condition_detection",
    #     outcome: :success,
    #     iterations: 5,
    #     context: { task: "classify API error" }
    #   )
    #
    class FeedbackCollector
      attr_reader :project_dir, :repository

      # Threshold for logging error about persistent version manager failures
      VERSION_MANAGER_FAILURE_THRESHOLD = 3

      def initialize(project_dir: Dir.pwd, repository: nil, version_manager: nil)
        @project_dir = project_dir
        @repository = repository || Database::Repositories::PromptFeedbackRepository.new(project_dir: project_dir)
        @version_manager_instance = version_manager
        @version_manager_failure_count = 0
      end

      # Lazily initialize version manager
      def version_manager
        @version_manager_instance ||= TemplateVersionManager.new(project_dir: @project_dir)
      end

      # Record feedback for a prompt template
      #
      # @param template_id [String] Template identifier
      # @param outcome [Symbol] :success, :failure, :abandoned, :timeout
      # @param iterations [Integer, nil] Number of iterations to completion
      # @param user_reaction [Symbol, nil] :positive, :negative, :neutral
      # @param suggestions [Array<String>, nil] Improvement suggestions
      # @param context [Hash] Additional context (task type, error type, etc.)
      # @param track_version [Boolean] Whether to update version manager (default: true)
      def record(template_id:, outcome:, iterations: nil, user_reaction: nil, suggestions: nil, context: {}, track_version: true)
        Aidp.log_debug("feedback_collector", "recording_feedback",
          template_id: template_id,
          outcome: outcome,
          iterations: iterations,
          user_reaction: user_reaction)

        result = @repository.record(
          template_id: template_id,
          outcome: outcome,
          iterations: iterations,
          user_reaction: user_reaction,
          suggestions: suggestions,
          context: context
        )

        if result[:success]
          Aidp.log_info("feedback_collector", "feedback_recorded",
            template_id: template_id,
            outcome: outcome)

          # Per issue #402: Update version manager based on user reaction
          if track_version && user_reaction
            update_version_feedback(
              template_id: template_id,
              user_reaction: user_reaction,
              suggestions: suggestions,
              context: context
            )
          end
        else
          Aidp.log_warn("feedback_collector", "feedback_record_failed",
            template_id: template_id,
            error: result[:error])
        end

        result
      end

      # Get feedback summary for a template
      #
      # @param template_id [String] Template identifier
      # @return [Hash] Summary statistics
      def summary(template_id:)
        @repository.summary(template_id: template_id)
      end

      # Get feedback entries for analysis
      #
      # @param template_id [String, nil] Filter by template (nil for all)
      # @param outcome [Symbol, nil] Filter by outcome
      # @param limit [Integer] Maximum entries to return
      # @return [Array<Hash>] Feedback entries
      def entries(template_id: nil, outcome: nil, limit: 100)
        @repository.list(template_id: template_id, outcome: outcome, limit: limit)
      end

      # Get templates that need improvement based on feedback
      #
      # @param min_uses [Integer] Minimum uses to consider
      # @param max_success_rate [Float] Success rate threshold (0-100)
      # @return [Array<Hash>] Templates needing improvement with summaries
      def templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)
        @repository.templates_needing_improvement(
          min_uses: min_uses,
          max_success_rate: max_success_rate
        )
      end

      # Clear all feedback data
      def clear
        result = @repository.clear
        Aidp.log_info("feedback_collector", "feedback_cleared", count: result[:count])
        result
      end

      # Check if any feedback exists
      #
      # @return [Boolean]
      def any?
        @repository.any?
      end

      private

      # Update version manager based on user reaction
      # Per issue #402:
      # - Positive feedback: Count votes, prioritize for future use
      # - Negative feedback: Trigger AGD to create new variant
      def update_version_feedback(template_id:, user_reaction:, suggestions:, context:)
        # Only process versionable templates (work_loop category initially)
        return unless version_manager.versionable?(template_id)

        case user_reaction.to_sym
        when :positive
          Aidp.log_debug("feedback_collector", "recording_positive_version_feedback",
            template_id: template_id)
          version_manager.record_positive_feedback(template_id: template_id)

        when :negative
          Aidp.log_debug("feedback_collector", "recording_negative_version_feedback",
            template_id: template_id,
            suggestion_count: suggestions&.size || 0)

          # Record negative feedback - this will mark evolution as pending
          version_manager.record_negative_feedback(
            template_id: template_id,
            suggestions: suggestions || [],
            context: context
          )
        end

        # Reset failure count on successful operation
        reset_version_manager_failure_count
      rescue => e
        # Track consecutive failures to detect persistent issues
        @version_manager_failure_count += 1

        if @version_manager_failure_count >= VERSION_MANAGER_FAILURE_THRESHOLD
          Aidp.log_error("feedback_collector", "persistent_version_manager_failures",
            template_id: template_id,
            failure_count: @version_manager_failure_count,
            error: e.message)
        else
          Aidp.log_warn("feedback_collector", "version_feedback_update_failed",
            template_id: template_id,
            error: e.message)
        end
      end

      # Reset failure count on successful version update (called after successful operations)
      def reset_version_manager_failure_count
        @version_manager_failure_count = 0
      end
    end
  end
end
