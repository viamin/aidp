# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::RunWorkLoopIterationActivity do
  let(:activity) { described_class.new }

  describe "#execute" do
    let(:input) do
      {
        project_dir: "/tmp/project",
        issue_number: 123,
        plan: {title: "Test plan"},
        iteration: 2
      }
    end

    before do
      allow(activity).to receive(:with_activity_context).and_yield
      allow(activity).to receive(:start_heartbeat_thread).and_return(instance_double("Thread", kill: true))
      allow(activity).to receive(:heartbeat)
      allow(activity).to receive(:check_cancellation!)
      allow(activity).to receive(:log_activity)
    end

    it "returns success when tests pass" do
      allow(activity).to receive(:run_agent).and_return({success: true, output: "done"})
      allow(activity).to receive(:run_tests).and_return({all_passing: true, results: {}})

      result = activity.execute(input)

      expect(result[:success]).to be true
      expect(result[:tests_passing]).to be true
      expect(result[:result][:agent_output]).to eq("done")
    end

    it "returns error when agent fails" do
      allow(activity).to receive(:run_agent).and_return({success: false, error: "boom"})

      result = activity.execute(input)

      expect(result[:success]).to be false
      expect(result[:error]).to include("Agent failed")
      expect(result[:tests_passing]).to be false
    end

    it "updates prompt when tests fail" do
      allow(activity).to receive(:run_agent).and_return({success: true, output: "done"})
      allow(activity).to receive(:run_tests).and_return({all_passing: false, results: {test: {success: false, output: "fail"}}})
      allow(activity).to receive(:update_prompt_with_failures)

      result = activity.execute(input)

      expect(activity).to have_received(:update_prompt_with_failures)
      expect(result[:success]).to be true
      expect(result[:tests_passing]).to be false
    end
  end

  describe "#run_agent" do
    let(:prompt_manager) do
      double(
        "PromptManager",
        read: nil,
        write: true,
        prompt_path: "/tmp/project/.aidp/PROMPT.md"
      )
    end
    let(:provider_manager) { instance_double("ProviderManager") }
    let(:config) { double("Config") }
    let(:model_selector) { double("ThinkingDepthManager", select: ["provider", "model"]) }

    before do
      allow(activity).to receive(:load_config).and_return(config)
      allow(activity).to receive(:create_provider_manager).and_return(provider_manager)
      allow(provider_manager).to receive(:execute_with_provider).and_return({success: true, output: "ok"})
      allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
      allow(Aidp::Harness::ThinkingDepthManager).to receive(:new).and_return(model_selector)
      allow(activity).to receive(:log_activity)
    end

    it "builds initial prompt when missing and executes provider" do
      result = activity.send(
        :run_agent,
        project_dir: "/tmp/project",
        issue_number: 123,
        plan: {title: "Plan title"},
        iteration: 1,
        injected_instructions: []
      )

      expect(prompt_manager).to have_received(:write).with(include("Plan title"))
      expect(result[:success]).to be true
    end

    it "injects instructions when provided" do
      result = activity.send(
        :run_agent,
        project_dir: "/tmp/project",
        issue_number: 123,
        plan: {title: "Plan title"},
        iteration: 1,
        injected_instructions: [{content: "Do X"}]
      )

      expect(prompt_manager).to have_received(:write).at_least(:once)
      expect(result[:success]).to be true
    end

    it "returns error on provider failure" do
      allow(provider_manager).to receive(:execute_with_provider).and_raise(StandardError.new("provider failed"))
      allow(Aidp).to receive(:log_error)

      result = activity.send(
        :run_agent,
        project_dir: "/tmp/project",
        issue_number: 123,
        plan: {title: "Plan title"},
        iteration: 1,
        injected_instructions: []
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq("provider failed")
    end
  end

  describe "#run_tests" do
    let(:config) { double("Config") }
    let(:runner) { double("TestRunner") }

    before do
      allow(activity).to receive(:load_config).and_return(config)
      allow(Aidp::Harness::TestRunner).to receive(:new).and_return(runner)
    end

    it "returns all_passing when all checks succeed" do
      allow(runner).to receive(:run_tests).and_return({success: true})
      allow(runner).to receive(:run_lint).and_return({success: true})

      result = activity.send(:run_tests, project_dir: "/tmp/project")

      expect(result[:all_passing]).to be true
    end

    it "returns error when runner raises" do
      allow(Aidp::Harness::TestRunner).to receive(:new).and_raise(StandardError.new("runner error"))
      allow(Aidp).to receive(:log_error)

      result = activity.send(:run_tests, project_dir: "/tmp/project")

      expect(result[:all_passing]).to be false
      expect(result[:error]).to eq("runner error")
    end
  end

  describe "#update_prompt_with_failures" do
    let(:prompt_manager) { instance_double(Aidp::Execute::PromptManager, read: "Current prompt", write: true) }

    before do
      allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
    end

    it "writes updated prompt when prompt exists" do
      test_result = {
        results: {
          test: {success: false, output: "failure output"}
        }
      }

      activity.send(:update_prompt_with_failures, "/tmp/project", test_result)

      expect(prompt_manager).to have_received(:write).with(include("Failures to Fix"))
    end

    it "skips when prompt is missing" do
      allow(prompt_manager).to receive(:read).and_return(nil)

      activity.send(:update_prompt_with_failures, "/tmp/project", {})

      expect(prompt_manager).not_to have_received(:write)
    end
  end

  describe "#build_initial_prompt" do
    it "includes issue number" do
      plan = {title: "Test fix", requirements: ["req1"], steps: [{description: "step1"}]}

      result = activity.send(:build_initial_prompt, plan, 123)

      expect(result).to include("Issue #123")
      expect(result).to include("Test fix")
    end

    it "includes requirements when present" do
      plan = {title: "Fix", requirements: ["Must do A", "Must do B"]}

      result = activity.send(:build_initial_prompt, plan, 456)

      expect(result).to include("Must do A")
      expect(result).to include("Must do B")
    end

    it "includes steps when present" do
      plan = {title: "Fix", steps: [{description: "First"}, {description: "Second"}]}

      result = activity.send(:build_initial_prompt, plan, 789)

      expect(result).to include("First")
      expect(result).to include("Second")
    end

    it "handles missing requirements and steps" do
      plan = {title: "Fix"}

      result = activity.send(:build_initial_prompt, plan, 100)

      expect(result).to include("Issue #100")
      expect(result).to include("Fix")
    end
  end

  describe "#inject_instructions" do
    it "appends instructions to prompt" do
      prompt = "Original prompt"
      instructions = [{content: "Do this"}, {content: "Do that"}]

      result = activity.send(:inject_instructions, prompt, instructions)

      expect(result).to include("Original prompt")
      expect(result).to include("Additional Instructions")
      expect(result).to include("Do this")
      expect(result).to include("Do that")
    end

    it "handles string instructions" do
      prompt = "Test"
      instructions = [{content: "Instruction 1"}, {content: "Instruction 2"}]

      result = activity.send(:inject_instructions, prompt, instructions)

      expect(result).to include("Instruction 1")
      expect(result).to include("Instruction 2")
    end

    it "handles empty instructions" do
      prompt = "Test"
      instructions = []

      result = activity.send(:inject_instructions, prompt, instructions)

      expect(result).to include("Test")
      expect(result).to include("Additional Instructions")
    end
  end

  describe "#extract_failures" do
    it "extracts test failures" do
      test_result = {
        results: {
          test: {success: false, output: "Test failed: assertion error"},
          lint: {success: false, output: "Lint error: trailing space"}
        }
      }

      result = activity.send(:extract_failures, test_result)

      expect(result).to include("Test Failures")
      expect(result).to include("assertion error")
      expect(result).to include("Lint Failures")
      expect(result).to include("trailing space")
    end

    it "skips successful phases" do
      test_result = {
        results: {
          test: {success: true, output: "All passed"},
          lint: {success: false, output: "Error here"}
        }
      }

      result = activity.send(:extract_failures, test_result)

      expect(result).not_to include("Test Failures")
      expect(result).to include("Lint Failures")
    end

    it "handles missing results" do
      test_result = {}

      result = activity.send(:extract_failures, test_result)

      expect(result).to eq("")
    end
  end

  describe "#truncate" do
    it "returns text unchanged when under limit" do
      text = "Short text"

      result = activity.send(:truncate, text, 100)

      expect(result).to eq("Short text")
    end

    it "truncates text over limit" do
      text = "a" * 2000

      result = activity.send(:truncate, text, 1000)

      expect(result.length).to be < 1050
      expect(result).to include("truncated")
    end

    it "handles nil text" do
      result = activity.send(:truncate, nil, 100)

      expect(result).to eq("")
    end
  end
end
