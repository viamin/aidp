# frozen_string_literal: true

require "yaml"
require "fileutils"

module Aidp
  module Harness
    # Stores and queries model capability metadata from the catalog
    # Provides information about model tiers, features, costs, and context windows
    class CapabilityRegistry
      # Valid thinking depth tiers
      VALID_TIERS = %w[mini standard thinking pro max].freeze

      # Tier priority for escalation (lower index = lower tier)
      TIER_PRIORITY = {
        "mini" => 0,
        "standard" => 1,
        "thinking" => 2,
        "pro" => 3,
        "max" => 4
      }.freeze

      attr_reader :catalog_path
      # Expose for testability
      attr_reader :catalog_data

      def initialize(catalog_path: nil, root_dir: nil)
        @root_dir = root_dir || Dir.pwd
        @catalog_path = catalog_path || default_catalog_path
        @catalog_data = nil
        @loaded_at = nil
      end

      # Load catalog from YAML file
      def load_catalog
        return false unless File.exist?(@catalog_path)

        @catalog_data = YAML.safe_load_file(
          @catalog_path,
          permitted_classes: [Symbol],
          symbolize_names: false
        )
        @loaded_at = Time.now

        validate_catalog(@catalog_data)
        Aidp.log_debug("capability_registry", "Loaded catalog", path: @catalog_path, providers: provider_names.size)
        true
      rescue => e
        Aidp.log_error("capability_registry", "Failed to load catalog", error: e.message, path: @catalog_path)
        @catalog_data = nil
        false
      end

      # Get catalog data (lazy load if needed)
      def catalog
        load_catalog if @catalog_data.nil?
        @catalog_data || default_empty_catalog
      end

      # Get all provider names in catalog
      def provider_names
        catalog.dig("providers")&.keys || []
      end

      # Get all models for a provider
      def models_for_provider(provider_name)
        provider_data = catalog.dig("providers", provider_name)
        return {} unless provider_data

        provider_data["models"] || {}
      end

      # Get tier for a specific model
      def tier_for_model(provider_name, model_name)
        model_data = model_info(provider_name, model_name)
        return nil unless model_data

        model_data["tier"]
      end

      # Get all models matching a specific tier
      # Returns hash: { provider_name => [model_name, ...] }
      def models_by_tier(tier, provider: nil)
        validate_tier!(tier)

        results = {}
        providers_to_search = provider ? [provider] : provider_names

        providers_to_search.each do |provider_name|
          matching_models = []
          models_for_provider(provider_name).each do |model_name, model_data|
            matching_models << model_name if model_data["tier"] == tier.to_s
          end
          results[provider_name] = matching_models unless matching_models.empty?
        end

        results
      end

      # Get complete info for a specific model
      def model_info(provider_name, model_name)
        catalog.dig("providers", provider_name, "models", model_name)
      end

      # Get display name for a provider
      def provider_display_name(provider_name)
        catalog.dig("providers", provider_name, "display_name") || provider_name
      end

      # Get all tiers supported by a provider
      def supported_tiers(provider_name)
        models = models_for_provider(provider_name)
        tiers = models.values.map { |m| m["tier"] }.compact.uniq
        tiers.sort_by { |t| TIER_PRIORITY[t] || 999 }
      end

      # Check if a tier is valid
      def valid_tier?(tier)
        VALID_TIERS.include?(tier.to_s)
      end

      # Get tier priority (0 = lowest, 4 = highest)
      def tier_priority(tier)
        TIER_PRIORITY[tier.to_s]
      end

      # Compare two tiers (returns -1, 0, 1 like <=>)
      def compare_tiers(tier1, tier2)
        priority1 = tier_priority(tier1) || -1
        priority2 = tier_priority(tier2) || -1
        priority1 <=> priority2
      end

      # Get next higher tier (or nil if already at max)
      def next_tier(tier)
        validate_tier!(tier)
        current_priority = tier_priority(tier)
        return nil if current_priority >= TIER_PRIORITY["max"]

        TIER_PRIORITY.key(current_priority + 1)
      end

      # Get next lower tier (or nil if already at mini)
      def previous_tier(tier)
        validate_tier!(tier)
        current_priority = tier_priority(tier)
        return nil if current_priority <= TIER_PRIORITY["mini"]

        TIER_PRIORITY.key(current_priority - 1)
      end

      # Find best model for a tier and provider
      # Returns [model_name, model_data] or nil
      def best_model_for_tier(tier, provider_name)
        validate_tier!(tier)
        models = models_for_provider(provider_name)

        # Find all models matching tier
        tier_models = models.select { |_name, data| data["tier"] == tier.to_s }
        return nil if tier_models.empty?

        # Prefer newer models (higher in the list)
        # Sort by cost (cheaper first) as tiebreaker
        tier_models.min_by do |_name, data|
          cost = data["cost_per_mtok_input"] || 0
          [cost]
        end
      end

      # Get tier recommendations from catalog
      def tier_recommendations
        catalog["tier_recommendations"] || {}
      end

      # Recommend tier based on complexity score (0.0-1.0)
      def recommend_tier_for_complexity(complexity_score)
        return "mini" if complexity_score <= 0.0

        recommendations = tier_recommendations.sort_by do |_name, data|
          data["complexity_threshold"] || 0.0
        end

        # Find first recommendation where complexity exceeds threshold
        recommendation = recommendations.find do |_name, data|
          complexity_score <= (data["complexity_threshold"] || 0.0)
        end

        recommendation ? recommendation[1]["recommended_tier"] : "max"
      end

      # Reload catalog from disk
      def reload
        @catalog_data = nil
        @loaded_at = nil
        load_catalog
      end

      # Check if catalog needs reload (based on file modification time)
      def stale?(max_age_seconds = 3600)
        return true unless @loaded_at
        return true unless File.exist?(@catalog_path)

        file_mtime = File.mtime(@catalog_path)
        file_mtime > @loaded_at || (Time.now - @loaded_at) > max_age_seconds
      end

      # Export catalog as structured data for display
      def export_for_display
        {
          schema_version: catalog["schema_version"],
          providers: provider_names.map do |provider_name|
            {
              name: provider_name,
              display_name: provider_display_name(provider_name),
              tiers: supported_tiers(provider_name),
              models: models_for_provider(provider_name)
            }
          end,
          tier_order: VALID_TIERS
        }
      end

      private

      def default_catalog_path
        File.join(@root_dir, ".aidp", "models_catalog.yml")
      end

      def default_empty_catalog
        {
          "schema_version" => "1.0",
          "providers" => {},
          "tier_order" => VALID_TIERS,
          "tier_recommendations" => {}
        }
      end

      def validate_catalog(data)
        unless data.is_a?(Hash)
          raise ArgumentError, "Catalog must be a hash"
        end

        unless data["providers"].is_a?(Hash)
          raise ArgumentError, "Catalog must have 'providers' hash"
        end

        # Validate each provider has models
        data["providers"].each do |provider_name, provider_data|
          unless provider_data.is_a?(Hash) && provider_data["models"].is_a?(Hash)
            raise ArgumentError, "Provider #{provider_name} must have 'models' hash"
          end

          # Validate each model has required fields
          provider_data["models"].each do |model_name, model_data|
            unless model_data["tier"]
              raise ArgumentError, "Model #{provider_name}/#{model_name} missing 'tier'"
            end

            unless valid_tier?(model_data["tier"])
              raise ArgumentError, "Model #{provider_name}/#{model_name} has invalid tier: #{model_data["tier"]}"
            end
          end
        end

        Aidp.log_debug("capability_registry", "Catalog validation passed", providers: data["providers"].size)
      end

      def validate_tier!(tier)
        unless valid_tier?(tier)
          raise ArgumentError, "Invalid tier: #{tier}. Must be one of: #{VALID_TIERS.join(", ")}"
        end
      end
    end
  end
end
