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
  let(:async_runner_class) do
    class_double(Aidp::Execute::AsyncWorkLoopRunner).tap do |klass|
      allow(klass).to receive(:new).and_return(async_runner)
    end
  end
  let(:options) { {prompt: prompt, async_runner_class: async_runner_class} }
  let(:options_with_runner) { {prompt: prompt, async_runner_class: async_runner_class, async_runner: async_runner} }

  before do
    allow(prompt).to receive(:say)
    allow(prompt).to receive(:error)
    allow(prompt).to receive(:warn)
    allow(prompt).to receive(:ok)
    allow(prompt).to receive(:yes?).and_return(false)
    allow(prompt).to receive(:select).and_return(:continue)
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
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(repl).to receive(:print).and_return(nil) # swallow output
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
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :pause_work_loop, message: "Paused", data: {}}
      allow(repl.repl_macros).to receive(:execute).with("/pause").and_return(macro_result)
      expect(prompt).to receive(:say).with("Paused")
      repl.send(:handle_command, "/pause")
    end

    it "handles resume macro" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :resume_work_loop, message: "Resumed", data: {}}
      allow(repl.repl_macros).to receive(:execute).with("/resume").and_return(macro_result)
      expect(prompt).to receive(:say).with("Resumed")
      repl.send(:handle_command, "/resume")
    end

    it "handles cancel macro" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :cancel_work_loop, message: "Cancelled", data: {save_checkpoint: true}}
      allow(repl.repl_macros).to receive(:execute).with("/cancel").and_return(macro_result)
      expect(prompt).to receive(:say).with("Cancelled")
      repl.send(:handle_command, "/cancel")
    end

    it "handles enqueue instruction macro" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :enqueue_instruction, message: nil, data: {instruction: "Do it", type: :immediate, priority: 1}}
      allow(repl.repl_macros).to receive(:execute).with("/inject Do it").and_return(macro_result)
      repl.send(:handle_command, "/inject Do it")
    end

    it "handles guard update macro" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :update_guard, message: "Guard updated", data: {key: :max_tokens, value: 1000}}
      allow(repl.repl_macros).to receive(:execute).with("/update guard max_tokens=1000").and_return(macro_result)
      expect(prompt).to receive(:say).with("Guard updated")
      repl.send(:handle_command, "/update guard max_tokens=1000")
    end

    it "handles config reload macro" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: true, action: :reload_config, message: "Config reload queued", data: {}}
      allow(repl.repl_macros).to receive(:execute).with("/reload config").and_return(macro_result)
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
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      macro_result = {success: false, message: "Unknown"}
      allow(repl.repl_macros).to receive(:execute).and_return(macro_result)
      expect(prompt).to receive(:error).with("Unknown")
      repl.send(:handle_command, "/bad")
    end
  end

  describe "#initialize" do
    it "initializes with default prompt when not provided" do
      allow(TTY::Prompt).to receive(:new).and_return(prompt)
      repl = described_class.new(project_dir, provider_manager, config)
      # Use the public async_runner accessor to verify initialization works
      expect(repl.async_runner).to be_nil
    end

    it "initializes with provided prompt" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      # Verify options are used by checking repl_macros is initialized
      expect(repl.repl_macros).to be_a(Aidp::Execute::ReplMacros)
    end

    it "initializes repl macros" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      expect(repl.repl_macros).to be_a(Aidp::Execute::ReplMacros)
    end
  end

  describe "#display_welcome" do
    it "displays welcome message" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      expect(prompt).to receive(:say).at_least(:once)
      repl.send(:display_welcome, "test_step")
    end
  end

  describe "#display_completion" do
    it "displays completed status" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      result = {status: "completed", iterations: 5}
      expect(prompt).to receive(:ok).with(/completed/)
      repl.send(:display_completion, result)
    end

    it "displays cancelled status" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      result = {status: "cancelled", iterations: 3}
      expect(prompt).to receive(:warn).with(/cancelled/)
      repl.send(:display_completion, result)
    end

    it "displays error status" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      result = {status: "error", iterations: 2}
      expect(prompt).to receive(:error).with(/error/)
      repl.send(:display_completion, result)
    end
  end

  describe "#handle_rollback" do
    it "pauses work loop before rollback" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(repl).to receive(:execute_git_rollback).and_return({success: true, message: "Done"})
      allow(async_runner.state).to receive(:paused?).and_return(false)

      repl.send(:handle_rollback, 2)

      expect(async_runner).to have_received(:pause)
    end

    it "asks to resume after successful rollback" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(repl).to receive(:execute_git_rollback).and_return({success: true, message: "Done"})
      allow(async_runner.state).to receive(:paused?).and_return(true)

      repl.send(:handle_rollback, 2)

      expect(prompt).to have_received(:yes?)
    end
  end

  describe "#handle_interrupt" do
    it "handles cancel choice" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(prompt).to receive(:select).and_return(:cancel)

      repl.send(:handle_interrupt)

      expect(async_runner).to have_received(:cancel).with(save_checkpoint: true)
      expect(repl.running).to be false
    end

    it "handles pause choice" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(prompt).to receive(:select).and_return(:pause)

      repl.send(:handle_interrupt)

      expect(async_runner).to have_received(:pause)
    end

    it "handles continue choice" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(prompt).to receive(:select).and_return(:continue)

      repl.send(:handle_interrupt)

      expect(async_runner).not_to have_received(:cancel)
      expect(async_runner).not_to have_received(:pause)
    end
  end

  describe "#display_output_entry" do
    it "handles info type" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      expect(prompt).to receive(:say).with("info message")
      repl.send(:display_output_entry, {message: "info message", type: :info})
    end
  end

  describe "#read_command_with_timeout" do
    it "returns nil on Ctrl-D" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(Reline).to receive(:readline).and_return(nil)
      allow(repl).to receive(:print)
      result = repl.send(:read_command_with_timeout)
      expect(result).to be_nil
    end

    it "handles errors gracefully" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(Reline).to receive(:readline).and_raise(StandardError.new("Test error"))
      allow(repl).to receive(:print)
      result = repl.send(:read_command_with_timeout)
      expect(result).to be_nil
    end
  end

  describe "#setup_completion" do
    it "sets up completion proc" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      expect(Reline.completion_proc).to be_a(Proc)
    end

    it "marks completion as set up" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      expect(repl.completion_setup_needed).to be false
    end
  end

  describe "#print_prompt_text" do
    it "displays state in prompt for PAUSED" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:status).and_return({state: "PAUSED", iteration: 5, queued_instructions: {total: 0}})
      expect(repl).to receive(:print).with(a_string_matching(/PAUSED/))
      repl.send(:print_prompt_text)
    end

    it "displays state in prompt for CANCELLED" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:status).and_return({state: "CANCELLED", iteration: 3, queued_instructions: {total: 0}})
      expect(repl).to receive(:print).with(a_string_matching(/CANCELLED/))
      repl.send(:print_prompt_text)
    end

    it "displays queued instructions for IDLE state" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:status).and_return({state: "IDLE", iteration: 2, queued_instructions: {total: 3}})
      expect(repl).to receive(:print).with(a_string_matching(/\+3/))
      repl.send(:print_prompt_text)
    end
  end

  describe "#execute_git_rollback" do
    it "refuses rollback on master branch" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(repl).to receive(:`).with("git branch --show-current").and_return("master")
      result = repl.send(:execute_git_rollback, 1)
      expect(result[:success]).to be false
      expect(result[:message]).to include("master")
    end

    it "refuses rollback on empty branch" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      allow(repl).to receive(:`).with("git branch --show-current").and_return("")
      result = repl.send(:execute_git_rollback, 1)
      expect(result[:success]).to be false
    end
  end

  describe "#start_output_display" do
    it "starts output display thread" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:running?).and_return(false)
      repl.send(:start_output_display)
      # Access thread via send since it's a private instance variable
      thread = repl.send(:instance_variable_get, :@output_display_thread)
      expect(thread).to be_a(Thread)
      thread.kill
      thread.join(1)
    end
  end

  describe "#stop_output_display" do
    it "stops output display thread" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:running?).and_return(false)
      repl.send(:start_output_display)
      repl.send(:stop_output_display)
      # Access thread via send since it's a private instance variable
      thread = repl.send(:instance_variable_get, :@output_display_thread)
      expect(thread).to be_nil
    end

    it "drains remaining output" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(async_runner).to receive(:drain_output).and_return([{message: "test", type: :info}])
      expect(prompt).to receive(:say).with("test")
      repl.send(:stop_output_display)
    end
  end

  describe "#handle_rollback" do
    it "reports rollback success" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(repl).to receive(:execute_git_rollback).and_return({success: true, message: "Rolled back"})
      allow(async_runner.state).to receive(:paused?).and_return(false)

      expect(prompt).to receive(:ok).with(/Rolled back/)
      repl.send(:handle_rollback, 2)
    end

    it "reports rollback failure" do
      repl = described_class.new(project_dir, provider_manager, config, options_with_runner)
      allow(repl).to receive(:execute_git_rollback).and_return({success: false, message: "Failed"})
      allow(async_runner.state).to receive(:paused?).and_return(false)

      expect(prompt).to receive(:error).with(/Failed/)
      repl.send(:handle_rollback, 2)
    end
  end

  describe "completion proc" do
    it "completes commands" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      completions = Reline.completion_proc.call("/pau")
      expect(completions).to be_an(Array)
    end

    it "completes /ws subcommands" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      completions = Reline.completion_proc.call("/ws lis")
      expect(completions).to include("list")
    end

    it "completes /skill subcommands" do
      repl = described_class.new(project_dir, provider_manager, config, options)
      repl.send(:setup_completion)
      completions = Reline.completion_proc.call("/skill sho")
      expect(completions).to include("show")
    end
  end
end
