# frozen_string_literal: true

module Aidp
  module Harness
    # Manages provider fallback strategies after retry exhaustion
    class FallbackManager
      def initialize(provider_manager, configuration, metrics_manager = nil)
        @provider_manager = provider_manager
        @configuration = configuration
        @metrics_manager = metrics_manager
        @fallback_strategies = {}
        @fallback_history = []
        @exhausted_providers = {}
        @exhausted_models = {}
        @fallback_attempts = {}
        @circuit_breaker_manager = CircuitBreakerManager.new
        @load_balancer = LoadBalancer.new
        @health_monitor = HealthMonitor.new
        initialize_fallback_strategies
      end

      # Main entry point for fallback handling
      def handle_retry_exhaustion(provider, model, error_type, context = {})
        fallback_info = {
          provider: provider,
          model: model,
          error_type: error_type,
          context: context,
          timestamp: Time.now,
          retry_count: context[:retry_count] || 0
        }

        # Record in metrics if available
        @metrics_manager&.record_fallback_attempt(fallback_info)

        # Add to fallback history
        @fallback_history << fallback_info

        # Mark provider/model as exhausted
        mark_as_exhausted(provider, model, error_type)

        # Get fallback strategy
        strategy = get_fallback_strategy(error_type, context)

        # Execute fallback
        result = execute_fallback(fallback_info, strategy)

        # Update fallback attempts tracking
        update_fallback_attempts(provider, model, error_type, result)

        result
      end

      # Execute fallback based on strategy
      def execute_fallback(fallback_info, strategy)
        case strategy[:action]
        when :switch_provider
          execute_provider_switch(fallback_info, strategy)
        when :switch_model
          execute_model_switch(fallback_info, strategy)
        when :switch_provider_model
          execute_provider_model_switch(fallback_info, strategy)
        when :load_balance
          execute_load_balanced_switch(fallback_info, strategy)
        when :circuit_breaker
          execute_circuit_breaker_fallback(fallback_info, strategy)
        when :escalate
          execute_escalation(fallback_info, strategy)
        when :abort
          execute_abort(fallback_info, strategy)
        else
          execute_default_fallback(fallback_info, strategy)
        end
      end

      # Get fallback strategy for error type and context
      def get_fallback_strategy(error_type, context = {})
        # Check for context-specific strategy
        if context[:fallback_strategy]
          return @fallback_strategies[context[:fallback_strategy]] || @fallback_strategies[:default]
        end

        # Get error-type specific strategy
        strategy = @fallback_strategies[error_type] || @fallback_strategies[:default]

        # Apply context modifications
        strategy = apply_context_modifications(strategy, context)

        strategy
      end

      # Check if provider is exhausted
      def provider_exhausted?(provider, error_type = nil)
        if error_type
          @exhausted_providers.dig(provider, error_type)
        else
          @exhausted_providers.key?(provider)
        end
      end

      # Check if model is exhausted
      def model_exhausted?(provider, model, error_type = nil)
        if error_type
          @exhausted_models.dig(provider, model, error_type)
        else
          @exhausted_models.dig(provider, model)
        end
      end

      # Get available providers (not exhausted)
      def get_available_providers(error_type = nil)
        all_providers = @provider_manager.configured_providers
        all_providers.reject do |provider|
          provider_exhausted?(provider, error_type) ||
            @circuit_breaker_manager.circuit_breaker_open?(provider)
        end
      end

      # Get available models for provider (not exhausted)
      def get_available_models(provider, error_type = nil)
        all_models = @provider_manager.get_provider_models(provider)
        all_models.reject do |model|
          model_exhausted?(provider, model, error_type) ||
            @circuit_breaker_manager.circuit_breaker_open?(provider, model)
        end
      end

      # Reset exhausted status for provider
      def reset_provider_exhaustion(provider, error_type = nil)
        if error_type
          @exhausted_providers[provider]&.delete(error_type)
          @exhausted_providers.delete(provider) if @exhausted_providers[provider] && @exhausted_providers[provider].empty?
        else
          @exhausted_providers.delete(provider)
        end
      end

      # Reset exhausted status for model
      def reset_model_exhaustion(provider, model, error_type = nil)
        if error_type
          @exhausted_models[provider]&.[](model)&.delete(error_type)
          @exhausted_models[provider]&.delete(model) if @exhausted_models[provider] && @exhausted_models[provider][model] && @exhausted_models[provider][model].empty?
          @exhausted_models.delete(provider) if @exhausted_models[provider] && @exhausted_models[provider].empty?
        else
          @exhausted_models[provider]&.delete(model)
          @exhausted_models.delete(provider) if @exhausted_models[provider] && @exhausted_models[provider].empty?
        end
      end

      # Reset all exhaustion status
      def reset_all_exhaustion
        @exhausted_providers.clear
        @exhausted_models.clear
        @fallback_attempts.clear
      end

      # Get fallback status
      def get_fallback_status
        {
          exhausted_providers: @exhausted_providers,
          exhausted_models: @exhausted_models,
          fallback_attempts: @fallback_attempts,
          circuit_breaker_status: @circuit_breaker_manager.get_status,
          health_status: @health_monitor.get_status
        }
      end

      # Get fallback history
      def get_fallback_history(time_range = nil)
        if time_range
          @fallback_history.select { |f| time_range.include?(f[:timestamp]) }
        else
          @fallback_history
        end
      end

      # Clear fallback history
      def clear_fallback_history
        @fallback_history.clear
      end

      # Configure fallback strategies
      def configure_fallback_strategies(strategies)
        @fallback_strategies.merge!(strategies)
      end

      private

      def initialize_fallback_strategies
        @fallback_strategies = {
          # Rate limit fallback - immediate provider switch
          rate_limit: {
            name: "rate_limit",
            action: :switch_provider,
            priority: :high,
            max_attempts: 3,
            cooldown_period: 300, # 5 minutes
            selection_strategy: :health_based,
            fallback_chain: :default
          },

          # Network error fallback - provider switch with health check
          network_error: {
            name: "network_error",
            action: :switch_provider,
            priority: :high,
            max_attempts: 2,
            cooldown_period: 60, # 1 minute
            selection_strategy: :load_balanced,
            fallback_chain: :network_optimized
          },

          # Server error fallback - provider switch with circuit breaker
          server_error: {
            name: "server_error",
            action: :switch_provider,
            priority: :medium,
            max_attempts: 2,
            cooldown_period: 120, # 2 minutes
            selection_strategy: :circuit_breaker_aware,
            fallback_chain: :reliability_optimized
          },

          # Timeout fallback - model switch first, then provider
          timeout: {
            name: "timeout",
            action: :switch_model,
            priority: :medium,
            max_attempts: 2,
            cooldown_period: 60, # 1 minute
            selection_strategy: :performance_based,
            fallback_chain: :performance_optimized
          },

          # Authentication fallback - escalation only
          authentication: {
            name: "authentication",
            action: :escalate,
            priority: :critical,
            max_attempts: 0,
            cooldown_period: 0,
            selection_strategy: :none,
            fallback_chain: :none
          },

          # Permission denied fallback - escalation only
          permission_denied: {
            name: "permission_denied",
            action: :escalate,
            priority: :critical,
            max_attempts: 0,
            cooldown_period: 0,
            selection_strategy: :none,
            fallback_chain: :none
          },

          # Default fallback strategy
          default: {
            name: "default",
            action: :switch_provider,
            priority: :low,
            max_attempts: 3,
            cooldown_period: 180, # 3 minutes
            selection_strategy: :round_robin,
            fallback_chain: :default
          }
        }

        # Override with configuration if available
        if @configuration.respond_to?(:fallback_config)
          config_strategies = @configuration.fallback_config[:strategies] || {}
          config_strategies.each do |error_type, config|
            @fallback_strategies[error_type.to_sym] = @fallback_strategies[error_type.to_sym].merge(config)
          end
        end
      end

      def mark_as_exhausted(provider, model, error_type)
        # Mark provider as exhausted for this error type
        @exhausted_providers[provider] ||= {}
        @exhausted_providers[provider][error_type] = Time.now

        # Mark model as exhausted for this error type
        @exhausted_models[provider] ||= {}
        @exhausted_models[provider][model] ||= {}
        @exhausted_models[provider][model][error_type] = Time.now
      end

      def apply_context_modifications(strategy, context)
        modified_strategy = strategy.dup

        # Apply context-specific modifications
        if context[:priority]
          modified_strategy[:priority] = context[:priority]
        end

        if context[:max_attempts]
          modified_strategy[:max_attempts] = context[:max_attempts]
        end

        if context[:cooldown_period]
          modified_strategy[:cooldown_period] = context[:cooldown_period]
        end

        if context[:selection_strategy]
          modified_strategy[:selection_strategy] = context[:selection_strategy]
        end

        modified_strategy
      end

      def execute_provider_switch(fallback_info, strategy)
        available_providers = get_available_providers(fallback_info[:error_type])

        if available_providers.empty?
          return {
            success: false,
            action: :no_providers_available,
            error: "No available providers for fallback",
            fallback_info: fallback_info
          }
        end

        # Select provider based on strategy
        selected_provider = select_provider(available_providers, strategy, fallback_info)

        if selected_provider
          # Switch to selected provider
          @provider_manager.set_current_provider(selected_provider)

          {
            success: true,
            action: :provider_switch,
            new_provider: selected_provider,
            reason: "Fallback after retry exhaustion",
            fallback_info: fallback_info,
            strategy: strategy[:name]
          }
        else
          {
            success: false,
            action: :provider_selection_failed,
            error: "Failed to select provider for fallback",
            fallback_info: fallback_info
          }
        end
      end

      def execute_model_switch(fallback_info, strategy)
        provider = fallback_info[:provider]
        available_models = get_available_models(provider, fallback_info[:error_type])

        if available_models.empty?
          # No models available, try provider switch
          return execute_provider_switch(fallback_info, strategy)
        end

        # Select model based on strategy
        selected_model = select_model(available_models, strategy, fallback_info)

        if selected_model
          # Switch to selected model
          @provider_manager.set_current_model(provider, selected_model)

          {
            success: true,
            action: :model_switch,
            provider: provider,
            new_model: selected_model,
            reason: "Fallback after retry exhaustion",
            fallback_info: fallback_info,
            strategy: strategy[:name]
          }
        else
          {
            success: false,
            action: :model_selection_failed,
            error: "Failed to select model for fallback",
            fallback_info: fallback_info
          }
        end
      end

      def execute_provider_model_switch(fallback_info, strategy)
        # Try model switch first
        model_result = execute_model_switch(fallback_info, strategy)

        if model_result[:success]
          return model_result
        end

        # If model switch fails, try provider switch
        provider_result = execute_provider_switch(fallback_info, strategy)

        if provider_result[:success]
          return provider_result
        end

        # Both failed
        {
          success: false,
          action: :provider_model_switch_failed,
          error: "Both model and provider switch failed",
          fallback_info: fallback_info,
          model_result: model_result,
          provider_result: provider_result
        }
      end

      def execute_load_balanced_switch(fallback_info, strategy)
        available_providers = get_available_providers(fallback_info[:error_type])

        if available_providers.empty?
          return {
            success: false,
            action: :no_providers_available,
            error: "No available providers for load balanced fallback",
            fallback_info: fallback_info
          }
        end

        # Use load balancer to select provider
        selected_provider = @load_balancer.select_provider(available_providers, strategy)

        if selected_provider
          @provider_manager.set_current_provider(selected_provider)

          {
            success: true,
            action: :load_balanced_switch,
            new_provider: selected_provider,
            reason: "Load balanced fallback after retry exhaustion",
            fallback_info: fallback_info,
            strategy: strategy[:name]
          }
        else
          {
            success: false,
            action: :load_balanced_selection_failed,
            error: "Load balancer failed to select provider",
            fallback_info: fallback_info
          }
        end
      end

      def execute_circuit_breaker_fallback(fallback_info, strategy)
        # Open circuit breaker for current provider/model
        @circuit_breaker_manager.open_circuit_breaker(
          fallback_info[:provider],
          fallback_info[:model],
          fallback_info[:error_type]
        )

        # Try to find alternative
        available_providers = get_available_providers(fallback_info[:error_type])

        if available_providers.empty?
          return {
            success: false,
            action: :circuit_breaker_no_alternatives,
            error: "Circuit breaker opened but no alternatives available",
            fallback_info: fallback_info
          }
        end

        # Select provider avoiding circuit breakers
        selected_provider = @circuit_breaker_manager.select_healthy_provider(available_providers)

        if selected_provider
          @provider_manager.set_current_provider(selected_provider)

          {
            success: true,
            action: :circuit_breaker_fallback,
            new_provider: selected_provider,
            reason: "Circuit breaker fallback after retry exhaustion",
            fallback_info: fallback_info,
            strategy: strategy[:name]
          }
        else
          {
            success: false,
            action: :circuit_breaker_fallback_failed,
            error: "Circuit breaker fallback failed",
            fallback_info: fallback_info
          }
        end
      end

      def execute_escalation(fallback_info, strategy)
        {
          success: false,
          action: :escalated,
          error: "Fallback escalated: #{fallback_info[:error_type]}",
          escalation_reason: "Retry exhaustion with no viable alternatives",
          fallback_info: fallback_info,
          requires_manual_intervention: true,
          strategy: strategy[:name]
        }
      end

      def execute_abort(fallback_info, strategy)
        {
          success: false,
          action: :aborted,
          error: "Fallback aborted: #{fallback_info[:error_type]}",
          abort_reason: "Retry exhaustion with abort strategy",
          fallback_info: fallback_info,
          strategy: strategy[:name]
        }
      end

      def execute_default_fallback(fallback_info, strategy)
        # Default to provider switch
        execute_provider_switch(fallback_info, strategy)
      end

      def select_provider(available_providers, strategy, fallback_info)
        case strategy[:selection_strategy]
        when :health_based
          @health_monitor.select_healthiest_provider(available_providers)
        when :load_balanced
          @load_balancer.select_provider(available_providers, strategy)
        when :circuit_breaker_aware
          @circuit_breaker_manager.select_healthy_provider(available_providers)
        when :performance_based
          select_performance_based_provider(available_providers, fallback_info)
        when :round_robin
          select_round_robin_provider(available_providers)
        else
          available_providers.first
        end
      end

      def select_model(available_models, strategy, fallback_info)
        case strategy[:selection_strategy]
        when :performance_based
          select_performance_based_model(available_models, fallback_info)
        when :health_based
          @health_monitor.select_healthiest_model(available_models)
        else
          available_models.first
        end
      end

      def select_performance_based_provider(available_providers, _fallback_info)
        # This would integrate with metrics to select best performing provider
        # For now, return first available
        available_providers.first
      end

      def select_performance_based_model(available_models, _fallback_info)
        # This would integrate with metrics to select best performing model
        # For now, return first available
        available_models.first
      end

      def select_round_robin_provider(available_providers)
        # Simple round robin selection
        @round_robin_index ||= 0
        selected = available_providers[@round_robin_index % available_providers.size]
        @round_robin_index += 1
        selected
      end

      def update_fallback_attempts(provider, model, error_type, result)
        key = "#{provider}:#{model}:#{error_type}"
        @fallback_attempts[key] ||= { count: 0, last_attempt: nil, results: [] }

        @fallback_attempts[key][:count] += 1
        @fallback_attempts[key][:last_attempt] = Time.now
        @fallback_attempts[key][:results] << result
      end

      # Helper classes
      class CircuitBreakerManager
        def initialize
          @circuit_breakers = {}
        end

        def circuit_breaker_open?(provider, model = nil)
          key = model ? "#{provider}:#{model}" : provider
          cb = @circuit_breakers[key]
          return false unless cb

          cb[:open] && (Time.now - cb[:opened_at] < cb[:timeout])
        end

        def open_circuit_breaker(provider, model, error_type)
          key = model ? "#{provider}:#{model}" : provider
          @circuit_breakers[key] = {
            open: true,
            opened_at: Time.now,
            timeout: 300, # 5 minutes default
            error_type: error_type
          }
        end

        def select_healthy_provider(providers)
          healthy_providers = providers.reject { |p| circuit_breaker_open?(p) }
          healthy_providers.first
        end

        def get_status
          @circuit_breakers.transform_values do |cb|
            {
              open: cb[:open],
              opened_at: cb[:opened_at],
              timeout: cb[:timeout],
              error_type: cb[:error_type]
            }
          end
        end
      end

      class LoadBalancer
        def select_provider(providers, _strategy)
          # Simple load balancing - could be enhanced with actual load metrics
          providers.sample
        end
      end

      class HealthMonitor
        def select_healthiest_provider(providers)
          # Simple health selection - could be enhanced with actual health metrics
          providers.first
        end

        def select_healthiest_model(models)
          # Simple health selection - could be enhanced with actual health metrics
          models.first
        end

        def get_status
          {
            providers: {},
            models: {}
          }
        end
      end
    end
  end
end
