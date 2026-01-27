# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::RunAgentActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }
  let(:mock_prompt_manager) { double("PromptManager") }
  let(:mock_provider_manager) { double("ProviderManager") }
  let(:mock_model_selector) { double("ThinkingDepthManager") }
  let(:mock_config) { {} }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Temporalio::Activity).to receive(:heartbeat)
    allow(Temporalio::Activity).to receive(:cancellation_requested?).and_return(false)
    allow(Aidp::Config).to receive(:load_harness_config).and_return(mock_config)
    allow(Aidp::Execute::PromptManager).to receive(:new).and_return(mock_prompt_manager)
    allow(activity).to receive(:create_provider_manager).and_return(mock_provider_manager)
    allow(activity).to receive(:create_model_selector).and_return(mock_model_selector)
    allow(mock_model_selector).to receive(:select).and_return(["claude", "claude-3-5-sonnet"])
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    let(:base_input) do
      {
        project_dir: project_dir,
        step_name: "implement",
        iteration: 1
      }
    end

    context "when PROMPT.md is missing" do
      before do
        allow(mock_prompt_manager).to receive(:read).and_return(nil)
      end

      it "returns error result" do
        result = activity.execute(base_input)

        expect(result[:success]).to be false
        expect(result[:error]).to include("No PROMPT.md found")
      end
    end

    context "when PROMPT.md exists" do
      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_prompt_manager).to receive(:write)
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: true, output: "Agent output"}
        )
      end

      it "returns success result" do
        result = activity.execute(base_input)

        expect(result[:success]).to be true
        expect(result[:provider]).to eq("claude")
        expect(result[:model]).to eq("claude-3-5-sonnet")
      end

      it "includes iteration in result" do
        result = activity.execute(base_input)

        expect(result[:iteration]).to eq(1)
      end
    end

    context "when agent execution fails" do
      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: false, error: "API error"}
        )
      end

      it "returns error result with message" do
        result = activity.execute(base_input)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("API error")
      end
    end

    context "when agent execution fails without error message" do
      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: false}
        )
      end

      it "uses default error message" do
        result = activity.execute(base_input)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Agent execution failed")
      end
    end

    context "with injected instructions" do
      let(:input_with_instructions) do
        base_input.merge(
          injected_instructions: [
            {content: "Fix the bug first"},
            {content: "Then add tests"}
          ]
        )
      end

      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_prompt_manager).to receive(:write)
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: true, output: "Done"}
        )
      end

      it "injects instructions into prompt" do
        expect(mock_prompt_manager).to receive(:write) do |content|
          expect(content).to include("Additional Instructions")
          expect(content).to include("Fix the bug first")
        end

        activity.execute(input_with_instructions)
      end
    end

    context "with empty instructions" do
      let(:input_empty_instructions) do
        base_input.merge(injected_instructions: [])
      end

      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: true, output: "Done"}
        )
      end

      it "does not modify prompt" do
        expect(mock_prompt_manager).not_to receive(:write)

        activity.execute(input_empty_instructions)
      end
    end

    context "with escalate flag" do
      let(:input_with_escalate) do
        base_input.merge(escalate: true)
      end

      before do
        allow(mock_prompt_manager).to receive(:read).and_return("# Test Prompt")
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: true, output: "Done"}
        )
      end

      it "passes escalate to model selector" do
        expect(activity).to receive(:create_model_selector).with(
          mock_config,
          escalate: true
        ).and_return(mock_model_selector)

        activity.execute(input_with_escalate)
      end
    end
  end

  describe "#inject_instructions (private)" do
    it "appends instructions to prompt" do
      instructions = [{content: "Instruction 1"}, {content: "Instruction 2"}]

      result = activity.send(:inject_instructions, "Original prompt", instructions)

      expect(result).to include("Original prompt")
      expect(result).to include("Additional Instructions")
      expect(result).to include("Instruction 1")
      expect(result).to include("Instruction 2")
    end

    it "handles multiple hash instructions" do
      instructions = [{content: "First"}, {content: "Second"}, {content: "Third"}]

      result = activity.send(:inject_instructions, "Original", instructions)

      expect(result).to include("First")
      expect(result).to include("Second")
      expect(result).to include("Third")
    end
  end

  describe "#execute_agent (private)" do
    before do
      FileUtils.mkdir_p(File.join(project_dir, ".aidp"))
    end

    context "when execution succeeds" do
      before do
        allow(mock_provider_manager).to receive(:execute_with_provider).and_return(
          {success: true, output: "Result", error: nil}
        )
      end

      it "returns success result" do
        result = activity.send(:execute_agent,
          project_dir: project_dir,
          provider_manager: mock_provider_manager,
          provider: "claude",
          model: "test-model",
          prompt_content: "test")

        expect(result[:success]).to be true
        expect(result[:output]).to eq("Result")
      end
    end

    context "when execution raises exception" do
      before do
        allow(mock_provider_manager).to receive(:execute_with_provider).and_raise(
          StandardError.new("Connection failed")
        )
      end

      it "returns error result" do
        result = activity.send(:execute_agent,
          project_dir: project_dir,
          provider_manager: mock_provider_manager,
          provider: "claude",
          model: "test-model",
          prompt_content: "test")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Connection failed")
      end
    end
  end
end
