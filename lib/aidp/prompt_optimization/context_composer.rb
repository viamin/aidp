# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Composes optimal context from scored fragments within token budget
    #
    # Selects the best combination of fragments that fits within
    # the token budget while maximizing relevance and coverage.
    #
    # Algorithm:
    # 1. Sort fragments by relevance score
    # 2. Always include critical fragments (score > 0.9)
    # 3. Fill remaining budget with highest-scoring fragments
    # 4. Deduplicate overlapping content
    # 5. Return selected fragments with statistics
    #
    # @example Basic usage
    #   composer = ContextComposer.new(max_tokens: 8000)
    #   selection = composer.compose(scored_fragments, thresholds: {...})
    class ContextComposer
      attr_reader :max_tokens

      # Thresholds for different fragment types
      CRITICAL_SCORE_THRESHOLD = 0.9
      MINIMUM_SCORE_THRESHOLD = 0.3

      def initialize(max_tokens: 16000)
        @max_tokens = max_tokens
      end

      # Compose optimal context from scored fragments
      #
      # @param scored_fragments [Array<Hash>] List of {fragment:, score:, breakdown:}
      # @param thresholds [Hash] Type-specific thresholds {:style_guide, :templates, :source}
      # @param reserved_tokens [Integer] Tokens to reserve for task description, etc.
      # @return [CompositionResult] Selected fragments and statistics
      def compose(scored_fragments, thresholds: {}, reserved_tokens: 2000)
        available_budget = @max_tokens - reserved_tokens

        # Separate fragments by type for threshold checking
        categorized = categorize_fragments(scored_fragments, thresholds)

        # Start with critical fragments (always included)
        selected = select_critical_fragments(categorized[:critical])
        used_tokens = calculate_total_tokens(selected)

        # Add high-priority fragments within budget
        selected, used_tokens = add_fragments_within_budget(
          selected,
          categorized[:high_priority],
          available_budget - used_tokens
        )

        # Fill remaining budget with other fragments if space allows
        selected, used_tokens = add_fragments_within_budget(
          selected,
          categorized[:medium_priority],
          available_budget - used_tokens
        )

        # Deduplicate if requested
        selected = deduplicate_fragments(selected) if categorized[:needs_dedup]

        CompositionResult.new(
          selected_fragments: selected,
          total_tokens: used_tokens,
          budget: available_budget,
          excluded_count: scored_fragments.length - selected.length,
          average_score: calculate_average_score(selected)
        )
      end

      private

      # Categorize fragments by priority and type
      #
      # @param scored_fragments [Array<Hash>] Scored fragments
      # @param thresholds [Hash] Type-specific thresholds
      # @return [Hash] Categorized fragments
      def categorize_fragments(scored_fragments, thresholds)
        critical = []
        high_priority = []
        medium_priority = []

        scored_fragments.each do |item|
          score = item[:score]
          fragment = item[:fragment]

          # Critical fragments always included
          if score >= CRITICAL_SCORE_THRESHOLD
            critical << item
          # Check type-specific thresholds
          elsif meets_threshold?(fragment, score, thresholds)
            high_priority << item
          # Medium priority if above minimum
          elsif score >= MINIMUM_SCORE_THRESHOLD
            medium_priority << item
          end
        end

        {
          critical: critical,
          high_priority: high_priority.sort_by { |item| -item[:score] },
          medium_priority: medium_priority.sort_by { |item| -item[:score] },
          needs_dedup: true
        }
      end

      # Check if fragment meets type-specific threshold
      #
      # @param fragment [Fragment] Fragment to check
      # @param score [Float] Relevance score
      # @param thresholds [Hash] Type-specific thresholds
      # @return [Boolean] True if meets threshold
      def meets_threshold?(fragment, score, thresholds)
        threshold = if fragment.class.name.include?("Fragment") && fragment.respond_to?(:heading)
          thresholds[:style_guide] || 0.75
        elsif fragment.respond_to?(:category)
          thresholds[:templates] || 0.8
        elsif fragment.respond_to?(:file_path) && fragment.respond_to?(:type)
          thresholds[:source] || 0.7
        else
          0.75
        end

        score >= threshold
      end

      # Select critical fragments (always included regardless of budget)
      #
      # @param critical_items [Array<Hash>] Critical scored fragments
      # @return [Array<Hash>] Selected critical fragments
      def select_critical_fragments(critical_items)
        critical_items
      end

      # Add fragments within remaining budget
      #
      # @param selected [Array<Hash>] Already selected fragments
      # @param candidates [Array<Hash>] Candidate fragments to add
      # @param remaining_budget [Integer] Remaining token budget
      # @return [Array] [updated_selected, tokens_used]
      def add_fragments_within_budget(selected, candidates, remaining_budget)
        used_tokens = 0

        candidates.each do |item|
          fragment_tokens = estimate_fragment_tokens(item[:fragment])

          if used_tokens + fragment_tokens <= remaining_budget
            selected << item
            used_tokens += fragment_tokens
          end
        end

        [selected, calculate_total_tokens(selected)]
      end

      # Deduplicate fragments with overlapping content
      #
      # @param selected [Array<Hash>] Selected fragments
      # @return [Array<Hash>] Deduplicated fragments
      def deduplicate_fragments(selected)
        # Simple deduplication: remove fragments with identical IDs
        seen_ids = Set.new
        selected.select do |item|
          id = item[:fragment].respond_to?(:id) ? item[:fragment].id : item[:fragment].object_id
          !seen_ids.include?(id).tap { seen_ids << id }
        end
      end

      # Estimate tokens for a fragment
      #
      # @param fragment [Fragment] Fragment to estimate
      # @return [Integer] Estimated tokens
      def estimate_fragment_tokens(fragment)
        if fragment.respond_to?(:estimated_tokens)
          fragment.estimated_tokens
        elsif fragment.respond_to?(:content)
          (fragment.content.length / 4.0).ceil
        else
          100 # Default estimate
        end
      end

      # Calculate total tokens for selected fragments
      #
      # @param selected [Array<Hash>] Selected fragments
      # @return [Integer] Total tokens
      def calculate_total_tokens(selected)
        selected.sum { |item| estimate_fragment_tokens(item[:fragment]) }
      end

      # Calculate average score of selected fragments
      #
      # @param selected [Array<Hash>] Selected fragments
      # @return [Float] Average score
      def calculate_average_score(selected)
        return 0.0 if selected.empty?

        total = selected.sum { |item| item[:score] }
        (total / selected.length.to_f).round(3)
      end
    end

    # Result of context composition
    #
    # Contains selected fragments and composition statistics
    class CompositionResult
      attr_reader :selected_fragments, :total_tokens, :budget, :excluded_count, :average_score

      def initialize(selected_fragments:, total_tokens:, budget:, excluded_count:, average_score:)
        @selected_fragments = selected_fragments
        @total_tokens = total_tokens
        @budget = budget
        @excluded_count = excluded_count
        @average_score = average_score
      end

      # Calculate budget utilization percentage
      #
      # @return [Float] Percentage used (0.0-100.0)
      def budget_utilization
        return 0.0 if @budget.zero?

        ((@total_tokens.to_f / @budget) * 100).round(2)
      end

      # Get count of selected fragments
      #
      # @return [Integer] Number of selected fragments
      def selected_count
        @selected_fragments.length
      end

      # Check if budget was exceeded
      #
      # @return [Boolean] True if over budget
      def over_budget?
        @total_tokens > @budget
      end

      # Get fragments by type
      #
      # @param type [Symbol] Fragment type (:style_guide, :template, :code)
      # @return [Array<Hash>] Fragments of specified type
      def fragments_by_type(type)
        @selected_fragments.select do |item|
          case type
          when :style_guide
            item[:fragment].class.name.include?("Fragment") && item[:fragment].respond_to?(:heading)
          when :template
            item[:fragment].respond_to?(:category) && !item[:fragment].respond_to?(:type)
          when :code
            item[:fragment].respond_to?(:type) && item[:fragment].respond_to?(:file_path)
          else
            false
          end
        end
      end

      # Get summary statistics
      #
      # @return [Hash] Composition statistics
      def summary
        {
          selected_count: selected_count,
          excluded_count: @excluded_count,
          total_tokens: @total_tokens,
          budget: @budget,
          utilization: budget_utilization,
          average_score: @average_score,
          over_budget: over_budget?,
          by_type: {
            style_guide: fragments_by_type(:style_guide).count,
            templates: fragments_by_type(:template).count,
            code: fragments_by_type(:code).count
          }
        }
      end

      def to_s
        "CompositionResult<#{selected_count} fragments, #{@total_tokens}/#{@budget} tokens (#{budget_utilization}%)>"
      end
    end
  end
end
