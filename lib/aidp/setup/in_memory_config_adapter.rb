# frozen_string_literal: true

module Aidp
  module Setup
    # Adapter that wraps in-memory configuration from the wizard
    # to provide the same interface as Harness::Configuration.
    #
    # This enables AGD (AI-Generated Determinism) to work during
    # the interactive configuration wizard before the config file
    # is written to disk.
    #
    # @example Usage in wizard
    #   adapter = InMemoryConfigAdapter.new(@config, project_dir)
    #   factory = AIFilterFactory.new(adapter)
    #
    class InMemoryConfigAdapter
      attr_reader :project_dir

      # Initialize with wizard's in-memory config hash
      #
      # @param config [Hash] The wizard's @config hash (symbolized keys)
      # @param project_dir [String] Project directory path
      def initialize(config, project_dir)
        @config = config || {}
        @project_dir = project_dir

        Aidp.log_debug("in_memory_config_adapter", "initialized",
          providers: configured_providers,
          default_provider: default_provider)
      end

      # Get harness-specific configuration
      def harness_config
        config = @config[:harness] || {}
        Aidp.log_debug("in_memory_config_adapter", "harness_config_retrieved",
          keys: config.keys)
        config
      end

      # Get provider configuration
      def provider_config(provider_name)
        providers = @config[:providers] || {}
        config = providers[provider_name.to_sym] || providers[provider_name.to_s] || {}
        Aidp.log_debug("in_memory_config_adapter", "provider_config_retrieved",
          provider: provider_name, found: !config.empty?)
        config
      end

      # Get all configured providers
      def configured_providers
        providers = @config[:providers] || {}
        providers.keys.map(&:to_s)
      end

      # Get default provider
      def default_provider
        harness_config[:default_provider]
      end

      # Get fallback providers
      def fallback_providers
        Array(harness_config[:fallback_providers])
      end

      # Get provider type (usage_based, subscription, passthrough)
      def provider_type(provider_name)
        provider_config(provider_name)[:type] || "unknown"
      end

      # Get model family for a provider
      def model_family(provider_name)
        provider_config(provider_name)[:model_family] || "auto"
      end

      # Get thinking tiers configuration for a provider
      def provider_thinking_tiers(provider_name)
        cfg = provider_config(provider_name)
        cfg[:thinking_tiers] || cfg["thinking_tiers"] || {}
      end

      # Get models configured for a specific tier and provider
      def models_for_tier(tier, provider_name)
        unless provider_name
          Aidp.log_debug("in_memory_config_adapter", "models_for_tier_skipped",
            reason: "no_provider_name")
          return []
        end

        tier_config = provider_thinking_tiers(provider_name)[tier] ||
          provider_thinking_tiers(provider_name)[tier.to_sym]
        unless tier_config
          Aidp.log_debug("in_memory_config_adapter", "models_for_tier_not_found",
            tier: tier, provider: provider_name)
          return []
        end

        models = tier_config[:models] || tier_config["models"]
        result = models ? Array(models).map(&:to_s).compact : []
        Aidp.log_debug("in_memory_config_adapter", "models_for_tier_retrieved",
          tier: tier, provider: provider_name, count: result.size)
        result
      end

      # Get all configured tiers for a provider
      def configured_tiers(provider_name)
        provider_thinking_tiers(provider_name).keys.map(&:to_s)
      end

      # Check if provider switching for tier is allowed
      def allow_provider_switch_for_tier?
        thinking_config[:allow_provider_switch] != false
      end

      # Get default thinking tier
      def default_tier
        thinking_config[:default_tier] || "mini"
      end

      # Get maximum thinking tier
      def max_tier
        thinking_config[:max_tier] || "pro"
      end

      # Get thinking configuration
      def thinking_config
        @config[:thinking] || default_thinking_config
      end

      # Get tier override for a skill or template
      def tier_override_for(key)
        thinking_overrides[key] || thinking_overrides[key.to_sym]
      end

      # Get thinking tier overrides
      def thinking_overrides
        thinking_config[:overrides] || {}
      end

      # Get permission level for a tier
      def permission_for_tier(tier)
        permissions = thinking_config[:permissions_by_tier] || {}
        permissions[tier] || permissions[tier.to_sym] || "tools"
      end

      # Get escalation configuration
      def escalation_config
        thinking_config[:escalation] || default_escalation_config
      end

      # Get fail attempts threshold for escalation
      def escalation_fail_attempts
        escalation_config[:on_fail_attempts] || 2
      end

      # Get complexity threshold configuration for escalation
      def escalation_complexity_threshold
        escalation_config[:on_complexity_threshold] || {}
      end

      # Issue #375: Get maximum tier for autonomous contexts (watch mode, work loops)
      def autonomous_max_tier
        thinking_config[:autonomous_max_tier] || default_thinking_config[:autonomous_max_tier]
      end

      # Issue #375: Get escalation configuration for autonomous contexts
      def autonomous_escalation_config
        thinking_config[:autonomous_escalation] || default_autonomous_escalation_config
      end

      # Issue #375: Minimum attempts per model before trying next model in tier
      def min_attempts_per_model
        autonomous_escalation_config[:min_attempts_per_model] || 2
      end

      # Issue #375: Minimum total attempts across all models before tier escalation
      def min_total_attempts_before_escalation
        autonomous_escalation_config[:min_total_attempts] || 10
      end

      # Issue #375: Whether to retry failed models after exhausting untested models
      def retry_failed_models?
        autonomous_escalation_config[:retry_failed_models] != false
      end

      # Get provider models configuration
      def provider_models(provider_name)
        provider_config(provider_name)[:models] || []
      end

      # Get default flags for a provider
      def default_flags(provider_name)
        provider_config(provider_name)[:default_flags] || []
      end

      # Get maximum tokens for a provider
      def max_tokens(provider_name)
        provider_config(provider_name)[:max_tokens]
      end

      # Check if provider is configured
      def provider_configured?(provider_name)
        result = configured_providers.include?(provider_name.to_s)
        Aidp.log_debug("in_memory_config_adapter", "provider_configured_check",
          provider: provider_name, configured: result)
        result
      end

      # Get work loop configuration
      def work_loop_config
        harness_config[:work_loop] || {}
      end

      # Get output filtering configuration
      def output_filtering_config
        work_loop_config[:output_filtering] || {}
      end

      # Get filter definitions
      def filter_definitions
        output_filtering_config[:filter_definitions] || {}
      end

      # Get raw configuration
      def raw_config
        @config.dup
      end

      private

      def default_thinking_config
        {
          default_tier: "mini",
          max_tier: "pro",
          autonomous_max_tier: "standard",  # Issue #375: restrict autonomous operations
          allow_provider_switch: true,
          autonomous_escalation: default_autonomous_escalation_config
        }
      end

      def default_escalation_config
        {
          on_fail_attempts: 2,
          on_complexity_threshold: {}
        }
      end

      # Issue #375: Default autonomous escalation configuration
      def default_autonomous_escalation_config
        {
          min_attempts_per_model: 2,
          min_total_attempts: 10,
          retry_failed_models: true
        }
      end
    end
  end
end
