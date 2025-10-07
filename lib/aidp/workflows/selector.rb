# frozen_string_literal: true

require "tty-prompt"
require_relative "definitions"
require_relative "../message_display"

module Aidp
  module Workflows
    # Enhanced workflow selector with support for custom workflows
    # Handles selection for analyze, execute, and hybrid modes
    class Selector
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new)
        @prompt = prompt
      end

      # Select mode (analyze, execute, or hybrid)
      def select_mode
        display_message("\n🚀 Welcome to AI Dev Pipeline!", type: :highlight)
        display_message("Choose your mode:\n", type: :highlight)

        choices = {
          "🔬 Analyze Mode" => :analyze,
          "🏗️  Execute Mode" => :execute,
          "🔀 Hybrid Mode" => :hybrid
        }

        @prompt.select("What would you like to do?", choices, per_page: 10)
      end

      # Select workflow for the given mode
      def select_workflow(mode)
        workflows = Definitions.workflows_for_mode(mode)

        display_message("\n#{mode_header(mode)}", type: :highlight)
        display_message("Choose a workflow:\n")

        # Build choices with icons and descriptions
        choices = workflows.map do |key, workflow|
          {
            name: "#{workflow[:icon]} #{workflow[:name]} - #{workflow[:description]}",
            value: key
          }
        end

        selected = @prompt.select(
          "Select workflow:",
          choices,
          per_page: 15,
          help: "(↑/↓ to navigate, Enter to select)"
        )

        workflow = workflows[selected]

        # Show workflow details
        display_workflow_details(workflow)

        # Handle custom workflows
        if workflow[:steps] == :custom
          steps = select_custom_steps(mode)
          {workflow_key: selected, steps: steps, workflow: workflow}
        else
          {workflow_key: selected, steps: workflow[:steps], workflow: workflow}
        end
      end

      # Select custom steps for hybrid or custom workflows
      def select_custom_steps(mode)
        display_message("\n⚙️ Custom Step Selection", type: :highlight)
        display_message("")

        if mode == :hybrid
          select_hybrid_steps
        elsif mode == :analyze
          select_steps_from_mode(:analyze)
        elsif mode == :execute
          select_steps_from_mode(:execute)
        end
      end

      private

      def mode_header(mode)
        case mode
        when :analyze
          "🔬 Analyze Mode - Understand Your Codebase"
        when :execute
          "🏗️ Execute Mode - Build New Features"
        when :hybrid
          "🔀 Hybrid Mode - Analyze Then Execute"
        end
      end

      def display_workflow_details(workflow)
        display_message("\n#{workflow[:icon]} #{workflow[:name]}", type: :highlight)
        display_message("─" * 60, type: :muted)
        display_message("")
        display_message("Description: #{workflow[:description]}")
        display_message("")
        display_message("Includes:", type: :highlight)
        workflow[:details].each do |detail|
          display_message("  • #{detail}", type: :info)
        end
        display_message("")
      end

      def select_steps_from_mode(mode)
        spec = (mode == :analyze) ? Aidp::Analyze::Steps::SPEC : Aidp::Execute::Steps::SPEC

        display_message("Available #{mode} steps:")
        display_message("")

        # Build step choices
        step_choices = spec.map do |step_key, step_spec|
          {
            name: "#{step_key} - #{step_spec["description"]}",
            value: step_key,
            disabled: step_spec["gate"] ? "(requires manual review)" : false
          }
        end

        selected_steps = @prompt.multi_select(
          "Select steps (Space to select, Enter when done):",
          step_choices,
          per_page: 20,
          help: "Select one or more steps"
        )

        if selected_steps.empty?
          display_message("⚠️  No steps selected, using default workflow", type: :warning)
          # Return a sensible default
          (mode == :analyze) ? ["01_REPOSITORY_ANALYSIS"] : ["00_PRD", "16_IMPLEMENTATION"]
        else
          selected_steps.sort
        end
      end

      def select_hybrid_steps
        display_message("You can mix analyze and execute steps for a custom hybrid workflow.")
        display_message("")

        all_steps = Definitions.all_available_steps

        # Group steps by mode for display
        step_choices = all_steps.map do |step_info|
          mode_tag = (step_info[:mode] == :analyze) ? "[ANALYZE]" : "[EXECUTE]"
          {
            name: "#{mode_tag} #{step_info[:step]} - #{step_info[:description]}",
            value: step_info[:step]
          }
        end

        selected_steps = @prompt.multi_select(
          "Select steps (Space to select, Enter when done):",
          step_choices,
          per_page: 25,
          help: "Mix analyze and execute steps as needed"
        )

        if selected_steps.empty?
          display_message("⚠️  No steps selected, using default hybrid workflow", type: :warning)
          # Return a sensible default hybrid
          ["01_REPOSITORY_ANALYSIS", "00_PRD", "16_IMPLEMENTATION"]
        else
          selected_steps.sort
        end
      end
    end
  end
end
