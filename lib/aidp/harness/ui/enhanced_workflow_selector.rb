# frozen_string_literal: true

require_relative "enhanced_tui"

module Aidp
  module Harness
    module UI
      # Enhanced workflow selector with modern CLI::UI interface
      class EnhancedWorkflowSelector
        class WorkflowError < StandardError; end

        def initialize(tui = nil)
          @tui = tui || EnhancedTUI.new
          @user_input = {}
        end

        def select_workflow(harness_mode: false)
          if harness_mode
            select_workflow_with_defaults
          else
            select_workflow_interactive
          end
        end

        private

        def select_workflow_interactive
          # Step 1: Collect project information
          collect_project_info_interactive

          # Step 2: Choose workflow type
          workflow_type = choose_workflow_type_interactive

          # Step 3: Generate workflow steps
          steps = generate_workflow_steps_interactive(workflow_type)

          {
            workflow_type: workflow_type,
            steps: steps,
            user_input: @user_input
          }
        end

        def select_workflow_with_defaults
          @tui.show_message("🚀 Starting harness with default workflow configuration...", :info)

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

        def collect_project_info_interactive
          ::CLI::UI::Frame.open("📋 Project Setup") do
            @tui.show_message("Let's set up your development workflow", :info)

            @user_input[:project_description] = @tui.get_user_input("What do you want to build? (Be specific about features and goals)")
            @tui.show_message("✅ Project description captured", :success)

            @user_input[:tech_stack] = @tui.get_user_input("What technology stack are you using? (e.g., Ruby/Rails, Node.js, Python/Django) [optional]")
            @tui.show_message("✅ Tech stack captured", :success)

            @user_input[:target_users] = @tui.get_user_input("Who are the target users? (e.g., developers, end users, internal team) [optional]")
            @tui.show_message("✅ Target users captured", :success)

            @user_input[:success_criteria] = @tui.get_user_input("How will you know this is successful? (e.g., performance metrics, user adoption) [optional]")
            @tui.show_message("✅ Success criteria captured", :success)
          end
        end

        def choose_workflow_type_interactive
          ::CLI::UI::Frame.open("🛠️ Workflow Selection") do
            @tui.show_message("Choose your development approach:", :info)

            workflow_type = ::CLI::UI::Prompt.ask("Select workflow type:") do |handler|
              handler.option("🔬 Exploration/Experiment - Quick prototype or proof of concept") { :exploration }
              handler.option("🏗️ Full Development - Production-ready feature or system") { :full }
            end

            case workflow_type
            when :exploration
              @tui.show_message("🔬 Using exploration workflow - fast iteration, minimal documentation", :info)
            when :full
              @tui.show_message("🏗️ Using full development workflow - comprehensive planning and documentation", :info)
            else
              @tui.show_message("Defaulting to exploration workflow", :warning)
              workflow_type = :exploration
            end

            workflow_type
          end
        end

        def generate_workflow_steps_interactive(workflow_type)
          case workflow_type
          when :exploration
            generate_exploration_steps
          when :full
            generate_full_steps_interactive
          else
            generate_exploration_steps
          end
        end

        def generate_exploration_steps
          @tui.show_message("🔬 Using exploration workflow - fast iteration, minimal documentation", :info)
          [
            "00_PRD",           # Generate PRD from user input (no manual gate)
            "10_TESTING_STRATEGY", # Ensure we have tests
            "11_STATIC_ANALYSIS",  # Code quality
            "16_IMPLEMENTATION"    # Special step for actual development work
          ]
        end

        def generate_full_steps_interactive
          ::CLI::UI::Frame.open("🏗️ Customize Full Workflow") do
            @tui.show_message("Customizing your full development workflow", :info)

            # Use CLI::UI's multiselect-like interface
            selected_steps = []

            available_steps = [
              { key: "00_PRD", name: "00_PRD - Product Requirements Document", required: true },
              { key: "01_NFRS", name: "01_NFRS - Non-Functional Requirements", required: false },
              { key: "02_ARCHITECTURE", name: "02_ARCHITECTURE - System Architecture", required: false },
              { key: "03_ADR_FACTORY", name: "03_ADR_FACTORY - Architecture Decision Records", required: false },
              { key: "04_DOMAIN_DECOMPOSITION", name: "04_DOMAIN_DECOMPOSITION - Domain Analysis", required: false },
              { key: "05_API_DESIGN", name: "05_API_DESIGN - API and Interface Design", required: false },
              { key: "07_SECURITY_REVIEW", name: "07_SECURITY_REVIEW - Security Analysis", required: false },
              { key: "08_PERFORMANCE_REVIEW", name: "08_PERFORMANCE_REVIEW - Performance Planning", required: false },
              { key: "10_TESTING_STRATEGY", name: "10_TESTING_STRATEGY - Testing Strategy", required: true },
              { key: "11_STATIC_ANALYSIS", name: "11_STATIC_ANALYSIS - Code Quality Analysis", required: true },
              { key: "12_OBSERVABILITY_SLOS", name: "12_OBSERVABILITY_SLOS - Monitoring & SLOs", required: false },
              { key: "13_DELIVERY_ROLLOUT", name: "13_DELIVERY_ROLLOUT - Deployment Planning", required: false }
            ]

            # Show available steps
            ::CLI::UI.puts "{{bold:Available steps:}}"
            available_steps.each_with_index do |step, index|
              required_marker = step[:required] ? "{{red:(required)}}" : "{{dim:(optional)}}"
              ::CLI::UI.puts "  #{index + 1}. #{step[:name]} #{required_marker}"
            end

            ::CLI::UI.puts

            # Get user selection
            selection = ::CLI::UI::Prompt.ask("Enter step numbers to include (comma-separated, e.g., 1,3,5,9,10):")

            if selection && !selection.strip.empty?
              selected_numbers = selection.split(",").map(&:strip).map(&:to_i)
              selected_steps = selected_numbers.map { |num| available_steps[num - 1] }.compact.map { |step| step[:key] }
            end

            # Always ensure we have required steps
            required_steps = available_steps.select { |step| step[:required] }.map { |step| step[:key] }
            selected_steps = (required_steps + selected_steps).uniq

            # Add implementation at the end
            selected_steps << "16_IMPLEMENTATION"

            @tui.show_message("✅ Selected #{selected_steps.length} steps for your workflow", :success)
            selected_steps
          end
        end

        def generate_workflow_steps(workflow_type)
          case workflow_type
          when :exploration
            generate_exploration_steps
          when :full
            generate_full_steps
          else
            generate_exploration_steps
          end
        end

        def generate_full_steps
          # Default full workflow steps
          [
            "00_PRD",
            "01_NFRS",
            "02_ARCHITECTURE",
            "03_ADR_FACTORY",
            "04_DOMAIN_DECOMPOSITION",
            "05_API_DESIGN",
            "07_SECURITY_REVIEW",
            "08_PERFORMANCE_REVIEW",
            "10_TESTING_STRATEGY",
            "11_STATIC_ANALYSIS",
            "12_OBSERVABILITY_SLOS",
            "13_DELIVERY_ROLLOUT",
            "16_IMPLEMENTATION"
          ]
        end
      end
    end
  end
end
