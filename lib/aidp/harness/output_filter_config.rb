# frozen_string_literal: true

module Aidp
  module Harness
    # Value object for output filter configuration
    # Provides validation and type-safe access to filtering options
    class OutputFilterConfig
      VALID_MODES = %i[full failures_only minimal].freeze
      DEFAULT_MODE = :full
      DEFAULT_INCLUDE_CONTEXT = true
      DEFAULT_CONTEXT_LINES = 3
      DEFAULT_MAX_LINES = 500
      MIN_CONTEXT_LINES = 0
      MAX_CONTEXT_LINES = 20
      MIN_MAX_LINES = 10
      MAX_MAX_LINES = 10_000

      attr_reader :mode, :include_context, :context_lines, :max_lines

      # Create a new OutputFilterConfig
      # @param mode [Symbol] Output mode (:full, :failures_only, :minimal)
      # @param include_context [Boolean] Include surrounding lines
      # @param context_lines [Integer] Number of context lines (0-20)
      # @param max_lines [Integer] Maximum output lines (10-10000)
      # @raise [ArgumentError] If any parameter is invalid
      def initialize(mode: DEFAULT_MODE, include_context: DEFAULT_INCLUDE_CONTEXT,
        context_lines: DEFAULT_CONTEXT_LINES, max_lines: DEFAULT_MAX_LINES)
        @mode = validate_mode(mode)
        @include_context = validate_boolean(include_context, "include_context")
        @context_lines = validate_context_lines(context_lines)
        @max_lines = validate_max_lines(max_lines)

        freeze
      end

      # Create from a hash (useful for configuration loading)
      # @param hash [Hash] Configuration hash
      # @return [OutputFilterConfig] New config instance
      def self.from_hash(hash)
        hash = hash.transform_keys(&:to_sym) if hash.respond_to?(:transform_keys)

        new(
          mode: hash[:mode] || DEFAULT_MODE,
          include_context: hash.fetch(:include_context, DEFAULT_INCLUDE_CONTEXT),
          context_lines: hash[:context_lines] || DEFAULT_CONTEXT_LINES,
          max_lines: hash[:max_lines] || DEFAULT_MAX_LINES
        )
      end

      # Convert to hash (useful for serialization)
      # @return [Hash] Configuration as hash
      def to_h
        {
          mode: @mode,
          include_context: @include_context,
          context_lines: @context_lines,
          max_lines: @max_lines
        }
      end

      # Check if filtering is enabled
      # @return [Boolean] True if mode is not :full
      def filtering_enabled?
        @mode != :full
      end

      # Compare with another config
      # @param other [OutputFilterConfig] Other config to compare
      # @return [Boolean] True if equal
      def ==(other)
        return false unless other.is_a?(OutputFilterConfig)

        @mode == other.mode &&
          @include_context == other.include_context &&
          @context_lines == other.context_lines &&
          @max_lines == other.max_lines
      end
      alias_method :eql?, :==

      # Hash for use in Hash/Set
      def hash
        [@mode, @include_context, @context_lines, @max_lines].hash
      end

      private

      def validate_mode(mode)
        mode = mode.to_sym if mode.respond_to?(:to_sym)

        unless VALID_MODES.include?(mode)
          raise ArgumentError,
            "Invalid mode: #{mode.inspect}. Must be one of #{VALID_MODES.join(", ")}"
        end

        mode
      end

      def validate_boolean(value, name)
        unless [true, false].include?(value)
          raise ArgumentError, "#{name} must be a boolean, got: #{value.inspect}"
        end

        value
      end

      def validate_context_lines(value)
        value = value.to_i if value.respond_to?(:to_i) && !value.is_a?(Integer)

        unless value.is_a?(Integer) && value >= MIN_CONTEXT_LINES && value <= MAX_CONTEXT_LINES
          raise ArgumentError,
            "context_lines must be an integer between #{MIN_CONTEXT_LINES} and #{MAX_CONTEXT_LINES}, got: #{value.inspect}"
        end

        value
      end

      def validate_max_lines(value)
        value = value.to_i if value.respond_to?(:to_i) && !value.is_a?(Integer)

        unless value.is_a?(Integer) && value >= MIN_MAX_LINES && value <= MAX_MAX_LINES
          raise ArgumentError,
            "max_lines must be an integer between #{MIN_MAX_LINES} and #{MAX_MAX_LINES}, got: #{value.inspect}"
        end

        value
      end
    end
  end
end
