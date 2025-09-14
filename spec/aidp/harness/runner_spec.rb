# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Harness::Runner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:runner) { described_class.new(temp_dir, :analyze) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with analyze mode" do
      expect(runner.instance_variable_get(:@mode)).to eq(:analyze)
      expect(runner.instance_variable_get(:@project_dir)).to eq(temp_dir)
    end

    it "initializes with execute mode" do
      execute_runner = described_class.new(temp_dir, :execute)
      expect(execute_runner.instance_variable_get(:@mode)).to eq(:execute)
    end

    it "initializes all components" do
      expect(runner.instance_variable_get(:@configuration)).to be_a(Aidp::Harness::Configuration)
      expect(runner.instance_variable_get(:@state_manager)).to be_a(Aidp::Harness::StateManager)
      expect(runner.instance_variable_get(:@condition_detector)).to be_a(Aidp::Harness::ConditionDetector)
      expect(runner.instance_variable_get(:@provider_manager)).to be_a(Aidp::Harness::ProviderManager)
      expect(runner.instance_variable_get(:@user_interface)).to be_a(Aidp::Harness::UserInterface)
      expect(runner.instance_variable_get(:@error_handler)).to be_a(Aidp::Harness::ErrorHandler)
      expect(runner.instance_variable_get(:@status_display)).to be_a(Aidp::Harness::StatusDisplay)
    end

    it "initializes with idle state" do
      expect(runner.instance_variable_get(:@state)).to eq("idle")
    end
  end

  describe "#status" do
    it "returns current harness status" do
      status = runner.status

      expect(status).to have_key(:state)
      expect(status).to have_key(:mode)
      expect(status).to have_key(:current_step)
      expect(status).to have_key(:current_provider)
      expect(status).to have_key(:start_time)
      expect(status).to have_key(:duration)
      expect(status).to have_key(:user_input_count)
      expect(status).to have_key(:execution_log_count)
      expect(status).to have_key(:progress)
    end

    it "includes progress summary" do
      status = runner.status
      expect(status[:progress]).to be_a(Hash)
      expect(status[:progress]).to have_key(:mode)
      expect(status[:progress]).to have_key(:completed_steps)
      expect(status[:progress]).to have_key(:total_steps)
    end
  end

  describe "#detailed_status" do
    it "returns comprehensive status information" do
      status = runner.detailed_status

      expect(status).to have_key(:harness)
      expect(status).to have_key(:configuration)
      expect(status).to have_key(:provider_manager)
      expect(status).to have_key(:error_stats)
    end
  end

  describe "#pause" do
    it "pauses the harness" do
      runner.instance_variable_set(:@state, "running")
      runner.pause
      expect(runner.instance_variable_get(:@state)).to eq("paused")
    end

    it "does not pause if not running" do
      runner.instance_variable_set(:@state, "idle")
      runner.pause
      expect(runner.instance_variable_get(:@state)).to eq("idle")
    end
  end

  describe "#resume" do
    it "resumes the harness" do
      runner.instance_variable_set(:@state, "paused")
      runner.resume
      expect(runner.instance_variable_get(:@state)).to eq("running")
    end

    it "does not resume if not paused" do
      runner.instance_variable_set(:@state, "idle")
      runner.resume
      expect(runner.instance_variable_get(:@state)).to eq("idle")
    end
  end

  describe "#stop" do
    it "stops the harness" do
      runner.instance_variable_set(:@state, "running")
      runner.stop
      expect(runner.instance_variable_get(:@state)).to eq("stopped")
    end
  end

  describe "#get_mode_runner" do
    it "returns analyze runner for analyze mode" do
      mode_runner = runner.send(:get_mode_runner)
      expect(mode_runner).to be_a(Aidp::Analyze::Runner)
    end

    it "returns execute runner for execute mode" do
      execute_runner = described_class.new(temp_dir, :execute)
      mode_runner = execute_runner.send(:get_mode_runner)
      expect(mode_runner).to be_a(Aidp::Execute::Runner)
    end

    it "raises error for unsupported mode" do
      runner.instance_variable_set(:@mode, :invalid)
      expect { runner.send(:get_mode_runner) }.to raise_error(ArgumentError)
    end
  end

  describe "#get_next_step" do
    it "delegates to state manager", pending: "State manager delegation not fully implemented" do
      state_manager = double("state_manager")
      allow(state_manager).to receive(:next_step).and_return("next_step")
      runner.instance_variable_set(:@state_manager, state_manager)

      result = runner.send(:get_next_step, nil)
      expect(result).to eq("next_step")
      expect(state_manager).to have_received(:next_step)
    end
  end

  describe "#execute_step" do
    let(:mock_runner) { double("mode_runner") }
    let(:state_manager) { double("state_manager") }
    let(:status_display) { double("status_display") }
    let(:provider_manager) { double("provider_manager") }
    let(:error_handler) { double("error_handler") }
    let(:condition_detector) { double("condition_detector") }

    before do
      runner.instance_variable_set(:@state_manager, state_manager)
      runner.instance_variable_set(:@status_display, status_display)
      runner.instance_variable_set(:@provider_manager, provider_manager)
      runner.instance_variable_set(:@error_handler, error_handler)
      runner.instance_variable_set(:@condition_detector, condition_detector)

      allow(state_manager).to receive(:mark_step_in_progress)
      allow(state_manager).to receive(:mark_step_completed)
      allow(status_display).to receive(:update_current_step)
      allow(status_display).to receive(:update_current_provider)
      allow(provider_manager).to receive(:current_provider).and_return("cursor")
      allow(error_handler).to receive(:execute_with_retry).and_yield.and_return({status: "completed"})
      allow(condition_detector).to receive(:needs_user_feedback?).and_return(false)
      allow(condition_detector).to receive(:is_rate_limited?).and_return(false)
      allow(mock_runner).to receive(:run_step).and_return({status: "completed"})
    end

    it "executes step successfully", pending: "Mode runner delegation not fully implemented" do
      result = runner.send(:execute_step, mock_runner, "test_step")

      expect(state_manager).to have_received(:mark_step_in_progress).with("test_step")
      expect(status_display).to have_received(:update_current_step).with("test_step")
      expect(status_display).to have_received(:update_current_provider).with("cursor")
      expect(mock_runner).to have_received(:run_step).with("test_step", hash_including(user_input: {}))
      expect(state_manager).to have_received(:mark_step_completed).with("test_step")
      expect(result[:status]).to eq("completed")
    end

    it "handles user feedback request", pending: "Mode runner delegation not fully implemented" do
      allow(condition_detector).to receive(:needs_user_feedback?).and_return(true)
      allow(condition_detector).to receive(:extract_questions).and_return([{question: "test?"}])

      user_interface = double("user_interface")
      allow(user_interface).to receive(:collect_feedback).and_return({"question_1" => "answer"})
      runner.instance_variable_set(:@user_interface, user_interface)

      runner.send(:execute_step, mock_runner, "test_step")

      expect(user_interface).to have_received(:collect_feedback)
    end

    it "handles rate limiting", pending: "Mode runner delegation not fully implemented" do
      allow(condition_detector).to receive(:is_rate_limited?).and_return(true)
      allow(provider_manager).to receive(:mark_rate_limited)
      allow(provider_manager).to receive(:switch_provider).and_return("claude")

      runner.send(:execute_step, mock_runner, "test_step")

      expect(provider_manager).to have_received(:mark_rate_limited).with("cursor")
      expect(provider_manager).to have_received(:switch_provider)
    end
  end

  describe "#handle_user_feedback_request" do
    let(:condition_detector) { double("condition_detector") }
    let(:user_interface) { double("user_interface") }
    let(:state_manager) { double("state_manager") }

    before do
      runner.instance_variable_set(:@condition_detector, condition_detector)
      runner.instance_variable_set(:@user_interface, user_interface)
      runner.instance_variable_set(:@state_manager, state_manager)

      allow(condition_detector).to receive(:extract_questions).and_return([{question: "test?"}])
      allow(user_interface).to receive(:collect_feedback).and_return({"question_1" => "answer"})
      allow(state_manager).to receive(:add_user_input)
    end

    it "collects and stores user feedback" do
      result = {output: "Please provide feedback"}

      runner.send(:handle_user_feedback_request, result)

      expect(condition_detector).to have_received(:extract_questions).with(result)
      expect(user_interface).to have_received(:collect_feedback)
      expect(state_manager).to have_received(:add_user_input).with("question_1", "answer")
      expect(runner.instance_variable_get(:@user_input)["question_1"]).to eq("answer")
    end
  end

  describe "#handle_rate_limit" do
    let(:provider_manager) { double("provider_manager") }

    before do
      runner.instance_variable_set(:@provider_manager, provider_manager)
      runner.instance_variable_set(:@current_provider, "cursor")
      allow(provider_manager).to receive(:mark_rate_limited)
      allow(provider_manager).to receive(:switch_provider).and_return("claude")
    end

    it "handles rate limiting by switching providers" do
      result = {error: "rate limit exceeded"}

      runner.send(:handle_rate_limit, result)

      expect(provider_manager).to have_received(:mark_rate_limited).with("cursor")
      expect(provider_manager).to have_received(:switch_provider)
      expect(runner.instance_variable_get(:@current_provider)).to eq("claude")
      expect(runner.instance_variable_get(:@state)).to eq("running")
    end

    it "waits for reset when all providers are rate limited" do
      allow(provider_manager).to receive(:switch_provider).and_return(nil)
      allow(provider_manager).to receive(:next_reset_time).and_return(Time.now + 60)

      # Mock the wait_for_rate_limit_reset method
      allow(runner).to receive(:wait_for_rate_limit_reset)

      result = {error: "rate limit exceeded"}
      runner.send(:handle_rate_limit, result)

      expect(runner).to have_received(:wait_for_rate_limit_reset)
    end
  end

  describe "#all_steps_completed?" do
    it "delegates to state manager", pending: "State manager delegation not fully implemented" do
      state_manager = double("state_manager")
      allow(state_manager).to receive(:all_steps_completed?).and_return(true)
      runner.instance_variable_set(:@state_manager, state_manager)

      result = runner.send(:all_steps_completed?, nil)
      expect(result).to be true
      expect(state_manager).to have_received(:all_steps_completed?)
    end
  end

  describe "state management integration" do
    it "loads existing state on initialization" do
      # Create a state manager with existing state
      state_manager = double("state_manager")
      allow(state_manager).to receive(:has_state?).and_return(true)
      allow(state_manager).to receive(:load_state).and_return({
        current_step: "test_step",
        current_provider: "cursor"
      })
      allow(state_manager).to receive(:user_input).and_return({"question_1" => "answer"})
      runner.instance_variable_set(:@state_manager, state_manager)

      runner.send(:load_state)

      expect(runner.instance_variable_get(:@current_step)).to eq("test_step")
      expect(runner.instance_variable_get(:@current_provider)).to eq("cursor")
      expect(runner.instance_variable_get(:@user_input)["question_1"]).to eq("answer")
    end

    it "saves state correctly" do
      state_manager = double("state_manager")
      allow(state_manager).to receive(:save_state)
      allow(state_manager).to receive(:add_execution_log)
      runner.instance_variable_set(:@state_manager, state_manager)
      runner.instance_variable_set(:@state, "running")
      runner.instance_variable_set(:@current_step, "test_step")
      runner.instance_variable_set(:@current_provider, "cursor")
      runner.instance_variable_set(:@user_input, {"test" => "data"})
      runner.instance_variable_set(:@execution_log, [{message: "test"}])

      runner.send(:save_state)

      expect(state_manager).to have_received(:save_state).with(hash_including(
        state: "running",
        current_step: "test_step",
        current_provider: "cursor"
      ))
      expect(state_manager).to have_received(:add_execution_log).with({message: "test"})
    end
  end

  describe "error handling" do
    it "handles errors gracefully" do
      error_handler = double("error_handler")
      allow(error_handler).to receive(:handle_error)
      runner.instance_variable_set(:@error_handler, error_handler)

      error = StandardError.new("test error")
      runner.send(:handle_error, error)

      expect(error_handler).to have_received(:handle_error).with(error, runner)
    end
  end
end
