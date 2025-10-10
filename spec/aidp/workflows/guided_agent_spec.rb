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
      expect(agent.instance_variable_get(:@prompt)).to eq(prompt)
    end

    it "creates a provider manager" do
      expect(agent.instance_variable_get(:@provider_manager)).to eq(provider_manager)
    end

    it "initializes empty conversation history and user input" do
      expect(agent.instance_variable_get(:@conversation_history)).to eq([])
      expect(agent.instance_variable_get(:@user_input)).to eq({})
    end
  end

  describe "#select_workflow" do
    let(:user_goal) { "Build a user authentication feature" }
    let(:ai_response) do
      <<~JSON
        ```json
        {
          "mode": "execute",
          "workflow_key": "feature_development",
          "reasoning": "This is a standard feature that needs architecture and testing",
          "additional_steps": [],
          "questions": [],
          "confidence": "high"
        }
        ```
      JSON
    end

    before do
      # Mock the user input flow
      allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?").and_return(true)

      # Mock provider response
      allow(provider).to receive(:send).and_return({
        status: :success,
        content: ai_response
      })
    end

    it "returns a complete workflow selection" do
      result = agent.select_workflow

      expect(result).to include(
        mode: :execute,
        workflow_key: :feature_development,
        workflow_type: :feature_development,
        steps: kind_of(Array),
        user_input: hash_including(original_goal: user_goal),
        workflow: hash_including(name: kind_of(String))
      )
    end

    it "asks the user for their goal" do
      expect(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      agent.select_workflow
    end

    it "calls the provider with correct parameters" do
      expect(provider).to receive(:send).with(hash_including(
        prompt: kind_of(String)
      )).and_return({
        status: :success,
        content: ai_response
      })

      agent.select_workflow
    end

    context "when user rejects the recommendation" do
      before do
        # First time: reject, second time: accept
        call_count = 0
        allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?") do
          call_count += 1
          !(call_count == 1)
        end
        allow(prompt).to receive(:select).with("What would you like to do?", kind_of(Array))
          .and_return(:restart)
        # Need to ensure ask returns the goal on second iteration
        allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      end

      it "offers alternatives" do
        expect(prompt).to receive(:select).with("What would you like to do?", kind_of(Array))
        agent.select_workflow
      end
    end

    context "when provider request fails" do
      before do
        allow(provider).to receive(:send).and_return({
          status: :error,
          error: "Rate limit exceeded"
        })
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
      end

      it "raises a ConversationError" do
        expect { agent.select_workflow }.to raise_error(
          Aidp::Workflows::GuidedAgent::ConversationError,
          /No provider configured/
        )
      end
    end
  end

  describe "AI response parsing" do
    let(:user_goal) { "Understand this codebase" }

    before do
      allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?").and_return(true)
    end

    context "with analyze mode recommendation" do
      let(:ai_response) do
        <<~JSON
          ```json
          {
            "mode": "analyze",
            "workflow_key": "quick_overview",
            "reasoning": "User wants basic understanding of the codebase",
            "additional_steps": [],
            "questions": [],
            "confidence": "high"
          }
          ```
        JSON
      end

      before do
        allow(provider).to receive(:send).and_return({status: :success, content: ai_response})
      end

      it "correctly parses analyze mode workflow" do
        result = agent.select_workflow
        expect(result[:mode]).to eq(:analyze)
        expect(result[:workflow_key]).to eq(:quick_overview)
      end
    end

    context "with hybrid mode recommendation" do
      let(:ai_response) do
        <<~JSON
          {
            "mode": "hybrid",
            "workflow_key": "legacy_modernization",
            "reasoning": "User needs to analyze then refactor",
            "additional_steps": [],
            "questions": [],
            "confidence": "medium"
          }
        JSON
      end

      before do
        allow(provider).to receive(:send).and_return({status: :success, content: ai_response})
      end

      it "correctly parses hybrid mode workflow" do
        result = agent.select_workflow
        expect(result[:mode]).to eq(:hybrid)
        expect(result[:workflow_key]).to eq(:legacy_modernization)
      end
    end

    context "with custom workflow recommendation" do
      let(:ai_response) do
        <<~JSON
          {
            "mode": "execute",
            "workflow_key": "custom_needed",
            "reasoning": "This requires a custom workflow",
            "additional_steps": ["00_PRD", "16_IMPLEMENTATION"],
            "questions": ["What is your timeline?"],
            "confidence": "medium"
          }
        JSON
      end

      before do
        allow(provider).to receive(:send).and_return({status: :success, content: ai_response})
        # Mock the custom workflow flow
        allow(prompt).to receive(:ask).with("What is your timeline?").and_return("2 weeks")
        allow(prompt).to receive(:multi_select).and_return(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "handles custom workflow recommendation" do
        result = agent.select_workflow
        expect(result[:workflow_key]).to eq(:custom)
        expect(result[:steps]).to include("00_PRD", "16_IMPLEMENTATION")
      end

      it "asks the clarifying questions" do
        expect(prompt).to receive(:ask).with("What is your timeline?")
        agent.select_workflow
      end
    end

    context "with invalid JSON response" do
      let(:ai_response) { "This is not valid JSON" }

      before do
        allow(provider).to receive(:send).and_return({status: :success, content: ai_response})
      end

      it "raises a ConversationError" do
        expect { agent.select_workflow }.to raise_error(
          Aidp::Workflows::GuidedAgent::ConversationError,
          /Could not parse recommendation/
        )
      end
    end
  end

  describe "execute mode workflow details collection" do
    let(:user_goal) { "Build a new API endpoint" }
    let(:ai_response) do
      <<~JSON
        {
          "mode": "execute",
          "workflow_key": "feature_development",
          "reasoning": "Standard feature development workflow",
          "additional_steps": [],
          "questions": [],
          "confidence": "high"
        }
      JSON
    end

    before do
      allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?").and_return(true)
      allow(provider).to receive(:send).and_return({status: :success, content: ai_response})

      # Mock the project details collection
      allow(prompt).to receive(:ask)
        .with("Describe what you're building (can reference your original goal):", default: user_goal)
        .and_return("A REST API endpoint for user management")
      allow(prompt).to receive(:ask)
        .with("Tech stack (e.g., Ruby/Rails, Node.js, Python)? [optional]", required: false)
        .and_return("Ruby/Rails")
      allow(prompt).to receive(:ask)
        .with("Who will use this? [optional]", required: false)
        .and_return("Mobile app developers")
      allow(prompt).to receive(:ask)
        .with("How will you measure success? [optional]", required: false)
        .and_return("API response time < 100ms")
    end

    it "collects project details for execute mode" do
      result = agent.select_workflow

      expect(result[:user_input]).to include(
        project_description: "A REST API endpoint for user management",
        tech_stack: "Ruby/Rails",
        target_users: "Mobile app developers",
        success_criteria: "API response time < 100ms"
      )
    end

    it "asks all required questions" do
      expect(prompt).to receive(:ask).exactly(5).times # goal + 4 project details
      agent.select_workflow
    end
  end

  describe "alternative workflow selection" do
    let(:user_goal) { "Build something" }
    let(:ai_response) do
      <<~JSON
        {
          "mode": "execute",
          "workflow_key": "exploration",
          "reasoning": "Quick exploration workflow",
          "additional_steps": [],
          "questions": [],
          "confidence": "low"
        }
      JSON
    end

    before do
      allow(prompt).to receive(:ask).with("Your goal:", required: true).and_return(user_goal)
      allow(provider).to receive(:send).and_return({status: :success, content: ai_response})
    end

    context "when user chooses a different workflow" do
      before do
        allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?").and_return(false)
        allow(prompt).to receive(:select).with("What would you like to do?", kind_of(Array))
          .and_return(:different_workflow)
        allow(prompt).to receive(:select).with("Choose a workflow:", kind_of(Array), per_page: 15)
          .and_return(:feature_development)
        # Mock execute details collection
        allow(prompt).to receive(:ask).and_return("test")
        allow(prompt).to receive(:ask).with(anything, required: false).and_return(nil)
      end

      it "allows manual workflow selection" do
        result = agent.select_workflow
        expect(result[:workflow_key]).to eq(:feature_development)
      end
    end

    context "when user switches mode" do
      before do
        allow(prompt).to receive(:yes?).with("Does this workflow fit your needs?").and_return(false)
        allow(prompt).to receive(:select).with("What would you like to do?", kind_of(Array))
          .and_return(:different_mode)
        allow(prompt).to receive(:select)
          .with("Select mode:", hash_including("🔬 Analyze Mode" => :analyze))
          .and_return(:analyze)
        allow(prompt).to receive(:select).with("Choose a workflow:", kind_of(Array), per_page: 15)
          .and_return(:quick_overview)
      end

      it "allows switching to analyze mode" do
        result = agent.select_workflow
        expect(result[:mode]).to eq(:analyze)
        expect(result[:workflow_key]).to eq(:quick_overview)
      end
    end
  end
end
