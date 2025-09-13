# frozen_string_literal: true

require_relative "config_manager"

module Aidp
  module Harness
    # Provider-specific configuration management
    class ProviderConfig
      def initialize(provider_name, config_manager = nil)
        @provider_name = provider_name.to_s
        @config_manager = config_manager || ConfigManager.new
        @provider_config = nil
        @harness_config = nil
        @cache_timestamp = nil
      end

      # Get complete provider configuration
      def get_config(options = {})
        return @provider_config if @provider_config && !options[:force_reload] && cache_valid?

        @provider_config = @config_manager.get_provider_config(@provider_name, options)
        @harness_config = @config_manager.get_harness_config(options)
        @cache_timestamp = Time.now

        @provider_config || {}
      end

      # Get provider type (api, package, byok)
      def get_type(options = {})
        config = get_config(options)
        config[:type] || config["type"] || "package"
      end

      # Check if provider is API type
      def api_provider?(options = {})
        get_type(options) == "api"
      end

      # Check if provider is package type
      def package_provider?(options = {})
        get_type(options) == "package"
      end

      # Check if provider is BYOK type
      def byok_provider?(options = {})
        get_type(options) == "byok"
      end

      # Get provider priority
      def get_priority(options = {})
        config = get_config(options)
        config[:priority] || config["priority"] || 1
      end

      # Get provider models
      def get_models(options = {})
        config = get_config(options)
        models = config[:models] || config["models"] || []
        models.map(&:to_s)
      end

      # Get default model
      def get_default_model(options = {})
        models = get_models(options)
        models.first
      end

      # Get model weights
      def get_model_weights(options = {})
        config = get_config(options)
        weights = config[:model_weights] || config["model_weights"] || {}
        weights.transform_values { |weight| [weight.to_i, 1].max }
      end

      # Get model configuration
      def get_model_config(model_name, options = {})
        config = get_config(options)
        models_config = config[:models_config] || config["models_config"] || {}
        model_config = models_config[model_name.to_sym] || models_config[model_name.to_s] || {}

        {
          flags: model_config[:flags] || model_config["flags"] || [],
          max_tokens: model_config[:max_tokens] || model_config["max_tokens"],
          timeout: model_config[:timeout] || model_config["timeout"],
          temperature: model_config[:temperature] || model_config["temperature"],
          max_retries: model_config[:max_retries] || model_config["max_retries"]
        }
      end

      # Get provider features
      def get_features(options = {})
        config = get_config(options)
        features = config[:features] || config["features"] || {}

        {
          file_upload: features[:file_upload] == true,
          code_generation: features[:code_generation] != false,
          analysis: features[:analysis] != false,
          vision: features[:vision] == true,
          streaming: features[:streaming] != false,
          function_calling: features[:function_calling] == true,
          tool_use: features[:tool_use] == true
        }
      end

      # Check if provider supports feature
      def supports_feature?(feature, options = {})
        features = get_features(options)
        features[feature.to_sym] == true
      end

      # Get provider capabilities
      def get_capabilities(options = {})
        features = get_features(options)
        capabilities = []

        capabilities << "file_upload" if features[:file_upload]
        capabilities << "code_generation" if features[:code_generation]
        capabilities << "analysis" if features[:analysis]
        capabilities << "vision" if features[:vision]
        capabilities << "streaming" if features[:streaming]
        capabilities << "function_calling" if features[:function_calling]
        capabilities << "tool_use" if features[:tool_use]

        capabilities
      end

      # Get provider max tokens
      def get_max_tokens(options = {})
        config = get_config(options)
        config[:max_tokens] || config["max_tokens"]
      end

      # Get provider timeout
      def get_timeout(options = {})
        config = get_config(options)
        config[:timeout] || config["timeout"] || 300
      end

      # Get provider default flags
      def get_default_flags(options = {})
        config = get_config(options)
        flags = config[:default_flags] || config["default_flags"] || []
        flags.map(&:to_s)
      end

      # Get model-specific flags
      def get_model_flags(model_name, options = {})
        model_config = get_model_config(model_name, options)
        model_config[:flags] || []
      end

      # Get combined flags (default + model-specific)
      def get_combined_flags(model_name = nil, options = {})
        default_flags = get_default_flags(options)
        model_flags = model_name ? get_model_flags(model_name, options) : []

        (default_flags + model_flags).uniq
      end

      # Get authentication configuration
      def get_auth_config(options = {})
        config = get_config(options)
        auth = config[:auth] || config["auth"] || {}

        {
          api_key_env: auth[:api_key_env] || auth["api_key_env"],
          api_key: auth[:api_key] || auth["api_key"],
          api_key_file: auth[:api_key_file] || auth["api_key_file"],
          username: auth[:username] || auth["username"],
          password: auth[:password] || auth["password"],
          token: auth[:token] || auth["token"],
          credentials_file: auth[:credentials_file] || auth["credentials_file"]
        }
      end

      # Get API key from environment or config
      def get_api_key(options = {})
        auth_config = get_auth_config(options)

        # Try environment variable first
        if auth_config[:api_key_env]
          api_key = ENV[auth_config[:api_key_env]]
          return api_key if api_key && !api_key.empty?
        end

        # Try direct config
        auth_config[:api_key]
      end

      # Get endpoints configuration
      def get_endpoints(options = {})
        config = get_config(options)
        endpoints = config[:endpoints] || config["endpoints"] || {}

        {
          default: endpoints[:default] || endpoints["default"],
          chat: endpoints[:chat] || endpoints["chat"],
          completion: endpoints[:completion] || endpoints["completion"],
          embedding: endpoints[:embedding] || endpoints["embedding"],
          vision: endpoints[:vision] || endpoints["vision"]
        }
      end

      # Get default endpoint
      def get_default_endpoint(options = {})
        endpoints = get_endpoints(options)
        endpoints[:default]
      end

      # Get monitoring configuration
      def get_monitoring_config(options = {})
        config = get_config(options)
        monitoring = config[:monitoring] || config["monitoring"] || {}

        {
          enabled: monitoring[:enabled] != false,
          metrics_interval: monitoring[:metrics_interval] || 60,
          health_check_interval: monitoring[:health_check_interval] || 300,
          log_level: monitoring[:log_level] || "info",
          log_requests: monitoring[:log_requests] != false,
          log_responses: monitoring[:log_responses] == true
        }
      end

      # Get rate limiting configuration
      def get_rate_limit_config(options = {})
        config = get_config(options)
        rate_limit = config[:rate_limit] || config["rate_limit"] || {}

        {
          enabled: rate_limit[:enabled] != false,
          requests_per_minute: rate_limit[:requests_per_minute] || 60,
          requests_per_hour: rate_limit[:requests_per_hour] || 1000,
          tokens_per_minute: rate_limit[:tokens_per_minute],
          tokens_per_hour: rate_limit[:tokens_per_hour],
          burst_limit: rate_limit[:burst_limit] || 10,
          reset_time: rate_limit[:reset_time] || 3600
        }
      end

      # Get retry configuration
      def get_retry_config(options = {})
        config = get_config(options)
        retry_config = config[:retry] || config["retry"] || {}

        {
          enabled: retry_config[:enabled] != false,
          max_attempts: retry_config[:max_attempts] || 3,
          base_delay: retry_config[:base_delay] || 1.0,
          max_delay: retry_config[:max_delay] || 60.0,
          exponential_base: retry_config[:exponential_base] || 2.0,
          jitter: retry_config[:jitter] != false,
          retry_on_rate_limit: retry_config[:retry_on_rate_limit] == true
        }
      end

      # Get circuit breaker configuration
      def get_circuit_breaker_config(options = {})
        config = get_config(options)
        cb_config = config[:circuit_breaker] || config["circuit_breaker"] || {}

        {
          enabled: cb_config[:enabled] != false,
          failure_threshold: cb_config[:failure_threshold] || 5,
          timeout: cb_config[:timeout] || 300,
          half_open_max_calls: cb_config[:half_open_max_calls] || 3,
          success_threshold: cb_config[:success_threshold] || 2
        }
      end

      # Get cost configuration
      def get_cost_config(options = {})
        config = get_config(options)
        cost = config[:cost] || config["cost"] || {}

        {
          input_cost_per_token: cost[:input_cost_per_token] || cost["input_cost_per_token"],
          output_cost_per_token: cost[:output_cost_per_token] || cost["output_cost_per_token"],
          fixed_cost_per_request: cost[:fixed_cost_per_request] || cost["fixed_cost_per_request"],
          currency: cost[:currency] || cost["currency"] || "USD"
        }
      end

      # Get provider-specific harness configuration
      def get_harness_config(options = {})
        config = get_config(options)
        harness_config = config[:harness] || config["harness"] || {}

        {
          enabled: harness_config[:enabled] != false,
          auto_switch_on_error: harness_config[:auto_switch_on_error] != false,
          auto_switch_on_rate_limit: harness_config[:auto_switch_on_rate_limit] != false,
          priority: harness_config[:priority] || get_priority(options),
          weight: harness_config[:weight] || 1,
          max_concurrent_requests: harness_config[:max_concurrent_requests] || 5
        }
      end

      # Get provider health check configuration
      def get_health_check_config(options = {})
        config = get_config(options)
        health_check = config[:health_check] || config["health_check"] || {}

        {
          enabled: health_check[:enabled] != false,
          interval: health_check[:interval] || 60,
          timeout: health_check[:timeout] || 10,
          failure_threshold: health_check[:failure_threshold] || 3,
          success_threshold: health_check[:success_threshold] || 2,
          check_url: health_check[:check_url] || health_check["check_url"],
          check_prompt: health_check[:check_prompt] || health_check["check_prompt"]
        }
      end

      # Get provider-specific environment variables
      def get_env_vars(options = {})
        config = get_config(options)
        env_vars = config[:env_vars] || config["env_vars"] || {}

        # Convert to string keys for environment variable access
        env_vars.transform_keys(&:to_s)
      end

      # Get provider-specific command line arguments
      def get_cmd_args(options = {})
        config = get_config(options)
        cmd_args = config[:cmd_args] || config["cmd_args"] || []
        cmd_args.map(&:to_s)
      end

      # Get provider-specific working directory
      def get_working_directory(options = {})
        config = get_config(options)
        config[:working_directory] || config["working_directory"] || Dir.pwd
      end

      # Get provider-specific log configuration
      def get_log_config(options = {})
        config = get_config(options)
        log_config = config[:log] || config["log"] || {}

        {
          enabled: log_config[:enabled] != false,
          level: log_config[:level] || "info",
          file: log_config[:file] || log_config["file"],
          max_size: log_config[:max_size] || 10_485_760, # 10MB
          max_files: log_config[:max_files] || 5,
          format: log_config[:format] || "json"
        }
      end

      # Get provider-specific cache configuration
      def get_cache_config(options = {})
        config = get_config(options)
        cache_config = config[:cache] || config["cache"] || {}

        {
          enabled: cache_config[:enabled] != false,
          ttl: cache_config[:ttl] || 3600,
          max_size: cache_config[:max_size] || 100,
          strategy: cache_config[:strategy] || "lru"
        }
      end

      # Get provider-specific security configuration
      def get_security_config(options = {})
        config = get_config(options)
        security = config[:security] || config["security"] || {}

        {
          ssl_verify: security[:ssl_verify] != false,
          allowed_hosts: security[:allowed_hosts] || security["allowed_hosts"] || [],
          blocked_hosts: security[:blocked_hosts] || security["blocked_hosts"] || [],
          timeout: security[:timeout] || 30,
          max_redirects: security[:max_redirects] || 5
        }
      end

      # Check if provider is configured
      def configured?(options = {})
        config = get_config(options)
        !config.empty?
      end

      # Check if provider is enabled
      def enabled?(options = {})
        harness_config = get_harness_config(options)
        harness_config[:enabled] != false
      end

      # Get provider status
      def get_status(options = {})
        return :not_configured unless configured?(options)
        return :disabled unless enabled?(options)

        :enabled
      end

      # Get provider summary
      def get_summary(options = {})
        config = get_config(options)
        return {} if config.empty?

        {
          name: @provider_name,
          type: get_type(options),
          priority: get_priority(options),
          models: get_models(options),
          features: get_capabilities(options),
          status: get_status(options),
          configured: configured?(options),
          enabled: enabled?(options)
        }
      end

      # Reload configuration
      def reload_config
        @provider_config = nil
        @harness_config = nil
        @cache_timestamp = nil
        @config_manager.reload_config
      end

      private

      def cache_valid?
        return false unless @cache_timestamp
        Time.now - @cache_timestamp < 300 # 5 minutes
      end
    end
  end
end
