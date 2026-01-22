# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that creates the initial PROMPT.md for a work loop
      # Assembles context, instructions, and constraints
      class CreatePromptActivity < BaseActivity

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            step_name = input[:step_name]
            step_spec = input[:step_spec] || {}
            context = input[:context] || {}

            log_activity("creating_prompt",
              project_dir: project_dir,
              step_name: step_name)

            # Load configuration
            config = load_config(project_dir)

            # Create prompt manager
            prompt_manager = Aidp::Execute::PromptManager.new(project_dir, config: config)

            # Build initial prompt content
            prompt_content = build_prompt_content(
              project_dir: project_dir,
              step_name: step_name,
              step_spec: step_spec,
              context: context
            )

            # Write the prompt
            prompt_manager.write(prompt_content)

            heartbeat(phase: "prompt_created", step_name: step_name)

            success_result(
              prompt_path: prompt_manager.prompt_path,
              prompt_length: prompt_content.length,
              step_name: step_name
            )
          end
        end

        private

        def build_prompt_content(project_dir:, step_name:, step_spec:, context:)
          sections = []

          # Header
          sections << "# Implementation Task: #{step_name}"
          sections << ""
          sections << "Generated at: #{Time.now.iso8601}"
          sections << ""

          # Step specification
          if step_spec[:description]
            sections << "## Objective"
            sections << ""
            sections << step_spec[:description]
            sections << ""
          end

          # Context from previous steps
          if context[:previous_output]
            sections << "## Context from Previous Steps"
            sections << ""
            sections << context[:previous_output]
            sections << ""
          end

          # Requirements
          if context[:requirements]&.any?
            sections << "## Requirements"
            sections << ""
            context[:requirements].each do |req|
              sections << "- #{req}"
            end
            sections << ""
          end

          # Constraints
          sections << "## Constraints"
          sections << ""
          sections << "- Follow the existing code style and patterns"
          sections << "- Make minimal changes to achieve the objective"
          sections << "- Ensure all tests pass after changes"
          sections << "- Do not introduce new dependencies without justification"
          sections << ""

          # Style guide reference
          style_guide_path = File.join(project_dir, "docs", "LLM_STYLE_GUIDE.md")
          if File.exist?(style_guide_path)
            sections << "## Style Guide"
            sections << ""
            sections << "Please follow the guidelines in `docs/LLM_STYLE_GUIDE.md`"
            sections << ""
          end

          # Instructions
          sections << "## Instructions"
          sections << ""
          sections << "1. Review the existing codebase to understand context"
          sections << "2. Implement the changes described in the objective"
          sections << "3. Ensure all tests pass"
          sections << "4. Signal completion when done"
          sections << ""

          sections.join("\n")
        end
      end
    end
  end
end
