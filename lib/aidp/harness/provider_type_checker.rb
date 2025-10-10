# frozen_string_literal: true

module Aidp
  module Harness
    # Shared module for provider type checking functionality
    # This eliminates duplication across ProviderConfig and ConfigManager
    module ProviderTypeChecker
      # Check if provider is usage-based (pay per token)
      def usage_based_provider?(provider_name_or_options = {}, options = {})
        # Handle both ConfigManager (provider_name, options) and ProviderConfig (options) signatures
        if provider_name_or_options.is_a?(String) || provider_name_or_options.is_a?(Symbol)
          provider_name = provider_name_or_options
          get_provider_type(provider_name, options) == "usage_based"
        else
          # ProviderConfig signature: usage_based_provider?(options)
          options = provider_name_or_options
          type(options) == "usage_based"
        end
      end

      # Check if provider is subscription-based (unlimited within limits)
      def subscription_provider?(provider_name_or_options = {}, options = {})
        if provider_name_or_options.is_a?(String) || provider_name_or_options.is_a?(Symbol)
          provider_name = provider_name_or_options
          get_provider_type(provider_name, options) == "subscription"
        else
          options = provider_name_or_options
          type(options) == "subscription"
        end
      end

      # Check if provider is passthrough (inherits billing from underlying service)
      def passthrough_provider?(provider_name_or_options = {}, options = {})
        if provider_name_or_options.is_a?(String) || provider_name_or_options.is_a?(Symbol)
          provider_name = provider_name_or_options
          get_provider_type(provider_name, options) == "passthrough"
        else
          options = provider_name_or_options
          type(options) == "passthrough"
        end
      end

      # Get provider type with fallback to subscription (ConfigManager signature)
      def get_provider_type(provider_name, options = {})
        provider_config = provider_config(provider_name, options)
        return "subscription" unless provider_config

        provider_config[:type] || provider_config["type"] || "subscription"
      end

      # Check if provider requires API key
      def requires_api_key?(provider_name_or_options = {}, options = {})
        usage_based_provider?(provider_name_or_options, options)
      end

      # Check if provider has underlying service (passthrough)
      def has_underlying_service?(provider_name_or_options = {}, options = {})
        return false unless passthrough_provider?(provider_name_or_options, options)

        if provider_name_or_options.is_a?(String) || provider_name_or_options.is_a?(Symbol)
          provider_name = provider_name_or_options
          provider_config = provider_config(provider_name, options)
        else
          options = provider_name_or_options
          provider_config = get_config(options)
        end

        underlying_service = provider_config[:underlying_service] || provider_config["underlying_service"]
        !underlying_service.nil? && !underlying_service.empty?
      end

      # Get underlying service name for passthrough providers
      def get_underlying_service(provider_name_or_options = {}, options = {})
        return nil unless passthrough_provider?(provider_name_or_options, options)

        if provider_name_or_options.is_a?(String) || provider_name_or_options.is_a?(Symbol)
          provider_name = provider_name_or_options
          provider_config = provider_config(provider_name, options)
        else
          options = provider_name_or_options
          provider_config = get_config(options)
        end

        provider_config[:underlying_service] || provider_config["underlying_service"]
      end
    end
  end
end
