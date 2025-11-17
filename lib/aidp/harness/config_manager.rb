# frozen_string_literal: true

require_relative "config_loader"
require_relative "config_schema"
require_relative "provider_type_checker"

module Aidp
  module Harness
    # Unified configuration manager for harness
    class ConfigManager
      include ProviderTypeChecker

      attr_reader :project_dir

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @loader = ConfigLoader.new(project_dir)
        @cache = {}
        @cache_timestamp = nil
      end

      # Get complete configuration
      def config(options = {})
        cache_key = "config_#{options.hash}"

        if cache_valid?(cache_key)
          return @cache[cache_key]
        end

        config = load_config_with_options(options)
        @cache[cache_key] = config if config
        config
      end

      # Get harness configuration
      def harness_config(options = {})
        config = config(options)
        return nil unless config

        config[:harness] || {}
      end

      # Get provider configuration
      def provider_config(provider_name, options = {})
        config = config(options)
        return nil unless config

        providers = config[:providers] || {}
        providers[provider_name.to_sym] || providers[provider_name.to_s]
      end

      # Get all provider configurations
      def all_providers(options = {})
        config = config(options)
        return {} unless config

        config[:providers] || {}
      end

      # Get configured provider names
      def provider_names(options = {})
        providers = all_providers(options)
        providers.keys.map(&:to_s)
      end

      # Get default provider
      def default_provider(options = {})
        harness_config = harness_config(options)
        harness_config[:default_provider] || harness_config["default_provider"]
      end

      # Get fallback providers
      def fallback_providers(options = {})
        harness_config = harness_config(options)
        fallback_providers = harness_config[:fallback_providers] || harness_config["fallback_providers"] || []

        # Ensure fallback providers are configured
        configured_providers = provider_names(options)
        fallback_providers.select { |provider| configured_providers.include?(provider) }
      end

      # Get provider weights
      def provider_weights(options = {})
        harness_config = harness_config(options)
        weights = harness_config[:provider_weights] || harness_config["provider_weights"] || {}

        # Normalize weights to ensure they're positive integers
        weights.transform_values { |weight| [weight.to_i, 1].max }
      end

      # Get retry configuration
      def retry_config(options = {})
        harness_config = harness_config(options)
        retry_config = harness_config[:retry] || harness_config["retry"] || {}

        {
          enabled: retry_config[:enabled] != false,
          max_attempts: retry_config[:max_attempts] || 3,
          base_delay: retry_config[:base_delay] || 1.0,
          max_delay: retry_config[:max_delay] || 60.0,
          exponential_base: retry_config[:exponential_base] || 2.0,
          jitter: retry_config[:jitter] != false
        }
      end

      # Get circuit breaker configuration
      def circuit_breaker_config(options = {})
        harness_config = harness_config(options)
        cb_config = harness_config[:circuit_breaker] || harness_config["circuit_breaker"] || {}

        {
          enabled: cb_config[:enabled] != false,
          failure_threshold: cb_config[:failure_threshold] || 5,
          timeout: cb_config[:timeout] || 300,
          half_open_max_calls: cb_config[:half_open_max_calls] || 3
        }
      end

      # Get rate limit configuration
      def rate_limit_config(options = {})
        harness_config = harness_config(options)
        rate_limit_config = harness_config[:rate_limit] || harness_config["rate_limit"] || {}

        {
          enabled: rate_limit_config[:enabled] != false,
          default_reset_time: rate_limit_config[:default_reset_time] || 3600,
          burst_limit: rate_limit_config[:burst_limit] || 10,
          sustained_limit: rate_limit_config[:sustained_limit] || 5
        }
      end

      # Get load balancing configuration
      def load_balancing_config(options = {})
        harness_config = harness_config(options)
        lb_config = harness_config[:load_balancing] || harness_config["load_balancing"] || {}

        {
          enabled: lb_config[:enabled] != false,
          strategy: lb_config[:strategy] || "weighted_round_robin",
          health_check_interval: lb_config[:health_check_interval] || 30,
          unhealthy_threshold: lb_config[:unhealthy_threshold] || 3
        }
      end

      # Get model switching configuration
      def model_switching_config(options = {})
        harness_config = harness_config(options)
        ms_config = harness_config[:model_switching] || harness_config["model_switching"] || {}

        {
          enabled: ms_config[:enabled] != false,
          auto_switch_on_error: ms_config[:auto_switch_on_error] != false,
          auto_switch_on_rate_limit: ms_config[:auto_switch_on_rate_limit] != false,
          fallback_strategy: ms_config[:fallback_strategy] || "sequential"
        }
      end

      # Get health check configuration
      def health_check_config(options = {})
        harness_config = harness_config(options)
        hc_config = harness_config[:health_check] || harness_config["health_check"] || {}

        {
          enabled: hc_config[:enabled] != false,
          interval: hc_config[:interval] || 60,
          timeout: hc_config[:timeout] || 10,
          failure_threshold: hc_config[:failure_threshold] || 3,
          success_threshold: hc_config[:success_threshold] || 2
        }
      end

      # Get metrics configuration
      def metrics_config(options = {})
        harness_config = harness_config(options)
        metrics_config = harness_config[:metrics] || harness_config["metrics"] || {}

        {
          enabled: metrics_config[:enabled] != false,
          retention_days: metrics_config[:retention_days] || 30,
          aggregation_interval: metrics_config[:aggregation_interval] || 300,
          export_interval: metrics_config[:export_interval] || 3600
        }
      end

      # Get session configuration
      def session_config(options = {})
        harness_config = harness_config(options)
        session_config = harness_config[:session] || harness_config["session"] || {}

        {
          enabled: session_config[:enabled] != false,
          timeout: session_config[:timeout] || 1800,
          sticky_sessions: session_config[:sticky_sessions] != false,
          session_affinity: session_config[:session_affinity] || "provider_model"
        }
      end

      # Get provider models
      def provider_models(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return [] unless provider_config

        models = provider_config[:models] || provider_config["models"] || []
        models.map(&:to_s)
      end

      # Get provider model weights
      def provider_model_weights(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        weights = provider_config[:model_weights] || provider_config["model_weights"] || {}
        weights.transform_values { |weight| [weight.to_i, 1].max }
      end

      # Get provider model configuration
      def provider_model_config(provider_name, model_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        models_config = provider_config[:models_config] || provider_config["models_config"] || {}
        model_config = models_config[model_name.to_sym] || models_config[model_name.to_s] || {}

        {
          flags: model_config[:flags] || model_config["flags"] || [],
          max_tokens: model_config[:max_tokens] || model_config["max_tokens"],
          timeout: model_config[:timeout] || model_config["timeout"]
        }
      end

      # Get provider features
      def provider_features(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        features = provider_config[:features] || provider_config["features"] || {}

        {
          file_upload: features[:file_upload] == true,
          code_generation: features[:code_generation] != false,
          analysis: features[:analysis] != false,
          vision: features[:vision] == true
        }
      end

      # Get provider monitoring configuration
      def provider_monitoring_config(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        monitoring = provider_config[:monitoring] || provider_config["monitoring"] || {}

        {
          enabled: monitoring[:enabled] != false,
          metrics_interval: monitoring[:metrics_interval] || 60
        }
      end

      # Check if provider supports feature
      def provider_supports_feature?(provider_name, feature, options = {})
        features = provider_features(provider_name, options)
        features[feature.to_sym] == true
      end

      # Get provider priority
      def provider_priority(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return 1 unless provider_config

        provider_config[:priority] || provider_config["priority"] || 1
      end

      # Get provider type
      def provider_type(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return nil unless provider_config

        provider_config[:type] || provider_config["type"]
      end

      # Provider type checking methods are now provided by ProviderTypeChecker module

      # Get provider max tokens
      def provider_max_tokens(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return nil unless provider_config

        provider_config[:max_tokens] || provider_config["max_tokens"]
      end

      # Get provider default flags
      def provider_default_flags(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return [] unless provider_config

        flags = provider_config[:default_flags] || provider_config["default_flags"] || []
        flags.map(&:to_s)
      end

      # Get provider auth configuration
      def provider_auth_config(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        auth = provider_config[:auth] || provider_config["auth"] || {}

        {
          api_key_env: auth[:api_key_env] || auth["api_key_env"],
          api_key: auth[:api_key] || auth["api_key"]
        }
      end

      # Get provider endpoints
      def provider_endpoints(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return {} unless provider_config

        endpoints = provider_config[:endpoints] || provider_config["endpoints"] || {}

        {
          default: endpoints[:default] || endpoints["default"]
        }
      end

      # Check if configuration is valid
      def config_valid?
        @loader.config_valid?
      end

      # Get validation errors
      def validation_errors
        @loader.validation_errors
      end

      # Get validation warnings
      def validation_warnings
        @loader.validation_warnings
      end

      # Reload configuration
      def reload_config
        @cache.clear
        @cache_timestamp = nil
        @loader.reload_config
      end

      # Get configuration summary
      def config_summary
        @loader.config_summary
      end

      private

      def load_config_with_options(options)
        # Apply different loading strategies based on options
        if options[:mode]
          @loader.mode_config(options[:mode], options[:force_reload])
        elsif options[:environment]
          @loader.environment_config(options[:environment], options[:force_reload])
        elsif options[:step]
          @loader.get_step_config(options[:step], options[:force_reload])
        elsif options[:features]
          @loader.config_with_features(options[:features], options[:force_reload])
        elsif options[:user]
          @loader.get_user_config(options[:user], options[:force_reload])
        elsif options[:time_based]
          @loader.time_based_config(options[:force_reload])
        elsif options[:overrides]
          @loader.config_with_overrides(options[:overrides])
        else
          @loader.load_config(options[:force_reload])
        end
      end

      def cache_valid?(cache_key)
        return false unless @cache[cache_key]
        return false unless @cache_timestamp

        # Cache is valid for 5 minutes
        Time.now - @cache_timestamp < 300
      end
    end
  end
end
