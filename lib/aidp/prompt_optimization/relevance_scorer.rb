# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Scores fragments based on relevance to current task context
    #
    # Calculates relevance scores (0.0-1.0) for fragments based on:
    # - Task type (feature, bugfix, refactor, test)
    # - Affected files and code locations
    # - Work loop step (planning vs implementation)
    # - Keywords and semantic similarity
    #
    # @example Basic usage
    #   scorer = RelevanceScorer.new
    #   context = TaskContext.new(task_type: :feature, affected_files: ["user.rb"])
    #   score = scorer.score_fragment(fragment, context)
    class RelevanceScorer
      # Default scoring weights
      DEFAULT_WEIGHTS = {
        task_type_match: 0.3,
        tag_match: 0.25,
        file_location_match: 0.25,
        step_match: 0.2
      }.freeze

      def initialize(weights: DEFAULT_WEIGHTS)
        @weights = weights
      end

      # Score a single fragment
      #
      # @param fragment [Fragment, TemplateFragment, CodeFragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Float] Relevance score (0.0-1.0)
      def score_fragment(fragment, context)
        scores = {}

        scores[:task_type] = score_task_type_match(fragment, context) * @weights[:task_type_match]
        scores[:tags] = score_tag_match(fragment, context) * @weights[:tag_match]
        scores[:location] = score_file_location_match(fragment, context) * @weights[:file_location_match]
        scores[:step] = score_step_match(fragment, context) * @weights[:step_match]

        total_score = scores.values.sum
        normalize_score(total_score)
      end

      # Score multiple fragments
      #
      # @param fragments [Array] List of fragments
      # @param context [TaskContext] Task context
      # @return [Array<Hash>] List of {fragment:, score:, breakdown:}
      def score_fragments(fragments, context)
        fragments.map do |fragment|
          score = score_fragment(fragment, context)
          {
            fragment: fragment,
            score: score,
            breakdown: score_breakdown(fragment, context)
          }
        end.sort_by { |result| -result[:score] }
      end

      private

      # Score based on task type matching
      #
      # @param fragment [Fragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Float] Score 0.0-1.0
      def score_task_type_match(fragment, context)
        return 0.5 unless context.task_type # Neutral if unknown

        task_tags = task_type_to_tags(context.task_type)
        return 0.3 if task_tags.empty? # Low default score

        if fragment.respond_to?(:tags)
          matching_tags = fragment.tags & task_tags
          matching_tags.empty? ? 0.3 : (matching_tags.count.to_f / task_tags.count)
        else
          0.3
        end
      end

      # Score based on tag matching
      #
      # @param fragment [Fragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Float] Score 0.0-1.0
      def score_tag_match(fragment, context)
        return 0.5 unless context.tags && !context.tags.empty?

        if fragment.respond_to?(:tags)
          matching_tags = fragment.tags & context.tags
          matching_tags.empty? ? 0.2 : (matching_tags.count.to_f / context.tags.count).clamp(0.0, 1.0)
        else
          0.5
        end
      end

      # Score based on file location matching
      #
      # @param fragment [Fragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Float] Score 0.0-1.0
      def score_file_location_match(fragment, context)
        return 0.5 unless context.affected_files && !context.affected_files.empty?

        # Only code fragments have file_path
        return 0.5 unless fragment.respond_to?(:file_path)

        # Check if fragment is from an affected file
        (context.affected_files.any? do |affected_file|
          fragment.file_path.include?(affected_file)
        end) ? 1.0 : 0.1
      end

      # Score based on work loop step
      #
      # @param fragment [Fragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Float] Score 0.0-1.0
      def score_step_match(fragment, context)
        return 0.5 unless context.step_name

        step_tags = step_to_tags(context.step_name)
        return 0.5 if step_tags.empty?

        if fragment.respond_to?(:tags)
          matching_tags = fragment.tags & step_tags
          matching_tags.empty? ? 0.3 : 0.8
        elsif fragment.respond_to?(:category)
          # Template fragments have categories
          step_tags.include?(fragment.category) ? 0.9 : 0.4
        else
          0.5
        end
      end

      # Get detailed score breakdown
      #
      # @param fragment [Fragment] Fragment to score
      # @param context [TaskContext] Task context
      # @return [Hash] Score breakdown
      def score_breakdown(fragment, context)
        {
          task_type: score_task_type_match(fragment, context),
          tags: score_tag_match(fragment, context),
          location: score_file_location_match(fragment, context),
          step: score_step_match(fragment, context)
        }
      end

      # Normalize score to 0.0-1.0 range
      #
      # @param score [Float] Raw score
      # @return [Float] Normalized score
      def normalize_score(score)
        score.clamp(0.0, 1.0)
      end

      # Map task type to relevant tags
      #
      # @param task_type [Symbol] Task type
      # @return [Array<String>] List of relevant tags
      def task_type_to_tags(task_type)
        case task_type
        when :feature, :enhancement
          ["implementation", "planning", "testing", "api"]
        when :bugfix, :fix
          ["testing", "error", "debugging", "logging"]
        when :refactor, :refactoring
          ["refactor", "architecture", "testing", "performance"]
        when :test, :testing
          ["testing", "analyst"]
        when :documentation, :docs
          ["documentation", "planning"]
        when :security
          ["security", "testing", "error"]
        when :performance
          ["performance", "testing", "refactor"]
        else
          []
        end
      end

      # Map work loop step to relevant tags
      #
      # @param step_name [String] Step name
      # @return [Array<String>] List of relevant tags
      def step_to_tags(step_name)
        step_lower = step_name.to_s.downcase

        tags = []
        tags << "planning" if step_lower.include?("plan") || step_lower.include?("design")
        tags << "analysis" if step_lower.include?("analy")
        tags << "implementation" if step_lower.include?("implement") || step_lower.include?("code")
        tags << "testing" if step_lower.include?("test")
        tags << "refactor" if step_lower.include?("refactor")
        tags << "documentation" if step_lower.include?("doc")
        tags << "security" if step_lower.include?("security")

        tags
      end
    end

    # Represents the context for a task
    #
    # Contains information about the current work being done,
    # used to calculate relevance scores for fragments
    class TaskContext
      attr_accessor :task_type, :description, :affected_files, :step_name, :tags

      # @param task_type [Symbol] Type of task (:feature, :bugfix, :refactor, etc.)
      # @param description [String] Task description
      # @param affected_files [Array<String>] List of files being modified
      # @param step_name [String] Current work loop step name
      # @param tags [Array<String>] Additional context tags
      def initialize(task_type: nil, description: nil, affected_files: [], step_name: nil, tags: [])
        @task_type = task_type
        @description = description
        @affected_files = affected_files || []
        @step_name = step_name
        @tags = tags || []

        # Extract additional tags from description if provided
        extract_tags_from_description if @description
      end

      # Extract relevant tags from description text
      def extract_tags_from_description
        return unless @description

        desc_lower = @description.downcase

        @tags << "testing" if /test|spec|coverage/.match?(desc_lower)
        @tags << "security" if /security|auth|permission/.match?(desc_lower)
        @tags << "performance" if /performance|speed|optimization/.match?(desc_lower)
        @tags << "database" if /database|sql|migration/.match?(desc_lower)
        @tags << "api" if /\bapi\b|endpoint|rest/.match?(desc_lower)
        @tags << "ui" if /\bui\b|interface|view/.match?(desc_lower)

        @tags.uniq!
      end

      def to_h
        {
          task_type: @task_type,
          description: @description,
          affected_files: @affected_files,
          step_name: @step_name,
          tags: @tags
        }
      end
    end
  end
end
