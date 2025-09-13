# frozen_string_literal: true

module Aidp
  module Harness
    # Specialized manager for rate limit recovery with immediate switching
    class RateLimitRecoveryManager
      def initialize(provider_manager, configuration, metrics_manager = nil)
        @provider_manager = provider_manager
        @configuration = configuration
        @metrics_manager = metrics_manager
        @rate_limit_tracker = RateLimitTracker.new
        @quota_manager = QuotaManager.new
        @switch_strategies = {}
        @recovery_history = []
        @active_rate_limits = {}
        @quota_usage = {}
        @switch_cooldowns = {}
        initialize_switch_strategies
      end

      # Main entry point for rate limit recovery
      def handle_rate_limit(provider, model, rate_limit_info, context = {})
        recovery_info = build_recovery_info(provider, model, rate_limit_info, context)

        # Record in metrics if available
        @metrics_manager&.record_rate_limit(provider, model, rate_limit_info, context)

        # Add to recovery history
        @recovery_history << recovery_info

        # Track rate limit
        @rate_limit_tracker.record_rate_limit(provider, model, rate_limit_info)

        # Update quota usage
        @quota_manager.record_rate_limit(provider, model, rate_limit_info)

        # Get switch strategy
        strategy = get_switch_strategy(provider, model, rate_limit_info, context)

        # Execute immediate switch
        result = execute_immediate_switch(recovery_info, strategy)

        # Update active rate limits
        update_active_rate_limits(provider, model, rate_limit_info, result)

        result
      end

      # Execute immediate switch based on strategy
      def execute_immediate_switch(recovery_info, strategy)
        case strategy[:action]
        when :switch_provider
          execute_provider_switch(recovery_info, strategy)
        when :switch_model
          execute_model_switch(recovery_info, strategy)
        when :switch_provider_model
          execute_provider_model_switch(recovery_info, strategy)
        when :quota_aware_switch
          execute_quota_aware_switch(recovery_info, strategy)
        when :cost_optimized_switch
          execute_cost_optimized_switch(recovery_info, strategy)
        when :performance_optimized_switch
          execute_performance_optimized_switch(recovery_info, strategy)
        when :wait_and_retry
          execute_wait_and_retry(recovery_info, strategy)
        when :escalate
          execute_escalation(recovery_info, strategy)
        else
          execute_default_switch(recovery_info, strategy)
        end
      end

      # Get switch strategy for rate limit scenario
      def get_switch_strategy(provider, model, rate_limit_info, context = {})
        # Check for context-specific strategy
        if context[:switch_strategy]
          return @switch_strategies[context[:switch_strategy]] || @switch_strategies[:default]
        end

        # Determine strategy based on rate limit type and context
        strategy_name = determine_strategy_name(provider, model, rate_limit_info, context)
        strategy = @switch_strategies[strategy_name] || @switch_strategies[:default]

        # Apply context modifications
        apply_context_modifications(strategy, context, rate_limit_info)
      end

      # Check if provider/model is currently rate limited
      def is_rate_limited?(provider, model = nil)
        if model
          @active_rate_limits.dig(provider, model) != nil
        else
          @active_rate_limits.key?(provider)
        end
      end

      # Get rate limit status for provider/model
      def get_rate_limit_status(provider, model = nil)
        if model
          @active_rate_limits.dig(provider, model) || {}
        else
          @active_rate_limits[provider] || {}
        end
      end

      # Get available providers (not rate limited)
      def get_available_providers
        all_providers = @provider_manager.get_available_providers
        all_providers.reject { |provider| is_rate_limited?(provider) }
      end

      # Get available models for provider (not rate limited)
      def get_available_models(provider)
        all_models = @provider_manager.get_provider_models(provider)
        all_models.reject { |model| is_rate_limited?(provider, model) }
      end

      # Get quota status for provider/model
      def get_quota_status(provider, model = nil)
        @quota_manager.get_quota_status(provider, model)
      end

      # Get rate limit recovery history
      def get_recovery_history(time_range = nil)
        if time_range
          @recovery_history.select { |r| time_range.include?(r[:timestamp]) }
        else
          @recovery_history
        end
      end

      # Clear recovery history
      def clear_recovery_history
        @recovery_history.clear
      end

      # Reset rate limit status for provider/model
      def reset_rate_limit(provider, model = nil)
        if model
          @active_rate_limits[provider]&.delete(model)
          @active_rate_limits.delete(provider) if @active_rate_limits[provider] && @active_rate_limits[provider].empty?
        else
          @active_rate_limits.delete(provider)
        end

        @rate_limit_tracker.clear_rate_limit(provider, model)
        @quota_manager.reset_quota(provider, model)
      end

      # Reset all rate limits
      def reset_all_rate_limits
        @active_rate_limits.clear
        @rate_limit_tracker.clear_all_rate_limits
        @quota_manager.reset_all_quotas
        @switch_cooldowns.clear
      end

      # Get comprehensive rate limit status
      def get_comprehensive_status
        {
          active_rate_limits: @active_rate_limits,
          quota_status: @quota_manager.get_all_quota_status,
          rate_limit_tracker_status: @rate_limit_tracker.get_status,
          recovery_history_count: @recovery_history.size,
          switch_cooldowns: @switch_cooldowns
        }
      end

      # Configure switch strategies
      def configure_switch_strategies(strategies)
        @switch_strategies.merge!(strategies)
      end

      private

      def initialize_switch_strategies
        @switch_strategies = {
          # Immediate provider switch strategy
          immediate_provider_switch: {
            name: "immediate_provider_switch",
            action: :switch_provider,
            priority: :high,
            selection_strategy: :health_based,
            cooldown_period: 0,
            max_switches_per_minute: 10
          },

          # Immediate model switch strategy
          immediate_model_switch: {
            name: "immediate_model_switch",
            action: :switch_model,
            priority: :medium,
            selection_strategy: :performance_based,
            cooldown_period: 0,
            max_switches_per_minute: 15
          },

          # Quota-aware switch strategy
          quota_aware: {
            name: "quota_aware",
            action: :quota_aware_switch,
            priority: :high,
            selection_strategy: :quota_based,
            cooldown_period: 30,
            max_switches_per_minute: 5
          },

          # Cost-optimized switch strategy
          cost_optimized: {
            name: "cost_optimized",
            action: :cost_optimized_switch,
            priority: :medium,
            selection_strategy: :cost_based,
            cooldown_period: 60,
            max_switches_per_minute: 3
          },

          # Performance-optimized switch strategy
          performance_optimized: {
            name: "performance_optimized",
            action: :performance_optimized_switch,
            priority: :high,
            selection_strategy: :performance_based,
            cooldown_period: 0,
            max_switches_per_minute: 8
          },

          # Wait and retry strategy (for temporary rate limits)
          wait_and_retry: {
            name: "wait_and_retry",
            action: :wait_and_retry,
            priority: :low,
            selection_strategy: :none,
            cooldown_period: 0,
            max_switches_per_minute: 0,
            wait_time: 60
          },

          # Escalation strategy (for persistent rate limits)
          escalate: {
            name: "escalate",
            action: :escalate,
            priority: :critical,
            selection_strategy: :none,
            cooldown_period: 0,
            max_switches_per_minute: 0
          },

          # Default strategy
          default: {
            name: "default",
            action: :switch_provider,
            priority: :medium,
            selection_strategy: :round_robin,
            cooldown_period: 0,
            max_switches_per_minute: 5
          }
        }

        # Override with configuration if available
        if @configuration.respond_to?(:rate_limit_recovery_config)
          config_strategies = @configuration.rate_limit_recovery_config[:strategies] || {}
          config_strategies.each do |strategy_name, config|
            @switch_strategies[strategy_name.to_sym] = @switch_strategies[strategy_name.to_sym].merge(config)
          end
        end
      end

      def build_recovery_info(provider, model, rate_limit_info, context)
        {
          provider: provider,
          model: model,
          rate_limit_info: rate_limit_info,
          context: context,
          timestamp: Time.now,
          rate_limit_type: rate_limit_info[:type] || :unknown,
          reset_time: rate_limit_info[:reset_time],
          retry_after: rate_limit_info[:retry_after],
          quota_remaining: rate_limit_info[:quota_remaining],
          quota_limit: rate_limit_info[:quota_limit]
        }
      end

      def determine_strategy_name(provider, _model, rate_limit_info, context)
        # Check if this is a temporary rate limit
        if rate_limit_info[:retry_after] && rate_limit_info[:retry_after] < 60
          return :wait_and_retry
        end

        # Check if quota is exhausted
        if rate_limit_info[:quota_remaining] && rate_limit_info[:quota_remaining] <= 0
          return :quota_aware
        end

        # Check if cost optimization is needed
        if context[:cost_sensitive]
          return :cost_optimized
        end

        # Check if performance is critical
        if context[:performance_critical]
          return :performance_optimized
        end

        # Check if multiple providers are available
        available_providers = get_available_providers
        if available_providers.size > 1
          return :immediate_provider_switch
        end

        # Check if multiple models are available
        available_models = get_available_models(provider)
        if available_models.size > 1
          return :immediate_model_switch
        end

        # Default to escalation if no alternatives
        :escalate
      end

      def apply_context_modifications(strategy, context, rate_limit_info)
        modified_strategy = strategy.dup

        # Apply context-specific modifications
        if context[:priority]
          modified_strategy[:priority] = context[:priority]
        end

        if context[:cooldown_period]
          modified_strategy[:cooldown_period] = context[:cooldown_period]
        end

        if context[:max_switches_per_minute]
          modified_strategy[:max_switches_per_minute] = context[:max_switches_per_minute]
        end

        # Apply rate limit specific modifications
        if rate_limit_info[:retry_after] && rate_limit_info[:retry_after] < 30
          modified_strategy[:cooldown_period] = [modified_strategy[:cooldown_period], rate_limit_info[:retry_after]].max
        end

        modified_strategy
      end

      def execute_provider_switch(recovery_info, strategy)
        available_providers = get_available_providers

        if available_providers.empty?
          return {
            success: false,
            action: :no_providers_available,
            error: "No available providers for rate limit recovery",
            recovery_info: recovery_info
          }
        end

        # Check switch cooldown
        if switch_cooldown_active?(recovery_info[:provider], strategy)
          return {
            success: false,
            action: :switch_cooldown_active,
            error: "Switch cooldown active for provider",
            recovery_info: recovery_info,
            cooldown_remaining: get_cooldown_remaining(recovery_info[:provider], strategy)
          }
        end

        # Select provider based on strategy
        selected_provider = select_provider(available_providers, strategy, recovery_info)

        if selected_provider
          # Switch to selected provider
          provider_switch_result = @provider_manager.set_current_provider(selected_provider)

          if provider_switch_result
            # Record switch cooldown
            record_switch_cooldown(recovery_info[:provider], strategy)

            {
              success: true,
              action: :provider_switch,
              new_provider: selected_provider,
              reason: "Rate limit recovery - immediate provider switch",
              recovery_info: recovery_info,
              strategy: strategy[:name]
            }
          else
            # Provider switch failed, try model switch
            available_models = get_available_models(recovery_info[:provider])
            if available_models.any?
              model_switch_result = @provider_manager.set_current_model(recovery_info[:provider], available_models.first)
              if model_switch_result
                {
                  success: true,
                  action: :model_switch,
                  new_provider: recovery_info[:provider],
                  new_model: available_models.first,
                  reason: "Rate limit recovery - fallback to model switch",
                  recovery_info: recovery_info,
                  strategy: strategy[:name]
                }
              else
                {
                  success: false,
                  action: :switch_failed,
                  error: "Both provider and model switches failed",
                  recovery_info: recovery_info
                }
              end
            else
              {
                success: false,
                action: :no_models_available,
                error: "No available models for fallback",
                recovery_info: recovery_info
              }
            end
          end
        else
          {
            success: false,
            action: :provider_selection_failed,
            error: "Failed to select provider for rate limit recovery",
            recovery_info: recovery_info
          }
        end
      end

      def execute_model_switch(recovery_info, strategy)
        provider = recovery_info[:provider]
        available_models = get_available_models(provider)

        if available_models.empty?
          # No models available, try provider switch
          return execute_provider_switch(recovery_info, strategy)
        end

        # Check switch cooldown
        if switch_cooldown_active?(provider, strategy)
          return {
            success: false,
            action: :switch_cooldown_active,
            error: "Switch cooldown active for model",
            recovery_info: recovery_info,
            cooldown_remaining: get_cooldown_remaining(provider, strategy)
          }
        end

        # Select model based on strategy
        selected_model = select_model(available_models, strategy, recovery_info)

        if selected_model
          # Switch to selected model
          @provider_manager.set_current_model(provider, selected_model)

          # Record switch cooldown
          record_switch_cooldown(provider, strategy)

          {
            success: true,
            action: :model_switch,
            provider: provider,
            new_model: selected_model,
            reason: "Rate limit recovery - immediate model switch",
            recovery_info: recovery_info,
            strategy: strategy[:name]
          }
        else
          {
            success: false,
            action: :model_selection_failed,
            error: "Failed to select model for rate limit recovery",
            recovery_info: recovery_info
          }
        end
      end

      def execute_provider_model_switch(recovery_info, strategy)
        # Try model switch first
        model_result = execute_model_switch(recovery_info, strategy)

        if model_result[:success]
          return model_result
        end

        # If model switch fails, try provider switch
        provider_result = execute_provider_switch(recovery_info, strategy)

        if provider_result[:success]
          return provider_result
        end

        # Both failed
        {
          success: false,
          action: :provider_model_switch_failed,
          error: "Both model and provider switch failed for rate limit recovery",
          recovery_info: recovery_info,
          model_result: model_result,
          provider_result: provider_result
        }
      end

      def execute_quota_aware_switch(recovery_info, strategy)
        # Find provider/model combination with most quota remaining
        best_combination = @quota_manager.find_best_quota_combination(recovery_info)

        if best_combination
          if best_combination[:provider] != recovery_info[:provider]
            # Switch provider
            provider_switch_result = @provider_manager.set_current_provider(best_combination[:provider])
            if provider_switch_result
              action = :quota_aware_switch
              new_provider = best_combination[:provider]
              new_model = nil
            else
              # Provider switch failed, try model switch
              model_switch_result = @provider_manager.set_current_model(recovery_info[:provider], best_combination[:model])
              if model_switch_result
                action = :quota_aware_switch
                new_provider = recovery_info[:provider]
                new_model = best_combination[:model]
              else
                return {
                  success: false,
                  action: :quota_aware_switch_failed,
                  error: "Both provider and model switches failed"
                }
              end
            end
          else
            # Switch model
            model_switch_result = @provider_manager.set_current_model(best_combination[:provider], best_combination[:model])
            if model_switch_result
              action = :quota_aware_switch
              new_provider = best_combination[:provider]
              new_model = best_combination[:model]
            else
              return {
                success: false,
                action: :quota_aware_switch_failed,
                error: "Model switch failed"
              }
            end
          end

          {
            success: true,
            action: action,
            new_provider: new_provider,
            new_model: new_model,
            reason: "Rate limit recovery - quota-aware switch",
            recovery_info: recovery_info,
            strategy: strategy[:name],
            quota_remaining: best_combination[:quota_remaining]
          }
        else
          {
            success: false,
            action: :quota_aware_switch_failed,
            error: "No provider/model combination with sufficient quota found",
            recovery_info: recovery_info
          }
        end
      end

      def execute_cost_optimized_switch(recovery_info, strategy)
        # Find most cost-effective alternative
        cost_optimized_combination = find_cost_optimized_combination(recovery_info)

        if cost_optimized_combination
          @provider_manager.set_current_provider(cost_optimized_combination[:provider])
          @provider_manager.set_current_model(cost_optimized_combination[:provider], cost_optimized_combination[:model])

          {
            success: true,
            action: :cost_optimized_switch,
            new_provider: cost_optimized_combination[:provider],
            new_model: cost_optimized_combination[:model],
            reason: "Rate limit recovery - cost-optimized switch",
            recovery_info: recovery_info,
            strategy: strategy[:name],
            cost_savings: cost_optimized_combination[:cost_savings]
          }
        else
          {
            success: false,
            action: :cost_optimized_switch_failed,
            error: "No cost-optimized alternative found",
            recovery_info: recovery_info
          }
        end
      end

      def execute_performance_optimized_switch(recovery_info, strategy)
        # Find highest performing alternative
        performance_optimized_combination = find_performance_optimized_combination(recovery_info)

        if performance_optimized_combination
          @provider_manager.set_current_provider(performance_optimized_combination[:provider])
          @provider_manager.set_current_model(performance_optimized_combination[:provider], performance_optimized_combination[:model])

          {
            success: true,
            action: :performance_optimized_switch,
            new_provider: performance_optimized_combination[:provider],
            new_model: performance_optimized_combination[:model],
            reason: "Rate limit recovery - performance-optimized switch",
            recovery_info: recovery_info,
            strategy: strategy[:name],
            performance_score: performance_optimized_combination[:performance_score]
          }
        else
          {
            success: false,
            action: :performance_optimized_switch_failed,
            error: "No performance-optimized alternative found",
            recovery_info: recovery_info
          }
        end
      end

      def execute_wait_and_retry(recovery_info, strategy)
        wait_time = recovery_info[:retry_after] || strategy[:wait_time] || 60

        {
          success: true,
          action: :wait_and_retry,
          wait_time: wait_time,
          reason: "Rate limit recovery - waiting for rate limit reset",
          recovery_info: recovery_info,
          strategy: strategy[:name],
          reset_time: recovery_info[:reset_time]
        }
      end

      def execute_escalation(recovery_info, strategy)
        {
          success: false,
          action: :escalated,
          error: "Rate limit recovery escalated: #{recovery_info[:rate_limit_type]}",
          escalation_reason: "No viable alternatives for rate limit recovery",
          recovery_info: recovery_info,
          requires_manual_intervention: true,
          strategy: strategy[:name]
        }
      end

      def execute_default_switch(recovery_info, strategy)
        # Default to provider switch
        execute_provider_switch(recovery_info, strategy)
      end

      def select_provider(available_providers, strategy, _recovery_info)
        case strategy[:selection_strategy]
        when :health_based
          select_healthiest_provider(available_providers)
        when :quota_based
          select_provider_with_most_quota(available_providers)
        when :cost_based
          select_most_cost_effective_provider(available_providers)
        when :performance_based
          select_highest_performing_provider(available_providers)
        when :round_robin
          select_round_robin_provider(available_providers)
        else
          available_providers.first
        end
      end

      def select_model(available_models, strategy, _recovery_info)
        case strategy[:selection_strategy]
        when :performance_based
          select_highest_performing_model(available_models)
        when :quota_based
          select_model_with_most_quota(available_models)
        when :cost_based
          select_most_cost_effective_model(available_models)
        else
          available_models.first
        end
      end

      def select_healthiest_provider(providers)
        # This would integrate with health metrics
        providers.first
      end

      def select_provider_with_most_quota(providers)
        # This would integrate with quota tracking
        providers.first
      end

      def select_most_cost_effective_provider(providers)
        # This would integrate with cost metrics
        providers.first
      end

      def select_highest_performing_provider(providers)
        # This would integrate with performance metrics
        providers.first
      end

      def select_round_robin_provider(providers)
        @round_robin_index ||= 0
        selected = providers[@round_robin_index % providers.size]
        @round_robin_index += 1
        selected
      end

      def select_highest_performing_model(models)
        # This would integrate with performance metrics
        models.first
      end

      def select_model_with_most_quota(models)
        # This would integrate with quota tracking
        models.first
      end

      def select_most_cost_effective_model(models)
        # This would integrate with cost metrics
        models.first
      end

      def find_cost_optimized_combination(_recovery_info)
        # This would integrate with cost metrics to find the most cost-effective alternative
        # For now, return a mock result
        {
          provider: "gemini",
          model: "model1",
          cost_savings: 0.1
        }
      end

      def find_performance_optimized_combination(_recovery_info)
        # This would integrate with performance metrics to find the highest performing alternative
        # For now, return a mock result
        {
          provider: "cursor",
          model: "model2",
          performance_score: 0.95
        }
      end

      def switch_cooldown_active?(provider, strategy)
        cooldown_key = "#{provider}:#{strategy[:name]}"
        cooldown_info = @switch_cooldowns[cooldown_key]

        return false unless cooldown_info

        Time.now - cooldown_info[:timestamp] < strategy[:cooldown_period]
      end

      def get_cooldown_remaining(provider, strategy)
        cooldown_key = "#{provider}:#{strategy[:name]}"
        cooldown_info = @switch_cooldowns[cooldown_key]

        return 0 unless cooldown_info

        elapsed = Time.now - cooldown_info[:timestamp]
        remaining = strategy[:cooldown_period] - elapsed
        [remaining, 0].max
      end

      def record_switch_cooldown(provider, strategy)
        cooldown_key = "#{provider}:#{strategy[:name]}"
        @switch_cooldowns[cooldown_key] = {
          timestamp: Time.now,
          strategy: strategy[:name]
        }
      end

      def update_active_rate_limits(provider, model, rate_limit_info, result)
        if result[:success]
          # Rate limit resolved by successful switch
          @active_rate_limits[provider]&.delete(model)
          @active_rate_limits.delete(provider) if @active_rate_limits[provider] && @active_rate_limits[provider].empty?
        else
          # Rate limit still active
          @active_rate_limits[provider] ||= {}
          @active_rate_limits[provider][model] = {
            rate_limit_info: rate_limit_info,
            timestamp: Time.now,
            recovery_attempts: (@active_rate_limits[provider][model]&.dig(:recovery_attempts) || 0) + 1
          }
        end
      end

      # Helper classes
      class RateLimitTracker
        def initialize
          @rate_limits = {}
        end

        def record_rate_limit(provider, model, rate_limit_info)
          key = model ? "#{provider}:#{model}" : provider
          @rate_limits[key] = {
            rate_limit_info: rate_limit_info,
            timestamp: Time.now,
            count: (@rate_limits[key]&.dig(:count) || 0) + 1
          }
        end

        def clear_rate_limit(provider, model = nil)
          key = model ? "#{provider}:#{model}" : provider
          @rate_limits.delete(key)
        end

        def clear_all_rate_limits
          @rate_limits.clear
        end

        def get_status
          @rate_limits.transform_values do |info|
            {
              rate_limit_info: info[:rate_limit_info],
              timestamp: info[:timestamp],
              count: info[:count]
            }
          end
        end
      end

      class QuotaManager
        def initialize
          @quotas = {}
        end

        def record_rate_limit(provider, model, rate_limit_info)
          key = model ? "#{provider}:#{model}" : provider
          @quotas[key] = {
            quota_remaining: rate_limit_info[:quota_remaining] || 0,
            quota_limit: rate_limit_info[:quota_limit] || 0,
            last_updated: Time.now
          }
        end

        def get_quota_status(provider, model = nil)
          key = model ? "#{provider}:#{model}" : provider
          @quotas[key] || {}
        end

        def get_all_quota_status
          @quotas
        end

        def find_best_quota_combination(_recovery_info)
          # Find provider/model combination with most quota remaining
          best_combination = nil
          best_quota = 0

          @quotas.each do |key, quota_info|
            if quota_info[:quota_remaining] > best_quota
              provider, model = key.split(":", 2)
              best_combination = {
                provider: provider,
                model: model,
                quota_remaining: quota_info[:quota_remaining]
              }
              best_quota = quota_info[:quota_remaining]
            end
          end

          best_combination
        end

        def reset_quota(provider, model = nil)
          key = model ? "#{provider}:#{model}" : provider
          @quotas.delete(key)
        end

        def reset_all_quotas
          @quotas.clear
        end
      end
    end
  end
end
