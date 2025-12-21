# frozen_string_literal: true

module Aidp
  module Setup
    # ConfigManager-compatible wrapper for in-memory wizard configuration.
    #
    # This class provides the same interface as Harness::ConfigManager but
    # reads from the wizard's in-memory @config hash instead of from disk.
    # This enables ProviderFactory to work during the wizard before
    # the config file is written.
    #
    # @example Usage
    #   config_manager = InMemoryConfigManager.new(@config, project_dir)
    #   factory = ProviderFactory.new(config_manager)
    #
    class InMemoryConfigManager
      attr_reader :project_dir

      # Initialize with wizard's in-memory config hash
      #
      # @param config [Hash] The wizard's @config hash (symbolized keys)
      # @param project_dir [String] Project directory path
      def initialize(config, project_dir)
        @config = config || {}
        @project_dir = project_dir

        Aidp.log_debug("in_memory_config_manager", "initialized",
          providers: provider_names)
      end

      # Get complete configuration
      def config(_options = {})
        @config
      end

      # Get harness configuration
      def harness_config(_options = {})
        @config[:harness] || {}
      end

      # Get provider configuration
      def provider_config(provider_name, _options = {})
        providers = @config[:providers] || {}
        providers[provider_name.to_sym] || providers[provider_name.to_s]
      end

      # Get all provider configurations
      def all_providers(_options = {})
        @config[:providers] || {}
      end

      # Get configured provider names
      def provider_names(_options = {})
        providers = all_providers
        providers.keys.map(&:to_s)
      end

      # Get default provider
      def default_provider(_options = {})
        harness_config[:default_provider] || harness_config["default_provider"]
      end

      # Get fallback providers
      def fallback_providers(_options = {})
        fallbacks = harness_config[:fallback_providers] || harness_config["fallback_providers"] || []
        configured = provider_names
        fallbacks.select { |p| configured.include?(p.to_s) }
      end

      # Check if configuration is valid
      def config_valid?
        default_provider && provider_config(default_provider)
      end

      # Get validation errors (empty for in-memory config)
      def validation_errors
        []
      end

      # Get validation warnings (empty for in-memory config)
      def validation_warnings
        []
      end

      # Reload configuration (no-op for in-memory)
      def reload_config
        # No-op: in-memory config doesn't need reloading
      end

      # Get configuration summary
      def config_summary
        {
          providers: provider_names.size,
          default_provider: default_provider,
          fallback_providers: fallback_providers.size
        }
      end

      # Get provider type
      def provider_type(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return nil unless cfg
        cfg[:type] || cfg["type"]
      end

      # Check if provider is usage-based
      def usage_based_provider?(provider_name, options = {})
        provider_type(provider_name, options) == "usage_based"
      end

      # Check if provider is subscription-based
      def subscription_provider?(provider_name, options = {})
        provider_type(provider_name, options) == "subscription"
      end

      # Check if provider is passthrough
      def passthrough_provider?(provider_name, options = {})
        provider_type(provider_name, options) == "passthrough"
      end

      # Get provider models
      def provider_models(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return [] unless cfg
        models = cfg[:models] || cfg["models"] || []
        models.map(&:to_s)
      end

      # Get provider features
      def provider_features(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return {} unless cfg
        features = cfg[:features] || cfg["features"] || {}
        {
          file_upload: features[:file_upload] == true,
          code_generation: features[:code_generation] != false,
          analysis: features[:analysis] != false,
          vision: features[:vision] == true
        }
      end

      # Check if provider supports feature
      def provider_supports_feature?(provider_name, feature, options = {})
        features = provider_features(provider_name, options)
        features[feature.to_sym] == true
      end

      # Get provider priority
      def provider_priority(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return 1 unless cfg
        cfg[:priority] || cfg["priority"] || 1
      end

      # Get retry configuration
      def retry_config(_options = {})
        cfg = harness_config[:retry] || {}
        {
          enabled: cfg[:enabled] != false,
          max_attempts: cfg[:max_attempts] || 3,
          base_delay: cfg[:base_delay] || 1.0,
          max_delay: cfg[:max_delay] || 60.0,
          exponential_base: cfg[:exponential_base] || 2.0,
          jitter: cfg[:jitter] != false
        }
      end

      # Get circuit breaker configuration
      def circuit_breaker_config(_options = {})
        cfg = harness_config[:circuit_breaker] || {}
        {
          enabled: cfg[:enabled] != false,
          failure_threshold: cfg[:failure_threshold] || 5,
          timeout: cfg[:timeout] || 300,
          half_open_max_calls: cfg[:half_open_max_calls] || 3
        }
      end

      # Get rate limit configuration
      def rate_limit_config(_options = {})
        cfg = harness_config[:rate_limit] || {}
        {
          enabled: cfg[:enabled] != false,
          default_reset_time: cfg[:default_reset_time] || 3600,
          burst_limit: cfg[:burst_limit] || 10,
          sustained_limit: cfg[:sustained_limit] || 5
        }
      end

      # Get provider monitoring configuration
      def provider_monitoring_config(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return {} unless cfg
        monitoring = cfg[:monitoring] || cfg["monitoring"] || {}
        {
          enabled: monitoring[:enabled] != false,
          metrics_interval: monitoring[:metrics_interval] || 60
        }
      end

      # Get provider model weights
      def provider_model_weights(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return {} unless cfg
        weights = cfg[:model_weights] || cfg["model_weights"] || {}
        weights.transform_values { |w| [w.to_i, 1].max }
      end

      # Get provider max tokens
      def provider_max_tokens(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return nil unless cfg
        cfg[:max_tokens] || cfg["max_tokens"]
      end

      # Get provider default flags
      def provider_default_flags(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return [] unless cfg
        flags = cfg[:default_flags] || cfg["default_flags"] || []
        flags.map(&:to_s)
      end

      # Get provider auth configuration
      def provider_auth_config(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return {} unless cfg
        auth = cfg[:auth] || cfg["auth"] || {}
        {
          api_key_env: auth[:api_key_env] || auth["api_key_env"],
          api_key: auth[:api_key] || auth["api_key"]
        }
      end

      # Get provider endpoints
      def provider_endpoints(provider_name, _options = {})
        cfg = provider_config(provider_name)
        return {} unless cfg
        endpoints = cfg[:endpoints] || cfg["endpoints"] || {}
        {
          default: endpoints[:default] || endpoints["default"]
        }
      end
    end
  end
end
