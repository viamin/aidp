# frozen_string_literal: true

require_relative "capability_registry"
require_relative "configuration"
require_relative "../message_display"

module Aidp
  module Harness
    # Custom exception for model availability issues
    class NoModelAvailableError < StandardError
      attr_reader :tier, :provider

      def initialize(tier:, provider:)
        @tier = tier
        @provider = provider
        super("No model available for tier '#{tier}' with provider '#{provider}'. " \
              "Check your aidp.yml configuration or run 'aidp models discover' to find available models.")
      end
    end

    # Manages thinking depth tier selection and escalation
    # Integrates with CapabilityRegistry and Configuration to select appropriate models
    class ThinkingDepthManager
      include Aidp::MessageDisplay

      # Configuration constants for tier management
      MAX_TIER_HISTORY_SIZE = 100
      MAX_COMMENT_LENGTH = 2000
      MAX_REASONING_DISPLAY_LENGTH = 100
      DEFAULT_CONFIDENCE = 0.7

      attr_reader :configuration, :registry

      # Issue #375: Model attempt tracking for intelligent escalation
      # Structure: { tier => { provider => { model => { attempts: n, failed: bool } } } }
      attr_reader :model_attempts

      def initialize(configuration, registry: nil, root_dir: nil, autonomous_mode: false)
        @configuration = configuration
        @registry = registry || CapabilityRegistry.new(root_dir: root_dir || configuration.project_dir)
        @current_tier = nil
        @session_max_tier = nil
        @tier_history = []
        @escalation_count = 0

        # Issue #375: Track model attempts for intelligent escalation
        @model_attempts = {}
        @total_attempts_in_tier = 0
        @autonomous_mode = autonomous_mode
        @model_denylist = []  # Models to skip (e.g., denylisted by user)

        Aidp.log_debug("thinking_depth_manager", "Initialized",
          default_tier: default_tier,
          max_tier: max_tier,
          autonomous_max_tier: autonomous_max_tier,
          autonomous_mode: autonomous_mode)
      end

      # Enable autonomous mode (restricts max tier, enables model-level tracking)
      # Should be called when entering watch mode or work loops
      def enable_autonomous_mode
        @autonomous_mode = true
        reset_model_tracking

        # Cap current tier at autonomous max if needed
        if @registry.compare_tiers(current_tier, autonomous_max_tier) > 0
          old_tier = current_tier
          @current_tier = autonomous_max_tier
          log_tier_change(old_tier, @current_tier, "autonomous_mode_cap")

          Aidp.log_info("thinking_depth_manager", "Tier capped for autonomous mode",
            old: old_tier,
            new: @current_tier,
            autonomous_max: autonomous_max_tier)
        end

        Aidp.log_debug("thinking_depth_manager", "Autonomous mode enabled",
          max_tier: autonomous_max_tier)
      end

      # Disable autonomous mode (restores normal max tier)
      def disable_autonomous_mode
        @autonomous_mode = false
        Aidp.log_debug("thinking_depth_manager", "Autonomous mode disabled")
      end

      # Check if in autonomous mode
      def autonomous_mode?
        @autonomous_mode
      end

      # Get maximum tier for autonomous operations (issue #375)
      def autonomous_max_tier
        @session_autonomous_max_tier || configuration.autonomous_max_tier
      end

      # Set autonomous max tier for this session
      def autonomous_max_tier=(tier)
        validate_tier!(tier)
        @session_autonomous_max_tier = tier

        Aidp.log_info("thinking_depth_manager", "Autonomous max tier updated",
          new: tier)
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

      # Get the base maximum tier (from session override or config, ignoring autonomous mode)
      # This is the "raw" max tier before autonomous mode restrictions are applied
      def base_max_tier
        @session_max_tier || configuration.max_tier
      end

      # Get effective maximum tier (applies autonomous mode restrictions)
      # Issue #375: In autonomous mode, respects autonomous_max_tier
      def max_tier
        apply_autonomous_tier_cap(base_max_tier)
      end

      # Apply autonomous mode tier cap if active
      # Returns the tier capped at autonomous_max_tier when in autonomous mode
      # @param tier [String] The tier to potentially cap
      # @return [String] The effective tier (capped if in autonomous mode)
      def apply_autonomous_tier_cap(tier)
        return tier unless @autonomous_mode

        auto_max = autonomous_max_tier
        if @registry.compare_tiers(auto_max, tier) < 0
          auto_max
        else
          tier
        end
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

      # ============================================================
      # Issue #375: Intelligent model-level escalation for autonomous mode
      # ============================================================

      # Record an attempt with a specific model
      # @param provider [String] Provider name
      # @param model [String] Model name
      # @param success [Boolean] Whether the attempt succeeded
      def record_model_attempt(provider:, model:, success:)
        tier = current_tier
        @model_attempts[tier] ||= {}
        @model_attempts[tier][provider] ||= {}
        @model_attempts[tier][provider][model] ||= {attempts: 0, failed: false, last_attempt_at: nil}

        @model_attempts[tier][provider][model][:attempts] += 1
        @model_attempts[tier][provider][model][:last_attempt_at] = Time.now
        @model_attempts[tier][provider][model][:failed] = !success

        @total_attempts_in_tier += 1

        Aidp.log_debug("thinking_depth_manager", "Recorded model attempt",
          tier: tier,
          provider: provider,
          model: model,
          success: success,
          total_attempts: @model_attempts[tier][provider][model][:attempts],
          tier_total: @total_attempts_in_tier)
      end

      # Get attempts for a specific model
      def model_attempt_count(provider:, model:)
        tier = current_tier
        @model_attempts.dig(tier, provider, model, :attempts) || 0
      end

      # Check if a model has been marked as failed
      def model_failed?(provider:, model:)
        tier = current_tier
        @model_attempts.dig(tier, provider, model, :failed) || false
      end

      # Add model to denylist
      def denylist_model(model)
        @model_denylist << model unless @model_denylist.include?(model)
        Aidp.log_debug("thinking_depth_manager", "Model denylisted", model: model)
      end

      # Check if model is denylisted
      def model_denylisted?(model)
        @model_denylist.include?(model)
      end

      # Get all available models for current tier and provider
      # @param provider [String] Provider name
      # @return [Array<String>] List of model names
      def available_models_for_tier(provider:)
        tier = current_tier

        # First try user-configured models
        configured = configuration.models_for_tier(tier, provider)

        if configured.any?
          # Filter out denylisted models
          return configured.reject { |m| model_denylisted?(m) }
        end

        # Fall back to catalog models
        model_name, _data = @registry.best_model_for_tier(tier, provider)
        return [] unless model_name

        [model_name].reject { |m| model_denylisted?(m) }
      end

      # Check if any models are configured for the current tier and provider
      # @param provider [String] Provider name
      # @return [Boolean] true if models are available, false if none configured
      def models_configured_for_tier?(provider:)
        available_models_for_tier(provider: provider).any?
      end

      # Select the next model to try in current tier
      # Issue #375: Tries all models before escalating, respects min attempts per model
      # @param provider [String] Provider name
      # @return [String, nil] Model name or nil if should escalate
      def select_next_model(provider:)
        tier = current_tier
        models = available_models_for_tier(provider: provider)

        if models.empty?
          Aidp.log_debug("thinking_depth_manager", "No models configured for tier",
            tier: tier,
            provider: provider,
            reason: "no_models_configured")
          return nil
        end

        min_attempts = configuration.min_attempts_per_model

        # First pass: find any model with under-min-attempts (must reach min before retry)
        # This ensures every model gets minimum attempts before we consider retrying
        models.each do |model|
          attempts = model_attempt_count(provider: provider, model: model)
          if attempts < min_attempts
            Aidp.log_debug("thinking_depth_manager", "Selected under-min-attempts model",
              model: model,
              attempts: attempts,
              min_required: min_attempts)
            return model
          end
        end

        # Second pass: retry models that have met min attempts (if retry enabled)
        # Prioritize non-failed models first, then retry failed models
        if configuration.retry_failed_models?
          # First try non-failed models that have met min attempts
          models.each do |model|
            attempts = model_attempt_count(provider: provider, model: model)
            if attempts >= min_attempts && !model_failed?(provider: provider, model: model)
              Aidp.log_debug("thinking_depth_manager", "Selected non-failed model for retry",
                model: model,
                attempts: attempts)
              return model
            end
          end

          # Then retry previously failed models that have met min attempts
          models.each do |model|
            attempts = model_attempt_count(provider: provider, model: model)
            if attempts >= min_attempts && model_failed?(provider: provider, model: model)
              Aidp.log_debug("thinking_depth_manager", "Retrying previously failed model",
                model: model,
                attempts: attempts)
              return model
            end
          end
        end

        # All models exhausted in this tier
        Aidp.log_debug("thinking_depth_manager", "All models exhausted in tier",
          tier: tier,
          models_tried: models.size)
        nil
      end

      # Check if we should escalate tier based on model exhaustion
      # Issue #375: Requires minimum total attempts and trying all models first
      # @param provider [String] Provider name
      # @return [Hash] {should_escalate: bool, reason: string}
      def should_escalate_tier?(provider:)
        return {should_escalate: false, reason: "not_autonomous"} unless @autonomous_mode

        min_total = configuration.min_total_attempts_before_escalation
        min_per_model = configuration.min_attempts_per_model
        models = available_models_for_tier(provider: provider)

        # Check if we have any untested models
        untested_models = models.select do |model|
          model_attempt_count(provider: provider, model: model) < min_per_model
        end

        if untested_models.any?
          return {
            should_escalate: false,
            reason: "untested_models_remain",
            untested_count: untested_models.size
          }
        end

        # Check minimum total attempts
        # Relax if tier lacks sufficient models (each model needs min 2 tries)
        effective_min_total = [min_total, models.size * min_per_model].min

        if @total_attempts_in_tier < effective_min_total
          return {
            should_escalate: false,
            reason: "below_min_attempts",
            current: @total_attempts_in_tier,
            required: effective_min_total
          }
        end

        # Check if all models have failed
        # Only escalate if ALL models have failed - don't escalate just because min attempts reached
        # if some models are still succeeding
        all_failed = models.all? { |m| model_failed?(provider: provider, model: m) }

        if all_failed
          return {
            should_escalate: true,
            reason: "all_models_failed",
            total_attempts: @total_attempts_in_tier
          }
        end

        {should_escalate: false, reason: "continue_current_tier"}
      end

      # Escalate tier with intelligent model tracking (issue #375)
      # Only escalates if all models in current tier have been tried
      # @param provider [String] Provider name
      # @param reason [String, nil] Reason for escalation
      # @return [String, nil] New tier or nil if cannot escalate
      def escalate_tier_intelligent(provider:, reason: nil)
        escalation_check = should_escalate_tier?(provider: provider)

        unless escalation_check[:should_escalate]
          Aidp.log_debug("thinking_depth_manager", "Intelligent escalation blocked",
            reason: escalation_check[:reason],
            details: escalation_check)
          return nil
        end

        # Reset model tracking for new tier
        old_tier = current_tier
        new_tier = escalate_tier(reason: reason || escalation_check[:reason])

        if new_tier
          attempts_before_reset = @total_attempts_in_tier
          reset_model_tracking
          Aidp.log_info("thinking_depth_manager", "Intelligent tier escalation",
            from: old_tier,
            to: new_tier,
            reason: reason || escalation_check[:reason],
            total_attempts_in_old_tier: attempts_before_reset)
        end

        new_tier
      end

      # Reset model tracking (call when changing tiers or starting new work)
      # Clears current tier's data for consistency; preserves other tiers' history for analysis
      def reset_model_tracking
        tier = current_tier
        @model_attempts[tier] = {} if @model_attempts[tier]
        @total_attempts_in_tier = 0

        Aidp.log_debug("thinking_depth_manager", "Model tracking reset for tier", tier: tier)
      end

      # Get summary of model attempts in current tier
      def model_attempts_summary
        tier = current_tier
        tier_attempts = @model_attempts[tier] || {}

        summary = {
          tier: tier,
          total_attempts: @total_attempts_in_tier,
          providers: {}
        }

        tier_attempts.each do |provider, models|
          summary[:providers][provider] = models.map do |model, data|
            {
              model: model,
              attempts: data[:attempts],
              failed: data[:failed]
            }
          end
        end

        summary
      end

      # ============================================================
      # Issue #375: ZFC-based tier determination from issue comments
      # ============================================================

      # Determine appropriate tier from issue/PR comment content using ZFC
      # @param comment_text [String] The issue or PR comment text
      # @param provider_manager [ProviderManager] Provider manager for AI calls
      # @param labels [Array<String>] Optional labels on the issue/PR
      # @return [Hash] {tier: String, confidence: Float, reasoning: String}
      def determine_tier_from_comment(comment_text:, provider_manager:, labels: [])
        # Check for explicit tier labels first (fast path)
        tier_from_labels = extract_tier_from_labels(labels)
        if tier_from_labels
          tier = tier_from_labels
          reasoning = "Explicit tier label found: #{tier_from_labels}"

          # In autonomous mode, cap at autonomous_max_tier (same as ZFC path)
          if @autonomous_mode && @registry.compare_tiers(tier, autonomous_max_tier) > 0
            original_tier = tier
            tier = autonomous_max_tier
            reasoning += " (capped from #{original_tier} due to autonomous mode)"

            Aidp.log_debug("thinking_depth_manager", "Label tier capped for autonomous mode",
              original: original_tier,
              capped_to: tier)
          end

          return {
            tier: tier,
            confidence: 1.0,
            reasoning: reasoning,
            source: "label"
          }
        end

        # Use ZFC to determine tier from comment content
        determine_tier_via_zfc(comment_text, provider_manager)
      rescue => e
        Aidp.log_warn("thinking_depth_manager", "ZFC tier determination failed, using default",
          error: e.message,
          error_class: e.class.name)

        # Return conservative default on error
        {
          tier: "mini",
          confidence: 0.5,
          reasoning: "ZFC determination failed, using conservative default",
          source: "fallback"
        }
      end

      # Select best model for current tier and provider
      # Returns [provider_name, model_name, model_data] or nil
      def select_model_for_tier(tier = nil, provider: nil)
        tier ||= current_tier
        validate_tier!(tier)
        provider_has_no_tiers = provider && configuration.configured_tiers(provider).empty?
        provider_has_catalog_models = provider && !@registry.models_for_provider(provider).empty?

        if provider_has_no_tiers && !provider_has_catalog_models
          Aidp.log_info("thinking_depth_manager", "No configured tiers for provider, deferring to provider auto model selection",
            requested_tier: tier,
            provider: provider)
          return [provider, nil, {auto_model: true, reason: "provider_has_no_tiers"}]
        end

        # First, try to get models from user's configuration for this tier and provider
        if provider
          configured_models = configuration.models_for_tier(tier, provider)

          if configured_models.any?
            # Use first configured model for this provider and tier
            model_name = configured_models.first

            # Check if model is deprecated and try to upgrade
            require_relative "ruby_llm_registry" unless defined?(Aidp::Harness::RubyLLMRegistry)
            llm_registry = Aidp::Harness::RubyLLMRegistry.new

            if llm_registry.model_deprecated?(model_name, provider)
              Aidp.log_warn("thinking_depth_manager", "Configured model is deprecated",
                tier: tier,
                provider: provider,
                model: model_name)

              # Try to find replacement
              replacement = llm_registry.find_replacement_model(model_name, provider: provider)
              if replacement
                Aidp.log_info("thinking_depth_manager", "Auto-upgrading to non-deprecated model",
                  tier: tier,
                  provider: provider,
                  old_model: model_name,
                  new_model: replacement)
                model_name = replacement
              else
                # Try next model in config list
                non_deprecated = configured_models.find { |m| !llm_registry.model_deprecated?(m, provider) }
                if non_deprecated
                  Aidp.log_info("thinking_depth_manager", "Using alternate configured model",
                    tier: tier,
                    provider: provider,
                    skipped: model_name,
                    selected: non_deprecated)
                  model_name = non_deprecated
                else
                  Aidp.log_warn("thinking_depth_manager", "All configured models deprecated, falling back to catalog",
                    tier: tier,
                    provider: provider)
                  # Fall through to catalog selection
                  model_name = nil
                end
              end
            end

            if model_name
              Aidp.log_debug("thinking_depth_manager", "Selected model from user config",
                tier: tier,
                provider: provider,
                model: model_name)
              return [provider, model_name, {}]
            end
          end

          # Provider specified but has no models for this tier in config
          # Try catalog for the specified provider before switching providers
          Aidp.log_debug("thinking_depth_manager", "Provider has no configured models for tier, trying catalog",
            tier: tier,
            provider: provider)

          # Continue to catalog-based selection below (will try specified provider first)
        else
          # No provider specified - this should not happen in normal flow
          # Log warning and fall through to catalog-based selection
          Aidp.log_warn("thinking_depth_manager", "select_model_for_tier called without provider",
            tier: tier)
        end

        # Fall back to catalog-based selection if no models in user config
        # If provider specified, try to find model for that provider in catalog
        if provider
          model_name, model_data = @registry.best_model_for_tier(tier, provider)
          if model_name
            Aidp.log_debug("thinking_depth_manager", "Selected model from catalog",
              tier: tier,
              provider: provider,
              model: model_name)
            return [provider, model_name, model_data]
          end
          # Per issue #323: Don't return nil here - let fallback logic handle missing tiers
        end

        # Try all providers in catalog if provider switching is allowed
        if configuration.allow_provider_switch_for_tier?
          providers_to_try = provider ? (@registry.provider_names - [provider]) : @registry.provider_names

          providers_to_try.each do |prov_name|
            model_name, model_data = @registry.best_model_for_tier(tier, prov_name)
            if model_name
              Aidp.log_info("thinking_depth_manager", "Selected model from catalog (alternate provider)",
                tier: tier,
                original_provider: provider,
                selected_provider: prov_name,
                model: model_name)
              return [prov_name, model_name, model_data]
            end
          end
        end

        # No model found for requested tier - try fallback to other tiers
        # Per issue #323: fallback events log at debug level
        Aidp.log_debug("thinking_depth_manager", "tier_not_found_trying_fallback",
          tier: tier,
          provider: provider)

        result = try_fallback_tiers(tier, provider)

        # If no model found after fallback, defer to provider auto model selection
        # This allows providers to select their own model when no explicit tier config exists
        # Per issue #323: log at debug level, don't constrain model selection
        if result.nil? && provider
          Aidp.log_debug("thinking_depth_manager", "no_model_for_tier_deferring_to_provider",
            requested_tier: tier,
            provider: provider,
            reason: provider_has_no_tiers ? "provider_has_no_tiers" : "tier_not_configured")
          return [provider, nil, {auto_model: true, reason: provider_has_no_tiers ? "provider_has_no_tiers" : "tier_not_configured"}]
        end

        unless result
          # This path should only be reached when no provider is specified
          # Enhanced error message with discovery hints
          display_enhanced_tier_error(tier, provider)

          Aidp.log_error("thinking_depth_manager", "No model found for tier or fallback tiers",
            tier: tier,
            provider: provider)
        end

        result
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
        @tier_history.shift if @tier_history.size > MAX_TIER_HISTORY_SIZE
      end

      # ============================================================
      # Issue #375: ZFC helper methods for tier determination
      # ============================================================

      # Extract tier from issue labels (fast path, no AI needed)
      # @param labels [Array<String>] Issue labels
      # @return [String, nil] Tier name or nil if no tier label found
      def extract_tier_from_labels(labels)
        return nil unless labels.is_a?(Array)

        tier_label_patterns = {
          /\btier[:\-_]?mini\b/i => "mini",
          /\btier[:\-_]?standard\b/i => "standard",
          /\btier[:\-_]?thinking\b/i => "thinking",
          /\btier[:\-_]?pro\b/i => "pro",
          /\btier[:\-_]?max\b/i => "max",
          /\bcomplexity[:\-_]?low\b/i => "mini",
          /\bcomplexity[:\-_]?medium\b/i => "standard",
          /\bcomplexity[:\-_]?high\b/i => "pro"
        }

        labels.each do |label|
          tier_label_patterns.each do |pattern, tier|
            return tier if label.match?(pattern)
          end
        end

        nil
      end

      # Use Zero Framework Cognition to determine tier from comment content
      # @param comment_text [String] The comment text to analyze
      # @param provider_manager [ProviderManager] Provider manager for AI calls
      # @return [Hash] Tier determination result
      def determine_tier_via_zfc(comment_text, provider_manager)
        prompt = build_tier_determination_prompt(comment_text)

        # Use mini tier for the ZFC decision itself (cost efficiency)
        provider_name, model_name, _data = select_model_for_tier("mini", provider: configuration.default_provider)

        # Handle case where no model is available for tier determination
        if provider_name.nil?
          Aidp.log_warn("thinking_depth_manager", "No model available for ZFC tier determination",
            tier: "mini",
            provider: configuration.default_provider)
          raise NoModelAvailableError.new(tier: "mini", provider: configuration.default_provider)
        end

        result = provider_manager.execute_with_provider(
          provider_name,
          prompt,
          {
            model: model_name,
            mode: :tier_determination,
            max_tokens: 500  # Keep response short
          }
        )

        parse_tier_determination_response(result[:output])
      end

      # Build prompt for ZFC tier determination
      def build_tier_determination_prompt(comment_text)
        max_length = MAX_COMMENT_LENGTH
        truncated = comment_text && comment_text.length > max_length
        truncation_note = truncated ? "\n\n[Note: Comment was truncated from #{comment_text.length} to #{max_length} characters]" : ""

        <<~PROMPT
          Analyze the following issue/PR comment and determine the appropriate thinking tier for an AI agent to address it.

          ## Available Tiers (lowest to highest capability/cost):
          - **mini**: Simple fixes, typos, minor changes, documentation updates
          - **standard**: Normal features, bug fixes, moderate complexity changes
          - **thinking**: Complex problems requiring extended reasoning, multi-step solutions
          - **pro**: Highly complex tasks, architectural decisions, security-sensitive work
          - **max**: Extreme complexity, requires maximum reasoning capability (rarely needed)

          ## Comment to Analyze:
          ```
          #{truncate_string(comment_text, max_length)}
          ```#{truncation_note}

          ## Your Task:
          Determine which tier is most appropriate for handling this work.
          Consider:
          1. Task complexity (simple fix vs architectural change)
          2. Reasoning depth required
          3. Risk level (security, data integrity)
          4. Domain expertise needed

          Respond in this exact format:
          TIER: <mini|standard|thinking|pro|max>
          CONFIDENCE: <0.0-1.0>
          REASONING: <brief explanation>
        PROMPT
      end

      # Parse the ZFC response for tier determination
      def parse_tier_determination_response(response)
        tier_match = response.match(/TIER:\s*(\w+)/i)
        confidence_match = response.match(/CONFIDENCE:\s*([\d.]+)/i)
        reasoning_match = response.match(/REASONING:\s*(.+)/mi)

        tier = tier_match&.[](1)&.downcase || "standard"
        raw_confidence = confidence_match&.[](1)&.to_f || DEFAULT_CONFIDENCE
        # Clamp confidence to valid 0.0-1.0 range
        confidence = [[raw_confidence, 0.0].max, 1.0].min
        reasoning = reasoning_match&.[](1)&.strip || "No reasoning provided"

        # Validate tier is in allowed list
        tier = "standard" unless CapabilityRegistry::VALID_TIERS.include?(tier)

        # In autonomous mode, cap at autonomous_max_tier
        if @autonomous_mode && @registry.compare_tiers(tier, autonomous_max_tier) > 0
          original_tier = tier
          tier = autonomous_max_tier
          reasoning += " (capped from #{original_tier} due to autonomous mode)"

          Aidp.log_debug("thinking_depth_manager", "ZFC tier capped for autonomous mode",
            original: original_tier,
            capped_to: tier)
        end

        Aidp.log_info("thinking_depth_manager", "ZFC tier determination",
          tier: tier,
          confidence: confidence,
          reasoning: truncate_string(reasoning, MAX_REASONING_DISPLAY_LENGTH))

        {
          tier: tier,
          confidence: confidence,
          reasoning: reasoning,
          source: "zfc"
        }
      end

      # Try to find a model in fallback tiers when requested tier has no models
      # Tries lower tiers first (cheaper), then higher tiers
      # Returns [provider_name, model_name, model_data] or nil
      def try_fallback_tiers(requested_tier, provider)
        # Generate fallback order: try lower tiers first, then higher
        fallback_tiers = generate_fallback_tier_order(requested_tier)

        fallback_tiers.each do |fallback_tier|
          # First, try user's configuration for this fallback tier and provider
          if provider
            configured_models = configuration.models_for_tier(fallback_tier, provider)

            if configured_models.any?
              model_name = configured_models.first
              # Per issue #323: fallback events log at debug level
              Aidp.log_debug("thinking_depth_manager", "tier_fallback_from_config",
                requested_tier: requested_tier,
                fallback_tier: fallback_tier,
                provider: provider,
                model: model_name)
              return [provider, model_name, {}]
            end
          end

          # Fall back to catalog if no models in config for the provider
          # Try specified provider first if given
          if provider
            model_name, model_data = @registry.best_model_for_tier(fallback_tier, provider)
            if model_name
              # Per issue #323: fallback events log at debug level
              Aidp.log_debug("thinking_depth_manager", "tier_fallback_from_catalog",
                requested_tier: requested_tier,
                fallback_tier: fallback_tier,
                provider: provider,
                model: model_name)
              return [provider, model_name, model_data]
            end
          end

          # Try all available providers in catalog if switching allowed
          if configuration.allow_provider_switch_for_tier?
            @registry.provider_names.each do |prov_name|
              next if prov_name == provider # Skip if already tried above

              model_name, model_data = @registry.best_model_for_tier(fallback_tier, prov_name)
              if model_name
                # Per issue #323: fallback events log at debug level
                Aidp.log_debug("thinking_depth_manager", "tier_fallback_provider_switch",
                  requested_tier: requested_tier,
                  fallback_tier: fallback_tier,
                  requested_provider: provider,
                  fallback_provider: prov_name,
                  model: model_name)
                return [prov_name, model_name, model_data]
              end
            end
          end
        end

        nil
      end

      # Generate fallback tier order: lower tiers first (cheaper), then higher
      # For example, if tier is "standard", try: mini, thinking, pro, max
      def generate_fallback_tier_order(tier)
        current_priority = @registry.tier_priority(tier) || 1
        all_tiers = CapabilityRegistry::VALID_TIERS

        # Split into lower and higher tiers
        lower_tiers = all_tiers.select { |t| (@registry.tier_priority(t) || 0) < current_priority }.reverse
        higher_tiers = all_tiers.select { |t| (@registry.tier_priority(t) || 0) > current_priority }

        # Try lower tiers first (cost optimization), then higher tiers
        lower_tiers + higher_tiers
      end

      # Display enhanced error message with discovery hints
      def display_enhanced_tier_error(tier, provider)
        return unless defined?(Aidp::MessageDisplay)

        # Check if there are discovered models in cache
        discovered_models = check_discovered_models(tier, provider)

        if discovered_models&.any?
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
      rescue => e
        Aidp.log_debug("thinking_depth_manager", "failed to check cached models",
          error: e.message)
        nil
      end

      # Display error with model suggestions from cache
      def display_tier_error_with_suggestions(tier, provider, models)
        display_message("\n❌ No model configured for '#{tier}' tier", type: :error)
        display_message("   Provider: #{provider}", type: :info) if provider

        display_message("\n💡 Discovered models for this tier:", type: :highlight)
        models.first(3).each do |model|
          model_name = model[:name] || model["name"]
          display_message("   - #{model_name}", type: :info)
        end

        display_message("\n   Add to aidp.yml:", type: :highlight)
        display_message("   providers:", type: :info)
        display_message("     #{provider}:", type: :info)
        display_message("       thinking:", type: :info)
        display_message("         tiers:", type: :info)
        display_message("           #{tier}:", type: :info)
        display_message("             models:", type: :info)
        first_model = models.first[:name] || models.first["name"]
        display_message("               - model: #{first_model}\n", type: :info)
      end

      # Display error with discovery hint
      def display_tier_error_with_discovery_hint(tier, provider)
        display_message("\n❌ No model configured for '#{tier}' tier", type: :error)
        display_message("   Provider: #{provider}", type: :info) if provider

        display_message("\n💡 Suggested actions:", type: :highlight)
        display_message("   1. Run 'aidp models discover' to find available models", type: :info)
        display_message("   2. Run 'aidp models list --tier=#{tier}' to see models for this tier", type: :info)
        display_message("   3. Run 'aidp models validate' to check your configuration\n", type: :info)
      end

      # Truncate string to max_length (plain Ruby replacement for ActiveSupport truncate)
      def truncate_string(string, max_length)
        return "" if string.nil?
        return string if string.length <= max_length

        "#{string[0, max_length - 3]}..."
      end
    end
  end
end
