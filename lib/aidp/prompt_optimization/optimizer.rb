# frozen_string_literal: true

require_relative "style_guide_indexer"
require_relative "template_indexer"
require_relative "source_code_fragmenter"
require_relative "relevance_scorer"
require_relative "context_composer"
require_relative "prompt_builder"

module Aidp
  module PromptOptimization
    # Main coordinator for prompt optimization
    #
    # Orchestrates all components to produce an optimized prompt:
    # 1. Index style guide, templates, and source code
    # 2. Score fragments based on task context
    # 3. Select optimal fragments within token budget
    # 4. Build final prompt markdown
    #
    # @example Basic usage
    #   optimizer = Optimizer.new(project_dir: "/project", config: config)
    #   result = optimizer.optimize_prompt(
    #     task_type: :feature,
    #     description: "Add user auth",
    #     affected_files: ["lib/user.rb"],
    #     step_name: "implementation"
    #   )
    #   result.write_to_file("PROMPT.md")
    class Optimizer
      attr_reader :project_dir, :config, :stats

      def initialize(project_dir:, config: nil)
        @project_dir = project_dir
        @config = config || default_config
        @stats = OptimizerStats.new

        # Initialize indexers (will cache results)
        @style_guide_indexer = nil
        @template_indexer = nil
        @fragmenter = nil
        @scorer = nil
        @composer = nil
        @builder = nil
      end

      # Optimize prompt for given task context
      #
      # @param task_type [Symbol] Type of task (:feature, :bugfix, etc.)
      # @param description [String] Task description
      # @param affected_files [Array<String>] Files being modified
      # @param step_name [String] Current work loop step
      # @param tags [Array<String>] Additional context tags
      # @param options [Hash] Additional options
      # @option options [Boolean] :include_metadata Include optimization metadata
      # @option options [Integer] :max_tokens Override default token budget
      # @return [PromptOutput] Optimized prompt with metadata
      def optimize_prompt(task_type: nil, description: nil, affected_files: [], step_name: nil, tags: [], options: {})
        start_time = Time.now

        # Build task context
        task_context = TaskContext.new(
          task_type: task_type,
          description: description,
          affected_files: affected_files,
          step_name: step_name,
          tags: tags
        )

        # Index all fragments
        all_fragments = index_all_fragments(affected_files)
        @stats.record_fragments_indexed(all_fragments.count)

        # Score fragments
        scored_fragments = score_fragments(all_fragments, task_context)
        @stats.record_fragments_scored(scored_fragments.count)

        # Select fragments within budget
        max_tokens = options[:max_tokens] || @config[:max_tokens]
        thresholds = @config[:include_threshold]
        composition_result = compose_context(scored_fragments, max_tokens, thresholds)

        @stats.record_fragments_selected(composition_result.selected_count)
        @stats.record_fragments_excluded(composition_result.excluded_count)
        @stats.record_tokens_used(composition_result.total_tokens)
        @stats.record_budget_utilization(composition_result.budget_utilization)

        # Build final prompt
        prompt_output = build_prompt(task_context, composition_result, options)

        elapsed = Time.now - start_time
        @stats.record_optimization_time(elapsed)

        log_optimization_result(prompt_output) if @config[:log_selected_fragments]

        prompt_output
      end

      # Clear cached indexes (useful for testing or when files change)
      def clear_cache
        @style_guide_indexer = nil
        @template_indexer = nil
        @fragmenter = nil
        @stats.reset!
      end

      # Get optimization statistics
      #
      # @return [Hash] Statistics about optimization runs
      def statistics
        @stats.summary
      end

      private

      # Index all fragment sources
      #
      # @param affected_files [Array<String>] Files to fragment
      # @return [Array] All fragments from all sources
      def index_all_fragments(affected_files)
        fragments = []

        # Style guide fragments
        style_guide_indexer.index!
        fragments.concat(style_guide_indexer.fragments)

        # Template fragments
        template_indexer.index!
        fragments.concat(template_indexer.templates)

        # Source code fragments (only for affected files)
        if affected_files && !affected_files.empty?
          code_fragments = fragmenter.fragment_files(affected_files)
          fragments.concat(code_fragments)
        end

        fragments
      end

      # Score all fragments against task context
      #
      # @param fragments [Array] Fragments to score
      # @param context [TaskContext] Task context
      # @return [Array<Hash>] Scored fragments
      def score_fragments(fragments, context)
        scorer.score_fragments(fragments, context)
      end

      # Compose optimal context within budget
      #
      # @param scored_fragments [Array<Hash>] Scored fragments
      # @param max_tokens [Integer] Token budget
      # @param thresholds [Hash] Type-specific thresholds
      # @return [CompositionResult] Selected fragments
      def compose_context(scored_fragments, max_tokens, thresholds)
        composer(max_tokens).compose(scored_fragments, thresholds: thresholds)
      end

      # Build final prompt from selected fragments
      #
      # @param task_context [TaskContext] Task context
      # @param composition_result [CompositionResult] Selected fragments
      # @param options [Hash] Build options
      # @return [PromptOutput] Final prompt
      def build_prompt(task_context, composition_result, options)
        builder.build(task_context, composition_result, options)
      end

      # Get or create style guide indexer (cached)
      def style_guide_indexer
        @style_guide_indexer ||= StyleGuideIndexer.new(project_dir: @project_dir)
      end

      # Get or create template indexer (cached)
      def template_indexer
        @template_indexer ||= TemplateIndexer.new(project_dir: @project_dir)
      end

      # Get or create source code fragmenter (cached)
      def fragmenter
        @fragmenter ||= SourceCodeFragmenter.new(project_dir: @project_dir)
      end

      # Get or create relevance scorer (cached)
      def scorer
        @scorer ||= RelevanceScorer.new
      end

      # Get or create context composer (cached, but with max_tokens)
      def composer(max_tokens = @config[:max_tokens])
        ContextComposer.new(max_tokens: max_tokens)
      end

      # Get or create prompt builder (cached)
      def builder
        @builder ||= PromptBuilder.new
      end

      # Default configuration
      def default_config
        {
          enabled: false,
          max_tokens: 16000,
          include_threshold: {
            style_guide: 0.75,
            templates: 0.8,
            source: 0.7
          },
          dynamic_adjustment: false,
          log_selected_fragments: false
        }
      end

      # Log optimization result
      def log_optimization_result(prompt_output)
        Aidp.log_info(
          "prompt_optimizer",
          "Optimized prompt generated",
          selected_fragments: prompt_output.composition_result.selected_count,
          excluded_fragments: prompt_output.composition_result.excluded_count,
          total_tokens: prompt_output.estimated_tokens,
          budget_utilization: prompt_output.composition_result.budget_utilization
        )
      end
    end

    # Statistics tracker for optimizer
    #
    # Tracks metrics across optimization runs for monitoring
    # and debugging prompt optimization performance
    class OptimizerStats
      attr_reader :runs_count,
        :total_fragments_indexed,
        :total_fragments_scored,
        :total_fragments_selected,
        :total_fragments_excluded,
        :total_tokens_used,
        :total_optimization_time

      def initialize
        reset!
      end

      # Reset all statistics
      def reset!
        @runs_count = 0
        @total_fragments_indexed = 0
        @total_fragments_scored = 0
        @total_fragments_selected = 0
        @total_fragments_excluded = 0
        @total_tokens_used = 0
        @total_optimization_time = 0.0
        @budget_utilizations = []
      end

      # Record fragments indexed
      def record_fragments_indexed(count)
        @total_fragments_indexed += count
      end

      # Record fragments scored
      def record_fragments_scored(count)
        @total_fragments_scored += count
      end

      # Record fragments selected
      def record_fragments_selected(count)
        @total_fragments_selected += count
        @runs_count += 1
      end

      # Record fragments excluded
      def record_fragments_excluded(count)
        @total_fragments_excluded += count
      end

      # Record tokens used
      def record_tokens_used(tokens)
        @total_tokens_used += tokens
      end

      # Record budget utilization
      def record_budget_utilization(utilization)
        @budget_utilizations << utilization
      end

      # Record optimization time
      def record_optimization_time(seconds)
        @total_optimization_time += seconds
      end

      # Get average budget utilization
      def average_budget_utilization
        return 0.0 if @budget_utilizations.empty?

        (@budget_utilizations.sum / @budget_utilizations.count.to_f).round(2)
      end

      # Get average optimization time
      def average_optimization_time
        return 0.0 if @runs_count.zero?

        (@total_optimization_time / @runs_count).round(4)
      end

      # Get average fragments selected per run
      def average_fragments_selected
        return 0.0 if @runs_count.zero?

        (@total_fragments_selected.to_f / @runs_count).round(2)
      end

      # Get summary statistics
      #
      # @return [Hash] Statistics summary
      def summary
        {
          runs_count: @runs_count,
          total_fragments_indexed: @total_fragments_indexed,
          total_fragments_scored: @total_fragments_scored,
          total_fragments_selected: @total_fragments_selected,
          total_fragments_excluded: @total_fragments_excluded,
          total_tokens_used: @total_tokens_used,
          average_fragments_selected: average_fragments_selected,
          average_budget_utilization: average_budget_utilization,
          average_optimization_time_ms: (average_optimization_time * 1000).round(2)
        }
      end

      def to_s
        avg_time_ms = (average_optimization_time * 1000).round(2)
        "OptimizerStats<#{@runs_count} runs, #{average_fragments_selected} avg fragments, #{avg_time_ms}ms avg time>"
      end
    end
  end
end
