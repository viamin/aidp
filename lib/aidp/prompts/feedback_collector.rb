# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../config_paths"

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
      # Maximum number of feedback entries to keep per template
      MAX_ENTRIES_PER_TEMPLATE = 100

      attr_reader :project_dir

      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
      end

      # Record feedback for a prompt template
      #
      # @param template_id [String] Template identifier
      # @param outcome [Symbol] :success, :failure, :abandoned, :timeout
      # @param iterations [Integer, nil] Number of iterations to completion
      # @param user_reaction [Symbol, nil] :positive, :negative, :neutral
      # @param suggestions [Array<String>, nil] Improvement suggestions
      # @param context [Hash] Additional context (task type, error type, etc.)
      def record(template_id:, outcome:, iterations: nil, user_reaction: nil, suggestions: nil, context: {})
        Aidp.log_debug("feedback_collector", "recording_feedback",
          template_id: template_id,
          outcome: outcome,
          iterations: iterations)

        entry = build_entry(
          template_id: template_id,
          outcome: outcome,
          iterations: iterations,
          user_reaction: user_reaction,
          suggestions: suggestions,
          context: context
        )

        append_entry(entry)
        prune_old_entries(template_id)

        Aidp.log_info("feedback_collector", "feedback_recorded",
          template_id: template_id,
          outcome: outcome)
      end

      # Get feedback summary for a template
      #
      # @param template_id [String] Template identifier
      # @return [Hash] Summary statistics
      def summary(template_id:)
        entries = load_entries.select { |e| e[:template_id] == template_id }

        return empty_summary if entries.empty?

        success_count = entries.count { |e| e[:outcome] == "success" }
        failure_count = entries.count { |e| e[:outcome] == "failure" }
        total_count = entries.size

        iterations = entries.map { |e| e[:iterations] }.compact
        avg_iterations = iterations.empty? ? nil : (iterations.sum.to_f / iterations.size).round(1)

        positive_reactions = entries.count { |e| e[:user_reaction] == "positive" }
        negative_reactions = entries.count { |e| e[:user_reaction] == "negative" }

        all_suggestions = entries.flat_map { |e| e[:suggestions] || [] }.compact.uniq

        {
          template_id: template_id,
          total_uses: total_count,
          success_rate: total_count > 0 ? (success_count.to_f / total_count * 100).round(1) : 0,
          success_count: success_count,
          failure_count: failure_count,
          avg_iterations: avg_iterations,
          positive_reactions: positive_reactions,
          negative_reactions: negative_reactions,
          common_suggestions: all_suggestions.take(5),
          first_use: entries.min_by { |e| e[:timestamp] }&.dig(:timestamp),
          last_use: entries.max_by { |e| e[:timestamp] }&.dig(:timestamp)
        }
      end

      # Get feedback entries for analysis
      #
      # @param template_id [String, nil] Filter by template (nil for all)
      # @param outcome [Symbol, nil] Filter by outcome
      # @param limit [Integer] Maximum entries to return
      # @return [Array<Hash>] Feedback entries
      def entries(template_id: nil, outcome: nil, limit: 100)
        result = load_entries

        result = result.select { |e| e[:template_id] == template_id } if template_id
        result = result.select { |e| e[:outcome] == outcome.to_s } if outcome

        result.sort_by { |e| e[:timestamp] }.reverse.take(limit)
      end

      # Get templates that need improvement based on feedback
      #
      # @param min_uses [Integer] Minimum uses to consider
      # @param max_success_rate [Float] Success rate threshold (0-100)
      # @return [Array<Hash>] Templates needing improvement with summaries
      def templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)
        template_ids = load_entries.map { |e| e[:template_id] }.uniq

        template_ids.filter_map do |template_id|
          stats = summary(template_id: template_id)

          next if stats[:total_uses] < min_uses
          next if stats[:success_rate] > max_success_rate

          stats
        end.sort_by { |s| s[:success_rate] }
      end

      # Clear all feedback data
      def clear
        feedback_file = ConfigPaths.prompt_feedback_file(@project_dir)
        FileUtils.rm_f(feedback_file) if File.exist?(feedback_file)
        Aidp.log_info("feedback_collector", "feedback_cleared")
      end

      private

      def build_entry(template_id:, outcome:, iterations:, user_reaction:, suggestions:, context:)
        {
          template_id: template_id,
          outcome: outcome.to_s,
          iterations: iterations,
          user_reaction: user_reaction&.to_s,
          suggestions: suggestions,
          context: context,
          timestamp: Time.now.iso8601,
          aidp_version: Aidp::VERSION
        }
      end

      def append_entry(entry)
        ConfigPaths.ensure_prompt_feedback_dir(@project_dir)
        feedback_file = ConfigPaths.prompt_feedback_file(@project_dir)

        File.open(feedback_file, "a") do |f|
          f.puts(JSON.generate(entry))
        end
      end

      def load_entries
        feedback_file = ConfigPaths.prompt_feedback_file(@project_dir)
        return [] unless File.exist?(feedback_file)

        File.readlines(feedback_file).filter_map do |line|
          JSON.parse(line.strip, symbolize_names: true)
        rescue JSON::ParserError
          nil
        end
      end

      def prune_old_entries(template_id)
        entries_list = load_entries

        # Group by template
        by_template = entries_list.group_by { |e| e[:template_id] }

        # Prune if template has too many entries
        template_entries = by_template[template_id] || []
        return if template_entries.size <= MAX_ENTRIES_PER_TEMPLATE

        # Keep most recent entries
        sorted = template_entries.sort_by { |e| e[:timestamp] }.reverse
        to_keep = sorted.take(MAX_ENTRIES_PER_TEMPLATE)
        to_keep_set = to_keep.to_set

        # Rewrite file with pruned entries
        pruned = entries_list.reject do |e|
          e[:template_id] == template_id && !to_keep_set.include?(e)
        end

        rewrite_entries(pruned)

        Aidp.log_debug("feedback_collector", "pruned_old_entries",
          template_id: template_id,
          removed: template_entries.size - to_keep.size)
      end

      def rewrite_entries(entries_list)
        ConfigPaths.ensure_prompt_feedback_dir(@project_dir)
        feedback_file = ConfigPaths.prompt_feedback_file(@project_dir)

        File.open(feedback_file, "w") do |f|
          entries_list.each { |entry| f.puts(JSON.generate(entry)) }
        end
      end

      def empty_summary
        {
          template_id: nil,
          total_uses: 0,
          success_rate: 0,
          success_count: 0,
          failure_count: 0,
          avg_iterations: nil,
          positive_reactions: 0,
          negative_reactions: 0,
          common_suggestions: [],
          first_use: nil,
          last_use: nil
        }
      end
    end
  end
end
