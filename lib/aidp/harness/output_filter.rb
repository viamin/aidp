# frozen_string_literal: true

module Aidp
  module Harness
    # Filters test and linter output to reduce token consumption
    # Uses framework-specific strategies to extract relevant information
    class OutputFilter
      # Output modes
      MODES = {
        full: :full,                   # No filtering (default for first run)
        failures_only: :failures_only, # Only failure information
        minimal: :minimal              # Minimal failure info + summary
      }.freeze

      # @param config [Hash] Configuration options
      # @option config [Symbol] :mode Output mode (:full, :failures_only, :minimal)
      # @option config [Boolean] :include_context Include surrounding lines
      # @option config [Integer] :context_lines Number of context lines
      # @option config [Integer] :max_lines Maximum output lines
      def initialize(config = {})
        @mode = config[:mode] || :full
        @include_context = config.fetch(:include_context, true)
        @context_lines = config.fetch(:context_lines, 3)
        @max_lines = config.fetch(:max_lines, 500)

        validate_mode!

        Aidp.log_debug("output_filter", "initialized",
          mode: @mode,
          include_context: @include_context,
          max_lines: @max_lines)
      rescue NameError
        # Logging infrastructure not available in some tests
      end

      # Filter output based on framework and mode
      # @param output [String] Raw output
      # @param framework [Symbol] Framework identifier
      # @return [String] Filtered output
      def filter(output, framework: :unknown)
        return output if @mode == :full
        return "" if output.nil? || output.empty?

        Aidp.log_debug("output_filter", "filtering_start",
          framework: framework,
          input_lines: output.lines.count)

        strategy = strategy_for_framework(framework)
        filtered = strategy.filter(output, self)

        truncated = truncate_if_needed(filtered)

        Aidp.log_debug("output_filter", "filtering_complete",
          output_lines: truncated.lines.count,
          reduction: reduction_stats(output, truncated))

        truncated
      rescue NameError
        # Logging infrastructure not available
        return output if @mode == :full
        return "" if output.nil? || output.empty?

        strategy = strategy_for_framework(framework)
        filtered = strategy.filter(output, self)
        truncate_if_needed(filtered)
      rescue => e
        # External failure - graceful degradation
        begin
          Aidp.log_error("output_filter", "filtering_failed",
            framework: framework,
            mode: @mode,
            error: e.message,
            error_class: e.class.name)
        rescue NameError
          # Logging not available
        end

        # Return original output as fallback
        output
      end

      # Accessors for strategy use
      attr_reader :mode, :include_context, :context_lines, :max_lines

      private

      def validate_mode!
        unless MODES.key?(@mode)
          raise ArgumentError, "Invalid mode: #{@mode}. Must be one of #{MODES.keys}"
        end
      end

      def strategy_for_framework(framework)
        case framework
        when :rspec
          require_relative "rspec_filter_strategy"
          RSpecFilterStrategy.new
        when :minitest
          require_relative "generic_filter_strategy"
          GenericFilterStrategy.new
        when :jest
          require_relative "generic_filter_strategy"
          GenericFilterStrategy.new
        when :pytest
          require_relative "generic_filter_strategy"
          GenericFilterStrategy.new
        else
          require_relative "generic_filter_strategy"
          GenericFilterStrategy.new
        end
      end

      def truncate_if_needed(output)
        lines = output.lines
        return output if lines.count <= @max_lines

        truncated = lines.first(@max_lines).join
        # Only add newline if truncated doesn't already end with one
        separator = truncated.end_with?("\n") ? "" : "\n"
        truncated + separator + "[Output truncated - #{lines.count - @max_lines} more lines omitted]"
      end

      def reduction_stats(input, output)
        input_size = input.bytesize
        output_size = output.bytesize
        reduction = ((input_size - output_size).to_f / input_size * 100).round(1)

        {
          input_bytes: input_size,
          output_bytes: output_size,
          reduction_percent: reduction
        }
      end
    end
  end
end
