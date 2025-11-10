# frozen_string_literal: true

module Aidp
  module Providers
    # CapabilityRegistry maintains a queryable registry of provider capabilities
    # and features. This enables runtime feature detection and provider selection
    # based on required capabilities.
    #
    # @see https://github.com/viamin/aidp/issues/243
    class CapabilityRegistry
      # Standard capability keys
      CAPABILITY_KEYS = [
        :reasoning_tiers,      # Array of supported reasoning tiers (mini, standard, thinking, etc.)
        :context_window,       # Maximum context window size in tokens
        :supports_json_mode,   # Boolean: supports JSON mode output
        :supports_tool_use,    # Boolean: supports tool/function calling
        :supports_vision,      # Boolean: supports image/vision inputs
        :supports_file_upload, # Boolean: supports file uploads
        :streaming,            # Boolean: supports streaming responses
        :supports_mcp,         # Boolean: supports Model Context Protocol
        :max_tokens,           # Maximum tokens per response
        :supports_dangerous_mode # Boolean: supports elevated permissions mode
      ].freeze

      def initialize
        @capabilities = {}
        @providers = {}
      end

      # Register a provider and its capabilities
      # @param provider [Aidp::Providers::Base] provider instance
      # @return [void]
      def register(provider)
        provider_name = provider.name
        @providers[provider_name] = provider

        # Collect capabilities from provider
        caps = provider.capabilities.dup
        caps[:supports_mcp] = provider.supports_mcp?
        caps[:supports_dangerous_mode] = provider.supports_dangerous_mode?

        @capabilities[provider_name] = caps

        Aidp.log_debug("CapabilityRegistry", "registered provider",
          provider: provider_name,
          capabilities: caps.keys
        )
      end

      # Unregister a provider
      # @param provider_name [String] provider identifier
      # @return [void]
      def unregister(provider_name)
        @capabilities.delete(provider_name)
        @providers.delete(provider_name)
      end

      # Get capabilities for a specific provider
      # @param provider_name [String] provider identifier
      # @return [Hash, nil] capabilities hash or nil if not found
      def capabilities_for(provider_name)
        @capabilities[provider_name]
      end

      # Check if a provider has a specific capability
      # @param provider_name [String] provider identifier
      # @param capability [Symbol] capability key
      # @param value [Object, nil] optional value to match
      # @return [Boolean] true if provider has the capability
      def has_capability?(provider_name, capability, value = nil)
        caps = @capabilities[provider_name]
        return false unless caps

        if value.nil?
          # Just check if capability exists and is truthy
          caps.key?(capability) && caps[capability]
        else
          # Check if capability matches specific value
          caps[capability] == value
        end
      end

      # Find providers that match capability requirements
      # @param requirements [Hash] capability requirements
      # @return [Array<String>] array of matching provider names
      # @example
      #   registry.find_providers(supports_vision: true, min_context_window: 100_000)
      def find_providers(**requirements)
        matching = []

        @capabilities.each do |provider_name, caps|
          matches = requirements.all? do |key, required_value|
            case key
            when :min_context_window
              caps[:context_window] && caps[:context_window] >= required_value
            when :max_context_window
              caps[:context_window] && caps[:context_window] <= required_value
            when :reasoning_tier
              caps[:reasoning_tiers] && caps[:reasoning_tiers].include?(required_value)
            else
              # Exact match for boolean and other values
              caps[key] == required_value
            end
          end

          matching << provider_name if matches
        end

        matching
      end

      # Get all registered providers
      # @return [Array<String>] array of provider names
      def registered_providers
        @providers.keys
      end

      # Get detailed information about all registered providers
      # @return [Hash] provider information indexed by provider name
      def provider_info
        info = {}

        @providers.each do |provider_name, provider|
          caps = @capabilities[provider_name] || {}

          info[provider_name] = {
            display_name: provider.display_name,
            available: provider.available?,
            capabilities: caps,
            dangerous_mode_enabled: provider.dangerous_mode_enabled?,
            health_status: provider.health_status
          }
        end

        info
      end

      # Check capability compatibility between providers
      # @param provider_name1 [String] first provider
      # @param provider_name2 [String] second provider
      # @return [Hash] compatibility report
      def compatibility_report(provider_name1, provider_name2)
        caps1 = @capabilities[provider_name1]
        caps2 = @capabilities[provider_name2]

        return {error: "Provider not found"} unless caps1 && caps2

        common = {}
        differences = {}

        all_keys = (caps1.keys + caps2.keys).uniq

        all_keys.each do |key|
          val1 = caps1[key]
          val2 = caps2[key]

          if val1 == val2
            common[key] = val1
          else
            differences[key] = {provider_name1 => val1, provider_name2 => val2}
          end
        end

        {
          common_capabilities: common,
          differences: differences,
          compatibility_score: common.size.to_f / all_keys.size
        }
      end

      # Get capability statistics across all providers
      # @return [Hash] statistics about capability support
      def capability_statistics
        stats = {}

        CAPABILITY_KEYS.each do |key|
          stats[key] = {
            total_providers: @providers.size,
            supporting_providers: 0,
            providers: []
          }
        end

        @capabilities.each do |provider_name, caps|
          caps.each do |key, value|
            next unless stats.key?(key)

            if value.is_a?(TrueClass) || (value.is_a?(Array) && !value.empty?) || (value.is_a?(Integer) && value > 0)
              stats[key][:supporting_providers] += 1
              stats[key][:providers] << provider_name
            end
          end
        end

        stats
      end

      # Clear all registered providers
      # @return [void]
      def clear
        @capabilities.clear
        @providers.clear
      end
    end
  end
end
