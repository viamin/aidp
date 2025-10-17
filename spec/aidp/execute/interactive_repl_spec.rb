# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/interactive_repl"

RSpec.describe Aidp::Execute::InteractiveRepl do
  let(:project_dir) { Dir.mktmpdir }
  let(:provider_manager) { double("ProviderManager") }
  let(:config) { {test: true} }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:async_runner) {
    double("AsyncWorkLoopRunner",
      execute_step_async: {state: {state: "RUNNING"}},
      wait: {status: "completed", state: {state: "IDLE"}},
      running?: true,
      state: double("State", paused?: false),
      status: {state: "RUNNING", iteration: 3, queued_instructions: {total: 0}},
      pause: {iteration: 3},
      resume: {iteration: 4},
      cancel: {iteration: 5},
      enqueue_instruction: nil,
      drain_output: [],
      request_guard_update: nil)
  }
  let(:options) { {prompt: prompt} }

  before do
    allow(prompt).to receive(:say)
    allow(prompt).to receive(:error)
    allow(prompt).to receive(:warn)
    allow(prompt).to receive(:ok)
    allow(prompt).to receive(:yes?).and_return(false)
    allow(prompt).to receive(:select).and_return(:continue)
    allow(Aidp::Execute::AsyncWorkLoopRunner).to receive(:new).and_return(async_runner)
    # Add stubs for state update methods used by macros
    allow(async_runner.state).to receive(:request_guard_update)
    allow(async_runner.state).to receive(:request_config_reload)
  end

  after { FileUtils.rm_rf(project_dir) }

  describe "#setup_completion" do
    it "initializes completion proc" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      expect(Reline.completion_proc).to be_a(Proc)
    end
  end

  describe "#print_prompt_text" do
    it "prints prompt text for running state" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(repl).to receive(:print).and_return(nil) # swallow output
      repl.instance_variable_set(:@async_runner, async_runner)
      repl.send(:print_prompt_text)
    end
  end

  describe "#execute_git_rollback" do
    it "refuses rollback on main branch" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(repl).to receive(:`).and_return("main")
      result = repl.send(:execute_git_rollback, 2)
      expect(result[:success]).to be(false)
    end
  end

  describe "#handle_command" do
    it "handles pause macro result" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :pause_work_loop, message: "Paused", data: {}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/pause").and_return(macro_result)
      expect(prompt).to receive(:say).with("Paused")
      repl.send(:handle_command, "/pause")
    end

    it "handles resume macro" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :resume_work_loop, message: "Resumed", data: {}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/resume").and_return(macro_result)
      expect(prompt).to receive(:say).with("Resumed")
      repl.send(:handle_command, "/resume")
    end

    it "handles cancel macro" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :cancel_work_loop, message: "Cancelled", data: {save_checkpoint: true}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/cancel").and_return(macro_result)
      expect(prompt).to receive(:say).with("Cancelled")
      repl.send(:handle_command, "/cancel")
    end

    it "handles enqueue instruction macro" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :enqueue_instruction, message: nil, data: {instruction: "Do it", type: :immediate, priority: 1}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/inject Do it").and_return(macro_result)
      repl.send(:handle_command, "/inject Do it")
    end

    it "handles guard update macro" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :update_guard, message: "Guard updated", data: {key: :max_tokens, value: 1000}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/update guard max_tokens=1000").and_return(macro_result)
      expect(prompt).to receive(:say).with("Guard updated")
      repl.send(:handle_command, "/update guard max_tokens=1000")
    end

    it "handles config reload macro" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: true, action: :reload_config, message: "Config reload queued", data: {}}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).with("/reload config").and_return(macro_result)
      expect(prompt).to receive(:say).with("Config reload queued")
      repl.send(:handle_command, "/reload config")
    end
  end

  describe "output display helpers" do
    it "displays success output entry" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(prompt).to receive(:ok)
      repl.send(:display_output_entry, {message: "Great", type: :success})
    end

    it "displays error output entry" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(prompt).to receive(:error)
      repl.send(:display_output_entry, {message: "Oops", type: :error})
    end

    it "displays warning output entry" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(prompt).to receive(:warn)
      repl.send(:display_output_entry, {message: "Careful", type: :warning})
    end
  end

  describe "#handle_command error path" do
    it "reports error for failed macro execution" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.instance_variable_set(:@async_runner, async_runner)
      macro_result = {success: false, message: "Unknown"}
      allow(repl.instance_variable_get(:@repl_macros)).to receive(:execute).and_return(macro_result)
      expect(prompt).to receive(:error).with("Unknown")
      repl.send(:handle_command, "/bad")
    end
  end
end
