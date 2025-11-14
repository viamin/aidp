# frozen_string_literal: true

module Aidp
  module Harness
    # Base class for framework-specific filtering strategies
    class FilterStrategy
      # @param output [String] Raw output
      # @param filter [OutputFilter] Filter instance for config access
      # @return [String] Filtered output
      def filter(output, filter_instance)
        raise NotImplementedError, "Subclasses must implement #filter"
      end

      protected

      # Extract lines around a match (for context)
      def extract_with_context(lines, index, context_lines)
        start_idx = [0, index - context_lines].max
        end_idx = [lines.length - 1, index + context_lines].min

        lines[start_idx..end_idx]
      end

      # Find failure markers in output
      def find_failure_markers(output)
        # Common failure patterns across frameworks
        patterns = [
          /FAILED/i,
          /ERROR/i,
          /FAIL:/i,
          /failures?:/i,
          /\d+\) /,  # Numbered failures
          /^  \d+\)/  # Indented numbered failures
        ]

        lines = output.lines
        markers = []

        lines.each_with_index do |line, index|
          if patterns.any? { |pattern| line.match?(pattern) }
            markers << index
          end
        end

        markers
      end
    end
  end
end
