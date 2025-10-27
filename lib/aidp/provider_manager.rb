# frozen_string_literal: true

require "tty-prompt"
require_relative "harness/provider_factory"

module Aidp
  class ProviderManager
    class << self
      def get_provider(provider_type, options = {})
        # Use harness factory if available
        if options[:use_harness] != false
          factory = get_harness_factory
          return factory.create_provider(provider_type, options) if factory
        end

        # Fallback to legacy method
        prompt = options[:prompt] || TTY::Prompt.new
        create_legacy_provider(provider_type, prompt: prompt)
      end

      def load_from_config(config = {}, options = {})
        provider_type = config["provider"] || "cursor"
        get_provider(provider_type, options)
      end

      # Get harness factory instance
      def get_harness_factory
        @harness_factory ||= begin
          require_relative "harness/config_manager"
          Aidp::Harness::ProviderFactory.new
        rescue LoadError
          nil
        end
      end

      # Create provider using harness configuration
      def create_harness_provider(provider_name, options = {})
        factory = get_harness_factory
        raise "Harness factory not available" unless factory

        factory.create_provider(provider_name, options)
      end

      # Get all configured providers
      def get_all_providers(options = {})
        factory = get_harness_factory
        return [] unless factory

        factory.create_all_providers(options)
      end

      # Get providers by priority
      def get_providers_by_priority(options = {})
        factory = get_harness_factory
        return [] unless factory

        factory.create_providers_by_priority(options)
      end

      # Get enabled providers
      def get_enabled_providers(options = {})
        factory = get_harness_factory
        return [] unless factory

        enabled_names = factory.get_enabled_providers(options)
        factory.create_providers(enabled_names, options)
      end

      # Check if provider is configured
      def provider_configured?(provider_name, options = {})
        factory = get_harness_factory
        return false unless factory

        factory.get_configured_providers(options).include?(provider_name.to_s)
      end

      # Check if provider is enabled
      def provider_enabled?(provider_name, options = {})
        factory = get_harness_factory
        return false unless factory

        factory.get_enabled_providers(options).include?(provider_name.to_s)
      end

      # Get provider capabilities
      def get_provider_capabilities(provider_name, options = {})
        factory = get_harness_factory
        return [] unless factory

        factory.get_provider_capabilities(provider_name, options)
      end

      # Check if provider supports feature
      def provider_supports_feature?(provider_name, feature, options = {})
        factory = get_harness_factory
        return false unless factory

        factory.provider_supports_feature?(provider_name, feature, options)
      end

      # Get provider models
      def get_provider_models(provider_name, options = {})
        factory = get_harness_factory
        return [] unless factory

        factory.get_provider_models(provider_name, options)
      end

      # Validate provider configuration
      def validate_provider_config(provider_name, options = {})
        factory = get_harness_factory
        return ["Harness factory not available"] unless factory

        factory.validate_provider_config(provider_name, options)
      end

      # Validate all provider configurations
      def validate_all_provider_configs(options = {})
        factory = get_harness_factory
        return {} unless factory

        factory.validate_all_provider_configs(options)
      end

      # Clear provider cache
      def clear_cache
        @harness_factory&.clear_cache
      end

      # Reload configuration
      def reload_config
        @harness_factory&.reload_config
      end

      private

      def create_legacy_provider(provider_type, prompt: TTY::Prompt.new)
        case provider_type
        when "cursor"
          Aidp::Providers::Cursor.new(prompt: prompt)
        when "anthropic", "claude"
          Aidp::Providers::Anthropic.new(prompt: prompt)
        when "gemini"
          Aidp::Providers::Gemini.new(prompt: prompt)
        when "github_copilot"
          Aidp::Providers::GithubCopilot.new(prompt: prompt)
        when "codex"
          Aidp::Providers::Codex.new(prompt: prompt)
        end
      end
    end
  end
end
