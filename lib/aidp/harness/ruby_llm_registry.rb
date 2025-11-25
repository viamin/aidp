# frozen_string_literal: true

require "ruby_llm"
require_relative "deprecation_cache"

module Aidp
  module Harness
    # RubyLLMRegistry wraps the ruby_llm gem's model registry
    # to provide AIDP-specific functionality while leveraging
    # ruby_llm's comprehensive and actively maintained model database
    class RubyLLMRegistry
      class RegistryError < StandardError; end
      class ModelNotFound < RegistryError; end

      # Map AIDP provider names to RubyLLM provider names
      # Some AIDP providers use different names than the upstream APIs
      PROVIDER_NAME_MAPPING = {
        "codex" => "openai",      # Codex is AIDP's OpenAI adapter
        "anthropic" => "anthropic",
        "gemini" => "gemini",     # Gemini provider name matches
        "aider" => nil,           # Aider aggregates multiple providers
        "cursor" => nil,          # Cursor has its own models
        "openai" => "openai",
        "google" => "gemini",     # Google's API uses gemini provider name
        "azure" => "bedrock",     # Azure OpenAI uses bedrock in registry
        "bedrock" => "bedrock",
        "openrouter" => "openrouter"
      }.freeze

      # Get deprecation cache instance (lazy loaded)
      def deprecation_cache
        @deprecation_cache ||= Aidp::Harness::DeprecationCache.new
      end

      # Tier classification based on model characteristics
      # These are heuristics since ruby_llm doesn't classify tiers
      TIER_CLASSIFICATION = {
        # Mini tier: fast, cost-effective models
        mini: ->(model) {
          return true if model.id.to_s.match?(/haiku|mini|flash|small/i)

          # Check pricing if available
          if model.pricing
            pricing_hash = model.pricing.to_h
            input_cost = pricing_hash.dig(:text_tokens, :standard, :input_per_million)
            return true if input_cost && input_cost < 1.0
          end
          false
        },

        # Advanced tier: high-capability, expensive models
        advanced: ->(model) {
          return true if model.id.to_s.match?(/opus|turbo|pro|preview|o1/i)

          # Check pricing if available
          if model.pricing
            pricing_hash = model.pricing.to_h
            input_cost = pricing_hash.dig(:text_tokens, :standard, :input_per_million)
            return true if input_cost && input_cost > 10.0
          end
          false
        },

        # Standard tier: everything else (default)
        standard: ->(model) { true }
      }.freeze

      def initialize
        @models = RubyLLM::Models.instance.instance_variable_get(:@models)
        @index_by_id = @models.to_h { |m| [m.id, m] }

        # Build family index for mapping versioned names to families
        @family_index = build_family_index

        Aidp.log_info("ruby_llm_registry", "initialized", models: @models.size)
      end

      # Resolve a model name (family or versioned) to the canonical API model
      #
      # @param model_name [String] Model name (e.g., "claude-3-5-haiku" or "claude-3-5-haiku-20241022")
      # @param provider [String, nil] Optional AIDP provider filter
      # @param skip_deprecated [Boolean] Skip deprecated models (default: true)
      # @return [String, nil] Canonical model ID for API calls, or nil if not found
      def resolve_model(model_name, provider: nil, skip_deprecated: true)
        # Map AIDP provider to registry provider if filtering
        registry_provider = provider ? PROVIDER_NAME_MAPPING[provider] : nil

        # Check if model is deprecated
        if skip_deprecated && model_deprecated?(model_name, registry_provider)
          Aidp.log_warn("ruby_llm_registry", "skipping deprecated model", model: model_name, provider: provider)
          return nil
        end

        # Try exact match first
        model = @index_by_id[model_name]
        return model.id if model && (registry_provider.nil? || model.provider.to_s == registry_provider)

        # Try family mapping
        family_models = @family_index[model_name]
        if family_models
          # Filter by provider if specified
          family_models = family_models.select { |m| m.provider.to_s == registry_provider } if registry_provider

          # Filter out deprecated models if requested
          if skip_deprecated
            family_models = family_models.reject do |m|
              deprecation_cache.deprecated?(provider: registry_provider, model_id: m.id.to_s)
            end
          end

          # Return the latest version (first non-"latest" model, or the latest one)
          model = family_models.reject { |m| m.id.to_s.include?("-latest") }.first || family_models.first
          return model.id if model
        end

        # Try fuzzy matching for common patterns
        fuzzy_match = find_fuzzy_match(model_name, registry_provider, skip_deprecated: skip_deprecated)
        return fuzzy_match.id if fuzzy_match

        Aidp.log_warn("ruby_llm_registry", "model not found", model: model_name, provider: provider)
        nil
      end

      # Get model information
      #
      # @param model_id [String] The model ID
      # @return [Hash, nil] Model information hash or nil if not found
      def get_model_info(model_id)
        model = @index_by_id[model_id]
        return nil unless model

        {
          id: model.id,
          name: model.name || model.display_name,
          provider: model.provider.to_s,
          tier: classify_tier(model),
          context_window: model.context_window,
          capabilities: extract_capabilities(model),
          pricing: model.pricing
        }
      end

      # Get all models for a specific tier
      #
      # @param tier [String, Symbol] The tier name (mini, standard, advanced)
      # @param provider [String, nil] Optional AIDP provider filter
      # @param skip_deprecated [Boolean] Skip deprecated models (default: true)
      # @return [Array<String>] List of model IDs for the tier
      def models_for_tier(tier, provider: nil, skip_deprecated: true)
        tier_sym = tier.to_sym
        classifier = TIER_CLASSIFICATION[tier_sym]

        unless classifier
          Aidp.log_warn("ruby_llm_registry", "invalid tier", tier: tier)
          return []
        end

        # Map AIDP provider to registry provider if filtering
        registry_provider = provider ? PROVIDER_NAME_MAPPING[provider] : nil
        return [] if provider && registry_provider.nil?

        models = @models.select do |model|
          (registry_provider.nil? || model.provider.to_s == registry_provider) &&
            classifier.call(model)
        end

        # For mini and standard tiers, exclude if advanced classification matches
        if tier_sym == :mini
          models.reject! { |m| TIER_CLASSIFICATION[:advanced].call(m) }
        elsif tier_sym == :standard
          models.reject! do |m|
            TIER_CLASSIFICATION[:mini].call(m) || TIER_CLASSIFICATION[:advanced].call(m)
          end
        end

        # Filter out deprecated models if requested
        if skip_deprecated
          models.reject! { |m| deprecation_cache.deprecated?(provider: registry_provider, model_id: m.id.to_s) }
        end

        model_ids = models.map(&:id).uniq
        Aidp.log_debug("ruby_llm_registry", "found models for tier",
          tier: tier, provider: provider, count: model_ids.size)
        model_ids
      end

      # Get all models for a provider
      #
      # @param provider [String] The AIDP provider name
      # @return [Array<String>] List of model IDs
      def models_for_provider(provider)
        # Map AIDP provider name to RubyLLM provider name
        registry_provider = PROVIDER_NAME_MAPPING[provider]

        # Return empty if provider doesn't map to a registry provider
        return [] if registry_provider.nil?

        @models.select { |m| m.provider.to_s == registry_provider }.map(&:id)
      end

      # Classify a model's tier
      #
      # @param model [RubyLLM::Model::Info] The model info object
      # @return [String] The tier name (mini, standard, advanced)
      def classify_tier(model)
        return "advanced" if TIER_CLASSIFICATION[:advanced].call(model)
        return "mini" if TIER_CLASSIFICATION[:mini].call(model)
        "standard"
      end

      # Refresh the model registry from ruby_llm
      def refresh!
        RubyLLM::Models.refresh!
        @models = RubyLLM::Models.instance.instance_variable_get(:@models)
        @index_by_id = @models.to_h { |m| [m.id, m] }
        @family_index = build_family_index
        Aidp.log_info("ruby_llm_registry", "refreshed", models: @models.size)
      end

      # Check if a model is deprecated
      # @param model_id [String] The model ID to check
      # @param provider [String, nil] The provider name (registry format)
      # @return [Boolean] True if model is deprecated
      def model_deprecated?(model_id, provider = nil)
        return false unless provider

        deprecation_cache.deprecated?(provider: provider, model_id: model_id.to_s)
      end

      # Find replacement for a deprecated model
      # Returns the latest non-deprecated model in the same family/tier
      # @param deprecated_model [String] The deprecated model ID
      # @param provider [String, nil] The provider name (AIDP format)
      # @return [String, nil] Replacement model ID or nil
      def find_replacement_model(deprecated_model, provider: nil)
        registry_provider = provider ? PROVIDER_NAME_MAPPING[provider] : nil
        return nil unless registry_provider

        # Determine tier of deprecated model
        deprecated_info = @index_by_id[deprecated_model]
        return nil unless deprecated_info

        tier = classify_tier(deprecated_info)

        # Get all non-deprecated models for this tier and provider
        candidates = models_for_tier(tier, provider: provider, skip_deprecated: true)

        # Prefer models in the same family (e.g., both "sonnet")
        family_keyword = extract_family_keyword(deprecated_model)
        same_family = candidates.select { |m| m.to_s.include?(family_keyword) } if family_keyword

        # Return first match from same family, or first candidate overall
        replacement = same_family&.first || candidates.first

        if replacement
          Aidp.log_info("ruby_llm_registry", "found replacement",
            deprecated: deprecated_model,
            replacement: replacement,
            tier: tier)
        end

        replacement
      end

      private

      # Build an index mapping family names to model objects
      # Family name is model ID with version suffix removed
      def build_family_index
        index = Hash.new { |h, k| h[k] = [] }

        @models.each do |model|
          # Remove date suffix (e.g., "claude-3-5-haiku-20241022" -> "claude-3-5-haiku")
          family = model.id.to_s.sub(/-\d{8}$/, "").sub(/-latest$/, "")
          index[family] << model unless family == model.id.to_s
        end

        index
      end

      # Find a model by fuzzy matching
      def find_fuzzy_match(model_name, provider, skip_deprecated: true)
        # Normalize the search term
        normalized = model_name.downcase.gsub(/[^a-z0-9]/, "")

        candidates = @models.select do |m|
          next false if provider && m.provider.to_s != provider

          # Skip deprecated if requested
          if skip_deprecated
            next false if deprecation_cache.deprecated?(provider: provider, model_id: m.id.to_s)
          end

          # Check if model ID contains the search term
          m.id.to_s.downcase.gsub(/[^a-z0-9]/, "").include?(normalized) ||
            m.name.to_s.downcase.gsub(/[^a-z0-9]/, "").include?(normalized)
        end

        # Prefer shorter matches (more specific)
        candidates.min_by { |m| m.id.to_s.length }
      end

      # Extract family keyword from model ID (e.g., "sonnet", "haiku", "opus")
      def extract_family_keyword(model_id)
        case model_id.to_s
        when /sonnet/i then "sonnet"
        when /haiku/i then "haiku"
        when /opus/i then "opus"
        when /gpt-4/i then "gpt-4"
        when /gpt-3/i then "gpt-3"
        end
      end

      # Extract capabilities from model info
      def extract_capabilities(model)
        caps = []
        caps << "chat" if model.capabilities.include?(:chat)
        caps << "code" if model.capabilities.include?(:code) || model.id.to_s.include?("code")
        caps << "vision" if model.capabilities.include?(:vision)
        caps << "tool_use" if model.capabilities.include?(:function_calling) || model.capabilities.include?(:tools)
        caps << "streaming" if model.capabilities.include?(:streaming)
        caps
      end
    end
  end
end
