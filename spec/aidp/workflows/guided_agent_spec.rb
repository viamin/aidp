# frozen_string_literal: true

require "spec_helper"
require "aidp/workflows/guided_agent"
require "tty-prompt"

RSpec.describe Aidp::Workflows::GuidedAgent do
  let(:project_dir) { Dir.mktmpdir }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
  let(:provider_factory) { instance_double(Aidp::Harness::ProviderFactory) }
  let(:provider) { instance_double(Aidp::Providers::Base) }
  let(:config_manager) { instance_double(Aidp::Harness::ConfigManager) }

  subject(:agent) { described_class.new(project_dir, prompt: prompt) }

  before do
    # Create the capabilities document in the temp project dir
    FileUtils.mkdir_p(File.join(project_dir, "docs"))
    capabilities_content = <<~DOC
      # AIDP Capabilities Reference
      Test capabilities document for specs.
    DOC
    File.write(File.join(project_dir, "docs", "AIDP_CAPABILITIES.md"), capabilities_content)

    # Mock the configuration and provider manager
    allow(Aidp::Harness::ConfigManager).to receive(:new).with(project_dir).and_return(config_manager)
    allow(Aidp::Harness::ProviderManager).to receive(:new)
      .with(config_manager, prompt: prompt)
      .and_return(provider_manager)

    # Mock provider creation
    allow(Aidp::Harness::ProviderFactory).to receive(:new).with(config_manager).and_return(provider_factory)
    allow(provider_factory).to receive(:create_provider).and_return(provider)
    allow(provider_manager).to receive(:current_provider).and_return("claude")
    # New validation now queries configured_providers; stub a minimal list
    allow(provider_manager).to receive(:configured_providers).and_return(["claude"])

    # Mock display_message calls (uses prompt.say)
    allow(prompt).to receive(:say)

    # Allow any ask calls by default (can be overridden in specific contexts)
    allow(prompt).to receive(:ask).and_return("")
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "#initialize" do
    it "initializes with project directory and prompt" do
      expect(agent.instance_variable_get(:@project_dir)).to eq(project_dir)
    end

    it "initializes empty conversation history and user input" do
      expect(agent.instance_variable_get(:@conversation_history)).to eq([])
      expect(agent.instance_variable_get(:@user_input)).to eq({})
    end

    it "uses EnhancedInput when prompt is nil and use_enhanced_input is true" do
      enhanced_prompt = instance_double("Aidp::CLI::EnhancedInput")
      allow(Aidp::CLI::EnhancedInput).to receive(:new).and_return(enhanced_prompt)

      # Also stub ProviderManager.new to accept any prompt type
      enhanced_provider_manager = instance_double("Aidp::Harness::ProviderManager")
      allow(Aidp::Harness::ProviderManager).to receive(:new)
        .with(config_manager, prompt: enhanced_prompt)
        .and_return(enhanced_provider_manager)
      allow(enhanced_provider_manager).to receive(:current_provider).and_return("claude")
      allow(enhanced_provider_manager).to receive(:configured_providers).and_return(["claude"])

      agent_with_enhanced = described_class.new(project_dir, prompt: nil, use_enhanced_input: true)

      expect(Aidp::CLI::EnhancedInput).to have_received(:new)
      expect(agent_with_enhanced.instance_variable_get(:@prompt)).to eq(enhanced_prompt)
    end
  end

  describe "#select_workflow" do
    let(:user_goal) { "Build a user authentication feature" }

    let(:plan_response) do
      {
        complete: true,
        questions: [],
        reasoning: "Plan is complete"
      }
    end

    let(:step_identification_response) do
      {
        steps: ["00_PRD", "02_ARCHITECTURE", "16_IMPLEMENTATION"],
        reasoning: "Need PRD, architecture design, and implementation"
      }
    end

    before do
      # Mock user goal input
      allow(prompt).to receive(:ask)
        .with("Your goal:", required: true)
        .and_return(user_goal)

      # Mock planning questions response and step identification
      # Provider.send returns a string (the content), not a hash
      allow(provider).to receive(:send).and_return(
        plan_response.to_json,
        step_identification_response.to_json
      )

      # Mock plan confirmation
      allow(prompt).to receive(:yes?)
        .with(/Is this plan ready for execution/)
        .and_return(true)
    end

    it "uses plan-and-execute workflow" do
      expect(prompt).to receive(:ask).with("Your goal:", required: true)
      agent.select_workflow
    end

    it "identifies needed steps from plan" do
      result = agent.select_workflow
      expect(result[:steps]).to eq(["00_PRD", "02_ARCHITECTURE", "16_IMPLEMENTATION"])
    end

    it "generates PRD from plan" do
      agent.select_workflow

      prd_path = File.join(project_dir, "docs", "prd.md")
      expect(File.exist?(prd_path)).to be true
      prd_content = File.read(prd_path)
      expect(prd_content).to include("Product Requirements Document")
      expect(prd_content).to include(user_goal)
    end

    it "returns workflow selection with plan data" do
      result = agent.select_workflow

      expect(result[:mode]).to eq(:execute)
      expect(result[:workflow_key]).to eq(:plan_and_execute)
      expect(result[:user_input]).to have_key(:plan)
      expect(result[:steps]).to be_an(Array)
    end

    it "includes completion criteria in workflow selection" do
      result = agent.select_workflow
      expect(result).to have_key(:completion_criteria)
    end

    context "when plan requires multiple iterations" do
      before do
        call_count = 0
        allow(provider).to receive(:send) do
          call_count += 1
          if call_count == 1
            # First call: AI needs more info
            # Provider.send returns a string (the content), not a hash
            {
              complete: false,
              questions: ["What level of security is needed?"],
              reasoning: "Need to understand security requirements"
            }.to_json
          elsif call_count == 2
            # Second call: Plan complete
            plan_response.to_json
          else
            # Third call: Step identification
            step_identification_response.to_json
          end
        end

        allow(prompt).to receive(:ask)
          .with("What level of security is needed?")
          .and_return("Enterprise-grade with MFA")
      end

      it "iterates until plan is complete" do
        expect(prompt).to receive(:ask).with("What level of security is needed?")
        agent.select_workflow
      end
    end

    context "when provider request fails" do
      before do
        # Provider.send returns nil/empty string on failure
        allow(provider).to receive(:send).and_return(nil)
      end

      it "raises a ConversationError" do
        expect { agent.select_workflow }.to raise_error(
          Aidp::Workflows::GuidedAgent::ConversationError,
          /Provider request failed/
        )
      end
    end

    context "when no provider is configured" do
      before do
        allow(provider_manager).to receive(:current_provider).and_return(nil)
        allow(provider_manager).to receive(:configured_providers).and_return([])
      end

      it "raises a ConversationError" do
        expect { agent.select_workflow }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError) { |err|
          # Wrapped message now includes prefix 'Failed to guide workflow selection:'
          expect(err.message).to match(/No providers? are configured|No provider configured/i)
        }
      end
    end

    context "when plan includes non-functional requirements" do
      before do
        # Simulate plan with NFRs
        plan_with_nfrs = plan_response.dup
        # Provider.send returns a string (the content), not a hash
        allow(provider).to receive(:send).and_return(
          plan_with_nfrs.to_json,
          step_identification_response.to_json
        )

        # Inject NFR data into the plan during iteration
        allow_any_instance_of(described_class).to receive(:update_plan_from_answer) do |instance, plan, question, answer|
          if question.downcase.include?("performance")
            plan[:requirements][:non_functional] = {
              "Performance requirements" => "Response time < 100ms"
            }
          end
        end
      end

      it "supports NFR document generation" do
        # This test validates that NFR generation is supported
        # In reality, NFRs are generated when plan[:requirements][:non_functional] exists
        agent.select_workflow

        # The workflow completes successfully even with NFR requirements in the plan
        expect(File.exist?(File.join(project_dir, "docs", "prd.md"))).to be true
      end
    end

    context "when primary provider is resource exhausted and fallback exists" do
      let(:secondary_provider) { "cursor" }

      before do
        # Simulate two providers: claude (current) then cursor fallback
        allow(provider_manager).to receive(:configured_providers).and_return(["claude", secondary_provider])

        call_count = 0
        allow(provider).to receive(:send) do
          call_count += 1
          if call_count == 1
            # First attempt triggers resource_exhausted failure via raising error
            raise StandardError, "ConnectError: [resource_exhausted] Error"
          elsif call_count == 2
            # Second attempt succeeds with plan then steps (reuse existing stubs)
            plan_response.to_json
          else
            step_identification_response.to_json
          end
        end

        # After failure, provider manager should switch providers
        allow(provider_manager).to receive(:switch_provider_for_error) do |error_type, details|
          allow(provider_manager).to receive(:current_provider).and_return(secondary_provider)
          secondary_provider
        end
      end

      it "falls back to secondary provider and completes workflow" do
        result = agent.select_workflow
        expect(result[:steps]).to eq(["00_PRD", "02_ARCHITECTURE", "16_IMPLEMENTATION"])
      end
    end

    context "when planning loop exceeds maximum iterations" do
      before do
        # Mock provider to always return incomplete plan to force iteration limit
        allow(provider).to receive(:send).and_return(
          {
            complete: false,
            questions: ["What else do you need?"],
            reasoning: "Need more info"
          }.to_json
        )

        # Mock user answers
        allow(prompt).to receive(:ask).and_return("More details")
      end

      it "breaks out of infinite loop after 10 iterations" do
        # Just verify that it eventually completes without hanging
        result = agent.select_workflow
        expect(result).to have_key(:steps)
      end
    end
  end

  describe "private methods" do
    before do
      # Set up basic mocks for provider communication
      allow(provider).to receive(:send).and_return('{"complete": true, "questions": []}')
      allow(prompt).to receive(:ask).and_return("Test goal")
      allow(prompt).to receive(:yes?).and_return(true)
    end

    describe "#iterative_planning" do
      it "collects user goal and initializes plan structure" do
        allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return("Build auth system")

        plan = agent.send(:iterative_planning)

        expect(plan[:goal]).to eq("Build auth system")
        expect(plan).to have_key(:scope)
        expect(plan).to have_key(:users)
        expect(plan).to have_key(:requirements)
        expect(plan).to have_key(:constraints)
        expect(plan).to have_key(:completion_criteria)
      end

      it "handles multiple planning iterations" do
        call_count = 0
        allow(provider).to receive(:send) do
          call_count += 1
          if call_count == 1
            {
              complete: false,
              questions: ["What authentication methods do you need?"],
              reasoning: "Need auth details"
            }.to_json
          else
            {
              complete: true,
              questions: [],
              reasoning: "Plan is complete"
            }.to_json
          end
        end

        allow(prompt).to receive(:ask).with("What authentication methods do you need?").and_return("OAuth and MFA")
        allow(prompt).to receive(:yes?).with(/Is this plan ready for execution/).and_return(true)

        plan = agent.send(:iterative_planning)
        expect(plan[:goal]).to eq("Test goal")
      end

      it "continues planning when user rejects initial plan" do
        call_count = 0
        allow(provider).to receive(:send) do
          call_count += 1
          case call_count
          when 1
            {complete: true, questions: [], reasoning: "Initial plan ready"}.to_json
          when 2
            {complete: true, questions: [], reasoning: "Refined plan ready"}.to_json
          else
            {complete: true, questions: [], reasoning: "Final plan"}.to_json
          end
        end

        # Reject first plan, then accept second
        allow(prompt).to receive(:yes?).with(/Is this plan ready for execution/).and_return(false, true)
        allow(prompt).to receive(:ask).with("What would you like to add or clarify?").and_return("Add more security features")

        plan = agent.send(:iterative_planning)
        expect(plan[:goal]).to eq("Test goal")

        # Verify we went through refinement cycle
        expect(prompt).to have_received(:yes?).twice
        expect(prompt).to have_received(:ask).with("What would you like to add or clarify?")
      end
    end

    describe "#get_planning_questions" do
      let(:test_plan) { {goal: "Test goal", requirements: {}} }

      it "calls provider with system and user prompts" do
        expect(provider).to receive(:send).with(prompt: kind_of(String))

        agent.send(:get_planning_questions, test_plan)
      end

      it "parses provider response into planning format" do
        response = {
          complete: false,
          questions: ["What technology stack?"],
          reasoning: "Need tech info"
        }.to_json

        allow(provider).to receive(:send).and_return(response)

        result = agent.send(:get_planning_questions, test_plan)
        expect(result[:complete]).to be false
        expect(result[:questions]).to eq(["What technology stack?"])
        expect(result[:reasoning]).to eq("Need tech info")
      end

      it "handles detailed requirements to avoid repetition" do
        detailed_plan = {
          goal: "Test goal",
          requirements: {
            functional: ["User login with username/password with minimum 8 characters"]
          }
        }

        expect(provider).to receive(:send).with(prompt: including("Requirements have been provided in detail"))

        agent.send(:get_planning_questions, detailed_plan)
      end
    end

    describe "#identify_steps_from_plan" do
      let(:test_plan) { {goal: "Build auth", requirements: {functional: ["User login"]}} }

      it "calls provider to identify needed steps" do
        step_response = {
          steps: ["00_PRD", "05_API_DESIGN", "16_IMPLEMENTATION"],
          reasoning: "Need PRD, API design, and implementation"
        }.to_json

        allow(provider).to receive(:send).and_return(step_response)

        result = agent.send(:identify_steps_from_plan, test_plan)
        expect(result).to eq(["00_PRD", "05_API_DESIGN", "16_IMPLEMENTATION"])
      end
    end

    describe "#generate_documents_from_plan" do
      let(:test_plan) do
        {
          goal: "Build auth system",
          requirements: {
            functional: ["User login"],
            non_functional: {"Performance" => "< 100ms response time"}
          },
          style_requirements: {"Language" => "Ruby"}
        }
      end

      it "generates PRD for all plans" do
        expect(agent).to receive(:generate_prd_from_plan).with(test_plan)

        agent.send(:generate_documents_from_plan, test_plan)
      end

      it "generates NFRs when non-functional requirements exist" do
        expect(agent).to receive(:generate_prd_from_plan).with(test_plan)
        expect(agent).to receive(:generate_nfr_from_plan).with(test_plan)

        agent.send(:generate_documents_from_plan, test_plan)
      end

      it "generates style guide when style requirements exist" do
        expect(agent).to receive(:generate_prd_from_plan).with(test_plan)
        expect(agent).to receive(:generate_nfr_from_plan).with(test_plan)
        expect(agent).to receive(:generate_style_guide_from_plan).with(test_plan)

        agent.send(:generate_documents_from_plan, test_plan)
      end
    end

    describe "#build_workflow_from_plan" do
      let(:test_plan) do
        {
          goal: "Build auth",
          completion_criteria: ["Users can log in successfully"]
        }
      end
      let(:test_steps) { ["00_PRD", "05_API_DESIGN", "16_IMPLEMENTATION"] }

      it "builds complete workflow configuration" do
        result = agent.send(:build_workflow_from_plan, test_plan, test_steps)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_key]).to eq(:plan_and_execute)
        expect(result[:workflow_type]).to eq(:plan_and_execute)
        expect(result[:steps]).to eq(test_steps)
        expect(result[:completion_criteria]).to eq(["Users can log in successfully"])
        expect(result[:workflow][:name]).to eq("Plan & Execute")
        expect(result[:user_input][:plan]).to eq(test_plan)
      end

      it "filters out unknown steps" do
        invalid_steps = ["00_PRD", "INVALID_STEP", "16_IMPLEMENTATION"]

        result = agent.send(:build_workflow_from_plan, test_plan, invalid_steps)

        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
      end
    end

    describe "#user_goal" do
      it "prompts user for their goal" do
        expect(prompt).to receive(:ask).with("Your goal:", required: true).and_return("Test user goal")

        result = agent.send(:user_goal)
        expect(result).to eq("Test user goal")
      end
    end

    describe "#validate_provider_configuration!" do
      context "when no providers are configured" do
        before do
          allow(provider_manager).to receive(:configured_providers).and_return([])
        end

        it "raises ConversationError" do
          expect {
            agent.send(:validate_provider_configuration!)
          }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError, /No providers? are configured/)
        end
      end

      context "when current provider is nil" do
        before do
          allow(provider_manager).to receive(:configured_providers).and_return(["claude"])
          allow(provider_manager).to receive(:current_provider).and_return(nil)
        end

        it "raises ConversationError" do
          expect {
            agent.send(:validate_provider_configuration!)
          }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError, /Default provider.*not found/)
        end
      end

      context "when provider is properly configured" do
        it "does not raise error" do
          expect {
            agent.send(:validate_provider_configuration!)
          }.not_to raise_error
        end
      end
    end

    describe "#display_plan_summary" do
      let(:test_plan) do
        {
          goal: "Build auth system",
          scope: {features: ["Login", "Registration"]},
          users: {primary: "End users"},
          requirements: {functional: ["User authentication"]},
          constraints: {timeline: "2 weeks"},
          completion_criteria: ["Users can log in"]
        }
      end

      it "displays all plan sections" do
        # Just verify it calls prompt.say without checking exact format
        expect(prompt).to receive(:say).at_least(5).times

        agent.send(:display_plan_summary, test_plan)
      end
    end

    describe "#parse_planning_response" do
      it "parses valid JSON response" do
        response = '```json\n{"complete": true, "questions": [], "reasoning": "Plan is ready"}\n```'

        result = agent.send(:parse_planning_response, response)

        expect(result[:complete]).to be true
        expect(result[:questions]).to eq([])
        expect(result[:reasoning]).to eq("Plan is ready")
      end

      it "parses JSON without code blocks" do
        response = '{"complete": false, "questions": ["What tech stack?"], "reasoning": "Need more info"}'

        result = agent.send(:parse_planning_response, response)

        expect(result[:complete]).to be false
        expect(result[:questions]).to eq(["What tech stack?"])
      end

      it "handles malformed JSON gracefully" do
        response = "This is not JSON at all"

        result = agent.send(:parse_planning_response, response)

        expect(result[:complete]).to be false
        expect(result[:questions]).to eq(["Could you tell me more about your requirements?"])
      end

      it "handles JSON parse errors gracefully" do
        response = '{"invalid": json,}'

        result = agent.send(:parse_planning_response, response)

        expect(result[:complete]).to be false
        expect(result[:questions]).to eq(["Could you tell me more about your requirements?"])
      end
    end

    describe "#parse_step_identification" do
      it "parses step identification response" do
        response = '{"steps": ["00_PRD", "16_IMPLEMENTATION"], "reasoning": "Need PRD and implementation"}'

        result = agent.send(:parse_step_identification, response)

        expect(result).to eq(["00_PRD", "16_IMPLEMENTATION"])
      end
    end

    describe "#update_plan_from_answer" do
      let(:test_plan) { {scope: {}, users: {}, requirements: {}, constraints: {}, completion_criteria: []} }

      it "updates scope for scope-related questions" do
        agent.send(:update_plan_from_answer, test_plan, "What should be included in scope?", "User management")

        expect(test_plan[:scope][:included]).to eq(["User management"])
      end

      it "updates users for user-related questions" do
        agent.send(:update_plan_from_answer, test_plan, "Who are the users?", "Developers and admins")

        expect(test_plan[:users][:personas]).to eq(["Developers and admins"])
      end

      it "updates functional requirements for requirement questions" do
        agent.send(:update_plan_from_answer, test_plan, "What are the key requirements?", "User login")

        expect(test_plan[:requirements][:functional]).to eq(["User login"])
      end

      it "updates non-functional requirements for performance questions" do
        agent.send(:update_plan_from_answer, test_plan, "What performance metrics do you need?", "< 100ms response")

        expect(test_plan[:requirements][:non_functional]).not_to be_nil
        expect(test_plan[:requirements][:non_functional]["What performance metrics do you need?"]).to eq("< 100ms response")
      end

      it "updates constraints for constraint questions" do
        agent.send(:update_plan_from_answer, test_plan, "What are the constraints?", "2 week timeline")

        expect(test_plan[:constraints][:technical]).to eq(["2 week timeline"])
      end

      it "updates completion criteria for success questions" do
        agent.send(:update_plan_from_answer, test_plan, "How will you know when it's complete?", "Users can log in")

        expect(test_plan[:completion_criteria]).to eq(["Users can log in"])
      end

      it "stores general information for unclassified questions" do
        agent.send(:update_plan_from_answer, test_plan, "Random question?", "Random answer")

        expect(test_plan[:additional_context]).to eq([{question: "Random question?", answer: "Random answer"}])
      end
    end

    describe "#call_provider_for_analysis" do
      it "calls provider with system and user prompts" do
        system_prompt = "You are an AI assistant"
        user_prompt = "Help me with this"

        expect(provider).to receive(:send).with(prompt: "#{system_prompt}\n\n#{user_prompt}")

        agent.send(:call_provider_for_analysis, system_prompt, user_prompt)
      end

      it "handles provider errors with fallback" do
        system_prompt = "System prompt"
        user_prompt = "User prompt"

        call_count = 0
        allow(provider).to receive(:send) do
          call_count += 1
          if call_count == 1
            raise StandardError, "[resource_exhausted] Error"
          else
            "Success response"
          end
        end

        allow(provider_manager).to receive(:switch_provider_for_error).and_return("cursor")

        result = agent.send(:call_provider_for_analysis, system_prompt, user_prompt)
        expect(result).to eq("Success response")
      end

      it "raises ConversationError when provider returns nil" do
        allow(provider).to receive(:send).and_return(nil)

        expect {
          agent.send(:call_provider_for_analysis, "system", "user")
        }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError, /Provider request failed/)
      end
    end

    describe "document generation methods" do
      let(:test_plan) do
        {
          goal: "Build authentication system",
          requirements: {
            functional: ["User login", "Password reset"],
            non_functional: {"Performance" => "< 100ms response time"}
          },
          completion_criteria: ["Users can log in successfully"]
        }
      end

      describe "#generate_prd_from_plan" do
        it "creates PRD file with plan content" do
          agent.send(:generate_prd_from_plan, test_plan)

          prd_path = File.join(project_dir, "docs", "prd.md")
          expect(File.exist?(prd_path)).to be true

          content = File.read(prd_path)
          expect(content).to include("Product Requirements Document")
          expect(content).to include("Build authentication system")
          expect(content).to include("User login")
          expect(content).to include("Users can log in successfully")
        end
      end

      describe "#generate_nfr_from_plan" do
        it "creates NFRs file when non-functional requirements exist" do
          agent.send(:generate_nfr_from_plan, test_plan)

          nfr_path = File.join(project_dir, "docs", "nfrs.md")
          expect(File.exist?(nfr_path)).to be true

          content = File.read(nfr_path)
          expect(content).to include("Non-Functional Requirements")
          expect(content).to include("Performance")
          expect(content).to include("< 100ms response time")
        end
      end

      describe "#generate_style_guide_from_plan" do
        let(:plan_with_style) do
          test_plan.merge(style_requirements: {"Language" => "Ruby", "Framework" => "Rails"})
        end

        it "creates style guide file when style requirements exist" do
          agent.send(:generate_style_guide_from_plan, plan_with_style)

          style_path = File.join(project_dir, "docs", "LLM_STYLE_GUIDE.md")
          expect(File.exist?(style_path)).to be true

          content = File.read(style_path)
          expect(content).to include("LLM Style Guide")
        end
      end
    end

    describe "#build_planning_system_prompt" do
      it "returns system prompt for planning" do
        result = agent.send(:build_planning_system_prompt)

        expect(result).to include("planning assistant")
        expect(result).to include("complete")
        expect(result).to include("questions")
        expect(result).to include("reasoning")
      end
    end

    describe "#build_step_identification_prompt" do
      it "includes available execute steps" do
        result = agent.send(:build_step_identification_prompt)

        expect(result).to include("expert at identifying")
        expect(result).to include("Available Execute Steps")
        expect(result).to include("00_PRD")
        expect(result).to include("16_IMPLEMENTATION")
      end
    end

    describe "#format_hash_for_doc" do
      it "returns 'None specified' for empty hash" do
        result = agent.send(:format_hash_for_doc, {})
        expect(result).to eq("None specified")
      end

      it "returns 'None specified' for nil" do
        result = agent.send(:format_hash_for_doc, nil)
        expect(result).to eq("None specified")
      end

      it "formats array values as bulleted lists" do
        hash = {features: ["Login", "Registration", "Password reset"]}
        result = agent.send(:format_hash_for_doc, hash)
        expect(result).to include("### Features")
        expect(result).to include("- Login")
        expect(result).to include("- Registration")
      end

      it "formats hash values as key-value lists" do
        hash = {performance: {"Response time" => "< 100ms", "Throughput" => "1000 req/s"}}
        result = agent.send(:format_hash_for_doc, hash)
        expect(result).to include("### Performance")
        expect(result).to include("- **Response time**: < 100ms")
        expect(result).to include("- **Throughput**: 1000 req/s")
      end

      it "formats string values with header" do
        hash = {description: "A comprehensive authentication system"}
        result = agent.send(:format_hash_for_doc, hash)
        expect(result).to include("### Description")
        expect(result).to include("A comprehensive authentication system")
      end
    end

    describe "analyze_user_intent workflow (legacy)" do
      let(:user_goal) { "Understand how payments work" }

      before do
        # Mock provider responses for legacy workflow
        allow(provider).to receive(:send).and_return(
          {
            mode: "analyze",
            workflow_key: "deep_dive",
            reasoning: "This requires code analysis",
            confidence: "high",
            questions: [],
            additional_steps: []
          }.to_json
        )
        allow(prompt).to receive(:yes?).and_return(true)
      end

      it "analyzes user intent and recommends workflow" do
        result = agent.send(:analyze_user_intent, user_goal)

        expect(result).to have_key(:mode)
        expect(result).to have_key(:workflow_key)
        expect(result).to have_key(:reasoning)
      end

      it "parses recommendation from provider" do
        recommendation = agent.send(:analyze_user_intent, user_goal)

        expect(recommendation[:mode]).to eq("analyze")
        expect(recommendation[:workflow_key]).to eq("deep_dive")
      end
    end

    describe "#parse_recommendation" do
      it "parses JSON from markdown code block" do
        response = '```json\n{"mode": "execute", "workflow_key": "quick_prototype"}\n```'
        result = agent.send(:parse_recommendation, response)

        expect(result[:mode]).to eq("execute")
        expect(result[:workflow_key]).to eq("quick_prototype")
      end

      it "parses plain JSON response" do
        response = '{"mode": "analyze", "workflow_key": "deep_dive", "confidence": "high"}'
        result = agent.send(:parse_recommendation, response)

        expect(result[:mode]).to eq("analyze")
        expect(result[:confidence]).to eq("high")
      end

      it "raises ConversationError when no JSON found" do
        response = "This is not JSON at all"

        expect {
          agent.send(:parse_recommendation, response)
        }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError, /Could not parse recommendation/)
      end

      it "raises ConversationError for malformed JSON" do
        response = '{"invalid": json,}'

        expect {
          agent.send(:parse_recommendation, response)
        }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError, /Invalid JSON/)
      end
    end

    describe "#build_system_prompt" do
      it "includes AIDP capabilities documentation" do
        result = agent.send(:build_system_prompt)

        expect(result).to include("expert AI assistant")
        expect(result).to include("AIDP Capabilities Reference")
        expect(result).to include("Test capabilities document") # From our test setup
      end

      it "requests JSON response format" do
        result = agent.send(:build_system_prompt)

        expect(result).to include("JSON response")
        expect(result).to include('"mode"')
        expect(result).to include('"workflow_key"')
      end
    end

    describe "#build_analysis_prompt" do
      it "includes user goal in prompt" do
        goal = "Build a REST API"
        result = agent.send(:build_analysis_prompt, goal)

        expect(result).to include("Build a REST API")
        expect(result).to include("Is this analysis or development")
      end
    end

    describe "#present_recommendation" do
      let(:recommendation) do
        {
          mode: "execute",
          workflow_key: "quick_prototype",
          reasoning: "Fast iteration needed",
          confidence: "high",
          additional_steps: [],
          questions: []
        }
      end

      before do
        allow(prompt).to receive(:yes?).and_return(true)
      end

      it "displays recommendation to user" do
        expect(prompt).to receive(:say).at_least(:once)

        result = agent.send(:present_recommendation, recommendation)
        expect(result).to have_key(:mode)
      end

      it "returns workflow selection when confirmed" do
        result = agent.send(:present_recommendation, recommendation)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_key]).to eq(:quick_prototype)
        expect(result).to have_key(:steps)
      end

      it "offers alternatives when not confirmed" do
        allow(prompt).to receive(:yes?).and_return(false)
        expect(agent).to receive(:offer_alternatives).with(:execute)

        agent.send(:present_recommendation, recommendation)
      end

      it "handles additional steps in recommendation" do
        recommendation[:additional_steps] = ["custom_validation", "custom_deployment"]

        result = agent.send(:present_recommendation, recommendation)
        expect(result[:steps]).to include("custom_validation")
      end

      it "handles custom workflow recommendation" do
        recommendation[:workflow_key] = "nonexistent_workflow"
        expect(agent).to receive(:handle_custom_workflow).with(recommendation)

        agent.send(:present_recommendation, recommendation)
      end
    end

    describe "#handle_custom_workflow" do
      let(:recommendation) do
        {
          mode: "execute",
          reasoning: "Custom workflow needed",
          questions: ["What's your timeline?", "What's the budget?"],
          additional_steps: ["00_PRD"]
        }
      end

      before do
        allow(prompt).to receive(:ask).and_return("2 weeks", "$10k")
        allow(agent).to receive(:select_custom_steps).and_return(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "asks clarifying questions" do
        expect(prompt).to receive(:ask).with("What's your timeline?")
        expect(prompt).to receive(:ask).with("What's the budget?")

        agent.send(:handle_custom_workflow, recommendation)
      end

      it "selects custom steps" do
        expect(agent).to receive(:select_custom_steps).with(:execute, ["00_PRD"])

        agent.send(:handle_custom_workflow, recommendation)
      end

      it "returns custom workflow configuration" do
        result = agent.send(:handle_custom_workflow, recommendation)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_key]).to eq(:custom)
        expect(result[:workflow_type]).to eq(:custom)
        expect(result[:workflow][:name]).to eq("Custom Workflow")
      end
    end

    describe "#select_custom_steps" do
      before do
        allow(prompt).to receive(:multi_select).and_return(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "presents available steps for execute mode" do
        expect(prompt).to receive(:multi_select).with(
          /Select steps/,
          kind_of(Array),
          hash_including(:per_page)
        )

        agent.send(:select_custom_steps, :execute, [])
      end

      it "pre-selects suggested steps" do
        suggested = ["00_PRD"]

        expect(prompt).to receive(:multi_select).with(
          anything,
          anything,
          hash_including(default: kind_of(Array))
        )

        agent.send(:select_custom_steps, :execute, suggested)
      end

      it "returns selected steps" do
        result = agent.send(:select_custom_steps, :execute)
        expect(result).to eq(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "returns suggested steps when no selection made" do
        allow(prompt).to receive(:multi_select).and_return([])
        result = agent.send(:select_custom_steps, :execute, ["00_PRD"])
        expect(result).to eq(["00_PRD"])
      end

      it "supports analyze mode steps" do
        allow(prompt).to receive(:multi_select).and_return(["01_CODEBASE_SUMMARY"])
        result = agent.send(:select_custom_steps, :analyze)
        expect(result).to eq(["01_CODEBASE_SUMMARY"])
      end

      it "supports hybrid mode with combined steps" do
        allow(prompt).to receive(:multi_select).and_return(["00_PRD", "01_CODEBASE_SUMMARY"])
        result = agent.send(:select_custom_steps, :hybrid)
        expect(result).to include("00_PRD")
      end
    end

    describe "#offer_alternatives" do
      before do
        allow(prompt).to receive(:select).and_return(:different_workflow)
        allow(agent).to receive(:select_manual_workflow).and_return({mode: :execute})
      end

      it "offers alternative options" do
        expect(prompt).to receive(:select).with(/What would you like to do/, kind_of(Array))

        agent.send(:offer_alternatives, :execute)
      end

      it "allows selecting different workflow in same mode" do
        expect(agent).to receive(:select_manual_workflow).with(:execute)

        agent.send(:offer_alternatives, :execute)
      end

      it "allows switching to different mode" do
        allow(prompt).to receive(:select).and_return(:different_mode, :analyze)
        expect(agent).to receive(:select_manual_workflow).with(:analyze)

        agent.send(:offer_alternatives, :execute)
      end

      it "allows building custom workflow" do
        allow(prompt).to receive(:select).and_return(:custom)
        expect(agent).to receive(:select_custom_steps).with(:execute)

        agent.send(:offer_alternatives, :execute)
      end

      it "allows restarting workflow selection" do
        allow(prompt).to receive(:select).and_return(:restart)
        expect(agent).to receive(:select_workflow)

        agent.send(:offer_alternatives, :execute)
      end
    end

    describe "#select_manual_workflow" do
      before do
        allow(prompt).to receive(:select).and_return(:quick_prototype)
      end

      it "presents available workflows for mode" do
        expect(prompt).to receive(:select).with(/Choose a workflow/, kind_of(Array), hash_including(:per_page))

        agent.send(:select_manual_workflow, :execute)
      end

      it "returns selected workflow configuration" do
        result = agent.send(:select_manual_workflow, :execute)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_key]).to eq(:quick_prototype)
        expect(result).to have_key(:steps)
        expect(result).to have_key(:workflow)
      end
    end

    describe "#collect_workflow_details" do
      let(:workflow_selection) { {mode: :execute, user_input: {}} }

      before do
        allow(agent).to receive(:collect_execute_details)
        agent.instance_variable_set(:@user_input, {})
      end

      it "collects execute details for execute mode" do
        expect(agent).to receive(:collect_execute_details)

        agent.send(:collect_workflow_details, workflow_selection)
      end

      it "sets analysis goal for analyze mode" do
        workflow_selection[:mode] = :analyze
        agent.instance_variable_set(:@user_input, {original_goal: "Analyze codebase"})

        agent.send(:collect_workflow_details, workflow_selection)

        user_input = agent.instance_variable_get(:@user_input)
        expect(user_input[:analysis_goal]).to eq("Analyze codebase")
      end

      it "collects execute details for hybrid mode" do
        workflow_selection[:mode] = :hybrid
        expect(agent).to receive(:collect_execute_details)

        agent.send(:collect_workflow_details, workflow_selection)
      end

      it "updates workflow selection with user input" do
        agent.instance_variable_set(:@user_input, {project_description: "Test project"})

        agent.send(:collect_workflow_details, workflow_selection)

        expect(workflow_selection[:user_input]).to eq({project_description: "Test project"})
      end
    end

    describe "#collect_execute_details" do
      before do
        allow(prompt).to receive(:ask).and_return("Build auth system", "Ruby/Rails", "End users", "100% test coverage")
        agent.instance_variable_set(:@user_input, {original_goal: "Build auth"})
      end

      it "skips if details already collected" do
        agent.instance_variable_set(:@user_input, {project_description: "Already done"})

        expect(prompt).not_to receive(:ask)
        agent.send(:collect_execute_details)
      end

      it "collects project description" do
        agent.send(:collect_execute_details)

        user_input = agent.instance_variable_get(:@user_input)
        expect(user_input[:project_description]).to eq("Build auth system")
      end

      it "collects optional tech stack" do
        agent.send(:collect_execute_details)

        user_input = agent.instance_variable_get(:@user_input)
        expect(user_input[:tech_stack]).to eq("Ruby/Rails")
      end

      it "collects optional target users" do
        agent.send(:collect_execute_details)

        user_input = agent.instance_variable_get(:@user_input)
        expect(user_input[:target_users]).to eq("End users")
      end

      it "collects optional success criteria" do
        agent.send(:collect_execute_details)

        user_input = agent.instance_variable_get(:@user_input)
        expect(user_input[:success_criteria]).to eq("100% test coverage")
      end

      it "defaults project description to original goal" do
        expect(prompt).to receive(:ask).with(
          anything,
          hash_including(default: "Build auth")
        ).and_return("Build auth system")

        agent.send(:collect_execute_details)
      end
    end

    describe "#build_plan_summary_for_step_identification" do
      let(:plan) { {goal: "Build auth", requirements: {functional: ["Login"]}} }

      it "includes plan as JSON" do
        result = agent.send(:build_plan_summary_for_step_identification, plan)

        expect(result).to include("Plan Summary")
        expect(result).to include('"goal"')
        expect(result).to include("Build auth")
      end
    end
  end
end
