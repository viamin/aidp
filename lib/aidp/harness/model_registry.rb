# frozen_string_literal: true

require "yaml"
require "pathname"

module Aidp
  module Harness
    # ModelRegistry manages the static registry of known model families and their tier classifications
    #
    # The registry uses model families (e.g., "claude-3-5-sonnet") rather than specific versioned
    # model IDs (e.g., "claude-3-5-sonnet-20241022"). This design provides:
    #   - No version tracking burden - registry tracks families, not every dated version
    #   - Future-proofing - new model versions automatically inherit family tier
    #   - Provider autonomy - each provider handles version-specific naming
    #
    # Usage:
    #   registry = ModelRegistry.new
    #   registry.get_model_info("claude-3-5-sonnet")
    #   # => { name: "Claude 3.5 Sonnet", tier: "standard", ... }
    #
    #   registry.models_for_tier("standard")
    #   # => ["claude-3-5-sonnet", "gpt-4-turbo", ...]
    #
    #   registry.match_to_family("claude-3-5-sonnet-20241022")
    #   # => "claude-3-5-sonnet"
    class ModelRegistry
      class RegistryError < StandardError; end
      class InvalidRegistrySchema < RegistryError; end
      class ModelNotFound < RegistryError; end

      VALID_TIERS = %w[mini standard advanced].freeze
      VALID_CAPABILITIES = %w[chat code vision tool_use streaming json_mode].freeze
      VALID_SPEEDS = %w[very_fast fast medium slow].freeze

      attr_reader :registry_data

      def initialize(registry_path: nil)
        @registry_path = registry_path || default_registry_path
        @registry_data = load_static_registry
        validate_registry_schema
        Aidp.log_debug("model_registry", "initialized", models: @registry_data["model_families"].keys.size)
      end

      # Get complete model information for a family
      #
      # @param family_name [String] The model family name (e.g., "claude-3-5-sonnet")
      # @return [Hash, nil] Model metadata hash or nil if not found
      def get_model_info(family_name)
        info = @registry_data["model_families"][family_name]
        return nil unless info

        info.merge("family" => family_name)
      end

      # Get all model families for a specific tier
      #
      # @param tier [String, Symbol] The tier name (mini, standard, advanced)
      # @return [Array<String>] List of model family names for the tier
      def models_for_tier(tier)
        tier_str = tier.to_s
        unless VALID_TIERS.include?(tier_str)
          Aidp.log_warn("model_registry", "invalid tier requested", tier: tier_str, valid: VALID_TIERS)
          return []
        end

        families = @registry_data["model_families"].select { |_family, info|
          info["tier"] == tier_str
        }.keys

        Aidp.log_debug("model_registry", "found models for tier", tier: tier_str, count: families.size)
        families
      end

      # Classify a model family's tier
      #
      # @param family_name [String] The model family name
      # @return [String, nil] The tier name or nil if not found
      def classify_model_tier(family_name)
        info = get_model_info(family_name)
        tier = info&.fetch("tier", nil)
        Aidp.log_debug("model_registry", "classified tier", family: family_name, tier: tier)
        tier
      end

      # Match a versioned model name to its family using pattern matching
      #
      # This method attempts to normalize versioned model names (e.g., "claude-3-5-sonnet-20241022")
      # to their family name (e.g., "claude-3-5-sonnet") by testing against version_pattern regexes.
      #
      # @param versioned_name [String] The versioned model name
      # @return [String, nil] The family name if matched, nil otherwise
      def match_to_family(versioned_name)
        @registry_data["model_families"].each do |family, info|
          pattern = info["version_pattern"]
          next unless pattern

          begin
            regex = Regexp.new("^#{pattern}$")
            if regex.match?(versioned_name)
              Aidp.log_debug("model_registry", "matched to family", versioned: versioned_name, family: family)
              return family
            end
          rescue RegexpError => e
            Aidp.log_error("model_registry", "invalid pattern", family: family, pattern: pattern, error: e.message)
          end
        end

        # If no pattern matches, check if the versioned_name is itself a family
        if @registry_data["model_families"].key?(versioned_name)
          Aidp.log_debug("model_registry", "exact family match", name: versioned_name)
          return versioned_name
        end

        Aidp.log_debug("model_registry", "no family match", versioned: versioned_name)
        nil
      end

      # Get all registered model families
      #
      # @return [Array<String>] List of all model family names
      def all_families
        @registry_data["model_families"].keys
      end

      # Check if a model family exists in the registry
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if the family exists
      def family_exists?(family_name)
        @registry_data["model_families"].key?(family_name)
      end

      # Get all tiers that have at least one model
      #
      # @return [Array<String>] List of tier names
      def available_tiers
        @registry_data["model_families"].values.map { |info| info["tier"] }.uniq.sort
      end

      private

      def default_registry_path
        Pathname.new(__dir__).parent.join("data", "model_registry.yml")
      end

      def load_static_registry
        unless File.exist?(@registry_path)
          raise RegistryError, "Model registry file not found at #{@registry_path}"
        end

        data = YAML.load_file(@registry_path)
        unless data.is_a?(Hash) && data.key?("model_families")
          raise InvalidRegistrySchema, "Registry must contain 'model_families' key"
        end

        Aidp.log_info("model_registry", "loaded registry", path: @registry_path, families: data["model_families"].size)
        data
      rescue Psych::SyntaxError => e
        raise InvalidRegistrySchema, "Invalid YAML in registry file: #{e.message}"
      end

      def validate_registry_schema
        @registry_data["model_families"].each do |family, info|
          validate_model_entry(family, info)
        end
      end

      def validate_model_entry(family, info)
        # Required fields
        unless info["tier"]
          raise InvalidRegistrySchema, "Model family '#{family}' missing required 'tier' field"
        end
        unless VALID_TIERS.include?(info["tier"])
          raise InvalidRegistrySchema, "Model family '#{family}' has invalid tier '#{info['tier']}'. Valid: #{VALID_TIERS.join(", ")}"
        end

        # Optional but validated if present
        if info["capabilities"]
          unless info["capabilities"].is_a?(Array)
            raise InvalidRegistrySchema, "Model family '#{family}' capabilities must be an array"
          end
          invalid_caps = info["capabilities"] - VALID_CAPABILITIES
          unless invalid_caps.empty?
            Aidp.log_warn("model_registry", "unknown capabilities", family: family, unknown: invalid_caps)
          end
        end

        if info["speed"] && !VALID_SPEEDS.include?(info["speed"])
          Aidp.log_warn("model_registry", "invalid speed", family: family, speed: info["speed"], valid: VALID_SPEEDS)
        end

        # Validate numeric fields if present
        %w[context_window max_output cost_per_1m_input cost_per_1m_output].each do |field|
          if info[field] && !info[field].is_a?(Numeric)
            raise InvalidRegistrySchema, "Model family '#{family}' field '#{field}' must be numeric"
          end
        end
      end
    end
  end
end
