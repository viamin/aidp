# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Builds the final PROMPT.md from selected fragments
    #
    # Assembles an optimized prompt that includes:
    # - Task description
    # - Relevant style guide sections
    # - Selected template fragments
    # - Code context
    # - Implementation guidance
    #
    # @example Basic usage
    #   builder = PromptBuilder.new
    #   prompt = builder.build(task_context, composition_result, options)
    class PromptBuilder
      # Build prompt from composition result
      #
      # @param task_context [TaskContext] Task context
      # @param composition_result [CompositionResult] Selected fragments
      # @param options [Hash] Build options
      # @option options [Boolean] :include_metadata Include selection metadata
      # @option options [Boolean] :include_stats Include composition statistics
      # @return [PromptOutput] Built prompt with metadata
      def build(task_context, composition_result, options = {})
        sections = []

        # Task section
        sections << build_task_section(task_context)

        # Group fragments by type
        style_guide_fragments = composition_result.fragments_by_type(:style_guide)
        template_fragments = composition_result.fragments_by_type(:template)
        code_fragments = composition_result.fragments_by_type(:code)

        # Add relevant sections if they have content
        sections << build_style_guide_section(style_guide_fragments) unless style_guide_fragments.empty?
        sections << build_template_section(template_fragments) unless template_fragments.empty?
        sections << build_code_section(code_fragments) unless code_fragments.empty?

        # Optional metadata
        if options[:include_metadata]
          sections << build_metadata_section(composition_result)
        end

        content = sections.join("\n\n---\n\n")

        PromptOutput.new(
          content: content,
          composition_result: composition_result,
          task_context: task_context,
          metadata: build_metadata(composition_result, options)
        )
      end

      private

      # Build task description section
      #
      # @param task_context [TaskContext] Task context
      # @return [String] Task section markdown
      def build_task_section(task_context)
        lines = ["# Task"]

        if task_context.task_type
          lines << "\n**Type**: #{task_context.task_type}"
        end

        if task_context.description
          lines << "\n## Description"
          lines << "\n#{task_context.description}"
        end

        if task_context.affected_files && !task_context.affected_files.empty?
          lines << "\n## Affected Files"
          task_context.affected_files.each do |file|
            lines << "- `#{file}`"
          end
        end

        if task_context.step_name
          lines << "\n## Current Step"
          lines << "\n#{task_context.step_name}"
        end

        lines.join("\n")
      end

      # Build style guide section
      #
      # @param fragments [Array<Hash>] Style guide fragments
      # @return [String] Style guide section markdown
      def build_style_guide_section(fragments)
        lines = ["# Relevant Style Guidelines"]

        lines << "\nThe following style guide sections are relevant to this task:"
        lines << ""

        fragments.each do |item|
          fragment = item[:fragment]
          score = item[:score]

          lines << "## #{fragment.heading}"
          lines << ""
          lines << fragment.content
          lines << ""

          if score >= 0.9
            lines << "_[Critical: Relevance score #{(score * 100).round}%]_"
            lines << ""
          end
        end

        lines.join("\n")
      end

      # Build template section
      #
      # @param fragments [Array<Hash>] Template fragments
      # @return [String] Template section markdown
      def build_template_section(fragments)
        lines = ["# Template Guidance"]

        lines << "\nThe following templates provide guidance for this type of work:"
        lines << ""

        fragments.each do |item|
          fragment = item[:fragment]

          lines << "## #{fragment.name}"
          lines << ""
          lines << "**Category**: #{fragment.category}"
          lines << ""
          lines << fragment.content
          lines << ""
        end

        lines.join("\n")
      end

      # Build code context section
      #
      # @param fragments [Array<Hash>] Code fragments
      # @return [String] Code section markdown
      def build_code_section(fragments)
        lines = ["# Code Context"]

        lines << "\nRelevant code from affected files:"
        lines << ""

        # Group by file
        by_file = fragments.group_by { |item| item[:fragment].file_path }

        by_file.each do |file_path, file_fragments|
          relative_path = file_fragments.first[:fragment].respond_to?(:relative_path) ?
                         file_fragments.first[:fragment].relative_path(File.dirname(file_path)) :
                         File.basename(file_path)

          lines << "## `#{relative_path}`"
          lines << ""

          file_fragments.each do |item|
            fragment = item[:fragment]

            lines << "### #{fragment.type}: #{fragment.name} (lines #{fragment.line_start}-#{fragment.line_end})"
            lines << ""
            lines << "```ruby"
            lines << fragment.content
            lines << "```"
            lines << ""
          end
        end

        lines.join("\n")
      end

      # Build metadata section
      #
      # @param composition_result [CompositionResult] Composition result
      # @return [String] Metadata section markdown
      def build_metadata_section(composition_result)
        lines = ["# Prompt Optimization Metadata"]
        lines << ""
        lines << "_This section shows how the prompt was optimized. Remove before sending to model._"
        lines << ""

        summary = composition_result.summary

        lines << "## Selection Statistics"
        lines << ""
        lines << "- **Fragments Selected**: #{summary[:selected_count]}"
        lines << "- **Fragments Excluded**: #{summary[:excluded_count]}"
        lines << "- **Token Budget**: #{summary[:total_tokens]} / #{summary[:budget]} (#{summary[:utilization]}%)"
        lines << "- **Average Relevance Score**: #{(summary[:average_score] * 100).round}%"
        lines << ""

        lines << "## Fragments by Type"
        lines << ""
        lines << "- **Style Guide Sections**: #{summary[:by_type][:style_guide]}"
        lines << "- **Templates**: #{summary[:by_type][:templates]}"
        lines << "- **Code Fragments**: #{summary[:by_type][:code]}"
        lines << ""

        lines.join("\n")
      end

      # Build metadata hash
      #
      # @param composition_result [CompositionResult] Composition result
      # @param options [Hash] Build options
      # @return [Hash] Metadata
      def build_metadata(composition_result, options)
        {
          selected_count: composition_result.selected_count,
          excluded_count: composition_result.excluded_count,
          total_tokens: composition_result.total_tokens,
          budget: composition_result.budget,
          utilization: composition_result.budget_utilization,
          average_score: composition_result.average_score,
          timestamp: Time.now.iso8601,
          include_metadata: options[:include_metadata] || false
        }
      end
    end

    # Output of prompt building
    #
    # Contains the built prompt content along with metadata
    # about the composition and selection process
    class PromptOutput
      attr_reader :content, :composition_result, :task_context, :metadata

      def initialize(content:, composition_result:, task_context:, metadata:)
        @content = content
        @composition_result = composition_result
        @task_context = task_context
        @metadata = metadata
      end

      # Get content length in characters
      #
      # @return [Integer] Character count
      def size
        @content.length
      end

      # Estimate token count for the prompt
      #
      # @return [Integer] Estimated tokens
      def estimated_tokens
        (size / 4.0).ceil
      end

      # Write prompt to file
      #
      # @param file_path [String] Path to write prompt
      def write_to_file(file_path)
        File.write(file_path, @content)
        Aidp.log_info("prompt_builder", "Wrote optimized prompt", path: file_path, tokens: estimated_tokens)
      end

      # Get fragment selection report
      #
      # @return [String] Human-readable report
      def selection_report
        lines = ["# Prompt Optimization Report"]
        lines << ""
        lines << "Generated at: #{@metadata[:timestamp]}"
        lines << ""

        lines << "## Task Context"
        lines << "- Type: #{@task_context.task_type || "N/A"}"
        lines << "- Step: #{@task_context.step_name || "N/A"}"
        if @task_context.affected_files && !@task_context.affected_files.empty?
          lines << "- Affected Files: #{@task_context.affected_files.join(", ")}"
        end
        lines << ""

        lines << "## Composition Statistics"
        lines << "- Selected: #{@metadata[:selected_count]} fragments"
        lines << "- Excluded: #{@metadata[:excluded_count]} fragments"
        lines << "- Tokens: #{@metadata[:total_tokens]} / #{@metadata[:budget]} (#{@metadata[:utilization]}%)"
        lines << "- Avg Score: #{(@metadata[:average_score] * 100).round}%"
        lines << ""

        lines << "## Selected Fragments"
        @composition_result.selected_fragments.each do |item|
          fragment = item[:fragment]
          score = item[:score]

          if fragment.respond_to?(:heading)
            lines << "- #{fragment.heading} (#{(score * 100).round}%)"
          elsif fragment.respond_to?(:name)
            lines << "- #{fragment.name} (#{(score * 100).round}%)"
          elsif fragment.respond_to?(:id)
            lines << "- #{fragment.id} (#{(score * 100).round}%)"
          end
        end

        lines.join("\n")
      end

      def to_s
        "PromptOutput<#{estimated_tokens} tokens, #{@composition_result.selected_count} fragments>"
      end
    end
  end
end
