# frozen_string_literal: true

require "json"
require_relative "provider_factory"
require_relative "thinking_depth_manager"
require_relative "../prompts/prompt_template_manager"

module Aidp
  module Harness
    # Zero Framework Cognition (ZFC) Decision Engine
    #
    # Delegates semantic analysis and decision-making to AI models instead of
    # using brittle pattern matching, scoring formulas, or heuristic thresholds.
    #
    # All prompts are loaded from YAML templates at:
    # - Project level: .aidp/prompts/decision_engine/<name>.yml
    # - User level: ~/.aidp/prompts/decision_engine/<name>.yml
    # - Built-in: lib/aidp/prompts/defaults/decision_engine/<name>.yml
    #
    # @example Basic usage
    #   engine = AIDecisionEngine.new(config, provider_manager)
    #   result = engine.decide(:condition_detection,
    #     context: { error: "Rate limit exceeded" },
    #     tier: "mini"
    #   )
    #   # => { condition: "rate_limit", confidence: 0.95, reasoning: "..." }
    #
    # @see docs/ZFC_COMPLIANCE_ASSESSMENT.md
    # @see docs/ZFC_IMPLEMENTATION_PLAN.md
    class AIDecisionEngine
      # Maps decision types to template file paths
      TEMPLATE_PATHS = {
        condition_detection: "decision_engine/condition_detection",
        error_classification: "decision_engine/error_classification",
        completion_detection: "decision_engine/completion_detection",
        implementation_verification: "decision_engine/implementation_verification",
        prompt_evaluation: "decision_engine/prompt_evaluation",
        template_improvement: "decision_engine/template_improvement",
        template_evolution: "decision_engine/template_evolution"
      }.freeze

      attr_reader :config, :provider_factory, :cache, :prompt_template_manager

      # Initialize the AI Decision Engine
      #
      # @param config [Configuration] AIDP configuration object
      # @param provider_factory [ProviderFactory] Factory for creating provider instances
      # @param prompt_template_manager [PromptTemplateManager] Optional template manager
      # @param project_dir [String] Project directory for template loading
      def initialize(config, provider_factory: nil, prompt_template_manager: nil, project_dir: Dir.pwd)
        @config = config
        # ProviderFactory expects a ConfigManager, not a Configuration object.
        # Pass nil to let ProviderFactory create its own ConfigManager.
        @provider_factory = provider_factory || ProviderFactory.new
        @prompt_template_manager = prompt_template_manager || Prompts::PromptTemplateManager.new(project_dir: project_dir)
        @cache = {}
        @cache_timestamps = {}
      end

      # Make an AI-powered decision
      #
      # @param decision_type [Symbol] Type of decision (:condition_detection, :error_classification, etc.)
      # @param context [Hash] Context data for the decision
      # @param schema [Hash, nil] JSON schema for response validation (overrides template schema)
      # @param tier [String, nil] Thinking depth tier (overrides template tier)
      # @param cache_ttl [Integer, nil] Cache TTL in seconds (overrides template cache_ttl)
      # @return [Hash] Validated decision result
      # @raise [ArgumentError] If decision_type is unknown
      # @raise [Prompts::TemplateNotFoundError] If template is not found
      # @raise [ValidationError] If response doesn't match schema
      def decide(decision_type, context:, schema: nil, tier: nil, cache_ttl: nil)
        template_path = TEMPLATE_PATHS[decision_type]
        raise ArgumentError, "Unknown decision type: #{decision_type}" unless template_path

        # Load template data
        template_data = @prompt_template_manager.load_template(template_path)
        raise Prompts::TemplateNotFoundError, "Template not found: #{template_path}" unless template_data

        # Check cache if TTL specified
        template_cache_ttl = template_data["cache_ttl"] || template_data[:cache_ttl]
        ttl = cache_ttl || template_cache_ttl
        cache_key = build_cache_key(decision_type, context)
        if ttl && (cached_result = get_cached(cache_key, ttl))
          Aidp.log_debug("ai_decision_engine", "cache_hit", {
            decision_type: decision_type,
            cache_key: cache_key,
            ttl: ttl
          })
          return cached_result
        end

        # Render prompt with variables
        prompt = @prompt_template_manager.render(template_path, **context)

        # Select tier from parameter, template, or default
        template_tier = template_data["tier"] || template_data[:tier]
        selected_tier = tier || template_tier || "mini"

        # Get model for tier, using harness default provider
        thinking_manager = ThinkingDepthManager.new(config)
        provider_name, model_name, _model_data = thinking_manager.select_model_for_tier(
          selected_tier,
          provider: config.default_provider
        )

        Aidp.log_debug("ai_decision_engine", "making_decision", {
          decision_type: decision_type,
          template_path: template_path,
          tier: selected_tier,
          provider: provider_name,
          model: model_name,
          cache_ttl: ttl
        })

        # Get schema from parameter or template
        template_schema = template_data["schema"] || template_data[:schema]
        response_schema = schema || symbolize_schema(template_schema)
        raise ArgumentError, "No schema defined for decision type: #{decision_type}" unless response_schema

        # Call AI with schema validation
        result = call_ai_with_schema(provider_name, model_name, prompt, response_schema)

        # Validate result
        validate_schema(result, response_schema)

        # Cache if TTL specified
        set_cached(cache_key, result) if ttl

        result
      end

      # List available decision types
      #
      # @return [Array<Symbol>] Available decision type symbols
      def available_decision_types
        TEMPLATE_PATHS.keys
      end

      private

      # Recursively symbolize schema keys for consistent access
      def symbolize_schema(schema)
        return nil unless schema

        case schema
        when Hash
          schema.transform_keys(&:to_sym).transform_values { |v| symbolize_schema(v) }
        when Array
          schema.map { |v| symbolize_schema(v) }
        else
          schema
        end
      end

      # Build cache key from decision type and context
      def build_cache_key(decision_type, context)
        "#{decision_type}:#{context.hash}"
      end

      # Get cached result if still valid
      def get_cached(key, ttl)
        return nil unless @cache.key?(key)
        return nil if Time.now - @cache_timestamps[key] > ttl
        @cache[key]
      end

      # Store result in cache
      def set_cached(key, value)
        @cache[key] = value
        @cache_timestamps[key] = Time.now
      end

      # Call AI with schema validation using structured output
      def call_ai_with_schema(provider_name, model_name, prompt, schema)
        # Create provider instance
        provider_options = {
          model: model_name,
          output: nil,  # No output for background decisions
          prompt: nil   # No TTY prompt needed
        }

        provider = @provider_factory.create_provider(provider_name, provider_options)

        # Build enhanced prompt requesting JSON output
        enhanced_prompt = <<~PROMPT
          #{prompt}

          IMPORTANT: Respond with ONLY valid JSON. No additional text or explanation.
          The JSON must match this structure: #{JSON.generate(schema[:properties].keys)}
        PROMPT

        # Call provider
        response = provider.send_message(prompt: enhanced_prompt, session: nil)

        # Parse JSON response
        begin
          response_text = response.is_a?(String) ? response : response.to_s

          # Try to extract JSON if there's extra text
          json_match = response_text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m) || response_text.match(/\{.*\}/m)
          json_text = json_match ? json_match[0] : response_text

          result = JSON.parse(json_text, symbolize_names: true)

          Aidp.log_debug("ai_decision_engine", "parsed_response", {
            response_length: response_text.length,
            json_length: json_text.length,
            result_keys: result.keys,
            provider: provider_name
          })

          result
        rescue JSON::ParserError => e
          Aidp.log_error("ai_decision_engine", "json_parse_failed", {
            error: e.message,
            response: response_text&.slice(0, 200),
            provider: provider_name,
            model: model_name
          })
          raise ValidationError, "AI response is not valid JSON: #{e.message}"
        end
      rescue => e
        Aidp.log_error("ai_decision_engine", "provider_error", {
          error: e.message,
          provider: provider_name,
          model: model_name,
          error_class: e.class.name
        })
        raise
      end

      # Validate response against JSON schema
      def validate_schema(result, schema)
        schema[:required]&.each do |field|
          field_sym = field.to_sym
          raise ValidationError, "Missing required field: #{field}" unless result.key?(field_sym)
        end

        schema[:properties]&.each do |field, constraints|
          field_sym = field.to_sym
          next unless result.key?(field_sym)
          value = result[field_sym]

          case constraints[:type]
          when "string"
            raise ValidationError, "Field #{field} must be string, got #{value.class}" unless value.is_a?(String)
            if constraints[:enum] && !constraints[:enum].include?(value)
              raise ValidationError, "Field #{field} must be one of #{constraints[:enum]}, got #{value}"
            end
          when "number"
            raise ValidationError, "Field #{field} must be number, got #{value.class}" unless value.is_a?(Numeric)
            if constraints[:minimum] && value < constraints[:minimum]
              raise ValidationError, "Field #{field} must be >= #{constraints[:minimum]}"
            end
            if constraints[:maximum] && value > constraints[:maximum]
              raise ValidationError, "Field #{field} must be <= #{constraints[:maximum]}"
            end
          when "boolean"
            raise ValidationError, "Field #{field} must be boolean, got #{value.class}" unless [true, false].include?(value)
          end
        end

        true
      end
    end

    # Validation error for schema violations
    class ValidationError < StandardError; end
  end
end
