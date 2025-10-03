# frozen_string_literal: true

require "tty-prompt"

module Aidp
  module Execute
    # Handles interactive workflow selection and project setup
    class WorkflowSelector
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new)
        @user_input = {}
        @prompt = prompt
      end

      # Main entry point for interactive workflow selection
      def select_workflow(harness_mode: false)
        if harness_mode
          # In harness mode, use default values to avoid blocking
          select_workflow_with_defaults
        else
          # Interactive mode for standalone usage
          select_workflow_interactive
        end
      end

      private

      def select_workflow_interactive
        display_message("\n🚀 Welcome to AI Dev Pipeline!", type: :highlight)
        display_message("Let's set up your development workflow.\n\n")

        # Step 1: Collect project information
        collect_project_info

        # Step 2: Choose workflow type
        workflow_type = choose_workflow_type

        # Step 3: Generate workflow steps
        steps = generate_workflow_steps(workflow_type)

        {
          workflow_type: workflow_type,
          steps: steps,
          user_input: @user_input
        }
      end

      def select_workflow_with_defaults
        display_message("\n🚀 Starting harness with default workflow configuration...", type: :highlight)

        # Use default project information
        @user_input = {
          project_description: "AI-powered development pipeline project",
          tech_stack: "Ruby/Rails",
          target_users: "developers",
          success_criteria: "Successful automation of development workflows"
        }

        # Default to exploration workflow for harness mode
        workflow_type = :exploration

        # Generate workflow steps
        steps = generate_workflow_steps(workflow_type)

        {
          workflow_type: workflow_type,
          steps: steps,
          user_input: @user_input
        }
      end

      private

      def collect_project_info
        display_message("📋 First, tell us about your project:\n", type: :highlight)

        @user_input[:project_description] = prompt_required(
          "What do you want to build? (Be specific about features and goals)"
        )

        @user_input[:tech_stack] = prompt_optional(
          "What technology stack are you using? (e.g., Ruby/Rails, Node.js, Python/Django)"
        )

        @user_input[:target_users] = prompt_optional(
          "Who are the target users? (e.g., developers, end users, internal team)"
        )

        @user_input[:success_criteria] = prompt_optional(
          "How will you know this is successful? (e.g., performance metrics, user adoption)"
        )
      end

      def choose_workflow_type
        display_message("\n🎯 Choose your development approach:\n", type: :highlight)
        display_message("1. 🔬 Exploration/Experiment - Quick prototype or proof of concept")
        display_message("   • Fast iteration, minimal documentation", type: :muted)
        display_message("   • Focus on core functionality and validation", type: :muted)
        display_message("   • Steps: PRD → Tasks → Implementation", type: :muted)
        display_message("")
        display_message("2. 🏗️  Full Development - Production-ready feature or system")
        display_message("   • Comprehensive planning and documentation", type: :muted)
        display_message("   • You can customize which steps to include", type: :muted)
        display_message("   • Full enterprise workflow available", type: :muted)
        display_message("")

        choice = prompt_choice("Which approach fits your project?", ["1", "2", "exploration", "full"])

        case choice.downcase
        when "1", "exploration"
          :exploration
        when "2", "full"
          :full
        else
          display_message("Invalid choice. Defaulting to exploration workflow.", type: :warning)
          :exploration
        end
      end

      def generate_workflow_steps(workflow_type)
        case workflow_type
        when :exploration
          exploration_workflow_steps
        when :full
          full_workflow_steps
        else
          exploration_workflow_steps
        end
      end

      def exploration_workflow_steps
        [
          "00_PRD", # Generate PRD from user input (no manual gate)
          "10_TESTING_STRATEGY", # Ensure we have tests
          "11_STATIC_ANALYSIS", # Code quality
          "16_IMPLEMENTATION" # Special step for actual development work
        ]
      end

      def full_workflow_steps
        display_message("\n🛠️ Customize your full development workflow:\n", type: :highlight)
        display_message("Select the steps you want to include (enter numbers separated by commas):\n")

        available_steps = {
          "1" => "00_PRD - Product Requirements Document",
          "2" => "01_NFRS - Non-Functional Requirements",
          "3" => "02_ARCHITECTURE - System Architecture",
          "4" => "03_ADR_FACTORY - Architecture Decision Records",
          "5" => "04_DOMAIN_DECOMPOSITION - Domain Analysis",
          "6" => "05_API_DESIGN - API and Interface Design",
          "7" => "07_SECURITY_REVIEW - Security Analysis",
          "8" => "08_PERFORMANCE_REVIEW - Performance Planning",
          "9" => "10_TESTING_STRATEGY - Testing Strategy",
          "10" => "11_STATIC_ANALYSIS - Code Quality Analysis",
          "11" => "12_OBSERVABILITY_SLOS - Monitoring & SLOs",
          "12" => "13_DELIVERY_ROLLOUT - Deployment Planning"
        }

        available_steps.each { |num, desc| display_message("  #{num}. #{desc}") }
        display_message("")

        selected = prompt_required("Enter step numbers (e.g., 1,3,5,9,10): ")
        selected_numbers = selected.split(",").map(&:strip).map(&:to_i)

        step_mapping = {
          1 => "00_PRD",
          2 => "01_NFRS",
          3 => "02_ARCHITECTURE",
          4 => "03_ADR_FACTORY",
          5 => "04_DOMAIN_DECOMPOSITION",
          6 => "05_API_DESIGN",
          7 => "07_SECURITY_REVIEW",
          8 => "08_PERFORMANCE_REVIEW",
          9 => "10_TESTING_STRATEGY",
          10 => "11_STATIC_ANALYSIS",
          11 => "12_OBSERVABILITY_SLOS",
          12 => "13_DELIVERY_ROLLOUT"
        }

        selected_steps = selected_numbers.map { |num| step_mapping[num] }.compact

        # Always ensure we have PRD and core quality steps
        core_steps = ["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS"]
        selected_steps = (core_steps + selected_steps).uniq

        # Add implementation at the end
        selected_steps << "16_IMPLEMENTATION"

        selected_steps
      end

      def prompt_required(question)
        loop do
          input = @prompt.ask("#{question}:")

          if input.nil? || input.strip.empty?
            display_message("❌ This field is required. Please provide an answer.", type: :error)
            next
          end

          return input.strip
        end
      end

      def prompt_optional(question)
        @prompt.ask("#{question} (optional):")
      end

      def prompt_choice(question, valid_choices)
        @prompt.select("#{question}:", valid_choices, per_page: valid_choices.length)
      end
    end
  end
end
