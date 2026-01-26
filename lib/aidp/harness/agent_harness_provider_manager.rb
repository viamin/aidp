# frozen_string_literal: true

require_relative "../agent_harness_adapter"

module Aidp
  module Harness
    # Provider manager that delegates to AgentHarness gem
    #
    # This class implements the same interface as ProviderManager but
    # delegates provider management to the AgentHarness gem's conductor.
    # It allows AIDP to use AgentHarness for provider orchestration while
    # maintaining compatibility with existing Runner and ErrorHandler code.
    #
    # @example Usage in Runner
    #   @provider_manager = AgentHarnessProviderManager.new(@configuration)
    #
    class AgentHarnessProviderManager
      include Aidp::MessageDisplay

      attr_reader :adapter
      attr_writer :current_model

      def initialize(configuration, prompt: nil, binary_checker: nil)
        @configuration = configuration
        @adapter = AgentHarnessAdapter.new(configuration, logger: Aidp.logger)
        @current_model = nil
        @rate_limit_info = {}
        @provider_history = []
      end

      # Get current provider name
      #
      # @return [Symbol] current provider name
      def current_provider
        @adapter.conductor.provider_manager.current_provider
      end

      # Get current model for provider
      #
      # @return [String, nil] current model name
      def current_model
        @current_model ||= default_model(current_provider)
      end

      # Get current provider and model combination
      #
      # @return [String] provider:model string
      def current_provider_model
        "#{current_provider}:#{current_model}"
      end

      # Get status information
      #
      # @return [Hash] status hash
      def status
        harness_status = @adapter.status
        {
          current_provider: current_provider,
          current_model: current_model,
          available_providers: available_providers,
          health_status: harness_status[:health_status],
          metrics: harness_status[:metrics]
        }
      end

      # Get list of configured providers
      #
      # @return [Array<Symbol>] provider names
      def configured_providers
        AgentHarness.configuration.providers.keys
      end

      # Get list of available (healthy) providers
      #
      # @return [Array<Symbol>] available provider names
      def available_providers
        @adapter.conductor.provider_manager.available_providers
      end

      # Switch to next available provider
      #
      # @param reason [String] reason for switch
      # @param context [Hash] additional context
      # @return [Symbol, nil] new provider name or nil
      def switch_provider(reason = "manual_switch", context = {})
        old_provider = current_provider

        begin
          new_provider_instance = @adapter.conductor.provider_manager.switch_provider(
            reason: reason.to_sym,
            context: context
          )

          if new_provider_instance
            new_provider = new_provider_instance.class.provider_name
            log_provider_switch(old_provider, new_provider, reason, context)
            Aidp.logger.info("agent_harness_provider_manager", "Provider switched",
              from: old_provider, to: new_provider, reason: reason)
            new_provider
          else
            Aidp.logger.warn("agent_harness_provider_manager", "No provider available for switch",
              reason: reason, current: old_provider)
            nil
          end
        rescue AgentHarness::NoProvidersAvailableError => e
          Aidp.logger.error("agent_harness_provider_manager", "No providers available",
            reason: reason, attempted: e.attempted_providers)
          nil
        end
      end

      # Switch provider based on error type
      #
      # @param error_type [Symbol] type of error
      # @param context [Hash] additional context
      # @return [Symbol, nil] new provider name or nil
      def switch_provider_for_error(error_type, context = {})
        switch_provider(error_type.to_s, context)
      end

      # Mark provider as rate limited
      #
      # @param provider [Symbol, String] provider name
      # @param reset_time [Time, nil] when rate limit resets
      # @return [void]
      def mark_rate_limited(provider, reset_time = nil)
        provider = provider.to_sym
        @rate_limit_info[provider] = {
          limited_at: Time.now,
          reset_time: reset_time
        }
        @adapter.conductor.provider_manager.mark_rate_limited(provider, reset_at: reset_time)
        Aidp.logger.info("agent_harness_provider_manager", "Provider marked rate limited",
          provider: provider, reset_time: reset_time)
      end

      # Check if provider is rate limited
      #
      # @param provider [Symbol, String] provider name
      # @return [Boolean] true if rate limited
      def is_rate_limited?(provider)
        @adapter.conductor.provider_manager.rate_limited?(provider.to_sym)
      end
      alias_method :rate_limited?, :is_rate_limited?

      # Get next rate limit reset time across all providers
      #
      # @return [Time, nil] earliest reset time
      def next_reset_time
        reset_times = @rate_limit_info.values
          .map { |info| info[:reset_time] }
          .compact
          .select { |t| t > Time.now }
        reset_times.min
      end

      # Mark provider as having auth failure
      #
      # @param provider [Symbol, String] provider name
      # @return [void]
      def mark_provider_auth_failure(provider)
        provider = provider.to_sym
        @adapter.conductor.provider_manager.record_failure(provider)
        Aidp.logger.warn("agent_harness_provider_manager", "Provider auth failure recorded",
          provider: provider)
      end

      # Mark provider as having exhausted failures
      #
      # @param provider [Symbol, String] provider name
      # @return [void]
      def mark_provider_failure_exhausted(provider)
        provider = provider.to_sym
        # Record multiple failures to trigger circuit breaker
        5.times { @adapter.conductor.provider_manager.record_failure(provider) }
        Aidp.logger.warn("agent_harness_provider_manager", "Provider failures exhausted",
          provider: provider)
      end

      # Record successful request
      #
      # @param provider [Symbol, String] provider name
      # @return [void]
      def record_success(provider)
        @adapter.conductor.provider_manager.record_success(provider.to_sym)
      end

      # Record failed request
      #
      # @param provider [Symbol, String] provider name
      # @return [void]
      def record_failure(provider)
        @adapter.conductor.provider_manager.record_failure(provider.to_sym)
      end

      # Check if provider is healthy
      #
      # @param provider [Symbol, String] provider name
      # @return [Boolean] true if healthy
      def healthy?(provider)
        @adapter.conductor.provider_manager.healthy?(provider.to_sym)
      end

      # Check if circuit is open for provider
      #
      # @param provider [Symbol, String] provider name
      # @return [Boolean] true if circuit is open
      def circuit_open?(provider)
        @adapter.conductor.provider_manager.circuit_open?(provider.to_sym)
      end

      # Get provider instance
      #
      # @param provider [Symbol, String] provider name
      # @return [AgentHarness::Providers::Base] provider instance
      def get_provider(provider = nil)
        provider ||= current_provider
        @adapter.conductor.provider_manager.get_provider(provider.to_sym)
      end

      # Switch to next model within provider
      #
      # @return [String, nil] new model name or nil
      def switch_model
        # AgentHarness doesn't support per-provider model switching yet
        # This is a no-op for now
        Aidp.logger.debug("agent_harness_provider_manager", "Model switching not yet supported via AgentHarness")
        nil
      end

      # Switch model based on error type
      #
      # @param error_type [Symbol] type of error
      # @param context [Hash] additional context
      # @return [String, nil] new model name or nil
      def switch_model_for_error(error_type, context = {})
        switch_model
      end

      # Reset all state
      #
      # @return [void]
      def reset!
        @adapter.reset!
        @rate_limit_info.clear
        @provider_history.clear
        @current_model = nil
      end

      # Get token usage summary
      #
      # @return [Hash] token usage
      def token_summary
        @adapter.token_summary
      end

      private

      def default_model(provider)
        config = AgentHarness.configuration.providers[provider.to_sym]
        config&.model || config&.models&.first
      end

      def log_provider_switch(from, to, reason, context)
        @provider_history << {
          from: from,
          to: to,
          reason: reason,
          context: context,
          timestamp: Time.now
        }
      end
    end
  end
end
