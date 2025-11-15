# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"
require "tmpdir"

RSpec.describe "Work Loop Header Prepending" do
  let(:provider_manager) { double("ProviderManager", current_provider: "test") }
  let(:config) do
    double("Config",
      guards_config: {},
      # Thinking depth configuration
      default_tier: "standard",
      max_tier: "pro",
      allow_provider_switch_for_tier?: true,
      escalation_fail_attempts: 2,
      escalation_complexity_threshold: {files_changed: 10, modules_touched: 5},
      permission_for_tier: "tools",
      tier_override_for: nil)
  end
  let(:prompt_content) { "## Tasks\n- [ ] Implement feature X" }

  # Mock CapabilityRegistry for ThinkingDepthManager
  let(:mock_registry) do
    instance_double("CapabilityRegistry",
      valid_tier?: true,
      compare_tiers: 0,
      next_tier: nil,
      previous_tier: nil,
      best_model_for_tier: ["anthropic", "claude-3-5-sonnet-20241022", {tier: "standard"}],
      provider_names: ["anthropic"])
  end

  before do
    # Mock CapabilityRegistry class
    registry_class = Class.new do
      def initialize(*args)
      end
    end

    stub_const("Aidp::Harness::CapabilityRegistry", registry_class)
    allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(mock_registry)
  end

  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      aidp_dir = File.join(@tmpdir, ".aidp")
      FileUtils.mkdir_p(aidp_dir)
      File.write(File.join(aidp_dir, "PROMPT.md"), prompt_content)

      example.run
    end
  end

  def create_runner
    test_prompt = TestPrompt.new
    runner = Aidp::Execute::WorkLoopRunner.new(@tmpdir, provider_manager, config, prompt: test_prompt)
    runner.instance_variable_set(:@step_name, "16_IMPLEMENTATION")
    runner.instance_variable_set(:@iteration_count, 3)
    runner
  end

  describe "#send_to_agent" do
    it "prepends work loop header to prompt" do
      runner = create_runner
      sent_prompt = nil
      allow(provider_manager).to receive(:execute_with_provider) do |_, prompt, _|
        sent_prompt = prompt
        {status: "success"}
      end

      runner.send(:send_to_agent)

      expect(sent_prompt).to include("# Work Loop: 16_IMPLEMENTATION (Iteration 3)")
      expect(sent_prompt).to include(prompt_content)
    end

    it "includes instructions to write/edit code files" do
      runner = create_runner
      sent_prompt = nil
      allow(provider_manager).to receive(:execute_with_provider) do |_, prompt, _|
        sent_prompt = prompt
        {status: "success"}
      end

      runner.send(:send_to_agent)

      expect(sent_prompt).to include("**Write/edit code files**")
      expect(sent_prompt).to include("You are working in a work loop")
    end

    it "includes working directory" do
      runner = create_runner
      sent_prompt = nil
      allow(provider_manager).to receive(:execute_with_provider) do |_, prompt, _|
        sent_prompt = prompt
        {status: "success"}
      end

      runner.send(:send_to_agent)

      expect(sent_prompt).to include("The working directory is: #{@tmpdir}")
    end

    it "changes to project directory before calling provider" do
      runner = create_runner
      execution_dir = nil
      allow(provider_manager).to receive(:execute_with_provider) do |_, _, _|
        execution_dir = Dir.pwd
        {status: "success"}
      end

      runner.send(:send_to_agent)

      expect(execution_dir).to eq(@tmpdir)
    end
  end

  describe "#build_work_loop_header" do
    it "generates header with step and iteration" do
      runner = create_runner
      header = runner.send(:build_work_loop_header, "TEST_STEP", 5)

      expect(header).to include("# Work Loop: TEST_STEP (Iteration 5)")
      expect(header).to include("## Instructions")
      expect(header).to include("**Write/edit code files**")
    end
  end
end
