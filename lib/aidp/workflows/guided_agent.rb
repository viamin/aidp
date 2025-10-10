# frozen_string_literal: true

require_relative "../harness/provider_manager"
require_relative "../harness/provider_factory"
require_relative "../harness/config_manager"
require_relative "definitions"
require_relative "../message_display"

module Aidp
  module Workflows
    # Guided workflow agent that uses AI to help users select appropriate workflows
    # Acts as a copilot to match user intent to AIDP capabilities
    class GuidedAgent
      include Aidp::MessageDisplay

      class ConversationError < StandardError; end

      def initialize(project_dir, prompt: nil)
        @project_dir = project_dir
        @prompt = prompt || TTY::Prompt.new
        @config_manager = Aidp::Harness::ConfigManager.new(project_dir)
        @provider_manager = Aidp::Harness::ProviderManager.new(@config_manager, prompt: @prompt)
        @conversation_history = []
        @user_input = {}
      end

      # Main entry point for guided workflow selection
      def select_workflow
        display_message("\n🤖 Welcome to AIDP Guided Workflow!", type: :highlight)
        display_message("I'll help you choose the right workflow for your needs.\n", type: :info)

        # Step 1: Get user's high-level goal
        goal = user_goal

        # Step 2: Use AI to analyze intent and recommend workflow
        recommendation = analyze_user_intent(goal)

        # Step 3: Present recommendation and get confirmation
        workflow_selection = present_recommendation(recommendation)

        # Step 4: Collect any additional required information
        collect_workflow_details(workflow_selection)

        workflow_selection
      rescue => e
        raise ConversationError, "Failed to guide workflow selection: #{e.message}"
      end

      private

      def user_goal
        display_message("What would you like to do?", type: :highlight)
        display_message("Examples:", type: :muted)
        display_message("  • Build a new feature for user authentication", type: :muted)
        display_message("  • Understand how this codebase handles payments", type: :muted)
        display_message("  • Improve test coverage in my API layer", type: :muted)
        display_message("  • Create a quick prototype for data export\n", type: :muted)

        goal = @prompt.ask("Your goal:", required: true)
        @user_input[:original_goal] = goal
        goal
      end

      def analyze_user_intent(user_goal)
        display_message("\n🔍 Analyzing your request...", type: :info)

        # Build the system prompt with AIDP capabilities
        system_prompt = build_system_prompt

        # Build the user prompt
        user_prompt = build_analysis_prompt(user_goal)

        # Call provider to analyze intent
        response = call_provider_for_analysis(system_prompt, user_prompt)

        # Parse the response
        parse_recommendation(response)
      end

      def build_system_prompt
        # Try to load from project dir first, fall back to gem's docs
        capabilities_path = File.join(@project_dir, "docs", "AIDP_CAPABILITIES.md")
        unless File.exist?(capabilities_path)
          # Use the gem's copy
          gem_root = File.expand_path("../../..", __dir__)
          capabilities_path = File.join(gem_root, "docs", "AIDP_CAPABILITIES.md")
        end

        capabilities_doc = File.read(capabilities_path)

        <<~PROMPT
          You are an expert AI assistant helping users select the right AIDP workflow for their needs.

          Your role:
          1. Understand what the user wants to accomplish
          2. Match their intent to AIDP's capabilities
          3. Recommend the most appropriate workflow
          4. Explain why this workflow fits their needs
          5. Identify if custom steps or templates are needed

          AIDP Capabilities Reference:
          #{capabilities_doc}

          Response Format:
          Provide a JSON response with:
          {
            "mode": "analyze|execute|hybrid",
            "workflow_key": "specific_workflow_key",
            "reasoning": "brief explanation of why this fits",
            "additional_steps": ["any", "custom", "steps", "if", "needed"],
            "questions": ["any", "clarifying", "questions"],
            "confidence": "high|medium|low"
          }

          Be concise to preserve the user's context window.
        PROMPT
      end

      def build_analysis_prompt(user_goal)
        <<~PROMPT
          User Goal: #{user_goal}

          Analyze this goal and recommend the most appropriate AIDP workflow.
          Consider:
          - Is this analysis or development?
          - What level of rigor is needed?
          - Are there any gaps in existing workflows?

          Provide your recommendation in JSON format.
        PROMPT
      end

      def call_provider_for_analysis(system_prompt, user_prompt)
        # Get current provider from provider manager
        provider_name = @provider_manager.current_provider

        unless provider_name
          raise ConversationError, "No provider configured for guided workflow"
        end

        # Create provider instance using ProviderFactory
        provider_factory = Aidp::Harness::ProviderFactory.new(@config_manager)
        provider = provider_factory.create_provider(provider_name, prompt: @prompt)

        unless provider
          raise ConversationError, "Failed to create provider instance for #{provider_name}"
        end

        # Make the request - combine system and user prompts
        combined_prompt = "#{system_prompt}\n\n#{user_prompt}"

        result = provider.send(prompt: combined_prompt)

        unless result[:status] == :success
          raise ConversationError, "Provider request failed: #{result[:error]}"
        end

        result[:content]
      end

      def parse_recommendation(response_text)
        # Extract JSON from response (might be wrapped in markdown code blocks)
        json_match = response_text.match(/```json\s*(\{.*?\})\s*```/m) ||
          response_text.match(/(\{.*\})/m)

        unless json_match
          raise ConversationError, "Could not parse recommendation from response"
        end

        JSON.parse(json_match[1], symbolize_names: true)
      rescue JSON::ParserError => e
        raise ConversationError, "Invalid JSON in recommendation: #{e.message}"
      end

      def present_recommendation(recommendation)
        display_message("\n✨ Recommendation", type: :highlight)
        display_message("─" * 60, type: :muted)

        mode = recommendation[:mode].to_sym
        workflow_key = recommendation[:workflow_key].to_sym

        # Get workflow details
        workflow = Definitions.get_workflow(mode, workflow_key)

        unless workflow
          # Handle custom workflow or error
          return handle_custom_workflow(recommendation)
        end

        # Display the recommendation
        display_message("Mode: #{mode.to_s.capitalize}", type: :info)
        display_message("Workflow: #{workflow[:name]}", type: :info)
        display_message("\n#{workflow[:description]}", type: :muted)
        display_message("\nReasoning: #{recommendation[:reasoning]}\n", type: :info)

        # Show what's included
        display_message("This workflow includes:", type: :highlight)
        workflow[:details].each do |detail|
          display_message("  • #{detail}", type: :info)
        end

        # Handle additional steps if needed
        steps = workflow[:steps]
        if recommendation[:additional_steps]&.any?
          display_message("\nAdditional custom steps recommended:", type: :highlight)
          recommendation[:additional_steps].each do |step|
            display_message("  • #{step}", type: :info)
          end
          steps = workflow[:steps] + recommendation[:additional_steps]
        end

        # Ask for confirmation
        display_message("")
        confirmed = @prompt.yes?("Does this workflow fit your needs?")

        if confirmed
          {
            mode: mode,
            workflow_key: workflow_key,
            workflow_type: workflow_key,
            steps: steps,
            user_input: @user_input,
            workflow: workflow
          }
        else
          # Offer alternatives
          offer_alternatives(mode)
        end
      end

      def handle_custom_workflow(recommendation)
        display_message("\n💡 Custom Workflow Needed", type: :highlight)
        display_message("The AI recommends creating a custom workflow:\n", type: :info)
        display_message(recommendation[:reasoning], type: :muted)

        if recommendation[:questions]&.any?
          display_message("\nLet me gather some more information:\n", type: :highlight)
          recommendation[:questions].each do |question|
            answer = @prompt.ask(question)
            @user_input[question.downcase.gsub(/\s+/, "_").to_sym] = answer
          end
        end

        # Let user select from available steps
        mode = recommendation[:mode].to_sym
        display_message("\nLet's build a custom workflow by selecting specific steps:", type: :info)

        steps = select_custom_steps(mode, recommendation[:additional_steps])

        {
          mode: mode,
          workflow_key: :custom,
          workflow_type: :custom,
          steps: steps,
          user_input: @user_input,
          workflow: {
            name: "Custom Workflow",
            description: recommendation[:reasoning],
            details: steps
          }
        }
      end

      def select_custom_steps(mode, suggested_steps = [])
        # Get available steps for the mode
        spec = case mode
        when :analyze
          Aidp::Analyze::Steps::SPEC
        when :execute
          Aidp::Execute::Steps::SPEC
        when :hybrid
          # Combine both
          Aidp::Analyze::Steps::SPEC.merge(Aidp::Execute::Steps::SPEC)
        else
          {}
        end

        step_choices = spec.map do |step_key, step_spec|
          {
            name: "#{step_key} - #{step_spec["description"]}",
            value: step_key
          }
        end

        # Pre-select suggested steps
        default_indices = suggested_steps.map do |step|
          step_choices.index { |choice| choice[:value].to_s == step.to_s }
        end.compact

        selected_steps = @prompt.multi_select(
          "Select steps for your custom workflow:",
          step_choices,
          default: default_indices,
          per_page: 20
        )

        selected_steps.empty? ? suggested_steps : selected_steps
      end

      def offer_alternatives(current_mode)
        display_message("\n🔄 Let's find a better fit", type: :highlight)

        choices = [
          {name: "Try a different #{current_mode} workflow", value: :different_workflow},
          {name: "Switch to a different mode", value: :different_mode},
          {name: "Build a custom workflow", value: :custom},
          {name: "Start over", value: :restart}
        ]

        choice = @prompt.select("What would you like to do?", choices)

        case choice
        when :different_workflow
          select_manual_workflow(current_mode)
        when :different_mode
          # Let user pick mode manually then workflow
          new_mode = @prompt.select(
            "Select mode:",
            {
              "🔬 Analyze Mode" => :analyze,
              "🏗️  Execute Mode" => :execute,
              "🔀 Hybrid Mode" => :hybrid
            }
          )
          select_manual_workflow(new_mode)
        when :custom
          select_custom_steps(current_mode)
        when :restart
          select_workflow # Recursive call to start over
        end
      end

      def select_manual_workflow(mode)
        workflows = Definitions.workflows_for_mode(mode)

        choices = workflows.map do |key, workflow|
          {
            name: "#{workflow[:icon]} #{workflow[:name]} - #{workflow[:description]}",
            value: key
          }
        end

        selected_key = @prompt.select("Choose a workflow:", choices, per_page: 15)
        workflow = workflows[selected_key]

        {
          mode: mode,
          workflow_key: selected_key,
          workflow_type: selected_key,
          steps: workflow[:steps],
          user_input: @user_input,
          workflow: workflow
        }
      end

      def collect_workflow_details(workflow_selection)
        # Collect additional information based on mode
        case workflow_selection[:mode]
        when :execute
          collect_execute_details
        when :analyze
          # Analyze mode typically doesn't need much user input
          @user_input[:analysis_goal] = @user_input[:original_goal]
        when :hybrid
          collect_execute_details # Hybrid often needs project details
        end

        # Update the workflow selection with collected input
        workflow_selection[:user_input] = @user_input
      end

      def collect_execute_details
        return if @user_input[:project_description] # Already collected

        display_message("\n📝 Project Information", type: :highlight)
        display_message("Let me gather some details for the PRD:\n", type: :info)

        @user_input[:project_description] = @prompt.ask(
          "Describe what you're building (can reference your original goal):",
          default: @user_input[:original_goal]
        )

        @user_input[:tech_stack] = @prompt.ask(
          "Tech stack (e.g., Ruby/Rails, Node.js, Python)? [optional]",
          required: false
        )

        @user_input[:target_users] = @prompt.ask(
          "Who will use this? [optional]",
          required: false
        )

        @user_input[:success_criteria] = @prompt.ask(
          "How will you measure success? [optional]",
          required: false
        )
      end
    end
  end
end
