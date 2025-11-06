# frozen_string_literal: true

require "fileutils"
require_relative "../prompt_optimization/optimizer"

module Aidp
  module Execute
    # Manages the PROMPT.md file lifecycle for work loops
    # Responsibilities:
    # - Read/write PROMPT.md
    # - Check existence
    # - Archive completed prompts
    # - Optionally optimize prompts using intelligent fragment selection (ZFC)
    class PromptManager
      PROMPT_FILENAME = "PROMPT.md"
      ARCHIVE_DIR = ".aidp/prompt_archive"

      attr_reader :optimizer, :last_optimization_stats

      def initialize(project_dir, config: nil)
        @project_dir = project_dir
        @aidp_dir = File.join(project_dir, ".aidp")
        @prompt_path = File.join(@aidp_dir, PROMPT_FILENAME)
        @archive_dir = File.join(project_dir, ARCHIVE_DIR)
        @config = config
        @optimizer = nil
        @last_optimization_stats = nil

        # Ensure .aidp directory exists
        FileUtils.mkdir_p(@aidp_dir)

        # Initialize optimizer if enabled
        if config&.respond_to?(:prompt_optimization_enabled?) && config.prompt_optimization_enabled?
          @optimizer = Aidp::PromptOptimization::Optimizer.new(
            project_dir: project_dir,
            config: config.prompt_optimization_config
          )
        end
      end

      # Write content to PROMPT.md
      # If optimization is enabled, stores the content but doesn't write yet
      # (use write_optimized instead)
      #
      # @param content [String] The prompt content to write
      # @param step_name [String, nil] Optional step name for immediate archiving
      # @return [String, nil] Archive path if archived, nil otherwise
      def write(content, step_name: nil)
        File.write(@prompt_path, content)

        # Archive immediately if step_name provided (issue #224)
        archive(step_name) if step_name
      end

      # Write optimized prompt using intelligent fragment selection
      #
      # Uses Zero Framework Cognition to select only the most relevant fragments
      # from style guides, templates, and source code based on task context.
      #
      # @param task_context [Hash] Context about the current task
      # @option task_context [Symbol] :task_type Type of task (:feature, :bugfix, etc.)
      # @option task_context [String] :description Task description
      # @option task_context [Array<String>] :affected_files Files being modified
      # @option task_context [String] :step_name Current work loop step
      # @option task_context [Array<String>] :tags Additional context tags
      # @param options [Hash] Optimization options
      # @option options [Boolean] :include_metadata Include debug metadata
      # @return [Boolean] True if optimization was used, false if fallback to regular write
      def write_optimized(task_context, options = {})
        unless @optimizer
          Aidp.logger.warn("prompt_manager", "Optimization requested but not enabled")
          return false
        end

        begin
          # Use optimizer to build intelligent prompt
          result = @optimizer.optimize_prompt(
            task_type: task_context[:task_type],
            description: task_context[:description],
            affected_files: task_context[:affected_files] || [],
            step_name: task_context[:step_name],
            tags: task_context[:tags] || [],
            options: options
          )

          # Write optimized prompt
          result.write_to_file(@prompt_path)

          # Store statistics for inspection
          @last_optimization_stats = result.composition_result

          # Log optimization results
          Aidp.logger.info(
            "prompt_manager",
            "Optimized prompt written",
            selected_fragments: result.composition_result.selected_count,
            excluded_fragments: result.composition_result.excluded_count,
            tokens: result.estimated_tokens,
            budget_utilization: result.composition_result.budget_utilization
          )

          # Archive immediately if step_name provided (issue #224)
          archive(task_context[:step_name]) if task_context[:step_name]

          true
        rescue => e
          Aidp.logger.error("prompt_manager", "Optimization failed, using fallback", error: e.message)
          false
        end
      end

      # Read content from PROMPT.md
      def read
        return nil unless exists?
        File.read(@prompt_path)
      end

      # Check if PROMPT.md exists
      def exists?
        File.exist?(@prompt_path)
      end

      # Archive PROMPT.md with timestamp and step name
      def archive(step_name)
        return unless exists?

        FileUtils.mkdir_p(@archive_dir)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        archive_filename = "#{timestamp}_#{step_name}_PROMPT.md"
        archive_path = File.join(@archive_dir, archive_filename)

        FileUtils.cp(@prompt_path, archive_path)
        archive_path
      end

      # Delete PROMPT.md (typically after archiving)
      def delete
        File.delete(@prompt_path) if exists?
      end

      # Get the full path to PROMPT.md
      def path
        @prompt_path
      end

      # Get optimization report for last optimization
      #
      # @return [String, nil] Markdown report or nil if no optimization performed
      def optimization_report
        return nil unless @last_optimization_stats

        # Build report from composition result
        lines = []
        lines << "# Prompt Optimization Report"
        lines << ""
        lines << "## Statistics"
        lines << "- **Selected Fragments**: #{@last_optimization_stats.selected_count}"
        lines << "- **Excluded Fragments**: #{@last_optimization_stats.excluded_count}"
        lines << "- **Total Tokens**: #{@last_optimization_stats.total_tokens} / #{@last_optimization_stats.budget}"
        lines << "- **Budget Utilization**: #{@last_optimization_stats.budget_utilization.round(1)}%"
        lines << "- **Average Relevance Score**: #{(@last_optimization_stats.average_score * 100).round(1)}%"
        lines << ""
        lines << "## Selected Fragments"
        @last_optimization_stats.selected_fragments.each do |scored|
          fragment = scored[:fragment]
          score = scored[:score]
          lines << "- #{fragment_name(fragment)} (#{(score * 100).round(0)}%)"
        end

        lines.join("\n")
      end

      # Check if optimization is enabled
      #
      # @return [Boolean] True if optimizer is available
      def optimization_enabled?
        !@optimizer.nil?
      end

      # Get optimizer statistics
      #
      # @return [Hash, nil] Statistics hash or nil if optimizer not available
      def optimizer_stats
        @optimizer&.statistics
      end

      private

      # Get human-readable name for a fragment
      def fragment_name(fragment)
        if fragment.respond_to?(:heading)
          fragment.heading
        elsif fragment.respond_to?(:name)
          fragment.name
        elsif fragment.respond_to?(:id)
          fragment.id
        else
          "Unknown fragment"
        end
      end
    end
  end
end
