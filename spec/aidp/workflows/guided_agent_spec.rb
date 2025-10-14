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
  end
end
