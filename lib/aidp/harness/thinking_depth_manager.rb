# frozen_string_literal: true

require_relative "capability_registry"
require_relative "configuration"

module Aidp
  module Harness
    # Manages thinking depth tier selection and escalation
    # Integrates with CapabilityRegistry and Configuration to select appropriate models
    class ThinkingDepthManager
      attr_reader :configuration, :registry

      def initialize(configuration, registry: nil, root_dir: nil)
        @configuration = configuration
        @registry = registry || CapabilityRegistry.new(root_dir: root_dir || configuration.instance_variable_get(:@project_dir))
        @current_tier = nil
        @session_max_tier = nil
        @tier_history = []
        @escalation_count = 0

        Aidp.log_debug("thinking_depth_manager", "Initialized",
          default_tier: default_tier,
          max_tier: max_tier)
      end

      # Get current tier (defaults to config default_tier if not set)
      def current_tier
        @current_tier || default_tier
      end

      # Set current tier (validates against max_tier)
      def current_tier=(tier)
        validate_tier!(tier)
        old_tier = current_tier
        @current_tier = enforce_max_tier(tier)

        if @current_tier != tier
          Aidp.log_warn("thinking_depth_manager", "Tier capped at max",
            requested: tier,
            applied: @current_tier,
            max: max_tier)
        end

        if @current_tier != old_tier
          log_tier_change(old_tier, @current_tier, "manual_set")
        end
      end

      # Get maximum allowed tier (respects session override)
      def max_tier
        @session_max_tier || configuration.max_tier
      end

      # Set maximum tier for this session (temporary override)
      def max_tier=(tier)
        validate_tier!(tier)
        old_max = max_tier
        @session_max_tier = tier

        # If current tier exceeds new max, cap it
        if @registry.compare_tiers(current_tier, tier) > 0
          self.current_tier = tier
        end

        Aidp.log_info("thinking_depth_manager", "Max tier updated",
          old: old_max,
          new: tier,
          current: current_tier)
      end

      # Get default tier from configuration
      def default_tier
        configuration.default_tier
      end

      # Reset to default tier
      def reset_to_default
        old_tier = current_tier
        @current_tier = nil
        @session_max_tier = nil
        @escalation_count = 0

        Aidp.log_info("thinking_depth_manager", "Reset to default",
          old: old_tier,
          new: current_tier)

        current_tier
      end

      # Check if we can escalate to next tier
      def can_escalate?
        next_tier = @registry.next_tier(current_tier)
        return false unless next_tier

        @registry.compare_tiers(next_tier, max_tier) <= 0
      end

      # Escalate to next higher tier
      # Returns new tier or nil if already at max
      def escalate_tier(reason: nil)
        unless can_escalate?
          Aidp.log_warn("thinking_depth_manager", "Cannot escalate",
            current: current_tier,
            max: max_tier,
            reason: reason)
          return nil
        end

        old_tier = current_tier
        new_tier = @registry.next_tier(current_tier)
        @current_tier = new_tier
        @escalation_count += 1

        log_tier_change(old_tier, new_tier, reason || "escalation")
        Aidp.log_info("thinking_depth_manager", "Escalated tier",
          from: old_tier,
          to: new_tier,
          reason: reason,
          count: @escalation_count)

        new_tier
      end

      # De-escalate to next lower tier
      # Returns new tier or nil if already at minimum
      def de_escalate_tier(reason: nil)
        prev_tier = @registry.previous_tier(current_tier)
        unless prev_tier
          Aidp.log_debug("thinking_depth_manager", "Cannot de-escalate",
            current: current_tier)
          return nil
        end

        old_tier = current_tier
        @current_tier = prev_tier
        @escalation_count = [@escalation_count - 1, 0].max

        log_tier_change(old_tier, prev_tier, reason || "de-escalation")
        Aidp.log_info("thinking_depth_manager", "De-escalated tier",
          from: old_tier,
          to: prev_tier,
          reason: reason)

        prev_tier
      end

      # Select best model for current tier and provider
      # Returns [provider_name, model_name, model_data] or nil
      def select_model_for_tier(tier = nil, provider: nil)
        tier ||= current_tier
        validate_tier!(tier)

        # If provider specified, try to find model for that provider
        if provider
          model_name, model_data = @registry.best_model_for_tier(tier, provider)
          if model_name
            Aidp.log_debug("thinking_depth_manager", "Selected model",
              tier: tier,
              provider: provider,
              model: model_name)
            return [provider, model_name, model_data]
          end

          # If provider doesn't support tier and switching allowed, try others
          unless configuration.allow_provider_switch_for_tier?
            Aidp.log_warn("thinking_depth_manager", "Provider lacks tier, switching disabled",
              tier: tier,
              provider: provider)
            return nil
          end
        end

        # Try all providers
        providers_to_try = provider ? [@registry.provider_names - [provider]].flatten : @registry.provider_names

        providers_to_try.each do |prov_name|
          model_name, model_data = @registry.best_model_for_tier(tier, prov_name)
          if model_name
            Aidp.log_info("thinking_depth_manager", "Selected model from alternate provider",
              tier: tier,
              original_provider: provider,
              selected_provider: prov_name,
              model: model_name)
            return [prov_name, model_name, model_data]
          end
        end

        # Enhanced error message with discovery hints
        display_enhanced_tier_error(tier, provider)

        Aidp.log_error("thinking_depth_manager", "No model found for tier",
          tier: tier,
          provider: provider)
        nil
      end

      # Get tier for a specific model
      def tier_for_model(provider, model)
        @registry.tier_for_model(provider, model)
      end

      # Get information about a specific tier
      def tier_info(tier)
        validate_tier!(tier)

        {
          tier: tier,
          priority: @registry.tier_priority(tier),
          next_tier: @registry.next_tier(tier),
          previous_tier: @registry.previous_tier(tier),
          available_models: @registry.models_by_tier(tier),
          at_max: tier == max_tier,
          at_min: @registry.previous_tier(tier).nil?,
          can_escalate: can_escalate_to?(tier)
        }
      end

      # Get tier recommendation based on complexity score (0.0-1.0)
      def recommend_tier_for_complexity(complexity_score)
        tier = @registry.recommend_tier_for_complexity(complexity_score)

        # Cap at max_tier
        if @registry.compare_tiers(tier, max_tier) > 0
          Aidp.log_debug("thinking_depth_manager", "Recommended tier capped",
            recommended: tier,
            complexity: complexity_score,
            capped_to: max_tier)
          return max_tier
        end

        Aidp.log_debug("thinking_depth_manager", "Recommended tier",
          tier: tier,
          complexity: complexity_score)
        tier
      end

      # Check if tier override exists for skill/template
      def tier_override_for(key)
        override = configuration.tier_override_for(key)
        return nil unless override

        validate_tier!(override)

        # Cap at max_tier
        if @registry.compare_tiers(override, max_tier) > 0
          Aidp.log_warn("thinking_depth_manager", "Override tier exceeds max",
            key: key,
            override: override,
            max: max_tier)
          return max_tier
        end

        override
      end

      # Get permission level for current tier
      def permission_for_current_tier
        configuration.permission_for_tier(current_tier)
      end

      # Get escalation attempt count
      attr_reader :escalation_count

      # Get tier change history
      def tier_history
        @tier_history.dup
      end

      # Check if should escalate based on failure count
      def should_escalate_on_failures?(failure_count)
        threshold = configuration.escalation_fail_attempts
        failure_count >= threshold
      end

      # Check if should escalate based on complexity thresholds
      def should_escalate_on_complexity?(context)
        thresholds = configuration.escalation_complexity_threshold
        return false if thresholds.empty?

        files_changed = context[:files_changed] || 0
        modules_touched = context[:modules_touched] || 0

        exceeds_threshold = false

        if thresholds[:files_changed] && files_changed >= thresholds[:files_changed]
          exceeds_threshold = true
        end

        if thresholds[:modules_touched] && modules_touched >= thresholds[:modules_touched]
          exceeds_threshold = true
        end

        if exceeds_threshold
          Aidp.log_debug("thinking_depth_manager", "Complexity check",
            files: files_changed,
            modules: modules_touched,
            exceeds: exceeds_threshold)
        end

        exceeds_threshold
      end

      private

      def validate_tier!(tier)
        unless @registry.valid_tier?(tier)
          raise ArgumentError, "Invalid tier: #{tier}. Must be one of: #{CapabilityRegistry::VALID_TIERS.join(", ")}"
        end
      end

      def enforce_max_tier(tier)
        if @registry.compare_tiers(tier, max_tier) > 0
          max_tier
        else
          tier
        end
      end

      def can_escalate_to?(tier)
        @registry.compare_tiers(tier, max_tier) <= 0
      end

      def log_tier_change(old_tier, new_tier, reason)
        entry = {
          timestamp: Time.now,
          from: old_tier,
          to: new_tier,
          reason: reason,
          escalation_count: @escalation_count
        }
        @tier_history << entry

        # Keep history bounded
        @tier_history.shift if @tier_history.size > 100
      end

      # Display enhanced error message with discovery hints
      def display_enhanced_tier_error(tier, provider)
        return unless defined?(Aidp::MessageDisplay)

        # Check if there are discovered models in cache
        discovered_models = check_discovered_models(tier, provider)

        if discovered_models && discovered_models.any?
          display_tier_error_with_suggestions(tier, provider, discovered_models)
        else
          display_tier_error_with_discovery_hint(tier, provider)
        end
      end

      # Check cache for discovered models for this tier
      def check_discovered_models(tier, provider)
        require_relative "model_cache"
        require_relative "model_registry"

        cache = Aidp::Harness::ModelCache.new
        registry = Aidp::Harness::ModelRegistry.new

        # Get all cached models for the provider
        cached_models = cache.get_cached_models(provider)
        return nil unless cached_models&.any?

        # Filter to models for the requested tier
        tier_models = cached_models.select do |model|
          family = model[:family] || model["family"]
          model_info = registry.get_model_info(family)
          model_info && model_info["tier"] == tier.to_s
        end

        tier_models.any? ? tier_models : nil
      rescue StandardError => e
        Aidp.log_debug("thinking_depth_manager", "failed to check cached models",
          error: e.message)
        nil
      end

      # Display error with model suggestions from cache
      def display_tier_error_with_suggestions(tier, provider, models)
        Aidp.display_message("\n❌ No model configured for '#{tier}' tier", type: :error)
        Aidp.display_message("   Provider: #{provider}", type: :info) if provider

        Aidp.display_message("\n💡 Discovered models for this tier:", type: :highlight)
        models.first(3).each do |model|
          model_name = model[:name] || model["name"]
          Aidp.display_message("   - #{model_name}", type: :info)
        end

        Aidp.display_message("\n   Add to aidp.yml:", type: :highlight)
        Aidp.display_message("   providers:", type: :info)
        Aidp.display_message("     #{provider}:", type: :info)
        Aidp.display_message("       thinking:", type: :info)
        Aidp.display_message("         tiers:", type: :info)
        Aidp.display_message("           #{tier}:", type: :info)
        Aidp.display_message("             models:", type: :info)
        first_model = models.first[:name] || models.first["name"]
        Aidp.display_message("               - model: #{first_model}\n", type: :info)
      end

      # Display error with discovery hint
      def display_tier_error_with_discovery_hint(tier, provider)
        Aidp.display_message("\n❌ No model configured for '#{tier}' tier", type: :error)
        Aidp.display_message("   Provider: #{provider}", type: :info) if provider

        Aidp.display_message("\n💡 Suggested actions:", type: :highlight)
        Aidp.display_message("   1. Run 'aidp models discover' to find available models", type: :info)
        Aidp.display_message("   2. Run 'aidp models list --tier=#{tier}' to see models for this tier", type: :info)
        Aidp.display_message("   3. Run 'aidp models validate' to check your configuration\n", type: :info)
      end
    end
  end
end
