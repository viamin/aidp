# frozen_string_literal: true

require_relative "filter_strategy"

module Aidp
  module Harness
    # Minitest-specific output filtering
    # Handles various Minitest output formats including:
    # - Standard Minitest output
    # - Minitest with Rails
    # - Minitest/Pride format
    class MinitestFilterStrategy < FilterStrategy
      # Summary line pattern: "10 runs, 20 assertions, 1 failures, 0 errors, 0 skips"
      SUMMARY_PATTERN = /^\d+\s+runs?,\s+\d+\s+assertions?/

      # Failure header patterns
      FAILURE_HEADER_PATTERNS = [
        /^(?:Failure|Error):/i,         # Standard failure/error header
        /^\s*\d+\)\s+(?:Failure|Error)/i, # Numbered failure "1) Failure:"
        /^FAIL\s+/i,                       # FAIL prefix
        /^ERROR\s+/i                       # ERROR prefix
      ].freeze

      # File location pattern: "test/models/user_test.rb:45"
      LOCATION_PATTERN = %r{[\w/]+_test\.rb:\d+}

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
        summary = extract_summary(lines)
        if summary
          parts << "Minitest Summary:"
          parts << summary
          parts << ""
        end

        # Extract failure blocks
        failure_blocks = extract_failure_blocks(lines, filter_instance)
        if failure_blocks.any?
          parts << "Failures:"
          parts << ""
          parts.concat(failure_blocks)
        end

        result = parts.join("\n")
        result.empty? ? output : result
      end

      def extract_minimal(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract only summary
        summary = extract_summary(lines)
        parts << summary if summary

        # Extract failure locations (file:line references)
        locations = extract_failure_locations(lines)
        if locations.any?
          parts << ""
          parts << "Failed tests:"
          parts.concat(locations.map { |loc| "  #{loc}" })
        end

        parts.join("\n")
      end

      def extract_summary(lines)
        lines.find { |line| line.match?(SUMMARY_PATTERN) }&.strip
      end

      def extract_failure_blocks(lines, filter_instance)
        blocks = []
        in_failure_block = false
        current_block = []
        blank_line_count = 0

        lines.each do |line|
          # Check if this line starts a new failure block
          if starts_failure_block?(line)
            # Save previous block if exists
            if current_block.any?
              blocks << current_block.join
              current_block = []
            end
            in_failure_block = true
            blank_line_count = 0
            current_block << line
            next
          end

          if in_failure_block
            # Track blank lines - two consecutive blanks end the block
            if line.strip.empty?
              blank_line_count += 1
              if blank_line_count >= 2
                blocks << current_block.join
                current_block = []
                in_failure_block = false
                blank_line_count = 0
              else
                current_block << line
              end
            else
              blank_line_count = 0
              # End block on summary line
              if line.match?(SUMMARY_PATTERN)
                blocks << current_block.join
                current_block = []
                in_failure_block = false
              else
                current_block << line
              end
            end
          end
        end

        # Don't forget the last block
        blocks << current_block.join if current_block.any?

        blocks
      end

      def starts_failure_block?(line)
        FAILURE_HEADER_PATTERNS.any? { |pattern| line.match?(pattern) }
      end

      def extract_failure_locations(lines)
        locations = []

        lines.each do |line|
          # Extract test file locations
          if line.match?(LOCATION_PATTERN)
            match = line.match(LOCATION_PATTERN)
            locations << match[0] if match
          end
        end

        locations.uniq
      end
    end
  end
end
