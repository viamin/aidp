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
    # Prompts can be customized via YAML templates at:
    # - Project level: .aidp/prompts/decision_engine/<name>.yml
    # - User level: ~/.aidp/prompts/decision_engine/<name>.yml
    # - Built-in: lib/aidp/prompts/defaults/decision_engine/<name>.yml
    #
    # @example Basic usage
    #   engine = AIDecisionEngine.new(config, provider_manager)
    #   result = engine.decide(:condition_detection,
    #     context: { error: "Rate limit exceeded" },
    #     schema: ConditionSchema,
    #     tier: "mini"
    #   )
    #   # => { condition: "rate_limit", confidence: 0.95, reasoning: "..." }
    #
    # @see docs/ZFC_COMPLIANCE_ASSESSMENT.md
    # @see docs/ZFC_IMPLEMENTATION_PLAN.md
    class AIDecisionEngine
      # Decision templates define prompts, schemas, and defaults for each decision type
      DECISION_TEMPLATES = {
        condition_detection: {
          prompt_template: <<~PROMPT,
            Analyze the following API response or error message and classify the condition.

            Response/Error:
            {{response}}

            Classify this into one of the following conditions:
            - rate_limit: API rate limiting or quota exceeded
            - auth_error: Authentication or authorization failure
            - timeout: Request timeout or network timeout
            - completion_marker: Work is complete or done
            - user_feedback_needed: AI is asking for user input/clarification
            - api_error: General API error (not rate limit/auth)
            - success: Successful response
            - other: None of the above

            Provide your classification with a confidence score (0.0 to 1.0) and brief reasoning.
          PROMPT
          schema: {
            type: "object",
            properties: {
              condition: {
                type: "string",
                enum: [
                  "rate_limit",
                  "auth_error",
                  "timeout",
                  "completion_marker",
                  "user_feedback_needed",
                  "api_error",
                  "success",
                  "other"
                ]
              },
              confidence: {
                type: "number",
                minimum: 0.0,
                maximum: 1.0
              },
              reasoning: {
                type: "string"
              }
            },
            required: ["condition", "confidence"]
          },
          default_tier: "mini",
          cache_ttl: nil  # Each response is unique
        },

        error_classification: {
          prompt_template: <<~PROMPT,
            Classify the following error and determine if it's retryable.

            Error:
            {{error_message}}

            Context:
            {{context}}

            Determine:
            1. Error type (rate_limit, auth, timeout, network, api_bug, other)
            2. Whether it's retryable (transient vs permanent)
            3. Recommended action (retry, switch_provider, escalate, fail)

            Provide classification with confidence and reasoning.
          PROMPT
          schema: {
            type: "object",
            properties: {
              error_type: {
                type: "string",
                enum: ["rate_limit", "auth", "timeout", "network", "api_bug", "other"]
              },
              retryable: {
                type: "boolean"
              },
              recommended_action: {
                type: "string",
                enum: ["retry", "switch_provider", "escalate", "fail"]
              },
              confidence: {
                type: "number",
                minimum: 0.0,
                maximum: 1.0
              },
              reasoning: {
                type: "string"
              }
            },
            required: ["error_type", "retryable", "recommended_action", "confidence"]
          },
          default_tier: "mini",
          cache_ttl: nil
        },

        completion_detection: {
          prompt_template: <<~PROMPT,
            Determine if the work described is complete based on the AI response.

            Task:
            {{task_description}}

            AI Response:
            {{response}}

            Is the work complete? Consider:
            - Explicit completion markers ("done", "finished", etc.)
            - Implicit indicators (results provided, no follow-up questions)
            - Requests for more information (incomplete)

            Provide boolean completion status with confidence and reasoning.
          PROMPT
          schema: {
            type: "object",
            properties: {
              complete: {
                type: "boolean"
              },
              confidence: {
                type: "number",
                minimum: 0.0,
                maximum: 1.0
              },
              reasoning: {
                type: "string"
              }
            },
            required: ["complete", "confidence"]
          },
          default_tier: "mini",
          cache_ttl: nil
        },

        implementation_verification: {
          prompt_template: "{{prompt}}",  # Custom prompt provided by caller
          schema: {
            type: "object",
            properties: {
              fully_implemented: {
                type: "boolean",
                description: "True if the implementation fully addresses all issue requirements"
              },
              reasoning: {
                type: "string",
                description: "Detailed explanation of the verification decision"
              },
              missing_requirements: {
                type: "array",
                items: {type: "string"},
                description: "List of specific requirements from the issue that are not yet implemented"
              },
              additional_work_needed: {
                type: "array",
                items: {type: "string"},
                description: "List of specific tasks needed to complete the implementation"
              }
            },
            required: ["fully_implemented", "reasoning", "missing_requirements", "additional_work_needed"]
          },
          default_tier: "mini",
          cache_ttl: nil
        },

        # FIX for issue #391: Prompt effectiveness evaluation for stuck work loops
        prompt_evaluation: {
          prompt_template: "{{prompt}}",  # Custom prompt provided by caller
          schema: {
            type: "object",
            properties: {
              effective: {
                type: "boolean",
                description: "True if the prompt is likely to lead to completion"
              },
              issues: {
                type: "array",
                items: {type: "string"},
                description: "Specific problems with the current prompt"
              },
              suggestions: {
                type: "array",
                items: {type: "string"},
                description: "Actionable suggestions to improve effectiveness"
              },
              likely_blockers: {
                type: "array",
                items: {type: "string"},
                description: "Potential blockers preventing progress"
              },
              confidence: {
                type: "number",
                minimum: 0.0,
                maximum: 1.0,
                description: "Confidence in this assessment"
              }
            },
            required: ["effective", "issues", "suggestions", "confidence"]
          },
          default_tier: "mini",
          cache_ttl: nil
        },

        # FIX for issue #391: Template improvement suggestions for AGD pattern
        template_improvement: {
          prompt_template: "{{prompt}}",  # Custom prompt provided by caller
          schema: {
            type: "object",
            properties: {
              improved_sections: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    section_name: {type: "string"},
                    original: {type: "string"},
                    improved: {type: "string"},
                    rationale: {type: "string"}
                  }
                }
              },
              additional_sections: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    section_name: {type: "string"},
                    content: {type: "string"},
                    rationale: {type: "string"}
                  }
                }
              },
              completion_criteria_improvements: {
                type: "array",
                items: {type: "string"},
                description: "Improvements to completion criteria definitions"
              }
            },
            required: ["improved_sections", "completion_criteria_improvements"]
          },
          default_tier: "standard",  # Use standard tier for thoughtful improvements
          cache_ttl: nil
        }
      }.freeze

      # Maps decision types to template file paths
      TEMPLATE_PATHS = {
        condition_detection: "decision_engine/condition_detection",
        error_classification: "decision_engine/error_classification",
        completion_detection: "decision_engine/completion_detection",
        implementation_verification: "decision_engine/implementation_verification",
        prompt_evaluation: "decision_engine/prompt_evaluation",
        template_improvement: "decision_engine/template_improvement"
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
      # @param schema [Hash, nil] JSON schema for response validation (overrides default)
      # @param tier [String, nil] Thinking depth tier (overrides default)
      # @param cache_ttl [Integer, nil] Cache TTL in seconds (overrides default)
      # @return [Hash] Validated decision result
      # @raise [ArgumentError] If decision_type is unknown
      # @raise [ValidationError] If response doesn't match schema
      def decide(decision_type, context:, schema: nil, tier: nil, cache_ttl: nil)
        # Get fallback template for defaults and fallback prompt
        fallback_template = DECISION_TEMPLATES[decision_type]
        raise ArgumentError, "Unknown decision type: #{decision_type}" unless fallback_template

        # Check cache if TTL specified
        cache_key = build_cache_key(decision_type, context)
        ttl = cache_ttl || fallback_template[:cache_ttl]
        if ttl && (cached_result = get_cached(cache_key, ttl))
          Aidp.log_debug("ai_decision_engine", "Cache hit for #{decision_type}", {
            cache_key: cache_key,
            ttl: ttl
          })
          return cached_result
        end

        # Load prompt from template manager, falling back to hardcoded template
        prompt = load_prompt_from_template(decision_type, context, fallback_template)

        # Select tier from template file or fallback
        selected_tier = tier || load_tier_from_template(decision_type) || fallback_template[:default_tier]

        # Get model for tier, using harness default provider
        thinking_manager = ThinkingDepthManager.new(config)
        provider_name, model_name, _model_data = thinking_manager.select_model_for_tier(
          selected_tier,
          provider: config.default_provider
        )

        Aidp.log_debug("ai_decision_engine", "Making AI decision", {
          decision_type: decision_type,
          tier: selected_tier,
          provider: provider_name,
          model: model_name,
          cache_ttl: ttl
        })

        # Call AI with schema validation
        response_schema = schema || template[:schema]
        result = call_ai_with_schema(provider_name, model_name, prompt, response_schema)

        # Validate result
        validate_schema(result, response_schema)

        # Cache if TTL specified
        if ttl
          set_cached(cache_key, result)
        end

        result
      end

      private

      # Load prompt from template manager, falling back to hardcoded template
      #
      # @param decision_type [Symbol] Decision type
      # @param context [Hash] Context variables for substitution
      # @param fallback_template [Hash] Hardcoded fallback template
      # @return [String] Rendered prompt
      def load_prompt_from_template(decision_type, context, fallback_template)
        template_path = TEMPLATE_PATHS[decision_type]
        fallback_prompt = fallback_template[:prompt_template]

        begin
          prompt = @prompt_template_manager.render(template_path, fallback: fallback_prompt, **context)

          Aidp.log_debug("ai_decision_engine", "loaded_template", {
            decision_type: decision_type,
            template_path: template_path,
            used_fallback: prompt == build_prompt(fallback_prompt, context)
          })

          prompt
        rescue Prompts::TemplateNotFoundError => e
          Aidp.log_debug("ai_decision_engine", "template_not_found_using_fallback", {
            decision_type: decision_type,
            error: e.message
          })
          build_prompt(fallback_prompt, context)
        rescue => e
          Aidp.log_warn("ai_decision_engine", "template_load_error_using_fallback", {
            decision_type: decision_type,
            error: e.message
          })
          build_prompt(fallback_prompt, context)
        end
      end

      # Load tier configuration from template file
      #
      # @param decision_type [Symbol] Decision type
      # @return [String, nil] Tier name or nil if not found
      def load_tier_from_template(decision_type)
        template_path = TEMPLATE_PATHS[decision_type]
        template_data = @prompt_template_manager.load_template(template_path)
        return nil unless template_data

        template_data["tier"] || template_data[:tier]
      rescue => e
        Aidp.log_debug("ai_decision_engine", "tier_load_error", {
          decision_type: decision_type,
          error: e.message
        })
        nil
      end

      # Build cache key from decision type and context
      def build_cache_key(decision_type, context)
        # Simple hash-based key
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

      # Build prompt from template with context substitution
      def build_prompt(template, context)
        prompt = template.dup
        context.each do |key, value|
          prompt.gsub!("{{#{key}}}", value.to_s)
        end
        prompt
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
          # Response might be a string or already structured
          response_text = response.is_a?(String) ? response : response.to_s

          # Try to extract JSON if there's extra text
          # Use non-greedy match and handle nested braces
          json_match = response_text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m) || response_text.match(/\{.*\}/m)
          json_text = json_match ? json_match[0] : response_text

          result = JSON.parse(json_text, symbolize_names: true)

          Aidp.log_debug("ai_decision_engine", "Parsed JSON successfully", {
            response_length: response_text.length,
            json_length: json_text.length,
            result_keys: result.keys,
            provider: provider_name
          })

          result
        rescue JSON::ParserError => e
          Aidp.log_error("ai_decision_engine", "Failed to parse AI response as JSON", {
            error: e.message,
            response: response_text&.slice(0, 200),
            provider: provider_name,
            model: model_name
          })
          raise ValidationError, "AI response is not valid JSON: #{e.message}"
        end
      rescue => e
        Aidp.log_error("ai_decision_engine", "Error calling AI provider", {
          error: e.message,
          provider: provider_name,
          model: model_name,
          error_class: e.class.name
        })
        raise
      end

      # Validate response against JSON schema
      def validate_schema(result, schema)
        # Basic validation of required fields and types
        # Schema uses string keys, but our result uses symbol keys from JSON parsing
        schema[:required]&.each do |field|
          field_sym = field.to_sym
          unless result.key?(field_sym)
            raise ValidationError, "Missing required field: #{field}"
          end
        end

        schema[:properties]&.each do |field, constraints|
          field_sym = field.to_sym
          next unless result.key?(field_sym)
          value = result[field_sym]

          # Type validation
          case constraints[:type]
          when "string"
            unless value.is_a?(String)
              raise ValidationError, "Field #{field} must be string, got #{value.class}"
            end
            # Enum validation
            if constraints[:enum] && !constraints[:enum].include?(value)
              raise ValidationError, "Field #{field} must be one of #{constraints[:enum]}, got #{value}"
            end
          when "number"
            unless value.is_a?(Numeric)
              raise ValidationError, "Field #{field} must be number, got #{value.class}"
            end
            # Range validation
            if constraints[:minimum] && value < constraints[:minimum]
              raise ValidationError, "Field #{field} must be >= #{constraints[:minimum]}"
            end
            if constraints[:maximum] && value > constraints[:maximum]
              raise ValidationError, "Field #{field} must be <= #{constraints[:maximum]}"
            end
          when "boolean"
            unless [true, false].include?(value)
              raise ValidationError, "Field #{field} must be boolean, got #{value.class}"
            end
          end
        end

        true
      end
    end

    # Validation error for schema violations
    class ValidationError < StandardError; end
  end
end
