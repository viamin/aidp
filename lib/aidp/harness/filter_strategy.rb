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
        lines = output.lines
        markers = []

        lines.each_with_index do |line, index|
          # Check for failure patterns using safe string methods
          if line.match?(/FAILED/i) ||
              line.match?(/ERROR/i) ||
              line.match?(/FAIL:/i) ||
              line.match?(/failures?:/i) ||
              line.match?(/^\s*\d{1,4}\)\s/) ||  # Numbered failures (limit digits to prevent ReDoS)
              line.include?(") ")  # Additional simple check for numbered patterns
            markers << index
          end
        end

        markers
      end
    end
  end
end
