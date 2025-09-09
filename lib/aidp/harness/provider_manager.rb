# frozen_string_literal: true

module Aidp
  module Harness
    # Manages provider switching and fallback logic
    class ProviderManager
      def initialize(configuration)
        @configuration = configuration
        @current_provider = nil
        @provider_history = []
        @rate_limit_info = {}
        @provider_metrics = {}
      end

      # Get current provider
      def current_provider
        @current_provider ||= @configuration.default_provider
      end

      # Switch to next available provider
      def switch_provider
        available_providers = get_available_providers

        # Find next provider in fallback chain
        current_index = available_providers.index(current_provider) || -1
        next_index = current_index + 1

        if next_index < available_providers.size
          next_provider = available_providers[next_index]
          set_current_provider(next_provider)
          next_provider
        else
          # No more providers available
          nil
        end
      end

      # Set current provider
      def set_current_provider(provider_name)
        return false unless @configuration.provider_configured?(provider_name)

        @provider_history << {
          provider: provider_name,
          switched_at: Time.now,
          reason: "manual_switch"
        }

        @current_provider = provider_name
        true
      end

      # Get available providers (not rate limited)
      def get_available_providers
        all_providers = @configuration.available_providers
        all_providers.reject { |provider| is_rate_limited?(provider) }
      end

      # Check if provider is rate limited
      def is_rate_limited?(provider_name)
        info = @rate_limit_info[provider_name]
        return false unless info

        reset_time = info[:reset_time]
        reset_time && Time.now < reset_time
      end

      # Mark provider as rate limited
      def mark_rate_limited(provider_name, reset_time = nil)
        @rate_limit_info[provider_name] = {
          rate_limited_at: Time.now,
          reset_time: reset_time || calculate_reset_time(provider_name),
          error_count: (@rate_limit_info[provider_name]&.dig(:error_count) || 0) + 1
        }

        # Switch to next provider if current one is rate limited
        if provider_name == current_provider
          switch_provider
        end
      end

      # Get next reset time for any provider
      def next_reset_time
        reset_times = @rate_limit_info.values
          .map { |info| info[:reset_time] }
          .compact
          .select { |time| time > Time.now }

        reset_times.min
      end

      # Clear rate limit for provider
      def clear_rate_limit(provider_name)
        @rate_limit_info.delete(provider_name)
      end

      # Get provider configuration
      def provider_config(provider_name)
        @configuration.provider_config(provider_name)
      end

      # Get provider type
      def provider_type(provider_name)
        @configuration.provider_type(provider_name)
      end

      # Get default flags for provider
      def default_flags(provider_name)
        @configuration.default_flags(provider_name)
      end

      # Record provider metrics
      def record_metrics(provider_name, success:, duration:, tokens_used: nil, _error: nil)
        @provider_metrics[provider_name] ||= {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          total_duration: 0.0,
          total_tokens: 0,
          last_used: nil
        }

        metrics = @provider_metrics[provider_name]
        metrics[:total_requests] += 1
        metrics[:last_used] = Time.now

        if success
          metrics[:successful_requests] += 1
          metrics[:total_duration] += duration
          metrics[:total_tokens] += tokens_used if tokens_used
        else
          metrics[:failed_requests] += 1
        end
      end

      # Get provider metrics
      def get_metrics(provider_name)
        @provider_metrics[provider_name] || {}
      end

      # Get all provider metrics
      def all_metrics
        @provider_metrics.dup
      end

      # Get provider history
      def provider_history
        @provider_history.dup
      end

      # Reset all provider state
      def reset
        @current_provider = nil
        @provider_history.clear
        @rate_limit_info.clear
        @provider_metrics.clear
      end

      # Get status summary
      def status
        {
          current_provider: current_provider,
          available_providers: get_available_providers,
          rate_limited_providers: @rate_limit_info.keys,
          next_reset_time: next_reset_time,
          total_switches: @provider_history.size
        }
      end

      private

      def calculate_reset_time(_provider_name)
        # Default reset time calculation
        # Most providers reset rate limits every hour
        Time.now + (60 * 60)
      end
    end
  end
end
