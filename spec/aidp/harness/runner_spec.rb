# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Harness::Runner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:runner) { described_class.new(temp_dir, :analyze) }

  before do
    # Create a minimal configuration file for testing
    config_content = {
      "harness" => {
        "default_provider" => "anthropic",
        "fallback_providers" => ["cursor", "macos"],
        "max_retries" => 2
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "priority" => 1,
          "max_tokens" => 100_000,
          "features" => {
            "file_upload" => true,
            "code_generation" => true,
            "analysis" => true
          }
        },
        "cursor" => {
          "type" => "subscription",
          "priority" => 2,
          "models" => ["cursor-default"],
          "features" => {
            "file_upload" => true,
            "code_generation" => true,
            "analysis" => true
          }
        },
        "macos" => {
          "type" => "passthrough",
          "priority" => 3,
          "underlying_service" => "cursor",
          "models" => ["cursor-chat"],
          "features" => {
            "file_upload" => false,
            "code_generation" => true,
            "analysis" => true,
            "interactive" => true
          }
        }
      }
    }

    config_file = File.join(temp_dir, ".aidp", "aidp.yml")
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, YAML.dump(config_content))
  end

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
      expect(runner.instance_variable_get(:@config_manager)).to be_a(Aidp::Harness::ConfigManager)
      expect(runner.instance_variable_get(:@state_manager)).to be_a(Aidp::Harness::StateManager)
      expect(runner.instance_variable_get(:@condition_detector)).to be_a(Aidp::Harness::ZfcConditionDetector)
      expect(runner.instance_variable_get(:@provider_manager)).to be_a(Aidp::Harness::ProviderManager)
      expect(runner.instance_variable_get(:@user_interface)).to be_a(Aidp::Harness::SimpleUserInterface)
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
    it "delegates to state manager" do
      mock_runner = double("mode_runner")
      allow(mock_runner).to receive(:all_steps_completed?).and_return(true)

      result = runner.send(:all_steps_completed?, mock_runner)
      expect(result).to be true
      expect(mock_runner).to have_received(:all_steps_completed?)
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

  describe "run loop scenarios" do
    before do
      # Stub error handler to execute block directly without retries or extra logic
      error_handler = double("error_handler")
      allow(error_handler).to receive(:execute_with_retry) { |&blk| blk.call }
      allow(error_handler).to receive(:handle_error)
      runner.instance_variable_set(:@error_handler, error_handler)

      # Basic provider manager stub; individual tests can override additional behavior
      provider_manager = double("provider_manager")
      allow(provider_manager).to receive(:current_provider).and_return("anthropic")
      allow(provider_manager).to receive(:mark_rate_limited)
      allow(provider_manager).to receive(:switch_provider).and_return(nil)
      allow(provider_manager).to receive(:next_reset_time).and_return(Time.now + 1)
      runner.instance_variable_set(:@provider_manager, provider_manager)

      # Status display stub to avoid real output and provide cleanup
      status_display = double("status_display",
        update_current_step: nil,
        update_current_provider: nil,
        update_rate_limit_countdown: nil,
        show_rate_limit_wait: nil,
        cleanup: nil)
      runner.instance_variable_set(:@status_display, status_display)

      # Default condition detector (tests override where needed)
      condition_detector = double("condition_detector")
      allow(condition_detector).to receive(:needs_user_feedback?).and_return(false)
      allow(condition_detector).to receive(:is_rate_limited?).and_return(false)
      runner.instance_variable_set(:@condition_detector, condition_detector)
    end
    it "marks completed when completion criteria met" do
      analyze_runner = double("analyze_runner")
      allow(analyze_runner).to receive(:next_step).and_return("step1", nil)
      allow(analyze_runner).to receive(:run_step).and_return({status: "completed"})
      allow(analyze_runner).to receive(:mark_step_in_progress)
      allow(analyze_runner).to receive(:mark_step_completed)
      allow(analyze_runner).to receive(:all_steps_completed?).and_return(true)

      completion_checker = double("completion_checker", completion_status: {all_complete: true, summary: "All good"})
      runner.instance_variable_set(:@completion_checker, completion_checker)

      # Inject mocked mode runner
      allow(runner).to receive(:get_mode_runner).and_return(analyze_runner)

      result = runner.run
      expect(result[:status]).to eq("completed")
    end

    it "handles unmet completion criteria with user override" do
      analyze_runner = double("analyze_runner")
      allow(analyze_runner).to receive(:next_step).and_return("step1", nil)
      allow(analyze_runner).to receive(:run_step).and_return({status: "completed"})
      allow(analyze_runner).to receive(:mark_step_in_progress)
      allow(analyze_runner).to receive(:mark_step_completed)
      allow(analyze_runner).to receive(:all_steps_completed?).and_return(true)

      completion_checker = double("completion_checker", completion_status: {all_complete: false, summary: "Missing artifacts"})
      runner.instance_variable_set(:@completion_checker, completion_checker)

      # Stub user interface confirmation to override
      ui = double("user_interface")
      allow(ui).to receive(:get_confirmation).and_return(true)
      runner.instance_variable_set(:@user_interface, ui)

      allow(runner).to receive(:get_mode_runner).and_return(analyze_runner)

      result = runner.run
      expect(result[:status]).to eq("completed")
    end

    it "enters error state when completion criteria not met and user declines override" do
      analyze_runner = double("analyze_runner")
      allow(analyze_runner).to receive(:next_step).and_return("step1", nil)
      allow(analyze_runner).to receive(:run_step).and_return({status: "completed"})
      allow(analyze_runner).to receive(:mark_step_in_progress)
      allow(analyze_runner).to receive(:mark_step_completed)
      allow(analyze_runner).to receive(:all_steps_completed?).and_return(true)

      completion_checker = double("completion_checker", completion_status: {all_complete: false, summary: "Missing coverage"})
      runner.instance_variable_set(:@completion_checker, completion_checker)

      ui = double("user_interface")
      allow(ui).to receive(:get_confirmation).and_return(false)
      runner.instance_variable_set(:@user_interface, ui)

      allow(runner).to receive(:get_mode_runner).and_return(analyze_runner)

      result = runner.run
      expect(result[:status]).to eq("error")
    end

    it "switches providers and waits for reset on rate limit" do
      analyze_runner = double("analyze_runner")
      allow(analyze_runner).to receive(:next_step).and_return("step1", nil)
      allow(analyze_runner).to receive(:run_step).and_return({status: "completed"})
      allow(analyze_runner).to receive(:mark_step_in_progress)
      allow(analyze_runner).to receive(:mark_step_completed)
      allow(analyze_runner).to receive(:all_steps_completed?).and_return(false)

      # Force a rate-limit condition on first result
      condition_detector = double("condition_detector")
      allow(condition_detector).to receive(:needs_user_feedback?).and_return(false)
      allow(condition_detector).to receive(:is_rate_limited?).and_return(true, false)
      runner.instance_variable_set(:@condition_detector, condition_detector)
      provider_manager = runner.instance_variable_get(:@provider_manager)

      # Stub countdown methods to avoid real sleep
      allow(runner).to receive(:sleep_until_reset) { runner.instance_variable_set(:@state, "running") }

      allow(runner).to receive(:get_mode_runner).and_return(analyze_runner)

      result = runner.run
      expect(provider_manager).to have_received(:mark_rate_limited).with("anthropic")
      expect(result[:status]).not_to eq("error")
    end

    it "transitions to error state when exception raised" do
      bad_runner = double("bad_runner")
      allow(bad_runner).to receive(:next_step).and_raise(StandardError.new("explode"))
      allow(runner).to receive(:get_mode_runner).and_return(bad_runner)
      result = runner.run
      expect(result[:status]).to eq("error")
    end
  end
end
