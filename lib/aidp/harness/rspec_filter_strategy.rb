# frozen_string_literal: true

require_relative "filter_strategy"

module Aidp
  module Harness
    # RSpec-specific output filtering
    class RSpecFilterStrategy < FilterStrategy
      def filter(output, filter_instance)
        case filter_instance.mode
        when :failures_only
          extract_failures_only(output, filter_instance)
        when :minimal
          extract_minimal(output, filter_instance)
        else
          output
        end
      end

      private

      def extract_failures_only(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract summary line
        if summary = lines.find { |l| l.match?(/^\d+ examples?, \d+ failures?/) }
          parts << "RSpec Summary:"
          parts << summary
          parts << ""
        end

        # Extract failed examples
        in_failure = false
        failure_lines = []

        lines.each_with_index do |line, index|
          # Start of failure section
          if line.match?(/^Failures:/)
            in_failure = true
            failure_lines << line
            next
          end

          # End of failure section (start of pending/seed info)
          if in_failure && (line.match?(/^Finished in/) || line.match?(/^Pending:/))
            in_failure = false
            break
          end

          failure_lines << line if in_failure
        end

        if failure_lines.any?
          parts << failure_lines.join
        end

        parts.join("\n")
      end

      def extract_minimal(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract only summary and failure locations
        if summary = lines.find { |l| l.match?(/^\d+ examples?, \d+ failures?/) }
          parts << summary
        end

        # Extract failure locations (file:line references)
        failure_locations = lines.select { |l| l.match?(/# \.\/\S+:\d+/) }
        if failure_locations.any?
          parts << ""
          parts << "Failed examples:"
          parts.concat(failure_locations.map(&:strip))
        end

        parts.join("\n")
      end
    end
  end
end
