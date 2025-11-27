# frozen_string_literal: true

require_relative "filter_strategy"

module Aidp
  module Harness
    # Jest-specific output filtering
    # Handles Jest test output formats including:
    # - Standard Jest output
    # - Jest with coverage
    # - Jest verbose mode
    class JestFilterStrategy < FilterStrategy
      # Jest test summary patterns
      SUMMARY_PATTERN = /Test Suites:\s+\d+/
      TESTS_SUMMARY_PATTERN = /Tests:\s+\d+/

      # Failure indicator - Jest uses the bullet point
      FAILURE_INDICATOR = /^\s*●\s+/

      # Test file result pattern: PASS/FAIL src/file.test.js
      FILE_RESULT_PATTERN = /^\s*(PASS|FAIL)\s+(.+\.(?:test|spec)\.[jt]sx?)$/i

      # Failed test location pattern
      LOCATION_PATTERN = %r{at\s+(?:Object\.|)[\w.<>]+\s+\((.+:\d+:\d+)\)}

      # Jest "Ran all test suites" line
      RAN_SUITES_PATTERN = /Ran all test suites/

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

        # Extract summary section
        summary = extract_summary(lines)
        if summary
          parts << "Jest Summary:"
          parts.concat(summary)
          parts << ""
        end

        # Extract failed test files
        failed_files = extract_failed_files(lines)
        if failed_files.any?
          parts << "Failed Files:"
          parts.concat(failed_files.map { |f| "  FAIL #{f}" })
          parts << ""
        end

        # Extract failure blocks (sections starting with ●)
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

        # Extract only test/suite counts
        summary_lines = extract_summary(lines)
        parts.concat(summary_lines) if summary_lines

        # Extract failed file names
        failed_files = extract_failed_files(lines)
        if failed_files.any?
          parts << ""
          parts << "Failed:"
          parts.concat(failed_files.map { |f| "  #{f}" })
        end

        # Extract failure locations (file:line:col)
        locations = extract_failure_locations(lines)
        if locations.any?
          parts << ""
          parts << "Locations:"
          parts.concat(locations.uniq.map { |loc| "  #{loc}" })
        end

        parts.join("\n")
      end

      def extract_summary(lines)
        summary_lines = []

        lines.each do |line|
          # Jest summary lines
          if line.match?(SUMMARY_PATTERN) ||
              line.match?(TESTS_SUMMARY_PATTERN) ||
              line.match?(/Snapshots:\s+\d+/) ||
              line.match?(/Time:\s+[\d.]+/)
            summary_lines << line.strip
          end
        end

        summary_lines.any? ? summary_lines : nil
      end

      def extract_failed_files(lines)
        failed = []

        lines.each do |line|
          if match = line.match(FILE_RESULT_PATTERN)
            status, file_path = match[1], match[2]
            failed << file_path if status.upcase == "FAIL"
          end
        end

        failed.uniq
      end

      def extract_failure_blocks(lines, filter_instance)
        blocks = []
        in_failure_block = false
        current_block = []
        blank_line_count = 0

        lines.each do |line|
          # Check if this line starts a new failure (● marker)
          if line.match?(FAILURE_INDICATOR)
            # Save previous block
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
            # End on "Ran all test suites" or similar summary or new PASS/FAIL file line
            if line.match?(RAN_SUITES_PATTERN) || line.match?(SUMMARY_PATTERN) || line.match?(FILE_RESULT_PATTERN)
              blocks << current_block.join
              current_block = []
              in_failure_block = false
              next
            end

            # Track blank lines - three consecutive blanks might end block
            if line.strip.empty?
              blank_line_count += 1
              if blank_line_count >= 3
                blocks << current_block.join
                current_block = []
                in_failure_block = false
                blank_line_count = 0
              else
                current_block << line
              end
            else
              blank_line_count = 0
              current_block << line
            end
          end
        end

        # Don't forget the last block
        blocks << current_block.join if current_block.any?

        blocks
      end

      def extract_failure_locations(lines)
        locations = []

        lines.each do |line|
          # Extract file:line:col from stack traces
          if match = line.match(LOCATION_PATTERN)
            location = match[1]
            # Filter out node_modules paths
            next if location.include?("node_modules")
            locations << location
          end
        end

        locations
      end
    end
  end
end
