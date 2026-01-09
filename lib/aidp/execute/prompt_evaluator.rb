# frozen_string_literal: true

require_relative "../harness/ai_decision_engine"
require_relative "../prompts/prompt_template_manager"

module Aidp
  module Execute
    # Evaluates prompt effectiveness using ZFC after multiple iterations
    #
    # FIX for issue #391: When the work loop reaches 10+ iterations without completion,
    # this evaluator assesses prompt quality and suggests improvements.
    #
    # Uses Zero Framework Cognition (ZFC) to analyze:
    # - Whether the prompt clearly defines completion criteria
    # - If task breakdown instructions are adequate
    # - Whether the agent has sufficient context
    # - If there are blockers preventing progress
    #
    # Prompts can be customized via YAML templates at:
    # - Project level: .aidp/prompts/prompt_evaluator/<name>.yml
    # - User level: ~/.aidp/prompts/prompt_evaluator/<name>.yml
    # - Built-in: lib/aidp/prompts/defaults/prompt_evaluator/<name>.yml
    #
    # @example
    #   evaluator = PromptEvaluator.new(config)
    #   result = evaluator.evaluate(
    #     prompt_content: prompt_manager.read,
    #     iteration_count: 12,
    #     task_summary: persistent_tasklist.summary,
    #     recent_failures: all_results
    #   )
    #   # => { effective: false, issues: [...], suggestions: [...] }
    #
    class PromptEvaluator
      # Template paths for dynamic prompts
      TEMPLATE_PATHS = {
        evaluation: "prompt_evaluator/evaluation",
        improvement: "prompt_evaluator/improvement"
      }.freeze

      # Threshold for triggering evaluation
      EVALUATION_ITERATION_THRESHOLD = 10

      # Re-evaluate periodically after threshold
      EVALUATION_INTERVAL = 5

      # Expose for testability
      attr_reader :ai_decision_engine, :prompt_template_manager

      def initialize(config, ai_decision_engine: nil, prompt_template_manager: nil, project_dir: Dir.pwd)
        @config = config
        @project_dir = project_dir
        @prompt_template_manager = prompt_template_manager || Prompts::PromptTemplateManager.new(project_dir: project_dir)
        @ai_decision_engine = ai_decision_engine || safely_build_ai_decision_engine
      end

      # Safely build AIDecisionEngine, returning nil if config doesn't support it
      # This allows tests with mock configs to work without AI calls
      def safely_build_ai_decision_engine
        # Check if config supports the methods AIDecisionEngine needs
        return nil unless @config.respond_to?(:default_provider)

        build_default_ai_decision_engine
      rescue => e
        Aidp.log_debug("prompt_evaluator", "skipping_ai_decision_engine",
          reason: e.message)
        nil
      end

      # Check if evaluation should be triggered based on iteration count
      # @param iteration_count [Integer] Current iteration number
      # @return [Boolean]
      def should_evaluate?(iteration_count)
        return false unless iteration_count >= EVALUATION_ITERATION_THRESHOLD

        # Evaluate at threshold and every EVALUATION_INTERVAL after
        (iteration_count - EVALUATION_ITERATION_THRESHOLD) % EVALUATION_INTERVAL == 0
      end

      # Evaluate prompt effectiveness
      # @param prompt_content [String] Current PROMPT.md content
      # @param iteration_count [Integer] Current iteration number
      # @param task_summary [Hash] Summary of task statuses
      # @param recent_failures [Hash] Recent test/lint failures
      # @param step_name [String] Name of current step
      # @return [Hash] Evaluation result with :effective, :issues, :suggestions
      def evaluate(prompt_content:, iteration_count:, task_summary:, recent_failures:, step_name: nil)
        Aidp.log_debug("prompt_evaluator", "starting_evaluation",
          iteration: iteration_count,
          step: step_name,
          prompt_size: prompt_content&.length || 0)

        # When AI decision engine is unavailable (e.g., in tests with mock configs),
        # return a neutral result that doesn't trigger feedback appending
        unless @ai_decision_engine
          Aidp.log_debug("prompt_evaluator", "skipping_evaluation_no_ai_engine")
          return {
            effective: true,  # Assume effective to avoid unnecessary feedback
            issues: [],
            suggestions: [],
            likely_blockers: [],
            recommended_actions: [],
            confidence: 0.0,
            skipped: true,
            skip_reason: "AI decision engine not available"
          }
        end

        prompt = build_evaluation_prompt(
          prompt_content: prompt_content,
          iteration_count: iteration_count,
          task_summary: task_summary,
          recent_failures: recent_failures
        )

        schema = {
          type: "object",
          properties: {
            effective: {
              type: "boolean",
              description: "True if the prompt is likely to lead to completion within a few more iterations"
            },
            issues: {
              type: "array",
              items: {type: "string"},
              description: "Specific problems identified with the current prompt"
            },
            suggestions: {
              type: "array",
              items: {type: "string"},
              description: "Actionable suggestions to improve prompt effectiveness"
            },
            likely_blockers: {
              type: "array",
              items: {type: "string"},
              description: "Potential blockers preventing progress"
            },
            recommended_actions: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  action: {type: "string"},
                  priority: {type: "string", enum: ["high", "medium", "low"]},
                  rationale: {type: "string"}
                }
              },
              description: "Specific actions to take, prioritized"
            },
            confidence: {
              type: "number",
              minimum: 0.0,
              maximum: 1.0,
              description: "Confidence in this assessment"
            }
          },
          required: ["effective", "issues", "suggestions", "confidence"]
        }

        begin
          result = @ai_decision_engine.decide(
            :prompt_evaluation,
            context: {prompt: prompt},
            schema: schema,
            tier: :mini,
            cache_ttl: nil  # Each evaluation is context-specific
          )

          Aidp.log_info("prompt_evaluator", "evaluation_complete",
            iteration: iteration_count,
            effective: result[:effective],
            issue_count: result[:issues]&.size || 0,
            confidence: result[:confidence])

          result
        rescue => e
          Aidp.log_error("prompt_evaluator", "evaluation_failed",
            error: e.message,
            error_class: e.class.name)

          build_fallback_result("Evaluation failed: #{e.message}")
        end
      end

      # Generate improvement recommendations for the prompt template
      # Used for AGD pattern - generating improved templates based on evaluation
      # @param evaluation_result [Hash] Result from evaluate()
      # @param original_template [String] The original template content
      # @return [Hash] Template improvements
      def generate_template_improvements(evaluation_result:, original_template:)
        return nil unless @ai_decision_engine

        Aidp.log_debug("prompt_evaluator", "generating_template_improvements",
          issue_count: evaluation_result[:issues]&.size || 0)

        prompt = build_improvement_prompt(evaluation_result, original_template)

        schema = {
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
              description: "Specific improvements to completion criteria definitions"
            }
          },
          required: ["improved_sections", "completion_criteria_improvements"]
        }

        @ai_decision_engine.decide(
          :template_improvement,
          context: {prompt: prompt},
          schema: schema,
          tier: :standard,  # Use standard tier for more thoughtful improvements
          cache_ttl: nil
        )
      rescue => e
        Aidp.log_error("prompt_evaluator", "template_improvement_failed",
          error: e.message)
        nil
      end

      private

      def build_evaluation_prompt(prompt_content:, iteration_count:, task_summary:, recent_failures:)
        variables = {
          iteration_count: iteration_count.to_s,
          prompt_content: truncate_content(prompt_content, 8000),
          task_summary: format_task_summary(task_summary),
          recent_failures: format_failures(recent_failures)
        }

        @prompt_template_manager.render(TEMPLATE_PATHS[:evaluation], **variables)
      end

      def build_improvement_prompt(evaluation_result, original_template)
        variables = {
          effective: evaluation_result[:effective].to_s,
          issues: (evaluation_result[:issues] || []).join(", "),
          suggestions: (evaluation_result[:suggestions] || []).join(", "),
          original_template: truncate_content(original_template, 4000)
        }

        @prompt_template_manager.render(TEMPLATE_PATHS[:improvement], **variables)
      end

      def format_task_summary(task_summary)
        return "_No task summary available_" if task_summary.nil? || task_summary.empty?

        if task_summary.is_a?(Hash)
          parts = []
          parts << "Total: #{task_summary[:total] || 0}"
          parts << "Done: #{task_summary[:done] || 0}"
          parts << "In Progress: #{task_summary[:in_progress] || 0}"
          parts << "Pending: #{task_summary[:pending] || 0}"
          parts << "Abandoned: #{task_summary[:abandoned] || 0}"
          parts.join(" | ")
        else
          task_summary.to_s
        end
      end

      def format_failures(recent_failures)
        return "_No recent failures_" if recent_failures.nil? || recent_failures.empty?

        parts = []
        recent_failures.each do |check_type, result|
          next unless result.is_a?(Hash)

          status = result[:success] ? "✅ passed" : "❌ failed"
          parts << "- #{check_type}: #{status}"

          if !result[:success] && result[:failures]
            failures = result[:failures].take(3)
            failures.each { |f| parts << "  - #{truncate_content(f.to_s, 200)}" }
          end
        end

        parts.empty? ? "_No failures to report_" : parts.join("\n")
      end

      def truncate_content(content, max_length)
        return "_No content_" if content.nil? || content.empty?
        return content if content.length <= max_length

        "#{content[0, max_length]}\n\n[... truncated, showing first #{max_length} characters ...]"
      end

      def build_fallback_result(reason)
        {
          effective: nil,
          issues: ["Unable to evaluate: #{reason}"],
          suggestions: ["Check AI configuration and try again"],
          likely_blockers: [],
          recommended_actions: [],
          confidence: 0.0
        }
      end

      def build_default_ai_decision_engine
        Aidp::Harness::AIDecisionEngine.new(@config)
      rescue => e
        Aidp.log_warn("prompt_evaluator", "failed_to_create_ai_decision_engine",
          error: e.message)
        nil
      end
    end
  end
end
