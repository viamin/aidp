# frozen_string_literal: true

require "yaml"
require_relative "template_version_manager"
require_relative "../harness/ai_decision_engine"

module Aidp
  module Prompts
    # Evolves prompt templates using AGD (AI-Generated Determinism) pattern
    #
    # Per issue #402:
    # - When negative feedback is recorded, AI generates improved template variants
    # - Uses "fix forward" methodology - no rollbacks, only new improved versions
    # - Evolution is triggered automatically on negative feedback
    #
    # AGD Pattern:
    # - AI runs ONCE at configuration/evolution time to generate improved template
    # - Improved template is stored in database
    # - Runtime uses stored template deterministically (no AI calls)
    #
    # @example Evolve a template based on negative feedback
    #   evolver = TemplateEvolver.new(config)
    #   result = evolver.evolve(
    #     template_id: "work_loop/decide_whats_next",
    #     suggestions: ["Be more specific about next unit selection"],
    #     context: { iterations: 15, task_type: "refactoring" }
    #   )
    #
    class TemplateEvolver
      # Template path for evolution prompts
      EVOLUTION_TEMPLATE_PATH = "decision_engine/template_evolution"

      attr_reader :config, :version_manager, :ai_decision_engine

      def initialize(
        config,
        version_manager: nil,
        ai_decision_engine: nil,
        project_dir: Dir.pwd
      )
        @config = config
        @project_dir = project_dir
        @version_manager = version_manager ||
          TemplateVersionManager.new(project_dir: project_dir)
        @ai_decision_engine = ai_decision_engine || build_ai_decision_engine
      end

      # Evolve a template based on feedback
      #
      # @param template_id [String] Template identifier
      # @param suggestions [Array<String>] User-provided improvement suggestions
      # @param context [Hash] Additional context (iterations, task_type, etc.)
      # @return [Hash] Result with :success, :new_version_id, :changes
      def evolve(template_id:, suggestions: [], context: {})
        Aidp.log_debug("template_evolver", "starting_evolution",
          template_id: template_id,
          suggestion_count: suggestions.size)

        # Get current active version
        active_version = @version_manager.active_version(template_id: template_id)
        unless active_version
          Aidp.log_warn("template_evolver", "no_active_version",
            template_id: template_id)
          return {success: false, error: "No active version to evolve"}
        end

        # Skip if AI engine not available
        unless @ai_decision_engine
          Aidp.log_warn("template_evolver", "ai_engine_unavailable")
          return {success: false, error: "AI decision engine not available"}
        end

        # Generate improved template using AI (AGD pattern - runs once)
        evolution_result = generate_improved_template(
          current_content: active_version[:content],
          suggestions: suggestions,
          context: context
        )

        unless evolution_result[:success]
          Aidp.log_error("template_evolver", "evolution_failed",
            template_id: template_id,
            error: evolution_result[:error])
          return evolution_result
        end

        # Create new version with improved content
        create_result = @version_manager.create_evolved_version(
          template_id: template_id,
          new_content: evolution_result[:improved_content],
          parent_version_id: active_version[:id],
          metadata: {
            suggestions: suggestions,
            context: context,
            changes: evolution_result[:changes]
          }
        )

        if create_result[:success]
          Aidp.log_info("template_evolver", "evolution_complete",
            template_id: template_id,
            parent_version_id: active_version[:id],
            new_version_id: create_result[:id],
            change_count: evolution_result[:changes]&.size || 0)

          {
            success: true,
            new_version_id: create_result[:id],
            new_version_number: create_result[:version_number],
            parent_version_id: active_version[:id],
            changes: evolution_result[:changes]
          }
        else
          create_result
        end
      end

      # Batch evolve all templates needing improvement
      #
      # @return [Array<Hash>] Results for each evolved template
      def evolve_all_pending
        versions_needing = @version_manager.versions_needing_evolution

        Aidp.log_info("template_evolver", "evolving_pending_versions",
          count: versions_needing.size)

        results = []
        versions_needing.each do |version|
          # Load metadata with suggestions from negative feedback
          metadata = version[:metadata] || {}
          suggestions = metadata[:suggestions] || []
          context = metadata[:context] || {}

          result = evolve(
            template_id: version[:template_id],
            suggestions: suggestions,
            context: context
          )

          results << result.merge(template_id: version[:template_id])
        end

        results
      end

      private

      def build_ai_decision_engine
        return nil unless @config.respond_to?(:default_provider)

        Harness::AIDecisionEngine.new(@config, project_dir: @project_dir)
      rescue => e
        Aidp.log_debug("template_evolver", "ai_engine_creation_failed",
          error: e.message)
        nil
      end

      def generate_improved_template(current_content:, suggestions:, context:)
        Aidp.log_debug("template_evolver", "generating_improved_template",
          content_size: current_content.size,
          suggestion_count: suggestions.size)

        # Parse current template
        current_template = YAML.safe_load(current_content, permitted_classes: [Symbol], aliases: true)

        # Build evolution prompt
        prompt = build_evolution_prompt(
          current_template: current_template,
          suggestions: suggestions,
          context: context
        )

        schema = evolution_schema

        begin
          result = @ai_decision_engine.decide(
            :template_evolution,
            context: {prompt: prompt},
            schema: schema,
            tier: :standard,  # Use standard tier for thoughtful improvements
            cache_ttl: nil    # Each evolution is unique
          )

          # Build improved template YAML
          improved_template = apply_improvements(current_template, result)
          improved_content = YAML.dump(improved_template)

          {
            success: true,
            improved_content: improved_content,
            changes: result[:changes] || []
          }
        rescue => e
          Aidp.log_error("template_evolver", "ai_evolution_failed",
            error: e.message,
            error_class: e.class.name)

          {success: false, error: "AI evolution failed: #{e.message}"}
        end
      end

      def build_evolution_prompt(current_template:, suggestions:, context:)
        prompt_text = current_template["prompt"] || current_template[:prompt] || ""
        variables = current_template["variables"] || current_template[:variables] || []

        <<~PROMPT
          # Template Evolution Task

          You are improving a prompt template based on user feedback.

          ## Current Template

          Name: #{current_template["name"] || current_template[:name]}
          Description: #{current_template["description"] || current_template[:description]}
          Version: #{current_template["version"] || current_template[:version]}

          ### Current Prompt Text

          ```
          #{prompt_text}
          ```

          ### Variables Used

          #{variables.join(", ")}

          ## User Feedback (Suggestions for Improvement)

          #{suggestions.map { |s| "- #{s}" }.join("\n")}

          ## Context

          #{context.map { |k, v| "- #{k}: #{v}" }.join("\n")}

          ## Your Task

          Improve this template based on the feedback. Focus on:
          1. Addressing specific user suggestions
          2. Making instructions clearer and more specific
          3. Adding missing context or guidance
          4. Improving completion criteria definitions
          5. Maintaining existing variables (do not add new ones unless essential)

          Provide the improved prompt text and describe the changes made.
        PROMPT
      end

      def evolution_schema
        {
          type: "object",
          properties: {
            improved_prompt: {
              type: "string",
              description: "The improved prompt text"
            },
            changes: {
              type: "array",
              items: {type: "string"},
              description: "List of changes made to the template"
            },
            reasoning: {
              type: "string",
              description: "Reasoning for the improvements"
            }
          },
          required: ["improved_prompt", "changes"]
        }
      end

      def apply_improvements(current_template, ai_result)
        improved = current_template.dup

        # Update prompt text
        improved["prompt"] = ai_result[:improved_prompt]

        # Increment version
        current_version = improved["version"] || "1.0.0"
        improved["version"] = increment_version(current_version)

        # Update description to note this is an evolved version
        original_desc = improved["description"] || ""
        improved["description"] = "#{original_desc} (AI-evolved based on feedback)"

        improved
      end

      def increment_version(version_string)
        parts = version_string.to_s.split(".")
        parts = ["1", "0", "0"] if parts.empty?

        # Increment patch version
        parts[2] = (parts[2].to_i + 1).to_s

        parts.join(".")
      end
    end
  end
end
