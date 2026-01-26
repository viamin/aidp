# frozen_string_literal: true

require "agent_harness"
require_relative "provider_config"

module Aidp
  module Harness
    # Factory for creating configured provider instances
    #
    # Uses AgentHarness providers for all provider instantiation.
    class ProviderFactory
      # Expose for testability
      attr_reader :provider_instances, :provider_configs

      # Provider class lookup - delegates to AgentHarness registry
      def self.provider_classes
        registry = AgentHarness::Providers::Registry.instance
        registry.all.each_with_object({}) do |name, hash|
          hash[name.to_s] = registry.get(name)
          # Add aliases
          hash["anthropic"] = registry.get(:claude) if name == :claude
        end
      end

      # For backwards compatibility - expose PROVIDER_CLASSES as a method
      PROVIDER_CLASSES = nil # Deprecated - use provider_classes method

      def initialize(config_manager = nil)
        @config_manager = config_manager || ConfigManager.new
        @provider_configs = {}
        @provider_instances = {}
      end

      # Create a provider instance with configuration
      def create_provider(provider_name, options = {})
        provider_name = provider_name.to_s
        cache_key = "#{provider_name}_#{options.hash}"

        # Return cached instance if available
        if @provider_instances[cache_key] && !options[:force_reload]
          return @provider_instances[cache_key]
        end

        # Get provider configuration
        provider_config = provider_config(provider_name)

        # Check if provider is configured and enabled
        unless provider_config.configured?(options)
          raise "Provider '#{provider_name}' is not configured"
        end

        unless provider_config.enabled?(options)
          raise "Provider '#{provider_name}' is disabled"
        end

        # Get provider class
        provider_class = provider_class(provider_name)
        raise "Unknown provider: #{provider_name}" unless provider_class

        # Create provider instance
        provider_instance = provider_class.new

        # Configure the provider instance
        configure_provider(provider_instance, provider_config, options)

        # Cache the instance
        @provider_instances[cache_key] = provider_instance

        provider_instance
      end

      # Create multiple provider instances
      def create_providers(provider_names, options = {})
        provider_names.map do |provider_name|
          create_provider(provider_name, options)
        end
      end

      # Create all configured providers
      def create_all_providers(options = {})
        configured_providers = @config_manager.provider_names(options)
        create_providers(configured_providers, options)
      end

      # Create providers by priority
      def create_providers_by_priority(options = {})
        all_providers = @config_manager.all_providers(options)

        # Sort by priority (lower number = higher priority)
        sorted_providers = all_providers.sort_by do |name, config|
          priority = config[:priority] || config["priority"] || 1
          [priority, name]
        end

        sorted_providers.map do |name, _config|
          create_provider(name, options)
        end
      end

      # Create providers by weight (for load balancing)
      def create_providers_by_weight(options = {})
        all_providers = @config_manager.all_providers(options)
        weighted_providers = []

        all_providers.each do |name, config|
          weight = config[:weight] || config["weight"] || 1
          weight.times { weighted_providers << name }
        end

        weighted_providers.shuffle.map do |name|
          create_provider(name, options)
        end
      end

      # Get provider configuration
      def provider_config(provider_name)
        @provider_configs[provider_name.to_s] ||= ProviderConfig.new(provider_name, @config_manager)
      end

      # Get provider class from AgentHarness registry
      def provider_class(provider_name)
        name = provider_name.to_s
        # Handle anthropic -> claude alias
        name = "claude" if name == "anthropic"
        AgentHarness::Providers::Registry.instance.get(name.to_sym)
      rescue AgentHarness::ConfigurationError
        nil
      end

      # Check if provider is supported
      def provider_supported?(provider_name)
        name = provider_name.to_s
        name = "claude" if name == "anthropic"
        AgentHarness::Providers::Registry.instance.registered?(name.to_sym)
      end

      # Get supported provider names
      def supported_providers
        AgentHarness::Providers::Registry.instance.all.map(&:to_s)
      end

      # Get configured provider names
      def configured_providers(options = {})
        @config_manager.provider_names(options)
      end

      # Get enabled provider names
      def enabled_providers(options = {})
        configured_providers = configured_providers(options)
        configured_providers.select do |provider_name|
          provider_config = provider_config(provider_name)
          provider_config.enabled?(options)
        end
      end

      # Get provider capabilities
      def provider_capabilities(provider_name, options = {})
        provider_config = provider_config(provider_name)
        provider_config.capabilities(options)
      end

      # Check if provider supports feature
      def provider_supports_feature?(provider_name, feature, options = {})
        provider_config = provider_config(provider_name)
        provider_config.supports_feature?(feature, options)
      end

      # Get provider models
      def provider_models(provider_name, options = {})
        provider_config = provider_config(provider_name)
        provider_config.models(options)
      end

      # Get provider summary
      def provider_summary(provider_name, options = {})
        provider_config = provider_config(provider_name)
        provider_config.summary(options)
      end

      # Get all provider summaries
      def all_provider_summaries(options = {})
        configured_providers = configured_providers(options)
        configured_providers.map do |provider_name|
          provider_summary(provider_name, options)
        end
      end

      # Validate provider configuration
      def validate_provider_config(provider_name, options = {})
        provider_config = provider_config(provider_name)
        errors = []

        # Check if provider is configured
        unless provider_config.configured?(options)
          errors << "Provider '#{provider_name}' is not configured"
          return errors
        end

        # Check if provider is supported
        unless provider_supported?(provider_name)
          errors << "Provider '#{provider_name}' is not supported"
        end

        # Check required configuration
        if provider_config.usage_based_provider?(options)
          api_key = provider_config.api_key(options)
          unless api_key && !api_key.empty?
            errors << "API key not configured for provider '#{provider_name}'"
          end
        end

        # Check models configuration
        models = provider_config.models(options)
        if models.empty?
          errors << "No models configured for provider '#{provider_name}'"
        end

        errors
      end

      # Validate all provider configurations
      def validate_all_provider_configs(options = {})
        configured_providers = configured_providers(options)
        all_errors = {}

        configured_providers.each do |provider_name|
          errors = validate_provider_config(provider_name, options)
          all_errors[provider_name] = errors unless errors.empty?
        end

        all_errors
      end

      # Clear provider cache
      def clear_cache
        @provider_instances.clear
        @provider_configs.clear
      end

      # Reload configuration
      def reload_config
        clear_cache
        @config_manager.reload_config
      end

      private

      def configure_provider(provider_instance, provider_config, options)
        # Set basic configuration
        config_hash = provider_config.config(options).dup

        # Add model to config if specified in options
        if options[:model]
          config_hash[:model] = options[:model]
        end

        if provider_instance.respond_to?(:configure)
          provider_instance.configure(config_hash)
        end

        # Set harness context if available
        if provider_instance.respond_to?(:set_harness_context)
          # This would be set by the harness runner
          # provider_instance.set_harness_context(harness_runner)
        end

        # Set monitoring configuration
        monitoring_config = provider_config.monitoring_config(options)
        if provider_instance.respond_to?(:set_monitoring_config)
          provider_instance.set_monitoring_config(monitoring_config)
        end

        # Set rate limiting configuration
        rate_limit_config = provider_config.rate_limit_config(options)
        if provider_instance.respond_to?(:set_rate_limit_config)
          provider_instance.set_rate_limit_config(rate_limit_config)
        end

        # Set retry configuration
        retry_config = provider_config.retry_config(options)
        if provider_instance.respond_to?(:set_retry_config)
          provider_instance.set_retry_config(retry_config)
        end

        # Set circuit breaker configuration
        circuit_breaker_config = provider_config.circuit_breaker_config(options)
        if provider_instance.respond_to?(:set_circuit_breaker_config)
          provider_instance.set_circuit_breaker_config(circuit_breaker_config)
        end

        # Set cost configuration
        cost_config = provider_config.cost_config(options)
        if provider_instance.respond_to?(:set_cost_config)
          provider_instance.set_cost_config(cost_config)
        end

        # Set health check configuration
        health_check_config = provider_config.health_check_config(options)
        if provider_instance.respond_to?(:set_health_check_config)
          provider_instance.set_health_check_config(health_check_config)
        end

        # Set log configuration
        log_config = provider_config.log_config(options)
        if provider_instance.respond_to?(:set_log_config)
          provider_instance.set_log_config(log_config)
        end

        # Set cache configuration
        cache_config = provider_config.cache_config(options)
        if provider_instance.respond_to?(:set_cache_config)
          provider_instance.set_cache_config(cache_config)
        end

        # Set security configuration
        security_config = provider_config.security_config(options)
        if provider_instance.respond_to?(:set_security_config)
          provider_instance.set_security_config(security_config)
        end

        provider_instance
      end
    end
  end
end
