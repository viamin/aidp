# frozen_string_literal: true

require_relative "usage_limit"
require_relative "usage_limit_tracker"

module Aidp
  module Harness
    # Exception raised when usage limits are exceeded
    # Contains context about the exceeded limit for fallback handling
    class UsageLimitExceededError < StandardError
      attr_reader :provider_name, :tier, :current_tokens, :current_cost,
        :max_tokens, :max_cost, :period_description

      def initialize(provider_name:, tier:, current_tokens:, current_cost:,
        max_tokens:, max_cost:, period_description:, message: nil)
        @provider_name = provider_name
        @tier = tier
        @current_tokens = current_tokens
        @current_cost = current_cost
        @max_tokens = max_tokens
        @max_cost = max_cost
        @period_description = period_description

        super(message || default_message)
      end

      def to_h
        {
          type: "usage_limit_exceeded",
          provider: @provider_name,
          tier: @tier,
          current_tokens: @current_tokens,
          current_cost: @current_cost,
          max_tokens: @max_tokens,
          max_cost: @max_cost,
          period: @period_description,
          timestamp: Time.now.iso8601
        }
      end

      private

      def default_message
        parts = []
        parts << "Usage limit exceeded for #{@provider_name} (tier: #{@tier})"
        parts << "Period: #{@period_description}"

        if @max_tokens && @current_tokens >= @max_tokens
          parts << "Tokens: #{@current_tokens}/#{@max_tokens}"
        end

        if @max_cost && @current_cost >= @max_cost
          parts << "Cost: $#{format("%.2f", @current_cost)}/$#{format("%.2f", @max_cost)}"
        end

        parts.join(". ")
      end
    end

    # Application service for enforcing usage limits
    # Coordinates between UsageLimit config and UsageLimitTracker
    class UsageLimitEnforcer
      attr_reader :provider_name, :usage_limit, :tracker

      # Initialize the enforcer with configuration
      #
      # @param provider_name [String] Name of the provider
      # @param usage_limit [UsageLimit] Usage limit configuration
      # @param tracker [UsageLimitTracker] Tracker instance for usage data
      def initialize(provider_name:, usage_limit:, tracker:)
        @provider_name = provider_name.to_s
        @usage_limit = usage_limit
        @tracker = tracker

        Aidp.log_debug("usage_limit_enforcer", "initialized",
          provider: @provider_name,
          enabled: @usage_limit.enabled?,
          period: @usage_limit.period)
      end

      # Check if usage limits allow a request before making API call
      #
      # @param tier [String] The tier for this request
      # @raise [UsageLimitExceededError] If limits are exceeded
      def check_before_request(tier: "standard")
        Aidp.log_debug("usage_limit_enforcer", "checking_limits",
          provider: @provider_name,
          tier: tier)

        return unless @usage_limit.enabled?

        current = @tracker.current_usage(
          period_type: @usage_limit.period,
          reset_day: @usage_limit.reset_day
        )

        limits = @usage_limit.limits_for_tier(tier)
        check_result = @usage_limit.exceeds_limit?(
          current_tokens: current[:total_tokens],
          current_cost: current[:total_cost],
          tier: tier
        )

        if check_result[:exceeded]
          Aidp.log_warn("usage_limit_enforcer", "limit_exceeded",
            provider: @provider_name,
            tier: tier,
            reason: check_result[:reason])

          raise UsageLimitExceededError.new(
            provider_name: @provider_name,
            tier: tier,
            current_tokens: current[:total_tokens],
            current_cost: current[:total_cost],
            max_tokens: limits[:max_tokens],
            max_cost: limits[:max_cost],
            period_description: current[:period_description]
          )
        end

        Aidp.log_debug("usage_limit_enforcer", "limits_ok",
          provider: @provider_name,
          tier: tier,
          tokens: current[:total_tokens],
          cost: current[:total_cost])
      end

      # Record usage after a successful API request
      #
      # @param tokens [Integer] Tokens used in the request
      # @param cost [Float] Cost of the request
      # @param tier [String] Tier used for the request
      def record_after_request(tokens:, cost:, tier: "standard")
        return unless @usage_limit.enabled?

        @tracker.record_usage(
          tokens: tokens,
          cost: cost,
          tier: tier,
          period_type: @usage_limit.period,
          reset_day: @usage_limit.reset_day
        )
      end

      # Check if limits would be exceeded by additional usage
      # Non-raising version for checking without blocking
      #
      # @param additional_tokens [Integer] Additional tokens to add
      # @param additional_cost [Float] Additional cost to add
      # @param tier [String] The tier to check
      # @return [Hash] Result with :would_exceed and :headroom
      def check_headroom(additional_tokens: 0, additional_cost: 0.0, tier: "standard")
        return {would_exceed: false, headroom: {tokens: nil, cost: nil}} unless @usage_limit.enabled?

        current = @tracker.current_usage(
          period_type: @usage_limit.period,
          reset_day: @usage_limit.reset_day
        )

        limits = @usage_limit.limits_for_tier(tier)

        projected_tokens = current[:total_tokens] + additional_tokens
        projected_cost = current[:total_cost] + additional_cost

        token_headroom = limits[:max_tokens] ? limits[:max_tokens] - current[:total_tokens] : nil
        cost_headroom = limits[:max_cost] ? limits[:max_cost] - current[:total_cost] : nil

        would_exceed = false
        would_exceed = true if limits[:max_tokens] && projected_tokens >= limits[:max_tokens]
        would_exceed = true if limits[:max_cost] && projected_cost >= limits[:max_cost]

        {
          would_exceed: would_exceed,
          headroom: {
            tokens: token_headroom,
            cost: cost_headroom
          },
          current: {
            tokens: current[:total_tokens],
            cost: current[:total_cost]
          },
          limits: limits
        }
      end

      # Get usage summary for display
      #
      # @return [Hash] Usage summary with current values, limits, and percentages
      def usage_summary
        return {enabled: false} unless @usage_limit.enabled?

        current = @tracker.current_usage(
          period_type: @usage_limit.period,
          reset_day: @usage_limit.reset_day
        )

        # Aggregate across common tiers
        tiers_summary = %w[mini standard advanced].map do |tier|
          limits = @usage_limit.limits_for_tier(tier)
          tier_usage = @tracker.tier_usage(
            tier: tier,
            period_type: @usage_limit.period,
            reset_day: @usage_limit.reset_day
          )

          {
            tier: tier,
            tokens: tier_usage[:tokens],
            cost: tier_usage[:cost],
            requests: tier_usage[:requests],
            max_tokens: limits[:max_tokens],
            max_cost: limits[:max_cost],
            token_percent: calculate_percent(tier_usage[:tokens], limits[:max_tokens]),
            cost_percent: calculate_percent(tier_usage[:cost], limits[:max_cost])
          }
        end

        {
          enabled: true,
          provider: @provider_name,
          period: @usage_limit.period,
          period_description: current[:period_description],
          total_tokens: current[:total_tokens],
          total_cost: current[:total_cost],
          total_requests: current[:request_count],
          remaining_seconds: current[:remaining_seconds],
          tiers: tiers_summary
        }
      end

      private

      def calculate_percent(current, max)
        return nil unless max && max.positive?

        ((current.to_f / max) * 100).round(1)
      end
    end
  end
end
