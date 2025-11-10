# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"
require "tmpdir"

RSpec.describe "Work Loop Header Prepending" do
  let(:provider_manager) { double("ProviderManager", current_provider: "test") }
  let(:config) { double("Config", guards_config: {}) }
  let(:prompt_content) { "## Tasks\n- [ ] Implement feature X" }

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
    runner = Aidp::Execute::WorkLoopRunner.new(@tmpdir, provider_manager, config)
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
