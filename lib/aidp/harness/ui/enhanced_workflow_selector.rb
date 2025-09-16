# frozen_string_literal: true

require_relative "enhanced_tui"

module Aidp
  module Harness
    module UI
      # Enhanced workflow selector with TTY components
      class EnhancedWorkflowSelector
        class WorkflowError < StandardError; end

        def initialize(tui = nil)
          @tui = tui || EnhancedTUI.new
          @user_input = {}
        end

        def select_workflow(harness_mode: false, mode: :analyze)
          if harness_mode
            select_workflow_with_defaults(mode)
          else
            select_workflow_interactive(mode)
          end
        end

        private

        def select_workflow_interactive(mode)
          case mode
          when :analyze
            select_analyze_workflow_interactive
          when :execute
            select_execute_workflow_interactive
          else
            raise ArgumentError, "Unknown mode: #{mode}"
          end
        end

        def select_workflow_with_defaults(mode)
          case mode
          when :analyze
            select_analyze_workflow_defaults
          when :execute
            select_execute_workflow_defaults
          else
            raise ArgumentError, "Unknown mode: #{mode}"
          end
        end

        def select_analyze_workflow_interactive
          # For analyze mode, we don't need complex project setup
          # Just use default values and start analysis
          @user_input = {
            project_description: "Codebase analysis",
            analysis_scope: "full",
            focus_areas: "all"
          }

          # Analyze mode uses predefined steps
          steps = Aidp::Analyze::Steps::SPEC.keys

          {
            workflow_type: :analysis,
            steps: steps,
            user_input: @user_input
          }
        end

        def select_execute_workflow_interactive
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

        def select_analyze_workflow_defaults
          @tui.show_message("🚀 Starting analyze mode with default configuration...", :info)

          @user_input = {
            project_description: "Codebase analysis",
            analysis_scope: "full",
            focus_areas: "all"
          }

          steps = Aidp::Analyze::Steps::SPEC.keys

          {
            workflow_type: :analysis,
            steps: steps,
            user_input: @user_input
          }
        end

        def select_execute_workflow_defaults
          @tui.show_message("🚀 Starting execute mode with default workflow configuration...", :info)

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
          @tui.show_message("📋 Project Setup", :info)
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

        def choose_workflow_type_interactive
          @tui.show_message("🛠️ Workflow Selection", :info)
          @tui.show_message("Choose your development approach:", :info)

          workflow_options = [
            "🔬 Exploration/Experiment - Quick prototype or proof of concept",
            "🏗️ Full Development - Production-ready feature or system"
          ]

          selected = @tui.single_select("Select workflow type", workflow_options, default: 1)
          @user_input[:workflow_type] = selected

          if selected.include?("Exploration")
            @tui.show_message("🔬 Using exploration workflow - fast iteration, minimal documentation", :info)
            :exploration
          else
            @tui.show_message("🏗️ Using full development workflow - comprehensive planning and documentation", :info)
            :full
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
          @tui.show_message("🏗️ Customize Full Workflow", :info)
          @tui.show_message("Customizing your full development workflow", :info)

          available_steps = [
            "00_PRD - Product Requirements Document (required)",
            "01_NFRS - Non-Functional Requirements (optional)",
            "02_ARCHITECTURE - System Architecture (optional)",
            "03_ADR_FACTORY - Architecture Decision Records (optional)",
            "04_DOMAIN_DECOMPOSITION - Domain Analysis (optional)",
            "05_API_DESIGN - API and Interface Design (optional)",
            "07_SECURITY_REVIEW - Security Analysis (optional)",
            "08_PERFORMANCE_REVIEW - Performance Planning (optional)",
            "10_TESTING_STRATEGY - Testing Strategy (required)",
            "11_STATIC_ANALYSIS - Code Quality Analysis (required)",
            "12_OBSERVABILITY_SLOS - Monitoring & SLOs (optional)",
            "13_DELIVERY_ROLLOUT - Deployment Planning (optional)"
          ]

          # Use TTY multiselect with required steps pre-selected
          selected = @tui.multiselect("Select steps to include in your workflow", available_steps, selected: [0, 8, 9])

          # Convert back to step keys
          selected_steps = selected.map do |step_name|
            step_name.split(" - ").first
          end

          # Add implementation at the end
          selected_steps << "16_IMPLEMENTATION"

          @tui.show_message("✅ Selected #{selected_steps.length} steps for your workflow", :success)
          selected_steps
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
