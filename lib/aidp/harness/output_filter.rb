# frozen_string_literal: true

require_relative "output_filter_config"

module Aidp
  module Harness
    # Filters test and linter output to reduce token consumption
    #
    # Supports two filtering approaches:
    # 1. AI-generated FilterDefinitions (preferred) - created once during config,
    #    applied deterministically at runtime for ANY tool
    # 2. Built-in RSpec strategy (fallback) - for backward compatibility
    #
    # @example Using AI-generated filter
    #   definition = FilterDefinition.from_hash(config[:filter_definitions][:pytest])
    #   filter = OutputFilter.new(mode: :failures_only, filter_definition: definition)
    #   filtered = filter.filter(output)
    #
    # @see AIFilterFactory for generating filter definitions
    # @see FilterDefinition for the definition format
    class OutputFilter
      # Output modes
      MODES = {
        full: :full,                   # No filtering (default for first run)
        failures_only: :failures_only, # Only failure information
        minimal: :minimal              # Minimal failure info + summary
      }.freeze

      # @param config [OutputFilterConfig, Hash] Configuration options
      # @option config [Symbol] :mode Output mode (:full, :failures_only, :minimal)
      # @option config [Boolean] :include_context Include surrounding lines
      # @option config [Integer] :context_lines Number of context lines
      # @option config [Integer] :max_lines Maximum output lines
      # @param filter_definition [FilterDefinition, nil] AI-generated filter patterns
      def initialize(config = {}, filter_definition: nil)
        @config = normalize_config(config)
        @mode = @config.mode
        @include_context = @config.include_context
        @context_lines = @config.context_lines
        @max_lines = @config.max_lines
        @filter_definition = filter_definition

        Aidp.log_debug("output_filter", "initialized",
          mode: @mode,
          include_context: @include_context,
          max_lines: @max_lines,
          has_definition: !@filter_definition.nil?)
      rescue NameError
        # Logging infrastructure not available in some tests
      end

      # Filter output based on framework and mode
      # @param output [String] Raw output
      # @param framework [Symbol] Framework identifier (:rspec, :minitest, :jest, :pytest, :unknown)
      # @return [String] Filtered output
      def filter(output, framework: :unknown)
        return output if @mode == :full
        return "" if output.nil? || output.empty?

        Aidp.log_debug("output_filter", "filtering_start",
          framework: framework,
          mode: @mode,
          input_lines: output.lines.count)

        strategy = strategy_for_framework(framework)
        filtered = strategy.filter(output, self)

        truncated = truncate_if_needed(filtered)

        Aidp.log_debug("output_filter", "filtering_complete",
          framework: framework,
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
      attr_reader :mode, :include_context, :context_lines, :max_lines, :config, :filter_definition

      private

      def normalize_config(config)
        case config
        when OutputFilterConfig
          config
        when Hash
          OutputFilterConfig.from_hash(config)
        when nil
          OutputFilterConfig.new
        else
          raise ArgumentError, "Config must be an OutputFilterConfig or Hash, got: #{config.class}"
        end
      end

      def strategy_for_framework(framework)
        # Use AI-generated filter definition if available (preferred)
        if @filter_definition
          require_relative "generated_filter_strategy"
          return GeneratedFilterStrategy.new(@filter_definition)
        end

        # Fall back to built-in strategies for backward compatibility
        case framework
        when :rspec
          require_relative "rspec_filter_strategy"
          RSpecFilterStrategy.new
        else
          # Use generic strategy for all other frameworks
          # Users should generate a FilterDefinition for better results
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
        reduction = input_size.zero? ? 0 : ((input_size - output_size).to_f / input_size * 100).round(1)

        {
          input_bytes: input_size,
          output_bytes: output_size,
          reduction_percent: reduction
        }
      end
    end
  end
end
