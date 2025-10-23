# frozen_string_literal: true

require "tty-prompt"
require_relative "provider_factory"
require_relative "../rescue_logging"
require_relative "../concurrency"

module Aidp
  module Harness
    # Manages provider switching and fallback logic
    class ProviderManager
      include Aidp::MessageDisplay
      include Aidp::RescueLogging

      def initialize(configuration, prompt: TTY::Prompt.new, binary_checker: Aidp::Util)
        @configuration = configuration
        @prompt = prompt
        @binary_checker = binary_checker
        @current_provider = nil
        @current_model = nil
        @provider_history = []
        @rate_limit_info = {}
        @provider_metrics = {}
        @fallback_chains = {}
        @provider_health = {}
        @retry_counts = {}
        @max_retries = 3
        @circuit_breaker_threshold = 5
        @circuit_breaker_timeout = 300 # 5 minutes
        @provider_weights = {}
        @load_balancing_enabled = true
        @sticky_sessions = {}
        @session_timeout = 1800 # 30 minutes
        @model_configs = {}
        @model_health = {}
        @model_metrics = {}
        @model_fallback_chains = {}
        @model_switching_enabled = true
        @model_weights = {}
        @unavailable_cache = {}
        @binary_check_cache = {}
        @binary_check_ttl = 300 # seconds
        initialize_fallback_chains
        initialize_provider_health
        initialize_model_configs
        initialize_model_health
      end

      # Get current provider
      def current_provider
        @current_provider ||= @configuration.default_provider
      end

      # Get current model
      def current_model
        @current_model ||= default_model(current_provider)
      end

      # Get current provider and model combination
      def current_provider_model
        "#{current_provider}:#{current_model}"
      end

      # Get configured providers from configuration
      def configured_providers
        # Handle both Configuration and ConfigManager instances
        if @configuration.respond_to?(:configured_providers)
          @configuration.configured_providers
        else
          @configuration.provider_names
        end
      end

      # Switch to next available provider with sophisticated fallback logic
      def switch_provider(reason = "manual_switch", context = {})
        old_provider = current_provider
        Aidp.logger.info("provider_manager", "Attempting provider switch", reason: reason, current: old_provider, **context)

        # Get fallback chain for current provider
        provider_fallback_chain = fallback_chain(old_provider)

        # Find next healthy provider in fallback chain
        next_provider = find_next_healthy_provider(provider_fallback_chain, old_provider)

        if next_provider
          success = set_current_provider(next_provider, reason, context)
          if success
            log_provider_switch(old_provider, next_provider, reason, context)
            Aidp.logger.info("provider_manager", "Provider switched successfully", from: old_provider, to: next_provider, reason: reason)
            return next_provider
          else
            Aidp.logger.warn("provider_manager", "Failed to switch to provider", provider: next_provider, reason: reason)
          end
        end

        # If no provider in fallback chain, try load balancing
        if @load_balancing_enabled
          next_provider = select_provider_by_load_balancing
          if next_provider
            success = set_current_provider(next_provider, reason, context)
            if success
              log_provider_switch(old_provider, next_provider, reason, context)
              return next_provider
            end
          end
        end

        # Last resort: try any available provider
        next_provider = find_any_available_provider
        if next_provider
          success = set_current_provider(next_provider, reason, context)
          if success
            log_provider_switch(old_provider, next_provider, reason, context)
            return next_provider
          end
        end

        # No providers available
        log_no_providers_available(reason, context)
        Aidp.logger.error("provider_manager", "No providers available for fallback", reason: reason, provider: old_provider)
        nil
      end

      # Switch provider for specific error type
      def switch_provider_for_error(error_type, error_details = {})
        Aidp.logger.warn("provider_manager", "Error triggered provider switch", error_type: error_type, **error_details)

        case error_type
        when "rate_limit"
          switch_provider("rate_limit", error_details)
        when "resource_exhausted", "quota_exceeded"
          # Treat capacity/resource exhaustion like rate limit for fallback purposes
          Aidp.logger.warn("provider_manager", "Resource/quota exhaustion detected", classified_from: error_type)
          switch_provider("rate_limit", error_details.merge(classified_from: error_type))
        when "authentication"
          switch_provider("authentication_error", error_details)
        when "network"
          switch_provider("network_error", error_details)
        when "server_error"
          switch_provider("server_error", error_details)
        when "timeout"
          switch_provider("timeout", error_details)
        else
          switch_provider("error", {error_type: error_type}.merge(error_details))
        end
      end

      # Switch provider with retry logic
      def switch_provider_with_retry(reason = "retry", max_retries = @max_retries)
        attempt_count = 0

        Aidp::Concurrency::Backoff.retry(
          max_attempts: max_retries,
          base: 0.5,
          strategy: :exponential,
          jitter: 0.2,
          on: [StandardError]
        ) do
          attempt_count += 1
          next_provider = switch_provider(reason, {retry_count: attempt_count - 1})

          if next_provider
            return next_provider
          else
            # Raise to trigger retry
            raise "Provider switch failed on attempt #{attempt_count}"
          end
        end
      rescue Aidp::Concurrency::MaxAttemptsError
        # All retries exhausted
        nil
      end

      # Switch to next available model within current provider
      def switch_model(reason = "manual_switch", context = {})
        return nil unless @model_switching_enabled

        # Get fallback chain for current provider's models
        model_chain = model_fallback_chain(current_provider)

        # Find next healthy model in fallback chain
        next_model = find_next_healthy_model(model_chain, current_model)

        if next_model
          success = set_current_model(next_model, reason, context)
          if success
            log_model_switch(current_model, next_model, reason, context)
            return next_model
          end
        end

        # If no model in fallback chain, try load balancing
        if @load_balancing_enabled
          next_model = select_model_by_load_balancing(current_provider)
          if next_model
            success = set_current_model(next_model, reason, context)
            if success
              log_model_switch(current_model, next_model, reason, context)
              return next_model
            end
          end
        end

        # Last resort: try any available model
        next_model = find_any_available_model(current_provider)
        if next_model
          success = set_current_model(next_model, reason, context)
          if success
            log_model_switch(current_model, next_model, reason, context)
            return next_model
          end
        end

        # No models available
        log_no_models_available(current_provider, reason, context)
        nil
      end

      # Switch model for specific error type
      def switch_model_for_error(error_type, error_details = {})
        return nil unless @model_switching_enabled

        case error_type
        when "rate_limit"
          switch_model("rate_limit", error_details)
        when "model_unavailable"
          switch_model("model_unavailable", error_details)
        when "model_error"
          switch_model("model_error", error_details)
        when "timeout"
          switch_model("timeout", error_details)
        else
          switch_model("error", {error_type: error_type}.merge(error_details))
        end
      end

      # Switch model with retry logic
      def switch_model_with_retry(reason = "retry", max_retries = @max_retries)
        return nil unless @model_switching_enabled

        attempt_count = 0

        Aidp::Concurrency::Backoff.retry(
          max_attempts: max_retries,
          base: 0.5,
          strategy: :exponential,
          jitter: 0.2,
          on: [StandardError]
        ) do
          attempt_count += 1
          next_model = switch_model(reason, {retry_count: attempt_count - 1})

          if next_model
            return next_model
          else
            # Raise to trigger retry
            raise "Model switch failed on attempt #{attempt_count}"
          end
        end
      rescue Aidp::Concurrency::MaxAttemptsError
        # All retries exhausted
        nil
      end

      # Set current model with enhanced validation
      def set_current_model(model_name, reason = "manual_switch", context = {})
        return false unless model_available?(current_provider, model_name)
        return false unless is_model_healthy?(current_provider, model_name)
        return false if is_model_circuit_breaker_open?(current_provider, model_name)

        # Update model health
        update_model_health(current_provider, model_name, "switched_to")

        # Record model switch
        @model_history ||= []
        @model_history << {
          provider: current_provider,
          model: model_name,
          switched_at: Time.now,
          reason: reason,
          context: context,
          previous_model: @current_model
        }

        @current_model = model_name
        true
      end

      # Set current provider with enhanced validation
      def set_current_provider(provider_name, reason = "manual_switch", context = {})
        # Use provider_config for ConfigManager, provider_configured? for legacy Configuration
        config_exists = if @configuration.respond_to?(:provider_config)
          @configuration.provider_config(provider_name)
        else
          @configuration.provider_configured?(provider_name)
        end

        unless config_exists
          Aidp.logger.warn("provider_manager", "Provider not configured", provider: provider_name)
          return false
        end

        unless is_provider_healthy?(provider_name)
          Aidp.logger.warn("provider_manager", "Provider not healthy", provider: provider_name)
          return false
        end

        if is_provider_circuit_breaker_open?(provider_name)
          Aidp.logger.warn("provider_manager", "Provider circuit breaker open", provider: provider_name)
          return false
        end

        # Update provider health
        update_provider_health(provider_name, "switched_to")

        # Record provider switch
        @provider_history << {
          provider: provider_name,
          switched_at: Time.now,
          reason: reason,
          context: context,
          previous_provider: @current_provider
        }

        # Update sticky session if enabled
        update_sticky_session(provider_name) if context[:session_id]

        # Reset current model when switching providers
        @current_model = default_model(provider_name)

        @current_provider = provider_name
        Aidp.logger.info("provider_manager", "Provider activated", provider: provider_name, reason: reason)
        true
      end

      # Get available providers (not rate limited, healthy, and circuit breaker closed)
      def available_providers
        all_providers = configured_providers
        all_providers.select do |provider|
          !is_rate_limited?(provider) &&
            is_provider_healthy?(provider) &&
            !is_provider_circuit_breaker_open?(provider)
        end
      end

      # Get available models for a provider
      def available_models(provider_name)
        models = provider_models(provider_name)
        models.select do |model|
          model_available?(provider_name, model) &&
            is_model_healthy?(provider_name, model) &&
            !is_model_circuit_breaker_open?(provider_name, model)
        end
      end

      # Check if model is available
      def model_available?(provider_name, model_name)
        # Check if model is configured for provider
        return false unless model_configured?(provider_name, model_name)

        # Check if model is not rate limited
        !is_model_rate_limited?(provider_name, model_name)
      end

      # Check if model is configured for provider
      def model_configured?(provider_name, model_name)
        models = provider_models(provider_name)
        models.include?(model_name)
      end

      # Get models for a provider
      def provider_models(provider_name)
        @model_configs[provider_name] || []
      end

      # Get default model for provider
      def default_model(provider_name)
        models = provider_models(provider_name)
        return models.first if models.any?

        # Fallback to provider-specific defaults
        case provider_name
        when "claude"
          "claude-3-5-sonnet-20241022"
        when "gemini"
          "gemini-1.5-pro"
        when "cursor"
          "cursor-default"
        else
          "default"
        end
      end

      # Get fallback chain for a provider
      def fallback_chain(provider_name)
        @fallback_chains[provider_name] || build_default_fallback_chain(provider_name)
      end

      # Get fallback chain for models within a provider
      def model_fallback_chain(provider_name)
        @model_fallback_chains[provider_name] || build_default_model_fallback_chain(provider_name)
      end

      # Build default model fallback chain
      def build_default_model_fallback_chain(provider_name)
        models = provider_models(provider_name)
        @model_fallback_chains[provider_name] = models.dup
        models
      end

      # Find next healthy model in fallback chain
      def find_next_healthy_model(model_chain, current_model)
        current_index = model_chain.index(current_model) || -1

        # Start from next model in chain
        (current_index + 1...model_chain.size).each do |index|
          model = model_chain[index]
          if model_available?(current_provider, model)
            return model
          end
        end

        nil
      end

      # Find any available model for provider
      def find_any_available_model(provider_name)
        available_models = available_models(provider_name)
        return nil if available_models.empty?

        # Use weighted selection if weights are configured
        if @model_weights[provider_name]&.any?
          select_model_by_weight(provider_name, available_models)
        else
          # Simple round-robin selection
          available_models.first
        end
      end

      # Select model by load balancing
      def select_model_by_load_balancing(provider_name)
        available_models = available_models(provider_name)
        return nil if available_models.empty?

        # Calculate load for each model
        model_loads = available_models.map do |model|
          load = calculate_model_load(provider_name, model)
          [model, load]
        end

        # Select model with lowest load
        model_loads.min_by { |_, load| load }&.first
      end

      # Select model by weight
      def select_model_by_weight(provider_name, available_models)
        weights = @model_weights[provider_name] || {}
        total_weight = available_models.sum { |model| weights[model] || 1 }
        return available_models.first if total_weight == 0

        random_value = rand(total_weight)
        current_weight = 0

        available_models.each do |model|
          weight = weights[model] || 1
          current_weight += weight
          return model if random_value < current_weight
        end

        available_models.last
      end

      # Calculate model load
      def calculate_model_load(provider_name, model_name)
        metrics = model_metrics(provider_name, model_name)
        return 0 if metrics.empty?

        # Calculate load based on success rate, response time, and current usage
        success_rate = metrics[:successful_requests].to_f / [metrics[:total_requests], 1].max
        avg_response_time = metrics[:total_duration] / [metrics[:successful_requests], 1].max
        current_usage = calculate_model_current_usage(provider_name, model_name)

        # Load formula: higher is worse
        (1 - success_rate) * 100 + avg_response_time + current_usage
      end

      # Calculate current usage for model
      def calculate_model_current_usage(provider_name, model_name)
        metrics = model_metrics(provider_name, model_name)
        return 0 if metrics.empty?

        last_used = metrics[:last_used]
        return 0 unless last_used

        # Higher usage if used recently
        time_since_last_use = Time.now - last_used
        if time_since_last_use < 60 # Used within last minute
          10
        elsif time_since_last_use < 300 # Used within last 5 minutes
          5
        else
          0
        end
      end

      # Build default fallback chain
      def build_default_fallback_chain(provider_name)
        all_providers = configured_providers

        # Harness-defined explicit ordering has priority
        harness_fallbacks = if @configuration.respond_to?(:fallback_providers)
          Array(@configuration.fallback_providers).map(&:to_s)
        else
          []
        end

        # Construct ordered chain:
        # 1. current provider first
        # 2. harness fallback providers (excluding current and de-duplicated)
        # 3. any remaining configured providers not already listed
        ordered = [provider_name]
        ordered += harness_fallbacks.reject { |p| p == provider_name || ordered.include?(p) }
        ordered += all_providers.reject { |p| ordered.include?(p) }

        @fallback_chains[provider_name] = ordered
        ordered
      end

      # Find next healthy provider in fallback chain
      def find_next_healthy_provider(fallback_chain, current_provider)
        current_index = fallback_chain.index(current_provider) || -1

        # Start from next provider in chain
        (current_index + 1...fallback_chain.size).each do |index|
          provider = fallback_chain[index]
          if is_provider_available?(provider)
            return provider
          end
        end

        nil
      end

      # Find any available provider
      def find_any_available_provider
        provider_list = available_providers
        return nil if provider_list.empty?

        # Use weighted selection if weights are configured
        if @provider_weights.any?
          select_provider_by_weight(provider_list)
        else
          # Simple round-robin selection
          provider_list.first
        end
      end

      # Select provider by load balancing
      def select_provider_by_load_balancing
        provider_list = available_providers
        return nil if provider_list.empty?

        # Calculate load for each provider
        provider_loads = provider_list.map do |provider|
          load = calculate_provider_load(provider)
          [provider, load]
        end

        # Select provider with lowest load
        provider_loads.min_by { |_, load| load }&.first
      end

      # Select provider by weight
      def select_provider_by_weight(available_providers)
        total_weight = available_providers.sum { |provider| @provider_weights[provider] || 1 }
        return available_providers.first if total_weight == 0

        random_value = rand(total_weight)
        current_weight = 0

        available_providers.each do |provider|
          weight = @provider_weights[provider] || 1
          current_weight += weight
          return provider if random_value < current_weight
        end

        available_providers.last
      end

      # Calculate provider load
      def calculate_provider_load(provider_name)
        provider_metrics = metrics(provider_name)
        return 0 if provider_metrics.empty?

        # Calculate load based on success rate, response time, and current usage
        success_rate = provider_metrics[:successful_requests].to_f / [provider_metrics[:total_requests], 1].max
        avg_response_time = provider_metrics[:total_duration] / [provider_metrics[:successful_requests], 1].max
        current_usage = calculate_current_usage(provider_name)

        # Load formula: higher is worse
        (1 - success_rate) * 100 + avg_response_time + current_usage
      end

      # Calculate current usage for provider
      def calculate_current_usage(provider_name)
        # Simple usage calculation based on recent activity
        provider_metrics = metrics(provider_name)
        return 0 if provider_metrics.empty?

        last_used = provider_metrics[:last_used]
        return 0 unless last_used

        # Higher usage if used recently
        time_since_last_use = Time.now - last_used
        if time_since_last_use < 60 # Used within last minute
          10
        elsif time_since_last_use < 300 # Used within last 5 minutes
          5
        else
          0
        end
      end

      # Check if provider is available (not rate limited, healthy, circuit breaker closed)
      def is_provider_available?(provider_name)
        cli_ok, _reason = provider_cli_available?(provider_name)
        return false unless cli_ok
        return false if is_rate_limited?(provider_name)
        return false unless is_provider_healthy?(provider_name)
        return false if is_provider_circuit_breaker_open?(provider_name)
        true
      end

      # Mark provider unhealthy (auth or generic) and optionally open circuit breaker
      def mark_provider_unhealthy(provider_name, reason: "manual", open_circuit: true)
        return unless @provider_health[provider_name]
        health = @provider_health[provider_name]
        health[:status] = (reason == "auth") ? "unhealthy_auth" : "unhealthy"
        health[:last_updated] = Time.now
        health[:unhealthy_reason] = reason
        if open_circuit
          health[:circuit_breaker_open] = true
          health[:circuit_breaker_opened_at] = Time.now
          log_circuit_breaker_event(provider_name, "opened")
        end
      end

      def mark_provider_auth_failure(provider_name)
        mark_provider_unhealthy(provider_name, reason: "auth", open_circuit: true)
      end

      # Mark provider unhealthy specifically due to failure exhaustion (non-auth)
      def mark_provider_failure_exhausted(provider_name)
        return unless @provider_health[provider_name]
        health = @provider_health[provider_name]
        # Don't override more critical states (auth or circuit already open)
        return if health[:unhealthy_reason] == "auth"
        mark_provider_unhealthy(provider_name, reason: "fail_exhausted", open_circuit: true)
      end

      # Check if model is rate limited
      def is_model_rate_limited?(provider_name, model_name)
        info = @model_rate_limit_info ||= {}
        model_key = "#{provider_name}:#{model_name}"
        rate_limit_info = info[model_key]
        return false unless rate_limit_info

        reset_time = rate_limit_info[:reset_time]
        reset_time && Time.now < reset_time
      end

      # Mark model as rate limited
      def mark_model_rate_limited(provider_name, model_name, reset_time = nil)
        @model_rate_limit_info ||= {}
        model_key = "#{provider_name}:#{model_name}"
        @model_rate_limit_info[model_key] = {
          rate_limited_at: Time.now,
          reset_time: reset_time || calculate_model_reset_time(provider_name, model_name),
          error_count: (@model_rate_limit_info[model_key]&.dig(:error_count) || 0) + 1
        }

        # Update model health
        update_model_health(provider_name, model_name, "rate_limited")

        # Switch to next model if current one is rate limited
        if provider_name == current_provider && model_name == current_model
          switch_model("rate_limit", {provider: provider_name, model: model_name})
        end
      end

      # Clear rate limit for model
      def clear_model_rate_limit(provider_name, model_name)
        @model_rate_limit_info ||= {}
        model_key = "#{provider_name}:#{model_name}"
        @model_rate_limit_info.delete(model_key)
      end

      # Check if model is healthy
      def is_model_healthy?(provider_name, model_name)
        health = @model_health[provider_name]&.dig(model_name)
        return true unless health # Default to healthy if no health info

        health[:status] == "healthy"
      end

      # Check if model circuit breaker is open
      def is_model_circuit_breaker_open?(provider_name, model_name)
        health = @model_health[provider_name]&.dig(model_name)
        return false unless health

        if health[:circuit_breaker_open]
          # Check if timeout has passed
          if health[:circuit_breaker_opened_at] &&
              Time.now - health[:circuit_breaker_opened_at] > @circuit_breaker_timeout
            # Reset circuit breaker
            reset_model_circuit_breaker(provider_name, model_name)
            return false
          end
          return true
        end

        false
      end

      # Update model health
      def update_model_health(provider_name, model_name, event, _details = {})
        @model_health[provider_name] ||= {}
        @model_health[provider_name][model_name] ||= {
          status: "healthy",
          last_updated: Time.now,
          error_count: 0,
          success_count: 0,
          circuit_breaker_open: false,
          circuit_breaker_opened_at: nil
        }

        health = @model_health[provider_name][model_name]
        health[:last_updated] = Time.now

        case event
        when "success"
          health[:success_count] += 1
          health[:error_count] = [health[:error_count] - 1, 0].max # Decay errors
          health[:status] = "healthy"

          # Reset circuit breaker on success
          if health[:circuit_breaker_open]
            reset_model_circuit_breaker(provider_name, model_name)
          end

        when "error"
          health[:error_count] += 1

          # Check if circuit breaker should open
          if health[:error_count] >= @circuit_breaker_threshold
            open_model_circuit_breaker(provider_name, model_name)
          end

          # Mark as unhealthy if too many errors
          if health[:error_count] > @circuit_breaker_threshold * 2
            health[:status] = "unhealthy"
          end

        when "switched_to"
          # Model was selected, update last used
          health[:last_used] = Time.now

        when "rate_limited"
          # Rate limiting doesn't affect health status
          health[:last_rate_limited] = Time.now
        end
      end

      # Open circuit breaker for model
      def open_model_circuit_breaker(provider_name, model_name)
        health = @model_health[provider_name]&.dig(model_name)
        return unless health

        health[:circuit_breaker_open] = true
        health[:circuit_breaker_opened_at] = Time.now
        health[:status] = "circuit_breaker_open"

        log_model_circuit_breaker_event(provider_name, model_name, "opened")
      end

      # Reset circuit breaker for model
      def reset_model_circuit_breaker(provider_name, model_name)
        health = @model_health[provider_name]&.dig(model_name)
        return unless health

        was_open = health[:circuit_breaker_open]
        health[:circuit_breaker_open] = false
        health[:circuit_breaker_opened_at] = nil
        health[:error_count] = 0
        health[:status] = "healthy"

        log_model_circuit_breaker_event(provider_name, model_name, "reset") if was_open
      end

      # Check if provider is rate limited
      def is_rate_limited?(provider_name)
        info = @rate_limit_info[provider_name]
        return false unless info

        reset_time = info[:reset_time]
        reset_time && Time.now < reset_time
      end

      # Check if provider is healthy
      def is_provider_healthy?(provider_name)
        health = @provider_health[provider_name]
        return true unless health # Default to healthy if no health info

        health[:status] == "healthy"
      end

      # Check if provider circuit breaker is open
      def is_provider_circuit_breaker_open?(provider_name)
        health = @provider_health[provider_name]
        return false unless health

        if health[:circuit_breaker_open]
          # Check if timeout has passed
          if health[:circuit_breaker_opened_at] &&
              Time.now - health[:circuit_breaker_opened_at] > @circuit_breaker_timeout
            # Reset circuit breaker
            reset_circuit_breaker(provider_name)
            return false
          end
          return true
        end

        false
      end

      # Update provider health
      def update_provider_health(provider_name, event, _details = {})
        @provider_health[provider_name] ||= {
          status: "healthy",
          last_updated: Time.now,
          error_count: 0,
          success_count: 0,
          circuit_breaker_open: false,
          circuit_breaker_opened_at: nil
        }

        health = @provider_health[provider_name]
        health[:last_updated] = Time.now

        case event
        when "success"
          health[:success_count] += 1
          health[:error_count] = [health[:error_count] - 1, 0].max # Decay errors
          health[:status] = "healthy"

          # Reset circuit breaker on success
          if health[:circuit_breaker_open]
            reset_circuit_breaker(provider_name)
          end

        when "error"
          health[:error_count] += 1

          # Check if circuit breaker should open
          if health[:error_count] >= @circuit_breaker_threshold
            open_circuit_breaker(provider_name)
          end

          # Mark as unhealthy if too many errors
          if health[:error_count] > @circuit_breaker_threshold * 2
            health[:status] = "unhealthy"
          end

        when "switched_to"
          # Provider was selected, update last used
          health[:last_used] = Time.now

        when "rate_limited"
          # Rate limiting doesn't affect health status
          health[:last_rate_limited] = Time.now
        end
      end

      # Open circuit breaker for provider
      def open_circuit_breaker(provider_name)
        health = @provider_health[provider_name]
        return unless health

        health[:circuit_breaker_open] = true
        health[:circuit_breaker_opened_at] = Time.now
        health[:status] = "circuit_breaker_open"

        log_circuit_breaker_event(provider_name, "opened")
      end

      # Reset circuit breaker for provider
      def reset_circuit_breaker(provider_name)
        health = @provider_health[provider_name]
        return unless health

        was_open = health[:circuit_breaker_open]
        health[:circuit_breaker_open] = false
        health[:circuit_breaker_opened_at] = nil
        health[:error_count] = 0
        health[:status] = "healthy"

        log_circuit_breaker_event(provider_name, "reset") if was_open
      end

      # Mark provider as rate limited
      def mark_rate_limited(provider_name, reset_time = nil)
        @rate_limit_info[provider_name] = {
          rate_limited_at: Time.now,
          reset_time: reset_time || calculate_reset_time(provider_name),
          error_count: (@rate_limit_info[provider_name]&.dig(:error_count) || 0) + 1
        }

        # Update provider health
        update_provider_health(provider_name, "rate_limited")

        # Switch to next provider if current one is rate limited
        if provider_name == current_provider
          switch_provider("rate_limit", {provider: provider_name})
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
      def record_metrics(provider_name, success:, duration:, tokens_used: nil, error: nil)
        @provider_metrics[provider_name] ||= {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          total_duration: 0.0,
          total_tokens: 0,
          last_used: nil,
          last_error: nil,
          last_error_time: nil
        }

        metrics = @provider_metrics[provider_name]
        metrics[:total_requests] += 1
        metrics[:last_used] = Time.now

        if success
          metrics[:successful_requests] += 1
          metrics[:total_duration] += duration
          metrics[:total_tokens] += tokens_used if tokens_used
          update_provider_health(provider_name, "success")
        else
          metrics[:failed_requests] += 1
          metrics[:last_error] = error&.message || "Unknown error"
          metrics[:last_error_time] = Time.now
          update_provider_health(provider_name, "error", {error: error})
        end
      end

      # Record model metrics
      def record_model_metrics(provider_name, model_name, success:, duration:, tokens_used: nil, error: nil)
        @model_metrics[provider_name] ||= {}
        @model_metrics[provider_name][model_name] ||= {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          total_duration: 0.0,
          total_tokens: 0,
          last_used: nil,
          last_error: nil,
          last_error_time: nil
        }

        metrics = @model_metrics[provider_name][model_name]
        metrics[:total_requests] += 1
        metrics[:last_used] = Time.now

        if success
          metrics[:successful_requests] += 1
          metrics[:total_duration] += duration
          metrics[:total_tokens] += tokens_used if tokens_used
          update_model_health(provider_name, model_name, "success")
        else
          metrics[:failed_requests] += 1
          metrics[:last_error] = error&.message || "Unknown error"
          metrics[:last_error_time] = Time.now
          update_model_health(provider_name, model_name, "error", {error: error})
        end
      end

      # Get model metrics
      def model_metrics(provider_name, model_name)
        @model_metrics[provider_name]&.dig(model_name) || {}
      end

      # Get all model metrics for provider
      def all_model_metrics(provider_name)
        @model_metrics[provider_name] || {}
      end

      # Get model history
      def model_history
        @model_history ||= []
        @model_history.dup
      end

      # Get provider metrics
      def metrics(provider_name)
        @provider_metrics[provider_name] || {}
      end

      # Get all provider metrics
      def all_metrics
        @provider_metrics.dup
      end

      # Determine whether a provider CLI/binary appears installed
      def provider_installed?(provider_name)
        return @unavailable_cache[provider_name] unless @unavailable_cache[provider_name].nil?
        installed = true
        begin
          case provider_name
          when "anthropic", "claude"
            # Prefer direct binary probe instead of Anthropic.available? (which uses which internally)
            path = begin
              Aidp::Util.which("claude")
            rescue
              nil
            end
            installed = !path.nil?
          when "cursor"
            require_relative "../providers/cursor"
            installed = Aidp::Providers::Cursor.available?
          end
        rescue LoadError => e
          log_rescue(e, component: "provider_manager", action: "check_provider_availability", fallback: false, provider: provider_name)
          installed = false
        end
        @unavailable_cache[provider_name] = installed
      end

      # Attempt to run a provider's CLI with --version (or no-op) to verify executable health
      def provider_cli_available?(provider_name)
        normalized = normalize_provider_name(provider_name)

        cache_key = "#{provider_name}:#{normalized}"
        cached = @binary_check_cache[cache_key]
        if cached && (Time.now - cached[:checked_at] < @binary_check_ttl)
          return [cached[:ok], cached[:reason]]
        end
        # Map normalized provider -> binary
        binary = case normalized
        when "claude" then "claude"
        when "cursor" then "cursor"
        when "gemini" then "gemini"
        when "macos" then nil # passthrough; no direct binary expected
        end
        unless binary
          @binary_check_cache[cache_key] = {ok: true, reason: nil, checked_at: Time.now}
          return [true, nil]
        end
        path = begin
          @binary_checker.which(binary)
        rescue => e
          log_rescue(e, component: "provider_manager", action: "locate_binary", fallback: nil, binary: binary)
          nil
        end
        unless path
          @binary_check_cache[cache_key] = {ok: false, reason: "binary_missing", checked_at: Time.now}
          return [false, "binary_missing"]
        end
        # Light command execution to ensure it responds quickly
        ok = true
        reason = nil
        begin
          # Use IO.popen to avoid shell injection and impose a short timeout
          r, w = IO.pipe
          pid = Process.spawn(binary, "--version", out: w, err: w)
          w.close
          # Wait for process to exit with timeout
          begin
            Aidp::Concurrency::Wait.for_process_exit(pid, timeout: 3, interval: 0.05)
          rescue Aidp::Concurrency::TimeoutError
            # Timeout -> kill process
            begin
              Process.kill("TERM", pid)
            rescue => e
              log_rescue(e, component: "provider_manager", action: "kill_timeout_process_term", fallback: nil, binary: binary, pid: pid)
              nil
            end

            # Brief wait for TERM to take effect
            begin
              Aidp::Concurrency::Wait.for_process_exit(pid, timeout: 0.1, interval: 0.02)
            rescue Aidp::Concurrency::TimeoutError
              # TERM didn't work, use KILL
              begin
                Process.kill("KILL", pid)
              rescue => e
                log_rescue(e, component: "provider_manager", action: "kill_timeout_process_kill", fallback: nil, binary: binary, pid: pid)
                nil
              end
            end

            ok = false
            reason = "binary_timeout"
          end
          output = r.read.to_s
          r.close
          if ok && output.strip.empty?
            # Some CLIs require just calling without args; treat empty as still OK
            ok = true
          end
        rescue => e
          log_rescue(e, component: "provider_manager", action: "verify_binary_health", fallback: "binary_error", binary: binary)
          ok = false
          reason = e.class.name.downcase.include?("enoent") ? "binary_missing" : "binary_error"
        end
        @binary_check_cache[cache_key] = {ok: ok, reason: reason, checked_at: Time.now}
        [ok, reason]
      end

      # Summarize health and metrics for dashboard/CLI display
      def health_dashboard
        now = Time.now
        statuses = provider_health_status
        metrics = all_metrics
        configured = configured_providers
        rows_by_normalized = {}
        configured.each do |prov|
          # Temporarily hide macos provider until it's user-configurable
          next if prov == "macos"
          normalized = normalize_provider_name(prov)
          cli_ok_prefetch, cli_reason_prefetch = provider_cli_available?(prov)
          h = statuses[prov] || {}
          m = metrics[prov] || {}
          rl = @rate_limit_info[prov]
          reset_in = (rl && rl[:reset_time]) ? [(rl[:reset_time] - now).to_i, 0].max : nil
          cb_remaining = if h[:circuit_breaker_open] && h[:circuit_breaker_opened_at]
            elapsed = now - h[:circuit_breaker_opened_at]
            rem = @circuit_breaker_timeout - elapsed
            rem.positive? ? rem.to_i : 0
          end
          row = {
            provider: normalized,
            installed: provider_installed?(prov),
            status: h[:status] || (provider_installed?(prov) ? "unknown" : "uninstalled"),
            unhealthy_reason: h[:unhealthy_reason],
            available: false, # will set true below only if all checks pass
            circuit_breaker: h[:circuit_breaker_open] ? "open" : "closed",
            circuit_breaker_remaining: cb_remaining,
            rate_limited: !!rl,
            rate_limit_reset_in: reset_in,
            total_requests: m[:total_requests] || 0,
            failed_requests: m[:failed_requests] || 0,
            success_requests: m[:successful_requests] || 0,
            total_tokens: m[:total_tokens] || 0,
            last_used: m[:last_used]
          }
          # Incorporate CLI check outcome into reason/availability if failing
          unless cli_ok_prefetch
            row[:available] = false
            row[:unhealthy_reason] ||= cli_reason_prefetch
            row[:status] = "unhealthy" if row[:status] == "healthy" || row[:status] == "healthy_auth"
          end
          if cli_ok_prefetch && is_provider_available?(prov)
            row[:available] = true
          end
          if (existing = rows_by_normalized[normalized])
            # Merge metrics: sum counts/tokens, keep most severe status, earliest unhealthy reason if any
            existing[:total_requests] += row[:total_requests]
            existing[:failed_requests] += row[:failed_requests]
            existing[:success_requests] += row[:success_requests]
            existing[:total_tokens] += row[:total_tokens]
            # If either unavailable then mark unavailable
            existing[:available] &&= row[:available]
            # Prefer an unhealthy or circuit breaker status over healthy
            existing[:status] = merge_status_priority(existing[:status], row[:status])
            existing[:unhealthy_reason] ||= row[:unhealthy_reason]
            # Circuit breaker open takes precedence
            if row[:circuit_breaker] == "open"
              existing[:circuit_breaker] = "open"
              existing[:circuit_breaker_remaining] = [existing[:circuit_breaker_remaining].to_i, row[:circuit_breaker_remaining].to_i].max
            end
            # Rate limited if any underlying
            if row[:rate_limited]
              existing[:rate_limited] = true
              existing[:rate_limit_reset_in] = [existing[:rate_limit_reset_in].to_i, row[:rate_limit_reset_in].to_i].max
            end
            # Keep most recent last_used
            if row[:last_used] && (!existing[:last_used] || row[:last_used] > existing[:last_used])
              existing[:last_used] = row[:last_used]
            end
          else
            rows_by_normalized[normalized] = row
          end
        end
        rows_by_normalized.values
      end

      # Get provider history
      def provider_history
        @provider_history.dup
      end

      # Reset all provider state
      def reset
        @current_provider = nil
        @current_model = nil
        @provider_history.clear
        @rate_limit_info.clear
        @provider_metrics.clear
        @provider_health.clear
        @retry_counts.clear
        @sticky_sessions.clear
        @model_configs.clear
        @model_health.clear
        @model_metrics.clear
        @model_fallback_chains.clear
        @model_rate_limit_info&.clear
        @model_history&.clear
        initialize_fallback_chains
        initialize_provider_health
        initialize_model_configs
        initialize_model_health
      end

      # Get status summary
      def status
        {
          current_provider: current_provider,
          current_model: current_model,
          current_provider_model: current_provider_model,
          available_providers: available_providers,
          rate_limited_providers: @rate_limit_info.keys,
          unhealthy_providers: @provider_health.select { |_, health| health[:status] != "healthy" }.keys,
          circuit_breaker_open: @provider_health.select { |_, health| health[:circuit_breaker_open] }.keys,
          next_reset_time: next_reset_time,
          total_switches: @provider_history.size,
          load_balancing_enabled: @load_balancing_enabled,
          provider_weights: @provider_weights,
          model_switching_enabled: @model_switching_enabled,
          model_weights: @model_weights
        }
      end

      # Get detailed provider health status
      def provider_health_status
        @provider_health.transform_values do |health|
          {
            status: health[:status],
            error_count: health[:error_count],
            success_count: health[:success_count],
            circuit_breaker_open: health[:circuit_breaker_open],
            last_updated: health[:last_updated],
            last_used: health[:last_used],
            last_rate_limited: health[:last_rate_limited],
            circuit_breaker_opened_at: health[:circuit_breaker_opened_at],
            unhealthy_reason: health[:unhealthy_reason]
          }
        end
      end

      # Get detailed model health status
      def model_health_status(provider_name)
        @model_health[provider_name]&.transform_values do |health|
          {
            status: health[:status],
            error_count: health[:error_count],
            success_count: health[:success_count],
            circuit_breaker_open: health[:circuit_breaker_open],
            last_updated: health[:last_updated],
            last_used: health[:last_used],
            last_rate_limited: health[:last_rate_limited]
          }
        end || {}
      end

      # Get all model health status
      def all_model_health_status
        @model_health.transform_values do |provider_models|
          provider_models.transform_values do |health|
            {
              status: health[:status],
              error_count: health[:error_count],
              success_count: health[:success_count],
              circuit_breaker_open: health[:circuit_breaker_open],
              last_updated: health[:last_updated],
              last_used: health[:last_used],
              last_rate_limited: health[:last_rate_limited]
            }
          end
        end
      end

      # Configure provider weights for load balancing
      def configure_provider_weights(weights)
        @provider_weights = weights.dup
      end

      # Configure model weights for load balancing
      def configure_model_weights(provider_name, weights)
        @model_weights[provider_name] = weights.dup
      end

      # Enable/disable load balancing
      def set_load_balancing(enabled)
        @load_balancing_enabled = enabled
      end

      # Enable/disable model switching
      def set_model_switching(enabled)
        @model_switching_enabled = enabled
      end

      # Update sticky session
      def update_sticky_session(provider_name)
        @sticky_sessions[provider_name] = Time.now
      end

      # Get sticky session provider
      def sticky_session_provider(session_id)
        return nil unless session_id

        # Find provider with recent session activity
        recent_sessions = @sticky_sessions.select do |_, time|
          Time.now - time < @session_timeout
        end

        recent_sessions.max_by { |_, time| time }&.first
      end

      # Execute a prompt with a specific provider
      def execute_with_provider(provider_type, prompt, options = {})
        # Create provider factory instance
        provider_factory = ProviderFactory.new

        # Create provider instance
        provider = provider_factory.create_provider(provider_type, options)

        # Set current provider
        @current_provider = provider_type

        # Execute the prompt with the provider
        result = provider.send(prompt: prompt, session: nil)

        # Return structured result
        {
          status: "completed",
          provider: provider_type,
          output: result,
          metadata: {
            provider_type: provider_type,
            prompt_length: prompt.length,
            timestamp: Time.now.strftime("%Y-%m-%dT%H:%M:%S.%3N%z")
          }
        }
      rescue => e
        log_rescue(e, component: "provider_manager", action: "execute_with_provider", fallback: "error_result", provider: provider_type, prompt_length: prompt.length)
        # Return error result
        {
          status: "error",
          provider: provider_type,
          error: e.message,
          metadata: {
            provider_type: provider_type,
            error_class: e.class.name,
            timestamp: Time.now.strftime("%Y-%m-%dT%H:%M:%S.%3N%z")
          }
        }
      end

      private

      # Initialize fallback chains
      def initialize_fallback_chains
        @fallback_chains.clear
        all_providers = configured_providers

        all_providers.each do |provider|
          build_default_fallback_chain(provider)
        end
      end

      # Initialize provider health
      def initialize_provider_health
        @provider_health.clear
        all_providers = configured_providers

        all_providers.each do |provider|
          @provider_health[provider] = {
            status: "healthy",
            last_updated: Time.now,
            error_count: 0,
            success_count: 0,
            circuit_breaker_open: false,
            circuit_breaker_opened_at: nil
          }
        end
      end

      # Initialize model configurations
      def initialize_model_configs
        @model_configs.clear
        all_providers = configured_providers

        all_providers.each do |provider|
          @model_configs[provider] = @configuration.provider_models(provider)
        end
      end

      # Initialize model health
      def initialize_model_health
        @model_health.clear
        all_providers = configured_providers

        all_providers.each do |provider|
          @model_health[provider] = {}
          models = @configuration.provider_models(provider)

          models.each do |model|
            @model_health[provider][model] = {
              status: "healthy",
              last_updated: Time.now,
              error_count: 0,
              success_count: 0,
              circuit_breaker_open: false,
              circuit_breaker_opened_at: nil
            }
          end
        end
      end

      # Get default models for provider
      def default_models_for_provider(provider_name)
        case provider_name
        when "claude"
          ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        when "gemini"
          ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]
        when "cursor"
          ["cursor-default", "cursor-fast", "cursor-precise"]
        else
          ["default"]
        end
      end

      # Calculate retry delay with exponential backoff
      def calculate_retry_delay(retry_count)
        # Exponential backoff: 1s, 2s, 4s, 8s, etc.
        delay = 2**retry_count
        [delay, 60].min # Cap at 60 seconds
      end

      private

      # Normalize provider naming for display (hide legacy 'anthropic')
      def normalize_provider_name(name)
        return "claude" if name == "anthropic"
        name
      end

      # Status priority for merging duplicate normalized providers
      def merge_status_priority(a, b)
        order = {
          "circuit_breaker_open" => 5,
          "unhealthy_auth" => 4,
          "unhealthy" => 3,
          "unknown" => 2,
          "healthy" => 1,
          nil => 0
        }
        ((order[a] || 0) >= (order[b] || 0)) ? a : b
      end

      public

      # Log provider switch
      def log_provider_switch(from_provider, to_provider, reason, context)
        display_message("🔄 Provider switch: #{from_provider} → #{to_provider} (#{reason})", type: :info)
        if context.any?
          display_message("   Context: #{context.inspect}", type: :muted)
        end
      end

      # Log no providers available
      def log_no_providers_available(reason, context)
        display_message("❌ No providers available for switching (#{reason})", type: :error)
        display_message("   All providers are rate limited, unhealthy, or circuit breaker open", type: :warning)
        if context.any?
          display_message("   Context: #{context.inspect}", type: :muted)
        end
      end

      # Log circuit breaker event
      def log_circuit_breaker_event(provider_name, event)
        case event
        when "opened"
          display_message("🔴 Circuit breaker opened for provider: #{provider_name}", type: :error)
        when "reset"
          display_message("🟢 Circuit breaker reset for provider: #{provider_name}", type: :success)
        end
      end

      # Log model switch
      def log_model_switch(from_model, to_model, reason, context)
        display_message("🔄 Model switch: #{from_model} → #{to_model} (#{reason})", type: :info)
        if context.any?
          display_message("   Context: #{context.inspect}", type: :muted)
        end
      end

      # Log no models available
      def log_no_models_available(provider_name, reason, context)
        display_message("❌ No models available for provider #{provider_name} (#{reason})", type: :error)
        display_message("   All models are rate limited, unhealthy, or circuit breaker open", type: :warning)
        if context.any?
          display_message("   Context: #{context.inspect}", type: :muted)
        end
      end

      # Log model circuit breaker event
      def log_model_circuit_breaker_event(provider_name, model_name, event)
        case event
        when "opened"
          display_message("🔴 Circuit breaker opened for model: #{provider_name}:#{model_name}", type: :error)
        when "reset"
          display_message("🟢 Circuit breaker reset for model: #{provider_name}:#{model_name}", type: :success)
        end
      end

      def calculate_reset_time(_provider_name)
        # Default reset time calculation
        # Most providers reset rate limits every hour
        Time.now + (60 * 60)
      end

      def calculate_model_reset_time(_provider_name, _model_name)
        # Default reset time calculation for models
        # Most models reset rate limits every hour
        Time.now + (60 * 60)
      end
    end
  end
end
