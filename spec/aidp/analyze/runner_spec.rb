# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Analyze::Runner do
  let(:project_dir) { "/tmp/test_project" }
  let(:test_prompt) { TestPrompt.new }
  let(:harness_runner) { instance_double("Aidp::Harness::Runner") }
  let(:runner) { described_class.new(project_dir, harness_runner, prompt: test_prompt) }
  let(:standalone_runner) { described_class.new(project_dir, nil, prompt: test_prompt) }

  before do
    # Mock file operations for test environment paths only
    allow(File).to receive(:write) # Don't actually write files in tests
    allow(FileUtils).to receive(:mkdir_p) # Don't create directories in tests

    # Mock YAML operations
    allow(YAML).to receive(:load_file).and_return({})

    # Mock specific test project paths but allow real file operations for templates
    allow(File).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).and_call_original

    # Mock only the specific test project files that don't exist
    allow(File).to receive(:exist?).with("#{project_dir}/.aidp/progress/analyze.yml").and_return(false)
    allow(Dir).to receive(:exist?).with("#{project_dir}/.aidp").and_return(true)
    allow(Dir).to receive(:exist?).with("#{project_dir}/.aidp/progress").and_return(true)
  end

  describe "initialization" do
    it "creates analyze runner with harness support" do
      expect(runner).to be_a(described_class)
      expect(runner.progress).to be_a(Aidp::Analyze::Progress)
      # Test behavior: harness mode should be detectable through public interface
      expect(runner.respond_to?(:run_step_with_harness)).to be true
    end

    it "creates standalone analyze runner" do
      expect(standalone_runner).to be_a(described_class)
      expect(standalone_runner.progress).to be_a(Aidp::Analyze::Progress)
      # Test behavior: standalone mode should be detectable through public interface
      expect(standalone_runner.respond_to?(:run_step_standalone)).to be true
    end
  end

  describe "harness integration methods" do
    it "returns all available steps" do
      steps = runner.all_steps
      expect(steps).to be_an(Array)
      expect(steps).to include("01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS", "03_TEST_ANALYSIS")
      expect(steps.size).to eq(Aidp::Analyze::Steps::SPEC.keys.size)
    end

    it "returns next step to execute" do
      allow(runner.progress).to receive(:step_completed?).and_return(false)

      next_step = runner.next_step
      expect(next_step).to eq("01_REPOSITORY_ANALYSIS")
    end

    it "checks if all steps are completed" do
      allow(runner.progress).to receive(:step_completed?).and_return(true)

      expect(runner.all_steps_completed?).to be true
    end

    it "provides harness-compatible interface" do
      expect(runner).to respond_to(:all_steps)
      expect(runner).to respond_to(:next_step)
      expect(runner).to respond_to(:all_steps_completed?)
      expect(runner).to respond_to(:step_completed?)
      expect(runner).to respond_to(:mark_step_completed)
      expect(runner).to respond_to(:mark_step_in_progress)
      expect(runner).to respond_to(:harness_status)
    end
  end

  describe "step execution" do
    let(:step_name) { "01_REPOSITORY_ANALYSIS" }
    let(:options) { {} }

    it "executes step in harness mode" do
      allow(runner).to receive(:run_step_with_harness).and_return({status: "completed"})

      result = runner.run_step(step_name, options)

      expect(runner).to have_received(:run_step_with_harness).with(step_name, options)
      expect(result[:status]).to eq("completed")
    end

    it "executes step in standalone mode" do
      allow(standalone_runner).to receive(:run_step_standalone).and_return({status: "completed"})

      result = standalone_runner.run_step(step_name, options)

      expect(standalone_runner).to have_received(:run_step_standalone).with(step_name, options)
      expect(result[:status]).to eq("completed")
    end
  end

  describe "harness status" do
    before do
      allow(runner.progress).to receive(:completed_steps).and_return(["01_REPOSITORY_ANALYSIS"])
      allow(runner.progress).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")
      allow(runner.progress).to receive(:started_at).and_return(Time.now - 3600)
      allow(runner.progress).to receive(:step_completed?).and_return(false)
      allow(runner.progress).to receive(:step_completed?).with("01_REPOSITORY_ANALYSIS").and_return(true)
    end

    it "returns harness status information" do
      status = runner.harness_status

      expect(status).to include(
        :mode,
        :total_steps,
        :completed_steps,
        :current_step,
        :next_step,
        :all_completed,
        :started_at,
        :progress_percentage
      )
      expect(status[:mode]).to eq(:analyze)
      expect(status[:total_steps]).to eq(Aidp::Analyze::Steps::SPEC.keys.size)
      expect(status[:completed_steps]).to eq(1)
      expect(status[:current_step]).to eq("02_ARCHITECTURE_ANALYSIS")
      expect(status[:next_step]).to eq("02_ARCHITECTURE_ANALYSIS")
      expect(status[:all_completed]).to be false
      expect(status[:started_at]).to be_a(Time)
      expect(status[:progress_percentage]).to be_a(Numeric)
    end
  end

  describe "harness-aware step execution" do
    let(:step_name) { "01_REPOSITORY_ANALYSIS" }
    let(:options) { {focus: "security,performance", format: "json"} }

    before do
      allow(harness_runner).to receive(:current_provider).and_return("claude")
      allow(harness_runner).to receive(:current_step).and_return("01_REPOSITORY_ANALYSIS")
      allow(harness_runner).to receive(:user_input).and_return({"focus_areas" => "security,performance"})
      allow(harness_runner).to receive(:execution_log).and_return([])
      allow(harness_runner).to receive(:provider_manager).and_return(instance_double("ProviderManager"))
    end

    it "executes step with harness context" do
      # Use real project directory for template resolution
      real_runner = described_class.new(Dir.pwd, harness_runner)

      provider_manager = instance_double("ProviderManager")
      allow(harness_runner).to receive(:provider_manager).and_return(provider_manager)
      allow(provider_manager).to receive(:execute_with_provider).and_return({status: "completed", output: "Analysis completed"})

      real_runner.run_step_with_harness(step_name, options)

      expect(provider_manager).to have_received(:execute_with_provider).with(
        "claude",
        anything,
        hash_including(step_name: step_name, project_dir: Dir.pwd, harness_mode: true)
      )
    end

    it "builds harness context for prompts" do
      context = runner.send(:build_harness_context)

      expect(context).to include("## Analysis Context")
      expect(context).to include("Project Directory: #{project_dir}")
      expect(context).to include("Current Step: 01_REPOSITORY_ANALYSIS")
      expect(context).to include("Current Provider: claude")
      expect(context).to include("## Previous User Input")
      expect(context).to include("focus_areas: security,performance")
    end

    it "processes result for harness consumption" do
      raw_result = {
        status: "completed",
        provider: "claude",
        output: "Analysis completed",
        token_usage: {input: 150, output: 300},
        focus_areas: ["security", "performance"],
        export_formats: ["json"]
      }

      processed_result = runner.send(:process_result_for_harness, raw_result, step_name, options)

      expect(processed_result).to include(
        :status,
        :provider,
        :step_name,
        :timestamp,
        :output,
        :metadata
      )
      expect(processed_result[:status]).to eq("completed")
      expect(processed_result[:provider]).to eq("claude")
      expect(processed_result[:step_name]).to eq(step_name)
      expect(processed_result[:output]).to eq("Analysis completed")
      expect(processed_result[:token_usage]).to eq({input: 150, output: 300})
      expect(processed_result[:focus_areas]).to eq(["security", "performance"])
      expect(processed_result[:export_formats]).to eq(["json"])
      expect(processed_result[:metadata][:harness_mode]).to be true
      expect(processed_result[:metadata][:project_dir]).to eq(project_dir)
    end
  end

  describe "error handling" do
    it "raises error for nonexistent step" do
      expect { runner.run_step("nonexistent_step", {}) }.to raise_error("Step 'nonexistent_step' not found")
    end

    it "handles harness execution errors gracefully" do
      # Mock harness runner accessors to raise error - should be handled safely
      allow(harness_runner).to receive(:current_provider).and_raise(StandardError, "Provider error")

      # Should continue with fallback provider and get template error instead
      expect { runner.run_step_with_harness("01_REPOSITORY_ANALYSIS", {}) }.to raise_error(RuntimeError, /Template not found/)
    end
  end
end
