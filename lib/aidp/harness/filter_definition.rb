# frozen_string_literal: true

module Aidp
  module Harness
    # Value object representing a generated filter definition
    # Created by AI during configuration, applied deterministically at runtime
    #
    # @example Usage
    #   definition = FilterDefinition.new(
    #     tool_name: "pytest",
    #     summary_patterns: ["\\d+ passed", "\\d+ failed"],
    #     failure_section_start: "=+ FAILURES =+",
    #     failure_section_end: "=+ short test summary",
    #     error_patterns: ["AssertionError", "Error:"],
    #     location_patterns: ["\\S+\\.py:\\d+"],
    #     noise_patterns: ["^\\s*$", "^platform "]
    #   )
    #
    # @see AIFilterFactory for generation
    # @see GeneratedFilterStrategy for runtime application
    class FilterDefinition
      attr_reader :tool_name, :tool_command, :summary_patterns, :failure_section_start,
        :failure_section_end, :error_section_start, :error_section_end,
        :error_patterns, :location_patterns, :noise_patterns,
        :important_patterns, :context_lines, :created_at

      # Initialize a filter definition
      #
      # @param tool_name [String] Human-readable tool name (e.g., "pytest", "eslint")
      # @param tool_command [String, nil] The command used to run the tool
      # @param summary_patterns [Array<String>] Regex patterns that match summary lines
      # @param failure_section_start [String, nil] Regex pattern marking start of failures section
      # @param failure_section_end [String, nil] Regex pattern marking end of failures section
      # @param error_section_start [String, nil] Regex pattern marking start of errors section
      # @param error_section_end [String, nil] Regex pattern marking end of errors section
      # @param error_patterns [Array<String>] Regex patterns that match error indicators
      # @param location_patterns [Array<String>] Regex patterns that extract file:line locations
      # @param noise_patterns [Array<String>] Regex patterns for lines to filter out
      # @param important_patterns [Array<String>] Regex patterns for lines to always keep
      # @param context_lines [Integer] Number of context lines around failures
      # @param created_at [Time, nil] When this definition was generated
      def initialize(
        tool_name:,
        tool_command: nil,
        summary_patterns: [],
        failure_section_start: nil,
        failure_section_end: nil,
        error_section_start: nil,
        error_section_end: nil,
        error_patterns: [],
        location_patterns: [],
        noise_patterns: [],
        important_patterns: [],
        context_lines: 3,
        created_at: nil
      )
        @tool_name = tool_name
        @tool_command = tool_command
        @summary_patterns = compile_patterns(summary_patterns)
        @failure_section_start = compile_pattern(failure_section_start)
        @failure_section_end = compile_pattern(failure_section_end)
        @error_section_start = compile_pattern(error_section_start)
        @error_section_end = compile_pattern(error_section_end)
        @error_patterns = compile_patterns(error_patterns)
        @location_patterns = compile_patterns(location_patterns)
        @noise_patterns = compile_patterns(noise_patterns)
        @important_patterns = compile_patterns(important_patterns)
        @context_lines = context_lines
        @created_at = created_at || Time.now

        freeze
      end

      # Create from a hash (e.g., loaded from YAML config)
      #
      # @param hash [Hash] Definition data with string or symbol keys
      # @return [FilterDefinition]
      def self.from_hash(hash)
        hash = hash.transform_keys(&:to_sym)

        new(
          tool_name: hash[:tool_name] || "unknown",
          tool_command: hash[:tool_command],
          summary_patterns: Array(hash[:summary_patterns]),
          failure_section_start: hash[:failure_section_start],
          failure_section_end: hash[:failure_section_end],
          error_section_start: hash[:error_section_start],
          error_section_end: hash[:error_section_end],
          error_patterns: Array(hash[:error_patterns]),
          location_patterns: Array(hash[:location_patterns]),
          noise_patterns: Array(hash[:noise_patterns]),
          important_patterns: Array(hash[:important_patterns]),
          context_lines: hash[:context_lines] || 3,
          created_at: hash[:created_at] ? Time.parse(hash[:created_at].to_s) : nil
        )
      end

      # Convert to hash for serialization (e.g., saving to YAML)
      #
      # @return [Hash] Serializable representation
      def to_h
        {
          tool_name: @tool_name,
          tool_command: @tool_command,
          summary_patterns: patterns_to_strings(@summary_patterns),
          failure_section_start: pattern_to_string(@failure_section_start),
          failure_section_end: pattern_to_string(@failure_section_end),
          error_section_start: pattern_to_string(@error_section_start),
          error_section_end: pattern_to_string(@error_section_end),
          error_patterns: patterns_to_strings(@error_patterns),
          location_patterns: patterns_to_strings(@location_patterns),
          noise_patterns: patterns_to_strings(@noise_patterns),
          important_patterns: patterns_to_strings(@important_patterns),
          context_lines: @context_lines,
          created_at: @created_at&.iso8601
        }.compact
      end

      # Check if this definition has failure section markers
      #
      # @return [Boolean]
      def has_failure_section?
        !@failure_section_start.nil?
      end

      # Check if this definition has error section markers
      #
      # @return [Boolean]
      def has_error_section?
        !@error_section_start.nil?
      end

      # Check if a line matches any summary pattern
      #
      # @param line [String] Line to check
      # @return [Boolean]
      def summary_line?(line)
        @summary_patterns.any? { |pattern| line.match?(pattern) }
      end

      # Check if a line matches any error pattern
      #
      # @param line [String] Line to check
      # @return [Boolean]
      def error_line?(line)
        @error_patterns.any? { |pattern| line.match?(pattern) }
      end

      # Check if a line should be filtered as noise
      #
      # @param line [String] Line to check
      # @return [Boolean]
      def noise_line?(line)
        @noise_patterns.any? { |pattern| line.match?(pattern) }
      end

      # Check if a line should always be kept
      #
      # @param line [String] Line to check
      # @return [Boolean]
      def important_line?(line)
        @important_patterns.any? { |pattern| line.match?(pattern) }
      end

      # Extract file locations from a line
      #
      # @param line [String] Line to extract locations from
      # @return [Array<String>] Extracted locations
      def extract_locations(line)
        @location_patterns.flat_map do |pattern|
          line.scan(pattern).flatten
        end.compact.uniq
      end

      # Equality based on all attributes
      def ==(other)
        return false unless other.is_a?(FilterDefinition)

        to_h == other.to_h
      end

      alias_method :eql?, :==

      def hash
        to_h.hash
      end

      private

      def compile_patterns(strings)
        Array(strings).map { |s| compile_pattern(s) }.compact
      end

      def compile_pattern(string)
        return nil if string.nil? || string.empty?
        Regexp.new(string, Regexp::IGNORECASE)
      rescue RegexpError => e
        Aidp.log_warn("filter_definition", "Invalid regex pattern",
          pattern: string, error: e.message)
        nil
      end

      def patterns_to_strings(patterns)
        patterns.map { |p| p&.source }.compact
      end

      def pattern_to_string(pattern)
        pattern&.source
      end
    end
  end
end
