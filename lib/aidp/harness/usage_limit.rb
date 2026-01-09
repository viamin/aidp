# frozen_string_literal: true

module Aidp
  module Harness
    # Immutable value object representing usage limit configuration
    # Encapsulates limit settings for a provider with tier-based limits
    class UsageLimit
      VALID_PERIODS = %w[daily weekly monthly].freeze
      VALID_TIERS = %w[mini standard thinking advanced pro max].freeze
      DEFAULT_PERIOD = "monthly"
      DEFAULT_RESET_DAY = 1

      attr_reader :enabled, :period, :reset_day, :tier_limits, :max_tokens, :max_cost

      # Create a new UsageLimit from configuration hash
      #
      # @param config [Hash] Configuration hash with usage limit settings
      # @return [UsageLimit] Immutable usage limit instance
      def self.from_config(config)
        return new(enabled: false) unless config.is_a?(Hash)

        new(
          enabled: config[:enabled] == true,
          period: normalize_period(config[:period]),
          reset_day: config[:reset_day] || DEFAULT_RESET_DAY,
          tier_limits: parse_tier_limits(config[:tier_limits]),
          max_tokens: config[:max_tokens],
          max_cost: config[:max_cost]
        )
      end

      def initialize(enabled: true, period: DEFAULT_PERIOD, reset_day: DEFAULT_RESET_DAY,
        tier_limits: {}, max_tokens: nil, max_cost: nil)
        @enabled = enabled
        @period = validate_period(period)
        @reset_day = validate_reset_day(reset_day)
        @tier_limits = freeze_tier_limits(tier_limits)
        @max_tokens = max_tokens&.to_i
        @max_cost = max_cost&.to_f
        freeze
      end

      # Check if limits are enabled and configured
      def enabled?
        @enabled
      end

      # Get limits for a specific tier
      #
      # @param tier [String, Symbol] The tier name (mini, standard, advanced, etc.)
      # @return [Hash] Tier-specific limits or global limits
      def limits_for_tier(tier)
        tier_key = tier.to_s.downcase

        # Map thinking tier names to usage limit tiers
        tier_key = case tier_key
        when "thinking", "pro", "max" then "advanced"
        when "standard" then "standard"
        else tier_key
        end

        tier_config = @tier_limits[tier_key] || @tier_limits[tier_key.to_sym]

        if tier_config
          {
            max_tokens: tier_config[:max_tokens],
            max_cost: tier_config[:max_cost]
          }
        else
          # Fall back to global limits
          {
            max_tokens: @max_tokens,
            max_cost: @max_cost
          }
        end
      end

      # Check if usage would exceed limits
      #
      # @param current_tokens [Integer] Current token count
      # @param current_cost [Float] Current cost
      # @param tier [String] The tier to check against
      # @return [Hash] Result with :exceeded boolean and :reason
      def exceeds_limit?(current_tokens:, current_cost:, tier: "standard")
        return {exceeded: false, reason: nil} unless enabled?

        limits = limits_for_tier(tier)

        if limits[:max_tokens] && current_tokens >= limits[:max_tokens]
          return {
            exceeded: true,
            reason: "Token limit exceeded: #{current_tokens}/#{limits[:max_tokens]}"
          }
        end

        if limits[:max_cost] && current_cost >= limits[:max_cost]
          return {
            exceeded: true,
            reason: "Cost limit exceeded: $#{format("%.2f", current_cost)}/$#{format("%.2f", limits[:max_cost])}"
          }
        end

        {exceeded: false, reason: nil}
      end

      # Value equality
      def ==(other)
        return false unless other.is_a?(UsageLimit)

        enabled == other.enabled &&
          period == other.period &&
          reset_day == other.reset_day &&
          tier_limits == other.tier_limits &&
          max_tokens == other.max_tokens &&
          max_cost == other.max_cost
      end

      alias_method :eql?, :==

      def hash
        [enabled, period, reset_day, tier_limits, max_tokens, max_cost].hash
      end

      # Convert to configuration hash
      def to_h
        {
          enabled: @enabled,
          period: @period,
          reset_day: @reset_day,
          tier_limits: @tier_limits.transform_values(&:to_h),
          max_tokens: @max_tokens,
          max_cost: @max_cost
        }.compact
      end

      def self.normalize_period(period)
        return DEFAULT_PERIOD unless period

        period_str = period.to_s.downcase
        VALID_PERIODS.include?(period_str) ? period_str : DEFAULT_PERIOD
      end

      def self.parse_tier_limits(tier_limits)
        return {} unless tier_limits.is_a?(Hash)

        tier_limits.transform_values do |limits|
          next {} unless limits.is_a?(Hash)

          {
            max_tokens: limits[:max_tokens] || limits["max_tokens"],
            max_cost: limits[:max_cost] || limits["max_cost"]
          }.compact
        end
      end

      private_class_method :normalize_period, :parse_tier_limits

      private

      def validate_period(period)
        period_str = period.to_s.downcase
        VALID_PERIODS.include?(period_str) ? period_str : DEFAULT_PERIOD
      end

      def validate_reset_day(day)
        day_int = day.to_i
        day_int.between?(1, 28) ? day_int : DEFAULT_RESET_DAY
      end

      def freeze_tier_limits(limits)
        return {}.freeze unless limits.is_a?(Hash)

        limits.transform_values do |tier_config|
          tier_config.is_a?(Hash) ? tier_config.freeze : {}
        end.freeze
      end
    end
  end
end
