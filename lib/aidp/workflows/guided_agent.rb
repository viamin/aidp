# frozen_string_literal: true

require_relative "../harness/provider_manager"
require_relative "../harness/provider_factory"
require_relative "../harness/config_manager"
require_relative "definitions"
require_relative "../message_display"
require_relative "../debug_mixin"
require_relative "../cli/enhanced_input"

module Aidp
  module Workflows
    # Guided workflow agent that uses AI to help users select appropriate workflows
    # Acts as a copilot to match user intent to AIDP capabilities
    class GuidedAgent
      include Aidp::MessageDisplay
      include Aidp::DebugMixin

      class ConversationError < StandardError; end

      def initialize(project_dir, prompt: nil, use_enhanced_input: true)
        @project_dir = project_dir

        # Use EnhancedInput with Reline for full readline-style key bindings
        @prompt = if use_enhanced_input && prompt.nil?
          Aidp::CLI::EnhancedInput.new
        else
          prompt || TTY::Prompt.new
        end

        @config_manager = Aidp::Harness::ConfigManager.new(project_dir)
        @provider_manager = Aidp::Harness::ProviderManager.new(@config_manager, prompt: @prompt)
        @conversation_history = []
        @user_input = {}
      end

      # Main entry point for guided workflow selection
      # Uses plan-then-execute approach: iterative planning conversation
      # to identify needed steps, then executes those steps
      def select_workflow
        display_message("\n🤖 Welcome to AIDP Guided Workflow!", type: :highlight)
        display_message("I'll help you plan and execute your project.\n", type: :info)

        validate_provider_configuration!

        plan_and_execute_workflow
      rescue => e
        raise ConversationError, "Failed to guide workflow selection: #{e.message}"
      end

      private

      # Plan-and-execute: iterative planning followed by execution
      def plan_and_execute_workflow
        display_message("\n📋 Plan Phase", type: :highlight)
        display_message("I'll ask clarifying questions to understand your needs.\n", type: :info)

        # Step 1: Iterative planning conversation
        plan = iterative_planning

        # Step 2: Identify needed steps based on plan
        needed_steps = identify_steps_from_plan(plan)

        # Step 3: Generate planning documents from plan
        generate_documents_from_plan(plan)

        # Step 4: Build workflow selection
        build_workflow_from_plan(plan, needed_steps)
      end

      def iterative_planning
        goal = user_goal
        plan = {goal: goal, scope: {}, users: {}, requirements: {}, constraints: {}, completion_criteria: []}

        @conversation_history << {role: "user", content: goal}

        iteration = 0
        loop do
          iteration += 1
          # Ask AI for next question based on current plan
          question_response = get_planning_questions(plan)

          # Debug: show raw provider response and parsed result
          debug_log("Planning iteration #{iteration} provider response", level: :debug, data: {
            raw_response: question_response[:raw_response]&.inspect,
            parsed: question_response.inspect
          })

          # If AI says plan is complete, confirm with user
          if question_response[:complete]
            display_message("\n✅ Plan Summary", type: :highlight)
            display_plan_summary(plan)

            if @prompt.yes?("\nIs this plan ready for execution?")
              break
            else
              # Continue planning
              question_response = {questions: ["What would you like to add or clarify?"]}
            end
          end

          # Ask questions
          question_response[:questions]&.each do |question|
            answer = @prompt.ask(question)
            @conversation_history << {role: "assistant", content: question}
            @conversation_history << {role: "user", content: answer}

            # Update plan with answer
            update_plan_from_answer(plan, question, answer)
          end

          # Guard: break loop after 10 iterations to avoid infinite loop
          if iteration >= 10
            display_message("[ERROR] Planning loop exceeded 10 iterations. Provider may be returning generic responses.", type: :error)
            break
          end
        end

        plan
      end

      def get_planning_questions(plan)
        system_prompt = build_planning_system_prompt
        user_prompt = build_planning_prompt(plan)

        # If requirements are already detailed, ask provider to check for completion
        requirements = plan[:requirements]
        requirements_detailed = requirements.is_a?(Hash) && requirements.values.flatten.any? { |r| r.length > 50 }
        if requirements_detailed
          user_prompt += "\n\nNOTE: Requirements have been provided in detail above. If you have enough information, set 'complete' to true. Do not repeat the same requirements question."
        end

        response = call_provider_for_analysis(system_prompt, user_prompt)
        parsed = parse_planning_response(response)
        # Attach raw response for debug
        parsed[:raw_response] = response
        parsed
      end

      def identify_steps_from_plan(plan)
        display_message("\n🔍 Identifying needed steps...", type: :info)

        system_prompt = build_step_identification_prompt
        user_prompt = build_plan_summary_for_step_identification(plan)

        response = call_provider_for_analysis(system_prompt, user_prompt)
        parse_step_identification(response)
      end

      def generate_documents_from_plan(plan)
        display_message("\n📝 Generating planning documents...", type: :info)

        # Generate PRD
        generate_prd_from_plan(plan)

        # Generate NFRs if applicable
        generate_nfr_from_plan(plan) if plan.dig(:requirements, :non_functional)

        # Generate style guide if applicable
        generate_style_guide_from_plan(plan) if plan[:style_requirements]

        display_message("  ✓ Documents generated", type: :success)
      end

      def build_workflow_from_plan(plan, needed_steps)
        # Filter out any unknown steps to avoid nil dereference if SPEC changed or an AI hallucinated a step key
        execute_spec = Aidp::Execute::Steps::SPEC
        unknown_steps = needed_steps.reject { |s| execute_spec.key?(s) }
        if unknown_steps.any?
          display_message("⚠️  Ignoring unknown execute steps: #{unknown_steps.join(", ")}", type: :warning)
          needed_steps -= unknown_steps
        end

        details = needed_steps.map { |step| execute_spec[step]["description"] }

        {
          mode: :execute,
          workflow_key: :plan_and_execute,
          workflow_type: :plan_and_execute,
          steps: needed_steps,
          user_input: @user_input.merge(plan: plan),
          workflow: {
            name: "Plan & Execute",
            description: "Custom workflow from iterative planning",
            details: details
          },
          completion_criteria: plan[:completion_criteria]
        }
      end

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
        attempts = 0
        max_attempts = (@provider_manager.respond_to?(:configured_providers) ? @provider_manager.configured_providers.size : 2)
        max_attempts = 2 if max_attempts < 2 # at least one retry if a fallback exists

        begin
          attempts += 1

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

          combined_prompt = "#{system_prompt}\n\n#{user_prompt}"
          result = provider.send(prompt: combined_prompt)

          if result.nil? || result.empty?
            raise ConversationError, "Provider request failed: empty response"
          end

          result
        rescue => e
          message = e.message.to_s
          classified = if message =~ /resource[_ ]exhausted/i || message =~ /\[resource_exhausted\]/i
            "resource_exhausted"
          elsif message =~ /quota[_ ]exceeded/i || message =~ /\[quota_exceeded\]/i
            "quota_exceeded"
          end

          if classified && attempts < max_attempts
            display_message("⚠️  Provider '#{provider_name}' #{classified.tr("_", " ")} – attempting fallback...", type: :warning)
            switched = @provider_manager.switch_provider_for_error(classified, stderr: message) if @provider_manager.respond_to?(:switch_provider_for_error)
            if switched && switched != provider_name
              display_message("↩️  Switched to provider '#{switched}'", type: :info)
              retry
            end
          end
          raise
        end
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

      def validate_provider_configuration!
        configured = @provider_manager.configured_providers
        if configured.nil? || configured.empty?
          raise ConversationError, <<~MSG.strip
            No providers are configured. Create an aidp.yml with at least one provider, for example:
            
            harness:\n  enabled: true\n  default_provider: claude\nproviders:\n  claude:\n    type: api\n    api_key: "${AIDP_CLAUDE_API_KEY}"\n    models:\n      - claude-3-5-sonnet-20241022
          MSG
        end

        default = @provider_manager.current_provider
        unless default && configured.include?(default)
          raise ConversationError, "Default provider '#{default || "(nil)"}' not found in configured providers: #{configured.join(", ")}"
        end
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

      # Plan-then-execute helper methods

      def build_planning_system_prompt
        <<~PROMPT
          You are a planning assistant helping gather requirements through clarifying questions.

          Your role:
          1. Ask 1-3 targeted questions at a time based on what's known
          2. Build towards a complete understanding of: scope, users, requirements, constraints
          3. Determine when enough information has been gathered
          4. Be concise to preserve context window

          Response Format (JSON):
          {
            "complete": true/false,
            "questions": ["question 1", "question 2"],
            "reasoning": "brief explanation of what you're trying to learn"
          }

          If complete is true, the plan is ready for execution.
        PROMPT
      end

      def build_planning_prompt(plan)
        <<~PROMPT
          Current Plan:
          Goal: #{plan[:goal]}
          Scope: #{plan[:scope].inspect}
          Users: #{plan[:users].inspect}
          Requirements: #{plan[:requirements].inspect}
          Constraints: #{plan[:constraints].inspect}
          Completion Criteria: #{plan[:completion_criteria].inspect}

          Conversation History:
          #{@conversation_history.map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")}

          Based on this plan, determine if you have enough information or what clarifying questions to ask next.
        PROMPT
      end

      def parse_planning_response(response_text)
        json_match = response_text.match(/```json\s*(\{.*?\})\s*```/m) ||
          response_text.match(/(\{.*\})/m)

        unless json_match
          return {complete: false, questions: ["Could you tell me more about your requirements?"]}
        end

        JSON.parse(json_match[1], symbolize_names: true)
      rescue JSON::ParserError
        {complete: false, questions: ["Could you tell me more about your requirements?"]}
      end

      def update_plan_from_answer(plan, question, answer)
        # Simple heuristic-based plan updates
        # In a more sophisticated implementation, use AI to categorize answers

        if question.downcase.include?("scope") || question.downcase.include?("include")
          plan[:scope][:included] ||= []
          plan[:scope][:included] << answer
        elsif question.downcase.include?("user") || question.downcase.include?("who")
          plan[:users][:personas] ||= []
          plan[:users][:personas] << answer
        elsif question.downcase.include?("requirement") || question.downcase.include?("feature")
          plan[:requirements][:functional] ||= []
          plan[:requirements][:functional] << answer
        elsif question.downcase.include?("performance") || question.downcase.include?("security") || question.downcase.include?("scalability")
          plan[:requirements][:non_functional] ||= {}
          plan[:requirements][:non_functional][question] = answer
        elsif question.downcase.include?("constraint") || question.downcase.include?("limitation")
          plan[:constraints][:technical] ||= []
          plan[:constraints][:technical] << answer
        elsif question.downcase.include?("complete") || question.downcase.include?("done") || question.downcase.include?("success")
          plan[:completion_criteria] << answer
        else
          # General information
          plan[:additional_context] ||= []
          plan[:additional_context] << {question: question, answer: answer}
        end
      end

      def display_plan_summary(plan)
        display_message("Goal: #{plan[:goal]}", type: :info)
        display_message("\nScope:", type: :highlight) if plan[:scope].any?
        plan[:scope].each { |k, v| display_message("  #{k}: #{v}", type: :muted) }
        display_message("\nUsers:", type: :highlight) if plan[:users].any?
        plan[:users].each { |k, v| display_message("  #{k}: #{v}", type: :muted) }
        display_message("\nRequirements:", type: :highlight) if plan[:requirements].any?
        plan[:requirements].each { |k, v| display_message("  #{k}: #{v}", type: :muted) }
        display_message("\nCompletion Criteria:", type: :highlight) if plan[:completion_criteria].any?
        plan[:completion_criteria].each { |c| display_message("  • #{c}", type: :info) }
      end

      def build_step_identification_prompt
        all_steps = Aidp::Execute::Steps::SPEC.map do |key, spec|
          "#{key}: #{spec["description"]}"
        end.join("\n")

        <<~PROMPT
          You are an expert at identifying which AIDP workflow steps are needed for a project.

          Available Execute Steps:
          #{all_steps}

          Based on the plan provided, identify which steps are needed and in what order.

          Response Format (JSON):
          {
            "steps": ["00_PRD", "02_ARCHITECTURE", "16_IMPLEMENTATION"],
            "reasoning": "brief explanation of why these steps"
          }

          Be concise and select only the necessary steps.
        PROMPT
      end

      def build_plan_summary_for_step_identification(plan)
        <<~PROMPT
          Plan Summary:
          #{plan.to_json}

          Which execute steps are needed for this plan?
        PROMPT
      end

      def parse_step_identification(response_text)
        json_match = response_text.match(/```json\s*(\{.*?\})\s*```/m) ||
          response_text.match(/(\{.*\})/m)

        unless json_match
          # Fallback to basic workflow
          return ["00_PRD", "16_IMPLEMENTATION"]
        end

        parsed = JSON.parse(json_match[1], symbolize_names: true)
        parsed[:steps] || ["00_PRD", "16_IMPLEMENTATION"]
      rescue JSON::ParserError
        ["00_PRD", "16_IMPLEMENTATION"]
      end

      def generate_prd_from_plan(plan)
        prd_content = <<~PRD
          # Product Requirements Document

          ## Goal
          #{plan[:goal]}

          ## Scope
          #{format_hash_for_doc(plan[:scope])}

          ## Users & Personas
          #{format_hash_for_doc(plan[:users])}

          ## Requirements
          #{format_hash_for_doc(plan[:requirements])}

          ## Constraints
          #{format_hash_for_doc(plan[:constraints])}

          ## Completion Criteria
          #{plan[:completion_criteria].map { |c| "- #{c}" }.join("\n")}

          ## Additional Context
          #{plan[:additional_context]&.map { |ctx| "**#{ctx[:question]}**: #{ctx[:answer]}" }&.join("\n\n")}

          ---
          Generated by AIDP Plan & Execute workflow on #{Time.now.strftime("%Y-%m-%d")}
        PRD

        File.write(File.join(@project_dir, "docs", "prd.md"), prd_content)
      end

      def generate_nfr_from_plan(plan)
        nfr_data = plan.dig(:requirements, :non_functional)
        return unless nfr_data

        nfr_content = <<~NFR
          # Non-Functional Requirements

          #{nfr_data.map { |k, v| "## #{k}\n#{v}" }.join("\n\n")}

          ---
          Generated by AIDP Plan & Execute workflow on #{Time.now.strftime("%Y-%m-%d")}
        NFR

        File.write(File.join(@project_dir, "docs", "nfrs.md"), nfr_content)
      end

      def generate_style_guide_from_plan(plan)
        return unless plan[:style_requirements]

        style_guide_content = <<~STYLE
          # LLM Style Guide

          #{plan[:style_requirements]}

          ---
          Generated by AIDP Plan & Execute workflow on #{Time.now.strftime("%Y-%m-%d")}
        STYLE

        File.write(File.join(@project_dir, "docs", "LLM_STYLE_GUIDE.md"), style_guide_content)
      end

      def format_hash_for_doc(hash)
        return "None specified" if hash.nil? || hash.empty?

        hash.map do |key, value|
          if value.is_a?(Array)
            "### #{key.to_s.capitalize}\n#{value.map { |v| "- #{v}" }.join("\n")}"
          elsif value.is_a?(Hash)
            "### #{key.to_s.capitalize}\n#{value.map { |k, v| "- **#{k}**: #{v}" }.join("\n")}"
          else
            "### #{key.to_s.capitalize}\n#{value}"
          end
        end.join("\n\n")
      end
    end
  end
end
