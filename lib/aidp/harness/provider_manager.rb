# frozen_string_literal: true

module Aidp
  module Harness
    # Manages provider switching and fallback logic
    class ProviderManager
      include Aidp::OutputHelper
      def initialize(configuration)
        @configuration = configuration
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
        @current_model ||= get_default_model(current_provider)
      end

      # Get current provider and model combination
      def current_provider_model
        "#{current_provider}:#{current_model}"
      end

      # Get configured providers from configuration
      def configured_providers
        @configuration.configured_providers
      end

      # Switch to next available provider with sophisticated fallback logic
      def switch_provider(reason = "manual_switch", context = {})
        # Get fallback chain for current provider
        fallback_chain = get_fallback_chain(current_provider)

        # Find next healthy provider in fallback chain
        next_provider = find_next_healthy_provider(fallback_chain, current_provider)

        if next_provider
          success = set_current_provider(next_provider, reason, context)
          if success
            log_provider_switch(current_provider, next_provider, reason, context)
            return next_provider
          end
        end

        # If no provider in fallback chain, try load balancing
        if @load_balancing_enabled
          next_provider = select_provider_by_load_balancing
          if next_provider
            success = set_current_provider(next_provider, reason, context)
            if success
              log_provider_switch(current_provider, next_provider, reason, context)
              return next_provider
            end
          end
        end

        # Last resort: try any available provider
        next_provider = find_any_available_provider
        if next_provider
          success = set_current_provider(next_provider, reason, context)
          if success
            log_provider_switch(current_provider, next_provider, reason, context)
            return next_provider
          end
        end

        # No providers available
        log_no_providers_available(reason, context)
        nil
      end

      # Switch provider for specific error type
      def switch_provider_for_error(error_type, error_details = {})
        case error_type
        when "rate_limit"
          switch_provider("rate_limit", error_details)
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
        retry_count = 0

        while retry_count < max_retries
          next_provider = switch_provider(reason, {retry_count: retry_count})

          if next_provider
            return next_provider
          end

          retry_count += 1

          # Wait before retrying
          sleep(calculate_retry_delay(retry_count))
        end

        nil
      end

      # Switch to next available model within current provider
      def switch_model(reason = "manual_switch", context = {})
        return nil unless @model_switching_enabled

        # Get fallback chain for current provider's models
        model_chain = get_model_fallback_chain(current_provider)

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

        retry_count = 0

        while retry_count < max_retries
          next_model = switch_model(reason, {retry_count: retry_count})

          if next_model
            return next_model
          end

          retry_count += 1

          # Wait before retrying
          sleep(calculate_retry_delay(retry_count))
        end

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
        return false unless @configuration.provider_configured?(provider_name)
        return false unless is_provider_healthy?(provider_name)
        return false if is_provider_circuit_breaker_open?(provider_name)

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
        @current_model = get_default_model(provider_name)

        @current_provider = provider_name
        true
      end

      # Get available providers (not rate limited, healthy, and circuit breaker closed)
      def get_available_providers
        all_providers = @configuration.available_providers
        all_providers.select do |provider|
          !is_rate_limited?(provider) &&
            is_provider_healthy?(provider) &&
            !is_provider_circuit_breaker_open?(provider)
        end
      end

      # Get available models for a provider
      def get_available_models(provider_name)
        models = get_provider_models(provider_name)
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
        models = get_provider_models(provider_name)
        models.include?(model_name)
      end

      # Get models for a provider
      def get_provider_models(provider_name)
        @model_configs[provider_name] || []
      end

      # Get default model for provider
      def get_default_model(provider_name)
        models = get_provider_models(provider_name)
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
      def get_fallback_chain(provider_name)
        @fallback_chains[provider_name] || build_default_fallback_chain(provider_name)
      end

      # Get fallback chain for models within a provider
      def get_model_fallback_chain(provider_name)
        @model_fallback_chains[provider_name] || build_default_model_fallback_chain(provider_name)
      end

      # Build default model fallback chain
      def build_default_model_fallback_chain(provider_name)
        models = get_provider_models(provider_name)
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
        available_models = get_available_models(provider_name)
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
        available_models = get_available_models(provider_name)
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
        metrics = get_model_metrics(provider_name, model_name)
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
        metrics = get_model_metrics(provider_name, model_name)
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
        all_providers = @configuration.available_providers
        fallback_chain = all_providers.dup
        fallback_chain.delete(provider_name)
        fallback_chain.unshift(provider_name) # Put current provider first
        @fallback_chains[provider_name] = fallback_chain
        fallback_chain
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
        available_providers = get_available_providers
        return nil if available_providers.empty?

        # Use weighted selection if weights are configured
        if @provider_weights.any?
          select_provider_by_weight(available_providers)
        else
          # Simple round-robin selection
          available_providers.first
        end
      end

      # Select provider by load balancing
      def select_provider_by_load_balancing
        available_providers = get_available_providers
        return nil if available_providers.empty?

        # Calculate load for each provider
        provider_loads = available_providers.map do |provider|
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
        metrics = get_metrics(provider_name)
        return 0 if metrics.empty?

        # Calculate load based on success rate, response time, and current usage
        success_rate = metrics[:successful_requests].to_f / [metrics[:total_requests], 1].max
        avg_response_time = metrics[:total_duration] / [metrics[:successful_requests], 1].max
        current_usage = calculate_current_usage(provider_name)

        # Load formula: higher is worse
        (1 - success_rate) * 100 + avg_response_time + current_usage
      end

      # Calculate current usage for provider
      def calculate_current_usage(provider_name)
        # Simple usage calculation based on recent activity
        metrics = get_metrics(provider_name)
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

      # Check if provider is available (not rate limited, healthy, circuit breaker closed)
      def is_provider_available?(provider_name)
        !is_rate_limited?(provider_name) &&
          is_provider_healthy?(provider_name) &&
          !is_provider_circuit_breaker_open?(provider_name)
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
      def get_model_metrics(provider_name, model_name)
        @model_metrics[provider_name]&.dig(model_name) || {}
      end

      # Get all model metrics for provider
      def get_all_model_metrics(provider_name)
        @model_metrics[provider_name] || {}
      end

      # Get model history
      def model_history
        @model_history ||= []
        @model_history.dup
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
          available_providers: get_available_providers,
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
      def get_provider_health_status
        @provider_health.transform_values do |health|
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

      # Get detailed model health status
      def get_model_health_status(provider_name)
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
      def get_all_model_health_status
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
      def get_sticky_session_provider(session_id)
        return nil unless session_id

        # Find provider with recent session activity
        recent_sessions = @sticky_sessions.select do |_, time|
          Time.now - time < @session_timeout
        end

        recent_sessions.max_by { |_, time| time }&.first
      end

      private

      # Initialize fallback chains
      def initialize_fallback_chains
        @fallback_chains.clear
        all_providers = @configuration.available_providers

        all_providers.each do |provider|
          build_default_fallback_chain(provider)
        end
      end

      # Initialize provider health
      def initialize_provider_health
        @provider_health.clear
        all_providers = @configuration.available_providers

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
        all_providers = @configuration.available_providers

        all_providers.each do |provider|
          @model_configs[provider] = get_default_models_for_provider(provider)
        end
      end

      # Initialize model health
      def initialize_model_health
        @model_health.clear
        all_providers = @configuration.available_providers

        all_providers.each do |provider|
          @model_health[provider] = {}
          models = get_default_models_for_provider(provider)

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
      def get_default_models_for_provider(provider_name)
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

      # Log provider switch
      def log_provider_switch(from_provider, to_provider, reason, context)
        puts "🔄 Provider switch: #{from_provider} → #{to_provider} (#{reason})"
        if context.any?
          puts "   Context: #{context.inspect}"
        end
      end

      # Log no providers available
      def log_no_providers_available(reason, context)
        puts "❌ No providers available for switching (#{reason})"
        puts "   All providers are rate limited, unhealthy, or circuit breaker open"
        if context.any?
          puts "   Context: #{context.inspect}"
        end
      end

      # Log circuit breaker event
      def log_circuit_breaker_event(provider_name, event)
        case event
        when "opened"
          puts "🔴 Circuit breaker opened for provider: #{provider_name}"
        when "reset"
          puts "🟢 Circuit breaker reset for provider: #{provider_name}"
        end
      end

      # Log model switch
      def log_model_switch(from_model, to_model, reason, context)
        puts "🔄 Model switch: #{from_model} → #{to_model} (#{reason})"
        if context.any?
          puts "   Context: #{context.inspect}"
        end
      end

      # Log no models available
      def log_no_models_available(provider_name, reason, context)
        puts "❌ No models available for provider #{provider_name} (#{reason})"
        puts "   All models are rate limited, unhealthy, or circuit breaker open"
        if context.any?
          puts "   Context: #{context.inspect}"
        end
      end

      # Log model circuit breaker event
      def log_model_circuit_breaker_event(provider_name, model_name, event)
        case event
        when "opened"
          puts "🔴 Circuit breaker opened for model: #{provider_name}:#{model_name}"
        when "reset"
          puts "🟢 Circuit breaker reset for model: #{provider_name}:#{model_name}"
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
