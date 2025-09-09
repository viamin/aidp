# frozen_string_literal: true

require_relative "../config"

module Aidp
  module Harness
    # Handles loading and validation of harness configuration from aidp.yml
    class Configuration
      def initialize(project_dir)
        @project_dir = project_dir
        @config = Aidp::Config.load_harness_config(project_dir)
        validate_configuration!
      end

      # Get harness-specific configuration
      def harness_config
        @config[:harness]
      end

      # Get provider configuration
      def provider_config(provider_name)
        @config.dig(:providers, provider_name.to_sym) || {}
      end

      # Get all configured providers
      def configured_providers
        @config[:providers]&.keys&.map(&:to_s) || []
      end

      # Get default provider
      def default_provider
        harness_config[:default_provider]
      end

      # Get fallback providers
      def fallback_providers
        harness_config[:fallback_providers]
      end

      # Get maximum retries
      def max_retries
        harness_config[:max_retries]
      end

      # Check if restricted to non-BYOK providers
      def restrict_to_non_byok?
        harness_config[:restrict_to_non_byok]
      end

      # Get provider type (api, package, etc.)
      def provider_type(provider_name)
        provider_config(provider_name)[:type] || "unknown"
      end

      # Get maximum tokens for API providers
      def max_tokens(provider_name)
        provider_config(provider_name)[:max_tokens]
      end

      # Get default flags for a provider
      def default_flags(provider_name)
        provider_config(provider_name)[:default_flags] || []
      end

      # Check if provider is configured
      def provider_configured?(provider_name)
        configured_providers.include?(provider_name.to_s)
      end

      # Get available providers (filtered by restrictions)
      def available_providers
        providers = configured_providers

        if restrict_to_non_byok?
          providers = providers.select { |p| provider_type(p) != "byok" }
        end

        providers
      end

      # Get configuration path
      def config_path
        File.join(@project_dir, "aidp.yml")
      end

      # Check if configuration file exists
      def config_exists?
        Aidp::Config.config_exists?(@project_dir)
      end

      # Create example configuration
      def create_example_config
        Aidp::Config.create_example_config(@project_dir)
      end

      # Get raw configuration
      def raw_config
        @config.dup
      end

      private

      def validate_configuration!
        errors = Aidp::Config.validate_harness_config(@config)

        # Additional harness-specific validation
        unless harness_config[:default_provider]
          errors << "Default provider not specified"
        end

        unless configured_providers.include?(default_provider)
          errors << "Default provider '#{default_provider}' not configured"
        end

        # Validate fallback providers
        fallback_providers.each do |provider|
          unless configured_providers.include?(provider)
            errors << "Fallback provider '#{provider}' not configured"
          end
        end

        raise ConfigurationError, errors.join(", ") if errors.any?

        true
      end

      # Custom error class for configuration issues
      class ConfigurationError < StandardError; end
    end
  end
end
