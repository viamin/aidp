# frozen_string_literal: true

require_relative "../../logger"
require "yaml"

module Aidp
  module Planning
    module Mappers
      # Maps tasks to personas using Zero Framework Cognition (ZFC)
      # NO heuristics, NO regex, NO keyword matching - pure AI decision making
      class PersonaMapper
        def initialize(ai_decision_engine:, config: nil, mode: :waterfall)
          @ai_decision_engine = ai_decision_engine
          @config = config
          @mode = mode
        end

        # Assign personas to tasks using ZFC
        # @param task_list [Array<Hash>] List of tasks to assign
        # @param available_personas [Array<String>] Available persona names
        # @return [Hash] Persona assignments
        def assign_personas(task_list, available_personas: nil)
          Aidp.log_debug("persona_mapper", "assign_personas", task_count: task_list.size)

          available_personas ||= default_personas

          assignments = {}

          task_list.each do |task|
            persona = assign_task_to_persona(task, available_personas)
            assignments[task[:id] || task[:name]] = {
              persona: persona,
              task: task[:name],
              phase: task[:phase],
              rationale: "AI-determined based on task characteristics"
            }

            Aidp.log_debug("persona_mapper", "assigned", task: task[:name], persona: persona)
          end

          {
            assignments: assignments,
            metadata: {
              generated_at: Time.now.iso8601,
              total_assignments: assignments.size,
              personas_used: assignments.values.map { |a| a[:persona] }.uniq
            }
          }
        end

        # Generate persona_map.yml configuration
        # @param assignments [Hash] Persona assignments
        # @return [String] YAML configuration
        def generate_persona_map(assignments)
          Aidp.log_debug("persona_mapper", "generate_persona_map")

          config = {
            "version" => "1.0",
            "generated_at" => Time.now.iso8601,
            "assignments" => format_assignments_for_yaml(assignments[:assignments])
          }

          YAML.dump(config)
        end

        private

        # Assign a single task to the best persona using AI decision engine
        # This is the ZFC pattern - meaning/decisions go to AI, not code
        def assign_task_to_persona(task, available_personas)
          Aidp.log_debug("persona_mapper", "assign_task", task: task[:name])

          # Use AI decision engine to determine best persona
          # NO regex, NO keyword matching, NO heuristics!
          decision = @ai_decision_engine.decide(
            context: "persona assignment",
            prompt: build_assignment_prompt(task, available_personas),
            data: {
              task_name: task[:name],
              task_description: task[:description],
              task_phase: task[:phase],
              task_effort: task[:effort],
              available_personas: available_personas
            },
            schema: {
              type: "string",
              enum: available_personas
            }
          )

          Aidp.log_debug("persona_mapper", "ai_decision", persona: decision)
          decision
        end

        def build_assignment_prompt(task, personas)
          <<~PROMPT
            Assign this task to the most appropriate persona based on the task characteristics.

            Task: #{task[:name]}
            Description: #{task[:description]}
            Phase: #{task[:phase]}
            Effort: #{task[:effort]}

            Available Personas: #{personas.join(", ")}

            Consider:
            - Task type and complexity
            - Required skills and expertise
            - Phase of project (requirements, design, implementation, etc.)
            - Technical vs. product focus

            Return ONLY the persona name, nothing else.
          PROMPT
        end

        def default_personas
          case @mode
          when :agile
            agile_personas
          when :waterfall
            waterfall_personas
          else
            waterfall_personas # Default to waterfall
          end
        end

        def waterfall_personas
          [
            "product_strategist",
            "architect",
            "senior_developer",
            "qa_engineer",
            "devops_engineer",
            "tech_writer"
          ]
        end

        def agile_personas
          [
            "product_manager",
            "ux_researcher",
            "architect",
            "senior_developer",
            "qa_engineer",
            "devops_engineer",
            "tech_writer",
            "marketing_strategist"
          ]
        end

        def format_assignments_for_yaml(assignments)
          assignments.transform_values do |assignment|
            {
              "persona" => assignment[:persona],
              "task" => assignment[:task],
              "phase" => assignment[:phase]
            }
          end
        end
      end
    end
  end
end
