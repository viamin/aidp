# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Execute::Runner do
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
    allow(File).to receive(:exist?).with("#{project_dir}/.aidp/progress/execute.yml").and_return(false)
    allow(Dir).to receive(:exist?).with("#{project_dir}/.aidp").and_return(true)
    allow(Dir).to receive(:exist?).with("#{project_dir}/.aidp/progress").and_return(true)
  end

  describe "initialization" do
    it "creates execute runner with harness support" do
      expect(runner).to be_a(described_class)
      expect(runner.progress).to be_a(Aidp::Execute::Progress)
      # Test behavior: harness mode should be detectable through public interface
      expect(runner.respond_to?(:run_step_with_harness)).to be true
    end

    it "creates standalone execute runner" do
      expect(standalone_runner).to be_a(described_class)
      expect(standalone_runner.progress).to be_a(Aidp::Execute::Progress)
      # Test behavior: standalone mode should be detectable through public interface
      expect(standalone_runner.respond_to?(:run_step_standalone)).to be true
    end
  end

  describe "progress tracking" do
    it "creates progress instance" do
      progress = runner.progress
      expect(progress).to be_a(Aidp::Execute::Progress)
      expect(progress.project_dir).to eq(project_dir)
    end

    it "reuses existing progress instance" do
      progress1 = runner.progress
      progress2 = runner.progress
      expect(progress1).to eq(progress2)
    end
  end

  describe "step execution" do
    let(:step_name) { "00_PRD" }
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

    it "validates step exists before execution" do
      expect { runner.run_step("nonexistent_step", options) }.to raise_error("Step 'nonexistent_step' not found")
    end
  end

  describe "harness integration methods" do
    it "returns all available steps" do
      steps = runner.all_steps
      expect(steps).to be_an(Array)
      expect(steps).to include("00_PRD", "01_NFRS", "02_ARCHITECTURE")
      expect(steps.size).to eq(Aidp::Execute::Steps::SPEC.keys.size)
    end

    it "returns next step to execute" do
      allow(runner.progress).to receive(:step_completed?).and_return(false)

      next_step = runner.next_step
      expect(next_step).to eq("00_LLM_STYLE_GUIDE")
    end

    it "returns nil when all steps completed" do
      allow(runner.progress).to receive(:step_completed?).and_return(true)

      next_step = runner.next_step
      expect(next_step).to be_nil
    end

    it "checks if all steps are completed" do
      allow(runner.progress).to receive(:step_completed?).and_return(true)

      expect(runner.all_steps_completed?).to be true
    end

    it "checks if specific step is completed" do
      allow(runner.progress).to receive(:step_completed?).with("00_PRD").and_return(true)

      expect(runner.step_completed?("00_PRD")).to be true
    end

    it "marks step as completed" do
      allow(runner.progress).to receive(:mark_step_completed).with("00_PRD")

      runner.mark_step_completed("00_PRD")

      expect(runner.progress).to have_received(:mark_step_completed).with("00_PRD")
    end

    it "marks step as in progress" do
      allow(runner.progress).to receive(:mark_step_in_progress).with("00_PRD")

      runner.mark_step_in_progress("00_PRD")

      expect(runner.progress).to have_received(:mark_step_in_progress).with("00_PRD")
    end
  end

  describe "step specification methods" do
    it "gets step specification" do
      spec = runner.get_step_spec("00_PRD")
      expect(spec).to be_a(Hash)
      expect(spec["templates"]).to eq(["planning/create_prd.md"])
      expect(spec["description"]).to eq("Generate Product Requirements Document")
      expect(spec["outs"]).to eq(["docs/prd.md"])
      expect(spec["gate"]).to be false # Changed in simplified workflow
    end

    it "returns nil for nonexistent step" do
      spec = runner.get_step_spec("nonexistent")
      expect(spec).to be_nil
    end

    it "gets step description" do
      description = runner.get_step_description("00_PRD")
      expect(description).to eq("Generate Product Requirements Document")
    end

    it "checks if step is a gate step" do
      expect(runner.is_gate_step?("00_PRD")).to be false # Changed in simplified workflow
      expect(runner.is_gate_step?("03_ADR_FACTORY")).to be false
    end

    it "gets step outputs" do
      outputs = runner.get_step_outputs("00_PRD")
      expect(outputs).to eq(["docs/prd.md"])
    end

    it "gets step templates" do
      templates = runner.get_step_templates("00_PRD")
      expect(templates).to eq(["planning/create_prd.md"])
    end
  end

  describe "harness status" do
    before do
      allow(runner.progress).to receive(:completed_steps).and_return(["00_LLM_STYLE_GUIDE"])
      allow(runner.progress).to receive(:current_step).and_return("00_PRD")
      allow(runner.progress).to receive(:started_at).and_return(Time.now - 3600)
      allow(runner.progress).to receive(:step_completed?).and_return(false)
      allow(runner.progress).to receive(:step_completed?).with("00_LLM_STYLE_GUIDE").and_return(true)
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
      expect(status[:mode]).to eq(:execute)
      expect(status[:total_steps]).to eq(Aidp::Execute::Steps::SPEC.keys.size)
      expect(status[:completed_steps]).to eq(1)
      expect(status[:current_step]).to eq("00_PRD")
      expect(status[:next_step]).to eq("00_PRD")
      expect(status[:all_completed]).to be false
      expect(status[:started_at]).to be_a(Time)
      expect(status[:progress_percentage]).to be_a(Numeric)
    end

    it "calculates progress percentage correctly" do
      allow(runner.progress).to receive(:completed_steps).and_return(["00_PRD", "01_NFRS"])
      total_steps = Aidp::Execute::Steps::SPEC.keys.size
      expected_percentage = (2.0 / total_steps * 100).round(2)

      status = runner.harness_status
      expect(status[:progress_percentage]).to eq(expected_percentage)
    end

    it "shows 100% when all steps completed" do
      allow(runner.progress).to receive(:step_completed?).and_return(true)

      status = runner.harness_status
      expect(status[:progress_percentage]).to eq(100.0)
      expect(status[:all_completed]).to be true
    end
  end

  describe "harness-aware step execution" do
    let(:step_name) { "00_PRD" }
    let(:options) { {user_input: {"project_name" => "Test Project"}} }

    before do
      allow(harness_runner).to receive(:current_provider).and_return("claude")
      allow(harness_runner).to receive(:current_step).and_return("00_PRD")
      allow(harness_runner).to receive(:user_input).and_return({"project_name" => "Test Project"})
      allow(harness_runner).to receive(:execution_log).and_return([])
      allow(harness_runner).to receive(:provider_manager).and_return(instance_double("ProviderManager"))
    end

    it "executes step with harness context" do
      # Use real project directory for template resolution
      actual_project_root = File.expand_path("../../../", __dir__)
      real_runner = described_class.new(actual_project_root, harness_runner)

      provider_manager = instance_double("ProviderManager")
      allow(harness_runner).to receive(:provider_manager).and_return(provider_manager)
      allow(provider_manager).to receive(:execute_with_provider).and_return({status: "completed", output: "Test output"})

      real_runner.run_step_with_harness(step_name, options)

      expect(provider_manager).to have_received(:execute_with_provider).with(
        "claude",
        anything,
        hash_including(step_name: step_name, project_dir: actual_project_root, harness_mode: true)
      )
    end

    it "builds harness context for prompts" do
      context = runner.send(:build_harness_context)

      expect(context).to include("## Execution Context")
      expect(context).to include("Project Directory: #{project_dir}")
      expect(context).to include("Current Step: 00_PRD")
      expect(context).to include("Current Provider: claude")
      expect(context).to include("## Previous User Input")
      expect(context).to include("project_name: Test Project")
    end

    it "processes result for harness consumption" do
      raw_result = {
        status: "completed",
        provider: "claude",
        output: "Test output",
        token_usage: {input: 100, output: 200}
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
      expect(processed_result[:output]).to eq("Test output")
      expect(processed_result[:token_usage]).to eq({input: 100, output: 200})
      expect(processed_result[:metadata][:harness_mode]).to be true
      expect(processed_result[:metadata][:project_dir]).to eq(project_dir)
    end

    it "handles error results" do
      raw_result = {
        status: "error",
        error: "Test error message"
      }

      processed_result = runner.send(:process_result_for_harness, raw_result, step_name, options)

      expect(processed_result[:status]).to eq("error")
      expect(processed_result[:error]).to eq("Test error message")
    end

    it "handles rate limit results" do
      reset_time = Time.now + 300
      raw_result = {
        status: "rate_limited",
        rate_limited: true,
        rate_limit_info: {reset_time: reset_time}
      }

      processed_result = runner.send(:process_result_for_harness, raw_result, step_name, options)

      expect(processed_result[:rate_limited]).to be true
      expect(processed_result[:rate_limit_info]).to eq({reset_time: reset_time})
    end

    it "handles user feedback requests" do
      raw_result = {
        status: "needs_feedback",
        needs_user_feedback: true,
        questions: ["What is the project name?"]
      }

      processed_result = runner.send(:process_result_for_harness, raw_result, step_name, options)

      expect(processed_result[:needs_user_feedback]).to be true
      expect(processed_result[:questions]).to eq(["What is the project name?"])
    end
  end

  describe "template composition" do
    let(:step_name) { "00_PRD" }
    let(:options) { {project_name: "Test Project", description: "Test Description"} }

    # Use a real project directory for template tests
    let(:actual_project_root) { File.expand_path("../../../", __dir__) }
    let(:real_project_runner) { described_class.new(actual_project_root, harness_runner) }

    before do
      # Mock harness runner methods needed for skills registry
      allow(harness_runner).to receive(:current_provider).and_return("anthropic")
    end

    it "composes prompt with template variables using real templates" do
      # This tests the real template resolution and composition
      prompt = real_project_runner.send(:composed_prompt, step_name, options)

      # Ensure proper encoding for the test
      prompt = prompt.force_encoding("UTF-8") if prompt.respond_to?(:force_encoding)

      # Verify that the real template was loaded and contains expected content
      expect(prompt).to include("AI Scaffold Product Requirements Document")
      expect(prompt).to include("You are a product strategist")
      expect(prompt).to be_a(String)
      expect(prompt.length).to be > 100 # Template should have substantial content
    end

    it "composes prompt with harness context using real templates" do
      allow(real_project_runner).to receive(:build_harness_context).and_return("## Execution Context\nTest context")

      prompt = real_project_runner.send(:composed_prompt_with_harness_context, step_name, options)

      # Ensure proper encoding for the test
      prompt = prompt.force_encoding("UTF-8") if prompt.respond_to?(:force_encoding)

      expect(prompt).to include("## Execution Context")
      expect(prompt).to include("Test context")
      # Should also include the real template content
      expect(prompt).to include("AI Scaffold Product Requirements Document")
    end

    it "finds templates in correct search paths" do
      # Reset the global mock for this specific test
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(project_dir, "templates", "planning/create_prd.md")).and_return(true)
      allow(File).to receive(:exist?).with(File.join(project_dir, "templates", "COMMON", "planning/create_prd.md")).and_return(false)

      # Override the find_template mock from the before block
      allow(runner).to receive(:find_template).and_call_original

      template_path = runner.send(:find_template, "planning/create_prd.md")

      expect(template_path).to eq(File.join(project_dir, "templates", "planning/create_prd.md"))
    end

    it "searches common templates path" do
      # Reset the global mock for this specific test
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(project_dir, "templates", "EXECUTE", "00_PRD.md")).and_return(false)
      allow(File).to receive(:exist?).with(File.join(project_dir, "templates", "COMMON", "00_PRD.md")).and_return(true)

      # Override the find_template mock from the before block
      allow(runner).to receive(:find_template).and_call_original

      template_path = runner.send(:find_template, "00_PRD.md")

      expect(template_path).to eq(File.join(project_dir, "templates", "COMMON", "00_PRD.md"))
    end
  end

  describe "standalone execution" do
    let(:step_name) { "00_PRD" }
    let(:options) { {} }
    let(:actual_project_root) { File.expand_path("../../../", __dir__) }
    let(:real_standalone_runner) { described_class.new(actual_project_root) }

    it "executes step synchronously" do
      result = real_standalone_runner.run_step_standalone(step_name, options)

      expect(result[:status]).to eq("completed")
      expect(result[:provider]).to eq("cursor")
      expect(result[:message]).to include("Execution step #{step_name} completed successfully")
    end
  end

  describe "error handling" do
    it "raises error for nonexistent step" do
      expect { runner.run_step("nonexistent_step", {}) }.to raise_error("Step 'nonexistent_step' not found")
    end

    it "raises error when template not found" do
      # Create a runner that will look for a template that doesn't exist
      # by using a real step but making the template file unavailable
      allow(File).to receive(:exist?).with(/.*00_PRD\.md$/).and_return(false)

      # Mock harness runner accessors for error handling
      allow(harness_runner).to receive(:current_provider).and_return("cursor")

      expect { runner.run_step("00_PRD", {}) }.to raise_error("Template not found for step 00_PRD")
    end

    it "handles harness execution errors gracefully" do
      # Mock harness runner accessors to raise error
      allow(harness_runner).to receive(:current_provider).and_raise(StandardError, "Test error")

      expect { runner.run_step_with_harness("00_PRD", {}) }.to raise_error(StandardError, "Test error")
    end
  end

  describe "integration with harness runner" do
    it "works with harness runner instance" do
      # Test integration through public behavior instead of internal state
      expect(runner.respond_to?(:run_step_with_harness)).to be true
      # Test harness mode through behavior, not internal state
      expect(runner.respond_to?(:run_step_with_harness)).to be true
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
end
