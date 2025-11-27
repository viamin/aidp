# frozen_string_literal: true

require_relative "filter_strategy"

module Aidp
  module Harness
    # Pytest-specific output filtering
    # Handles pytest output formats including:
    # - Standard pytest output
    # - pytest verbose mode (-v)
    # - pytest with coverage
    class PytestFilterStrategy < FilterStrategy
      # Pytest summary line patterns
      # e.g., "= 1 failed, 2 passed in 0.12s ="
      # or "= 5 passed in 0.50s ="
      SUMMARY_PATTERN = /^=+.*(?:passed|failed|error|skipped|warning).*=+$/i

      # Short summary pattern: "FAILED tests/test_file.py::test_name - AssertionError"
      SHORT_SUMMARY_PATTERN = /^(?:PASSED|FAILED|ERROR|SKIPPED)\s+/

      # Failure section header
      FAILURES_HEADER = /^=+\s*FAILURES\s*=+$/i
      ERRORS_HEADER = /^=+\s*ERRORS\s*=+$/i

      # Individual test failure header
      # e.g., "_ test_something _" or "______ test_module.py::test_name ______"
      TEST_FAILURE_HEADER = /^_+\s+.*\s+_+$/

      # File location in traceback
      # e.g., "tests/test_file.py:42: AssertionError"
      LOCATION_PATTERN = %r{([\w/.]+\.py):(\d+)}

      # Assertion error details
      ASSERTION_PATTERN = /^(?:E\s+)?(?:AssertionError|assert\s+)/i

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

        # Extract final summary
        summary = extract_summary(lines)
        if summary
          parts << "Pytest Summary:"
          parts << summary
          parts << ""
        end

        # Extract FAILURES section
        failures = extract_failures_section(lines, filter_instance)
        if failures.any?
          parts << "Failures:"
          parts << ""
          parts.concat(failures)
        end

        # Extract ERRORS section
        errors = extract_errors_section(lines, filter_instance)
        if errors.any?
          parts << ""
          parts << "Errors:"
          parts << ""
          parts.concat(errors)
        end

        result = parts.join("\n")
        result.empty? ? output : result
      end

      def extract_minimal(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract summary only
        summary = extract_summary(lines)
        parts << summary if summary

        # Extract short summary lines (FAILED test_name - error)
        short_summary = extract_short_summary(lines)
        if short_summary.any?
          parts << ""
          parts << "Failed Tests:"
          parts.concat(short_summary.map { |s| "  #{s}" })
        end

        # Extract file locations
        locations = extract_failure_locations(lines)
        if locations.any?
          parts << ""
          parts << "Locations:"
          parts.concat(locations.uniq.map { |loc| "  #{loc}" })
        end

        parts.join("\n")
      end

      def extract_summary(lines)
        # Look for the final summary line with = padding
        lines.reverse_each do |line|
          return line.strip if line.match?(SUMMARY_PATTERN)
        end
        nil
      end

      def extract_failures_section(lines, filter_instance)
        extract_section(lines, FAILURES_HEADER, filter_instance)
      end

      def extract_errors_section(lines, filter_instance)
        extract_section(lines, ERRORS_HEADER, filter_instance)
      end

      def extract_section(lines, header_pattern, filter_instance)
        blocks = []
        in_section = false
        in_test_block = false
        current_block = []

        lines.each do |line|
          # Check for section start
          if line.match?(header_pattern)
            in_section = true
            next
          end

          # Exit on summary line
          if in_section && line.match?(SUMMARY_PATTERN)
            blocks << current_block.join if current_block.any?
            break
          end

          next unless in_section

          # Check for individual test failure header
          if line.match?(TEST_FAILURE_HEADER)
            # Save previous block
            blocks << current_block.join if current_block.any?
            current_block = [line]
            in_test_block = true
            next
          end

          current_block << line if in_test_block
        end

        # Don't forget last block
        blocks << current_block.join if current_block.any?

        blocks
      end

      def extract_short_summary(lines)
        lines.filter_map do |line|
          if line.match?(/^FAILED\s+/)
            # Extract just the test name and error type
            line.strip.sub(/^FAILED\s+/, "")
          end
        end
      end

      def extract_failure_locations(lines)
        locations = []
        in_failure_section = false

        lines.each do |line|
          # Track when we're in FAILURES or ERRORS section
          if line.match?(FAILURES_HEADER) || line.match?(ERRORS_HEADER)
            in_failure_section = true
            next
          end

          if line.match?(SUMMARY_PATTERN)
            in_failure_section = false
            next
          end

          if in_failure_section
            # Extract file:line from traceback
            if match = line.match(LOCATION_PATTERN)
              file, line_num = match[1], match[2]
              # Skip conftest.py and __pycache__ entries
              next if file.include?("conftest") || file.include?("__pycache__")
              locations << "#{file}:#{line_num}"
            end
          end
        end

        locations.uniq
      end
    end
  end
end
