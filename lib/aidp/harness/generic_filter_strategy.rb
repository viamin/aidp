# frozen_string_literal: true

require_relative "filter_strategy"

module Aidp
  module Harness
    # Generic filtering for unknown frameworks
    class GenericFilterStrategy < FilterStrategy
      def filter(output, filter_instance)
        case filter_instance.mode
        when :failures_only
          extract_failure_lines(output, filter_instance)
        when :minimal
          extract_summary(output, filter_instance)
        else
          output
        end
      end

      private

      def extract_failure_lines(output, filter_instance)
        lines = output.lines
        failure_indices = find_failure_markers(output)

        return output if failure_indices.empty?

        # Extract failures with context
        relevant_lines = Set.new
        failure_indices.each do |index|
          if filter_instance.include_context
            extract_with_context(lines, index, filter_instance.context_lines)
            start_idx = [0, index - filter_instance.context_lines].max
            end_idx = [lines.length - 1, index + filter_instance.context_lines].min
            (start_idx..end_idx).each { |idx| relevant_lines.add(idx) }
          else
            relevant_lines.add(index)
          end
        end

        selected = relevant_lines.to_a.sort.map { |idx| lines[idx] }
        selected.join
      end

      def extract_summary(output, filter_instance)
        lines = output.lines

        # Take first line, last line, and any lines with numbers/statistics
        parts = []
        parts << lines.first if lines.first

        summary_lines = lines.select do |line|
          line.match?(/\d+/) || line.match?(/summary|total|passed|failed/i)
        end

        parts.concat(summary_lines.uniq)
        parts << lines.last if lines.last && !parts.include?(lines.last)

        parts.join("\n")
      end
    end
  end
end
