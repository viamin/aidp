# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/enhanced_runner"

RSpec.describe Aidp::Harness::EnhancedRunner do
  let(:project_dir) { Dir.mktmpdir }
  let(:options) { {selected_steps: ["step1", "step2"], workflow_type: :default} }

  before do
    # Stub out heavy dependencies inside initializer so we don't need a real config file
    allow(Aidp.logger).to receive(:info)
    allow(Aidp.logger).to receive(:error)
    allow(Aidp::Harness::UI).to receive(:with_processing_spinner).and_yield

    mock_config = double("Configuration")
    allow(Aidp::Harness::Configuration).to receive(:new).and_return(mock_config)
    allow(Aidp::Harness::StateManager).to receive(:new).and_return(double("StateManager"))
    allow(Aidp::Harness::ConditionDetector).to receive(:new).and_return(double("ConditionDetector",
      needs_user_feedback?: false,
      extract_questions: [],
      is_rate_limited?: false))
    allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(double("ProviderManager", current_provider: "test"))
    allow(Aidp::Harness::ErrorHandler).to receive(:new).and_return(double("ErrorHandler", execute_with_retry: {status: "completed"}))
    allow(Aidp::Harness::CompletionChecker).to receive(:new).and_return(double("CompletionChecker", completion_status: {all_complete: true}))
  end

  after { FileUtils.rm_rf(project_dir) }

  def build_runner(mode = :analyze)
    r = described_class.new(project_dir, mode, options)
    tui = r.instance_variable_get(:@tui)
    tui.instance_variable_set(:@jobs, {"main_workflow" => {}})
    r
  end

  # Helper to create instances with dependency injection
  def create_instance(mode: :analyze, tui: nil, provider_manager: nil, selected_steps: ["step1", "step2"], workflow_type: :default, sleeper: nil)
    opts = {selected_steps: selected_steps, workflow_type: workflow_type}
    instance = if sleeper
      described_class.new(project_dir, mode, opts, sleeper: sleeper)
    else
      described_class.new(project_dir, mode, opts)
    end

    # Inject TUI if provided
    instance.instance_variable_set(:@tui, tui) if tui

    # Inject provider_manager if provided (or explicitly set to nil)
    instance.instance_variable_set(:@provider_manager, provider_manager) if provider_manager || provider_manager.nil?

    # Set up jobs hash in TUI
    current_tui = instance.instance_variable_get(:@tui)
    current_tui&.instance_variable_set(:@jobs, {"main_workflow" => {}})

    instance
  end

  describe "#status" do
    it "returns a hash with state info" do
      runner = build_runner
      st = runner.status
      expect(st).to include(:state, :mode, :current_step, :jobs_count)
    end
  end

  describe "#calculate_progress_percentage" do
    it "returns 0 when no steps" do
      runner = build_runner
      fake_mode_runner = double("ModeRunner", all_steps: [], progress: double(completed_steps: []))
      pct = runner.send(:calculate_progress_percentage, fake_mode_runner)
      expect(pct).to eq(0)
    end

    it "calculates percentage when steps present" do
      runner = build_runner
      fake_mode_runner = double("ModeRunner", all_steps: ["a", "b"], progress: double(completed_steps: ["a"]))
      pct = runner.send(:calculate_progress_percentage, fake_mode_runner)
      expect(pct).to eq(50.0)
    end
  end

  describe "#get_mode_runner" do
    it "raises for unsupported mode" do
      bad = build_runner(:unknown)
      expect { bad.send(:get_mode_runner) }.to raise_error(ArgumentError)
    end
  end

  describe "#should_stop? (private)" do
    let(:instance) { create_instance }

    it "returns false by default" do
      expect(instance.send(:should_stop?)).to be false
    end
  end

  describe "#should_pause? (private) (private)" do
    let(:instance) { create_instance }

    it "returns false by default" do
      expect(instance.send(:should_pause?)).to be false
    end
  end

  describe "#current_provider" do
    let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
    let(:instance) { create_instance(provider_manager: provider_manager) }

    it "returns current provider from instance variable when set" do
      instance.instance_variable_set(:@current_provider, "test_provider")
      expect(instance.current_provider).to eq("test_provider")
    end

    it "returns current provider from provider_manager when instance variable not set" do
      allow(provider_manager).to receive(:current_provider).and_return("manager_provider")
      expect(instance.current_provider).to eq("manager_provider")
    end

    it "returns 'unknown' when provider_manager returns nil" do
      allow(provider_manager).to receive(:current_provider).and_return(nil)
      expect(instance.current_provider).to eq("unknown")
    end
  end

  describe "#current_step" do
    let(:instance) { create_instance }

    it "returns the current step being executed" do
      instance.instance_variable_set(:@current_step, "step1")
      expect(instance.current_step).to eq("step1")
    end

    it "returns nil when no step is being executed" do
      expect(instance.current_step).to be_nil
    end
  end

  describe "#user_input" do
    let(:instance) { create_instance }

    it "returns user input hash when set" do
      instance.instance_variable_set(:@user_input, {key: "value"})
      expect(instance.user_input).to eq({key: "value"})
    end

    it "returns empty hash when not set" do
      expect(instance.user_input).to eq({})
    end
  end

  describe "#execution_log" do
    let(:instance) { create_instance }

    it "returns execution log array when set" do
      instance.instance_variable_set(:@execution_log, ["step1", "step2"])
      expect(instance.execution_log).to eq(["step1", "step2"])
    end

    it "returns empty array when not set" do
      expect(instance.execution_log).to eq([])
    end
  end

  describe "#provider_manager" do
    let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
    let(:instance) { create_instance(provider_manager: provider_manager) }

    it "returns the injected provider manager" do
      expect(instance.provider_manager).to eq(provider_manager)
    end
  end

  describe "#run" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:mock_runner) { double }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      # Mock TUI methods
      allow(mock_tui).to receive(:show_message)
      allow(mock_tui).to receive(:start_display_loop)
      allow(mock_tui).to receive(:stop_display_loop)
      allow(mock_tui).to receive(:add_job)
      allow(mock_tui).to receive(:update_job)
      allow(mock_tui).to receive(:remove_job)
      allow(mock_tui).to receive(:show_step_execution)
      allow(mock_tui).to receive(:show_input_area)

      # Mock core methods
      allow(instance).to receive(:get_mode_runner).and_return(mock_runner)
      allow(instance).to receive(:register_workflow_job)
      allow(instance).to receive(:show_workflow_status)
      allow(instance).to receive(:show_mode_specific_feedback)
      allow(instance).to receive(:should_stop?).and_return(false, true) # Stop after one iteration
      allow(instance).to receive(:should_pause?).and_return(false)
      allow(instance).to receive(:get_next_step).and_return(nil) # No steps to execute
      allow(instance).to receive(:complete_workflow_job)
      allow(instance).to receive(:all_steps_completed?).and_return(true)
      allow(instance).to receive(:save_state)
      allow(instance).to receive(:cleanup)
      allow(instance).to receive(:get_completion_message).and_return("Completed")

      # Mock completion checker
      completion_checker = double
      allow(completion_checker).to receive(:completion_status).and_return({all_complete: true})
      instance.instance_variable_set(:@completion_checker, completion_checker)

      # Mock workflow controller
      workflow_controller = double
      allow(workflow_controller).to receive(:complete_workflow)
      instance.instance_variable_set(:@workflow_controller, workflow_controller)
    end

    it "initializes state and timing correctly" do
      freeze_time = Time.parse("2024-01-01 12:00:00")
      allow(Time).to receive(:now).and_return(freeze_time)

      result = instance.run

      expect(instance.instance_variable_get(:@state)).to eq("completed")
      expect(instance.instance_variable_get(:@start_time)).to eq(freeze_time)
      expect(result).to eq({status: "completed", message: "Completed"})
    end

    it "starts and stops TUI display loop properly" do
      expect(mock_tui).to receive(:start_display_loop).once
      expect(mock_tui).to receive(:stop_display_loop).once

      instance.run
    end

    it "shows initial startup message" do
      expect(mock_tui).to receive(:show_message).with("🚀 Starting Analyze Mode", :info)

      instance.run
    end

    it "calls core setup methods in order" do
      expect(instance).to receive(:get_mode_runner).ordered
      expect(instance).to receive(:register_workflow_job).ordered
      expect(instance).to receive(:show_workflow_status).ordered
      expect(instance).to receive(:show_mode_specific_feedback).ordered

      instance.run
    end

    it "handles successful completion" do
      expect(mock_tui).to receive(:show_message).with("🎉 Harness completed successfully - all criteria met", :success)

      result = instance.run

      expect(result[:status]).to eq("completed")
    end

    it "handles completion criteria not met" do
      completion_checker = double
      allow(completion_checker).to receive(:completion_status).and_return({all_complete: false})
      instance.instance_variable_set(:@completion_checker, completion_checker)

      allow(instance).to receive(:handle_completion_criteria_not_met)

      expect(mock_tui).to receive(:show_message).with("⚠️ Steps completed but completion criteria not met", :warning)
      expect(instance).to receive(:handle_completion_criteria_not_met)

      instance.run
    end

    it "handles errors gracefully" do
      allow(instance).to receive(:get_mode_runner).and_raise(StandardError.new("Test error"))

      expect(mock_tui).to receive(:show_message).with("❌ Error: Test error", :error)

      result = instance.run

      expect(result[:status]).to eq("error")
    end

    it "ensures cleanup happens even on error" do
      allow(instance).to receive(:get_mode_runner).and_raise(StandardError.new("Test error"))

      expect(instance).to receive(:save_state)
      expect(instance).to receive(:cleanup)
      expect(mock_tui).to receive(:stop_display_loop)

      instance.run
    end

    context "when steps are available" do
      before do
        allow(instance).to receive(:get_next_step).and_return("step1", nil) # One step then done
        allow(instance).to receive(:execute_step_with_enhanced_tui)
        allow(instance).to receive(:update_state)
        allow(instance).to receive(:show_step_spinner).and_yield.and_return("step1")
      end

      it "executes steps in the main loop" do
        expect(instance).to receive(:execute_step_with_enhanced_tui).with(mock_runner, "step1")
        expect(instance).to receive(:update_state)

        instance.run
      end

      it "shows step spinner during step discovery" do
        expect(instance).to receive(:show_step_spinner).with("Finding next step to execute...")

        instance.run
      end
    end

    context "when pause conditions are detected" do
      before do
        allow(instance).to receive(:should_pause?).and_return(true, false)
        allow(instance).to receive(:handle_pause_condition)
        allow(instance).to receive(:get_next_step).and_return(nil) # No steps after pause
      end

      it "handles pause condition" do
        expect(instance).to receive(:handle_pause_condition)

        instance.run
      end
    end

    context "when pause condition is triggered mid-execution" do
      let(:test_sleeper) { double("Sleeper") }
      let(:paused_instance) { create_instance(tui: mock_tui, sleeper: test_sleeper) }

      before do
        # Mock dependencies for paused instance
        allow(paused_instance).to receive(:get_mode_runner).and_return(mock_runner)
        allow(paused_instance).to receive(:register_workflow_job)
        allow(paused_instance).to receive(:show_workflow_status)
        allow(paused_instance).to receive(:show_mode_specific_feedback)
        allow(paused_instance).to receive(:complete_workflow_job)
        allow(paused_instance).to receive(:all_steps_completed?).and_return(true)
        allow(paused_instance).to receive(:save_state)
        allow(paused_instance).to receive(:cleanup)
        allow(paused_instance).to receive(:get_completion_message).and_return("Completed")

        # Mock completion checker
        completion_checker = double
        allow(completion_checker).to receive(:completion_status).and_return({all_complete: true})
        paused_instance.instance_variable_set(:@completion_checker, completion_checker)

        # Mock workflow controller
        workflow_controller = double
        allow(workflow_controller).to receive(:complete_workflow)
        paused_instance.instance_variable_set(:@workflow_controller, workflow_controller)

        # Stub sleeper for predictable timing
        allow(test_sleeper).to receive(:sleep)
      end

      it "pauses execution and handles pause state correctly" do
        # Simulate: running -> paused -> running -> stop
        pause_call_count = 0
        allow(paused_instance).to receive(:should_pause?) do
          pause_call_count += 1
          pause_call_count <= 2 # Return true twice, then false
        end

        allow(paused_instance).to receive(:should_stop?) do
          pause_call_count > 2 # Stop after pause handling
        end

        allow(paused_instance).to receive(:get_next_step).and_return(nil)

        # Set state to paused and test handle_pause_condition directly
        paused_instance.instance_variable_set(:@state, "paused")

        # Test the private method directly for paused state
        expect(test_sleeper).to receive(:sleep).with(1)
        paused_instance.send(:handle_pause_condition)

        # Now run the main loop (but stub handle_pause_condition to avoid duplicate sleep calls)
        allow(paused_instance).to receive(:handle_pause_condition)

        paused_instance.run

        # Verify pause condition was detected
        expect(pause_call_count).to be > 2
      end

      it "handles waiting_for_user state without sleeping" do
        allow(paused_instance).to receive(:should_pause?).and_return(true, false)
        allow(paused_instance).to receive(:should_stop?).and_return(false, true)
        allow(paused_instance).to receive(:get_next_step).and_return(nil)

        # Set state to waiting_for_user
        paused_instance.instance_variable_set(:@state, "waiting_for_user")

        # Should not call sleep for waiting_for_user state
        expect(test_sleeper).not_to receive(:sleep)

        paused_instance.run
      end

      it "handles waiting_for_rate_limit state without sleeping" do
        allow(paused_instance).to receive(:should_pause?).and_return(true, false)
        allow(paused_instance).to receive(:should_stop?).and_return(false, true)
        allow(paused_instance).to receive(:get_next_step).and_return(nil)

        # Set state to waiting_for_rate_limit
        paused_instance.instance_variable_set(:@state, "waiting_for_rate_limit")

        # Should not call sleep for waiting_for_rate_limit state
        expect(test_sleeper).not_to receive(:sleep)

        paused_instance.run
      end
    end

    context "thread cleanup verification" do
      let(:thread_tracking_instance) { create_instance(tui: mock_tui) }

      before do
        # Mock dependencies
        allow(thread_tracking_instance).to receive(:get_mode_runner).and_return(mock_runner)
        allow(thread_tracking_instance).to receive(:register_workflow_job)
        allow(thread_tracking_instance).to receive(:show_workflow_status)
        allow(thread_tracking_instance).to receive(:show_mode_specific_feedback)
        allow(thread_tracking_instance).to receive(:should_stop?).and_return(false, true)
        allow(thread_tracking_instance).to receive(:should_pause?).and_return(false)
        allow(thread_tracking_instance).to receive(:get_next_step).and_return(nil)
        allow(thread_tracking_instance).to receive(:complete_workflow_job)
        allow(thread_tracking_instance).to receive(:all_steps_completed?).and_return(true)
        allow(thread_tracking_instance).to receive(:save_state)
        allow(thread_tracking_instance).to receive(:cleanup)
        allow(thread_tracking_instance).to receive(:get_completion_message).and_return("Completed")

        # Mock completion checker
        completion_checker = double
        allow(completion_checker).to receive(:completion_status).and_return({all_complete: true})
        thread_tracking_instance.instance_variable_set(:@completion_checker, completion_checker)

        # Mock workflow controller
        workflow_controller = double
        allow(workflow_controller).to receive(:complete_workflow)
        thread_tracking_instance.instance_variable_set(:@workflow_controller, workflow_controller)
      end

      it "cleans up background threads after run completion" do
        initial_thread_count = Thread.list.count

        thread_tracking_instance.run

        # Allow time for any background threads to complete
        sleep(0.1)

        final_thread_count = Thread.list.count

        # Verify no lingering threads (allowing for main thread and test framework threads)
        expect(final_thread_count).to be <= initial_thread_count + 1
      end

      it "calls cleanup method which removes remaining jobs" do
        # Cleanup method should remove all jobs from TUI
        jobs = {"job1" => {}, "job2" => {}}
        allow(mock_tui).to receive(:instance_variable_get).with(:@jobs).and_return(jobs)

        # The cleanup method is called during run, so we need to test it directly
        # or ensure it's called during the run method
        expect(thread_tracking_instance).to receive(:cleanup).and_call_original
        expect(mock_tui).to receive(:remove_job).with("job1")
        expect(mock_tui).to receive(:remove_job).with("job2")

        thread_tracking_instance.run
      end
    end
  end

  describe "#execute_step_with_enhanced_tui" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:mock_runner) { double }
    let(:mock_error_handler) { double }
    let(:mock_condition_detector) { double }
    let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
    let(:test_sleeper) { double("Sleeper", sleep: nil) }
    let(:instance) { create_instance(tui: mock_tui, provider_manager: provider_manager, sleeper: test_sleeper) }

    before do
      # Mock TUI methods
      allow(mock_tui).to receive(:show_message)
      allow(mock_tui).to receive(:add_job)
      allow(mock_tui).to receive(:update_job)
      allow(mock_tui).to receive(:remove_job)
      allow(mock_tui).to receive(:show_step_execution)

      # Mock runner methods
      allow(mock_runner).to receive(:mark_step_in_progress)
      allow(mock_runner).to receive(:mark_step_completed)
      allow(mock_runner).to receive(:run_step).and_return({status: "completed"})

      # Mock dependencies
      instance.instance_variable_set(:@error_handler, mock_error_handler)
      instance.instance_variable_set(:@condition_detector, mock_condition_detector)
      allow(mock_error_handler).to receive(:execute_with_retry).and_yield
      allow(mock_condition_detector).to receive(:needs_user_feedback?).and_return(false)
      allow(mock_condition_detector).to receive(:is_rate_limited?).and_return(false)
      allow(provider_manager).to receive(:current_provider).and_return("test_provider")

      # Mock spinner
      allow(instance).to receive(:show_step_spinner).and_yield

      # Mock Thread.new to avoid actual thread creation in tests
      allow(Thread).to receive(:new).and_yield
    end

    it "sets current step and shows initial message" do
      expect(mock_tui).to receive(:show_message).with("🔄 Executing step: test_step", :info)

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")

      expect(instance.current_step).to eq("test_step")
    end

    it "registers step as a job with correct data" do
      expected_job_data = {
        name: "test_step",
        status: :running,
        progress: 0,
        provider: "unknown",  # Provider is nil initially, so uses fallback
        message: "Starting execution..."
      }

      expect(mock_tui).to receive(:add_job).with("step_test_step", expected_job_data)

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end

    it "marks step as in progress" do
      expect(mock_runner).to receive(:mark_step_in_progress).with("test_step")

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end

    it "shows step execution starting" do
      # current_provider is nil initially
      expect(mock_tui).to receive(:show_step_execution).with("test_step", :starting, {provider: nil})

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end

    context "when step execution succeeds" do
      before do
        allow(mock_runner).to receive(:run_step).and_return({status: "completed"})
      end

      it "updates job status to completed" do
        expect(mock_tui).to receive(:update_job).with("step_test_step", {
          status: :completed,
          progress: 100,
          message: "Completed successfully"
        })

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end

      it "shows step execution completed" do
        expect(mock_tui).to receive(:show_step_execution).with("test_step", :completed, {duration: be_a(Numeric)})

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end

      it "marks step as completed" do
        expect(mock_runner).to receive(:mark_step_completed).with("test_step")

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end
    end

    context "when step execution fails" do
      before do
        allow(mock_runner).to receive(:run_step).and_return({status: "failed", error: "Test error"})
      end

      it "updates job status to failed" do
        expect(mock_tui).to receive(:update_job).with("step_test_step", {
          status: :failed,
          message: "Test error"
        })

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end

      it "shows step execution failed" do
        expect(mock_tui).to receive(:show_step_execution).with("test_step", :failed, {
          error: "Test error"
        })

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end
    end

    context "when step returns nil result" do
      before do
        allow(mock_runner).to receive(:run_step).and_return(nil)
      end

      it "handles nil result gracefully" do
        expect(mock_tui).to receive(:update_job).with("step_test_step", {
          status: :failed,
          message: "Step execution failed"
        })

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end
    end

    it "uses error handler for retry logic" do
      expect(mock_error_handler).to receive(:execute_with_retry).and_yield

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end

    it "executes step in correct directory" do
      project_dir = "/test/project"
      instance.instance_variable_set(:@project_dir, project_dir)

      expect(Dir).to receive(:chdir).with(project_dir).and_yield
      expect(mock_runner).to receive(:run_step)

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end

    context "when user feedback is needed" do
      before do
        result = {status: "completed", needs_feedback: true}
        allow(mock_runner).to receive(:run_step).and_return(result)
        allow(mock_condition_detector).to receive(:needs_user_feedback?).and_return(true)
        allow(instance).to receive(:handle_user_feedback_request_with_tui)
      end

      it "handles user feedback request" do
        expect(instance).to receive(:handle_user_feedback_request_with_tui)

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end
    end

    context "when rate limited" do
      before do
        result = {status: "completed", rate_limited: true}
        allow(mock_runner).to receive(:run_step).and_return(result)
        allow(mock_condition_detector).to receive(:is_rate_limited?).and_return(true)
        allow(instance).to receive(:handle_rate_limit)
      end

      it "handles rate limit" do
        expect(instance).to receive(:handle_rate_limit)

        instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
      end
    end

    it "creates thread for job removal delay" do
      # Just verify that Thread.new is called - simpler test
      expect(Thread).to receive(:new).once

      instance.execute_step_with_enhanced_tui(mock_runner, "test_step")
    end
  end

  describe "#handle_user_feedback_request_with_tui" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:mock_condition_detector) { double }
    let(:mock_workflow_controller) { double }
    let(:mock_state_manager) { double }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      instance.instance_variable_set(:@condition_detector, mock_condition_detector)
      instance.instance_variable_set(:@workflow_controller, mock_workflow_controller)
      instance.instance_variable_set(:@state_manager, mock_state_manager)
      instance.instance_variable_set(:@user_input, {})

      # Mock TUI methods
      allow(mock_tui).to receive(:show_message)
      allow(mock_tui).to receive(:show_input_area)
      allow(mock_tui).to receive(:get_user_input)

      # Mock other dependencies
      allow(mock_workflow_controller).to receive(:pause_workflow)
      allow(mock_workflow_controller).to receive(:resume_workflow)
      allow(mock_state_manager).to receive(:add_user_input)
    end

    it "sets state to waiting for user then back to running" do
      result = {feedback_needed: true}
      questions = [{number: 1, question: "Test question?"}]

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)
      allow(mock_tui).to receive(:get_user_input).and_return("test response")

      instance.handle_user_feedback_request_with_tui(result)

      # After method completes, state is back to running
      expect(instance.instance_variable_get(:@state)).to eq("running")
    end

    it "pauses workflow" do
      result = {feedback_needed: true}
      questions = []

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)

      expect(mock_workflow_controller).to receive(:pause_workflow).with("Waiting for user feedback")

      instance.handle_user_feedback_request_with_tui(result)
    end

    it "shows waiting message" do
      result = {feedback_needed: true}
      questions = []

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)

      expect(mock_tui).to receive(:show_message).with("⏸️ Waiting for user feedback", :warning)

      instance.handle_user_feedback_request_with_tui(result)
    end

    it "extracts and processes questions" do
      result = {feedback_needed: true}
      questions = [
        {number: 1, question: "First question?"},
        {number: 2, question: "Second question?"}
      ]

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)
      allow(mock_tui).to receive(:get_user_input).and_return("response1", "response2")

      expect(mock_tui).to receive(:get_user_input).with("Question 1: First question?")
      expect(mock_tui).to receive(:get_user_input).with("Question 2: Second question?")

      instance.handle_user_feedback_request_with_tui(result)
    end

    it "stores user responses" do
      result = {feedback_needed: true}
      questions = [{number: 1, question: "Test question?"}]

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)
      allow(mock_tui).to receive(:get_user_input).and_return("test response")

      expect(mock_state_manager).to receive(:add_user_input).with("question_1", "test response")

      instance.handle_user_feedback_request_with_tui(result)

      expect(instance.user_input["question_1"]).to eq("test response")
    end

    it "handles questions without explicit numbers" do
      result = {feedback_needed: true}
      questions = [{question: "Unnumbered question?"}]

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)
      allow(mock_tui).to receive(:get_user_input).and_return("response")

      expect(mock_tui).to receive(:get_user_input).with("Question 1: Unnumbered question?")

      instance.handle_user_feedback_request_with_tui(result)
    end

    it "resumes workflow after collecting feedback" do
      result = {feedback_needed: true}
      questions = []

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)

      expect(mock_workflow_controller).to receive(:resume_workflow).with("User feedback collected")

      instance.handle_user_feedback_request_with_tui(result)

      expect(instance.instance_variable_get(:@state)).to eq("running")
    end

    it "shows success message after collecting feedback" do
      result = {feedback_needed: true}
      questions = []

      allow(mock_condition_detector).to receive(:extract_questions).and_return(questions)

      expect(mock_tui).to receive(:show_message).with("✅ User feedback collected", :success)

      instance.handle_user_feedback_request_with_tui(result)
    end
  end

  describe "#show_workflow_status" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:mock_runner) { double }
    let(:mock_progress) { double }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      allow(mock_runner).to receive(:all_steps).and_return(%w[step1 step2 step3])
      allow(mock_runner).to receive(:progress).and_return(mock_progress)
      allow(mock_progress).to receive(:completed_steps).and_return(["step1"])
      allow(mock_progress).to receive(:current_step).and_return("step2")
      allow(instance).to receive(:calculate_progress_percentage).and_return(33.33)
      allow(mock_tui).to receive(:show_workflow_status)

      instance.instance_variable_set(:@workflow_type, "test_workflow")
      instance.instance_variable_set(:@selected_steps, %w[step1 step2])
    end

    it "shows workflow status with correct data" do
      expected_data = {
        workflow_type: "test_workflow",
        steps: %w[step1 step2],
        completed_steps: 1,
        current_step: "step2",
        progress_percentage: 33.33
      }

      expect(mock_tui).to receive(:show_workflow_status).with(expected_data)

      instance.show_workflow_status(mock_runner)
    end

    it "uses all_steps when selected_steps is nil" do
      instance.instance_variable_set(:@selected_steps, nil)

      expected_data = {
        workflow_type: "test_workflow",
        steps: %w[step1 step2 step3],
        completed_steps: 1,
        current_step: "step2",
        progress_percentage: 33.33
      }

      expect(mock_tui).to receive(:show_workflow_status).with(expected_data)

      instance.show_workflow_status(mock_runner)
    end
  end

  describe "#register_workflow_job" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      allow(mock_tui).to receive(:add_job)
      instance.instance_variable_set(:@current_provider, "test_provider")
    end

    it "registers main workflow job with correct data" do
      expected_job_data = {
        name: "Main Workflow",
        status: :running,
        progress: 0,
        provider: "test_provider",
        message: "Starting workflow execution..."
      }

      expect(mock_tui).to receive(:add_job).with("main_workflow", expected_job_data)

      instance.register_workflow_job
    end

    it "uses 'unknown' provider when current_provider is nil" do
      instance.instance_variable_set(:@current_provider, nil)

      expected_job_data = {
        name: "Main Workflow",
        status: :running,
        progress: 0,
        provider: "unknown",
        message: "Starting workflow execution..."
      }

      expect(mock_tui).to receive(:add_job).with("main_workflow", expected_job_data)

      instance.register_workflow_job
    end
  end

  describe "#complete_workflow_job" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      allow(mock_tui).to receive(:update_job)
    end

    it "updates main workflow job to completed" do
      expected_update_data = {
        status: :completed,
        progress: 100,
        message: "Workflow completed"
      }

      expect(mock_tui).to receive(:update_job).with("main_workflow", expected_update_data)

      instance.complete_workflow_job
    end
  end

  describe "#stop" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:mock_workflow_controller) { double }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      instance.instance_variable_set(:@workflow_controller, mock_workflow_controller)
      allow(mock_workflow_controller).to receive(:stop_workflow)
      allow(mock_tui).to receive(:show_message)
    end

    it "sets state to stopped" do
      instance.stop

      expect(instance.instance_variable_get(:@state)).to eq("stopped")
    end

    it "stops workflow with message" do
      expect(mock_workflow_controller).to receive(:stop_workflow).with("User requested stop")

      instance.stop
    end

    it "shows stop message to user" do
      expect(mock_tui).to receive(:show_message).with("⏹️ Harness stopped by user", :warning)

      instance.stop
    end
  end

  describe "#status" do
    let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
    let(:instance) { create_instance(tui: mock_tui) }

    before do
      start_time = Time.parse("2024-01-01 12:00:00")
      current_time = Time.parse("2024-01-01 12:05:00")

      instance.instance_variable_set(:@state, "running")
      instance.instance_variable_set(:@mode, "test")
      instance.instance_variable_set(:@current_step, "step1")
      instance.instance_variable_set(:@current_provider, "test_provider")
      instance.instance_variable_set(:@start_time, start_time)
      instance.instance_variable_set(:@user_input, {key1: "value1", key2: "value2"})
      instance.instance_variable_set(:@execution_log, ["event1", "event2", "event3"])

      allow(Time).to receive(:now).and_return(current_time)
      allow(mock_tui).to receive(:instance_variable_get).with(:@jobs).and_return({"job1" => {}, "job2" => {}})
    end

    it "returns comprehensive status information" do
      expected_status = {
        state: "running",
        mode: "test",
        current_step: "step1",
        current_provider: "test_provider",
        start_time: Time.parse("2024-01-01 12:00:00"),
        duration: 300, # 5 minutes
        user_input_count: 2,
        execution_log_count: 3,
        jobs_count: 2
      }

      expect(instance.status).to eq(expected_status)
    end

    it "returns 0 duration when start_time is nil" do
      instance.instance_variable_set(:@start_time, nil)

      status = instance.status

      expect(status[:duration]).to eq(0)
    end
  end

  # Private method tests
  describe "private methods" do
    let(:instance) { create_instance }

    describe "#show_step_spinner" do
      it "uses unified spinner helper and yields block" do
        expect(Aidp::Harness::UI).to receive(:with_processing_spinner).with("Test message").and_yield

        result = instance.send(:show_step_spinner, "Test message") { "test_result" }

        expect(result).to eq("test_result")
      end
    end

    describe "#get_mode_runner" do
      it "returns analyze runner for analyze mode" do
        instance.instance_variable_set(:@mode, :analyze)
        instance.instance_variable_set(:@project_dir, "/test/project")

        expect(Aidp::Analyze::Runner).to receive(:new).with("/test/project", instance, prompt: be_a(TTY::Prompt))

        instance.send(:get_mode_runner)
      end

      it "returns execute runner for execute mode" do
        instance.instance_variable_set(:@mode, :execute)
        instance.instance_variable_set(:@project_dir, "/test/project")

        expect(Aidp::Execute::Runner).to receive(:new).with("/test/project", instance, prompt: be_a(TTY::Prompt))

        instance.send(:get_mode_runner)
      end

      it "raises error for unsupported mode" do
        instance.instance_variable_set(:@mode, :unsupported)

        expect { instance.send(:get_mode_runner) }.to raise_error(ArgumentError, "Unsupported mode: unsupported")
      end
    end

    describe "#get_next_step" do
      let(:mock_runner) { double }

      it "delegates to runner's next_step method" do
        expect(mock_runner).to receive(:next_step).and_return("next_step")

        result = instance.send(:get_next_step, mock_runner)

        expect(result).to eq("next_step")
      end
    end

    describe "#should_stop?" do
      it "returns true when state is stopped" do
        instance.instance_variable_set(:@state, "stopped")
        expect(instance.send(:should_stop?)).to be true
      end

      it "returns true when state is completed" do
        instance.instance_variable_set(:@state, "completed")
        expect(instance.send(:should_stop?)).to be true
      end

      it "returns true when state is error" do
        instance.instance_variable_set(:@state, "error")
        expect(instance.send(:should_stop?)).to be true
      end

      it "returns false for other states" do
        instance.instance_variable_set(:@state, "running")
        expect(instance.send(:should_stop?)).to be false
      end
    end

    describe "#should_pause?" do
      it "returns true when state is paused" do
        instance.instance_variable_set(:@state, "paused")
        expect(instance.send(:should_pause?)).to be true
      end

      it "returns true when state is waiting_for_user" do
        instance.instance_variable_set(:@state, "waiting_for_user")
        expect(instance.send(:should_pause?)).to be true
      end

      it "returns true when state is waiting_for_rate_limit" do
        instance.instance_variable_set(:@state, "waiting_for_rate_limit")
        expect(instance.send(:should_pause?)).to be true
      end

      it "returns false for other states" do
        instance.instance_variable_set(:@state, "running")
        expect(instance.send(:should_pause?)).to be false
      end
    end

    describe "#handle_pause_condition" do
      it "sleeps when state is paused" do
        instance.instance_variable_set(:@state, "paused")
        sleeper = instance.instance_variable_get(:@sleeper)
        expect(sleeper).to receive(:sleep).with(1)

        instance.send(:handle_pause_condition)
      end

      it "returns nil for waiting_for_user state" do
        instance.instance_variable_set(:@state, "waiting_for_user")

        result = instance.send(:handle_pause_condition)

        expect(result).to be_nil
      end

      it "returns nil for waiting_for_rate_limit state" do
        instance.instance_variable_set(:@state, "waiting_for_rate_limit")

        result = instance.send(:handle_pause_condition)

        expect(result).to be_nil
      end
    end

    describe "#all_steps_completed?" do
      let(:mock_runner) { double }

      it "delegates to runner's all_steps_completed? method" do
        expect(mock_runner).to receive(:all_steps_completed?).and_return(true)

        result = instance.send(:all_steps_completed?, mock_runner)

        expect(result).to be true
      end
    end

    describe "#calculate_progress_percentage" do
      let(:mock_runner) { double }
      let(:mock_progress) { double }

      before do
        allow(mock_runner).to receive(:progress).and_return(mock_progress)
      end

      it "calculates percentage correctly" do
        allow(mock_runner).to receive(:all_steps).and_return(%w[step1 step2 step3 step4])
        allow(mock_progress).to receive(:completed_steps).and_return(["step1", "step2"])

        result = instance.send(:calculate_progress_percentage, mock_runner)

        expect(result).to eq(50.0)
      end

      it "returns 0 when no steps exist" do
        allow(mock_runner).to receive(:all_steps).and_return([])
        allow(mock_progress).to receive(:completed_steps).and_return([])

        result = instance.send(:calculate_progress_percentage, mock_runner)

        expect(result).to eq(0)
      end

      it "rounds to 2 decimal places" do
        allow(mock_runner).to receive(:all_steps).and_return(%w[step1 step2 step3])
        allow(mock_progress).to receive(:completed_steps).and_return(["step1"])

        result = instance.send(:calculate_progress_percentage, mock_runner)

        expect(result).to eq(33.33)
      end
    end

    describe "#update_state" do
      let(:mock_state_manager) { double }

      before do
        instance.instance_variable_set(:@state_manager, mock_state_manager)
        instance.instance_variable_set(:@state, "running")
        instance.instance_variable_set(:@current_step, "step1")
        instance.instance_variable_set(:@current_provider, "test_provider")
        instance.instance_variable_set(:@user_input, {key: "value"})
        allow(mock_state_manager).to receive(:update_state)
      end

      it "updates state manager with current state" do
        freeze_time = Time.parse("2024-01-01 12:00:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        expected_state = {
          state: "running",
          current_step: "step1",
          current_provider: "test_provider",
          user_input: {key: "value"},
          last_updated: freeze_time
        }

        expect(mock_state_manager).to receive(:update_state).with(expected_state)

        instance.send(:update_state)
      end
    end

    describe "#load_state" do
      let(:mock_state_manager) { double }

      before do
        instance.instance_variable_set(:@state_manager, mock_state_manager)
        instance.instance_variable_set(:@user_input, {})
      end

      it "loads state when state manager has state" do
        saved_state = {
          state: "running",
          user_input: {key: "value"}
        }

        allow(mock_state_manager).to receive(:has_state?).and_return(true)
        allow(mock_state_manager).to receive(:load_state).and_return(saved_state)

        instance.send(:load_state)

        expect(instance.user_input).to eq({key: "value"})
      end

      it "handles nil state gracefully" do
        allow(mock_state_manager).to receive(:has_state?).and_return(true)
        allow(mock_state_manager).to receive(:load_state).and_return(nil)

        expect { instance.send(:load_state) }.not_to raise_error
      end

      it "handles non-hash state gracefully" do
        allow(mock_state_manager).to receive(:has_state?).and_return(true)
        allow(mock_state_manager).to receive(:load_state).and_return("invalid_state")

        expect { instance.send(:load_state) }.not_to raise_error
      end

      it "does not load when state manager has no state" do
        allow(mock_state_manager).to receive(:has_state?).and_return(false)

        expect(mock_state_manager).not_to receive(:load_state)

        instance.send(:load_state)
      end
    end

    describe "#save_state" do
      let(:mock_state_manager) { double }

      before do
        instance.instance_variable_set(:@state_manager, mock_state_manager)
        instance.instance_variable_set(:@state, "completed")
        instance.instance_variable_set(:@current_step, "final_step")
        instance.instance_variable_set(:@current_provider, "test_provider")
        instance.instance_variable_set(:@user_input, {key: "value"})
        allow(mock_state_manager).to receive(:save_state)
      end

      it "saves current state to state manager" do
        freeze_time = Time.parse("2024-01-01 12:00:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        expected_state = {
          state: "completed",
          current_step: "final_step",
          current_provider: "test_provider",
          user_input: {key: "value"},
          last_updated: freeze_time
        }

        expect(mock_state_manager).to receive(:save_state).with(expected_state)

        instance.send(:save_state)
      end
    end

    describe "#show_mode_specific_feedback" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:instance) { create_instance(tui: mock_tui) }

      before do
        allow(mock_tui).to receive(:show_message)
      end

      it "shows analyze mode feedback" do
        instance.instance_variable_set(:@mode, :analyze)

        expect(mock_tui).to receive(:show_message).with("🔬 Starting codebase analysis...", :info)
        expect(mock_tui).to receive(:show_message).with("Press 'j' to view background jobs, 'h' for help", :info)

        instance.send(:show_mode_specific_feedback)
      end

      it "shows execute mode feedback" do
        instance.instance_variable_set(:@mode, :execute)

        expect(mock_tui).to receive(:show_message).with("🏗️ Starting development workflow...", :info)
        expect(mock_tui).to receive(:show_message).with("Press 'j' to view background jobs, 'h' for help", :info)

        instance.send(:show_mode_specific_feedback)
      end
    end

    describe "#handle_error" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:instance) { create_instance(tui: mock_tui) }

      before do
        instance.instance_variable_set(:@execution_log, [])
        allow(mock_tui).to receive(:show_message)
      end

      it "shows error message" do
        error = StandardError.new("Test error")

        expect(mock_tui).to receive(:show_message).with("❌ Harness error: Test error", :error)
        expect(mock_tui).to receive(:show_message).with("Error type: StandardError", :error)

        instance.send(:handle_error, error)
      end

      it "logs error to execution log" do
        error = StandardError.new("Test error")
        error.set_backtrace(["line1", "line2", "line3", "line4", "line5", "line6"])

        freeze_time = Time.parse("2024-01-01 12:00:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        instance.send(:handle_error, error)

        log_entry = instance.execution_log.first
        expect(log_entry[:timestamp]).to eq(freeze_time)
        expect(log_entry[:level]).to eq(:error)
        expect(log_entry[:message]).to eq("Test error")
        expect(log_entry[:backtrace]).to eq(["line1", "line2", "line3", "line4", "line5"])
      end

      it "shows backtrace in debug mode" do
        error = StandardError.new("Test error")
        error.set_backtrace(["line1", "line2", "line3", "line4"])

        allow(ENV).to receive(:[]).with("DEBUG").and_return("true")

        expect(mock_tui).to receive(:show_message).with("Backtrace: line1\nline2\nline3", :error)

        instance.send(:handle_error, error)
      end

      it "does not show backtrace when not in debug mode" do
        error = StandardError.new("Test error")
        error.set_backtrace(["line1", "line2"])

        allow(ENV).to receive(:[]).with("DEBUG").and_return(nil)

        expect(mock_tui).not_to receive(:show_message).with(/Backtrace/, :error)

        instance.send(:handle_error, error)
      end
    end

    describe "#handle_completion_criteria_not_met" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:mock_workflow_controller) { double }
      let(:instance) { create_instance(tui: mock_tui) }

      before do
        instance.instance_variable_set(:@workflow_controller, mock_workflow_controller)
        allow(mock_tui).to receive(:show_message)
        allow(mock_workflow_controller).to receive(:complete_workflow)
        allow(mock_workflow_controller).to receive(:stop_workflow)
      end

      it "shows completion criteria warning" do
        completion_status = {summary: "Missing required files"}

        allow(mock_tui).to receive(:get_confirmation).and_return(false)

        expect(mock_tui).to receive(:show_message).with("Completion criteria not met: Missing required files", :warning)

        instance.send(:handle_completion_criteria_not_met, completion_status)
      end

      context "when user chooses to continue" do
        before do
          allow(mock_tui).to receive(:get_confirmation).and_return(true)
        end

        it "completes workflow with override" do
          completion_status = {summary: "Missing required files"}

          expect(mock_workflow_controller).to receive(:complete_workflow).with("Completed with user override")
          expect(mock_tui).to receive(:show_message).with("✅ Harness completed with user override", :success)

          instance.send(:handle_completion_criteria_not_met, completion_status)

          expect(instance.instance_variable_get(:@state)).to eq("completed")
        end
      end

      context "when user chooses not to continue" do
        before do
          allow(mock_tui).to receive(:get_confirmation).and_return(false)
        end

        it "stops workflow due to unmet criteria" do
          completion_status = {summary: "Missing required files"}

          expect(mock_workflow_controller).to receive(:stop_workflow).with("Completion criteria not met")
          expect(mock_tui).to receive(:show_message).with("❌ Harness stopped due to unmet completion criteria", :error)

          instance.send(:handle_completion_criteria_not_met, completion_status)

          expect(instance.instance_variable_get(:@state)).to eq("error")
        end
      end
    end

    describe "#handle_rate_limit" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
      let(:instance) { create_instance(tui: mock_tui, provider_manager: provider_manager) }

      before do
        instance.instance_variable_set(:@current_provider, "current_provider")
        allow(mock_tui).to receive(:show_message)
        allow(provider_manager).to receive(:mark_rate_limited)
        allow(provider_manager).to receive(:switch_provider)
        allow(instance).to receive(:wait_for_rate_limit_reset)
      end

      it "sets state to waiting for rate limit then back to running when switch succeeds" do
        allow(provider_manager).to receive(:switch_provider).and_return("new_provider")

        instance.send(:handle_rate_limit, {})

        # After successful switch, state is back to running
        expect(instance.instance_variable_get(:@state)).to eq("running")
      end

      it "shows rate limit message" do
        allow(provider_manager).to receive(:switch_provider).and_return("new_provider")

        expect(mock_tui).to receive(:show_message).with("⏳ Rate limit detected, switching provider", :warning)

        instance.send(:handle_rate_limit, {})
      end

      it "marks current provider as rate limited" do
        allow(provider_manager).to receive(:switch_provider).and_return("new_provider")

        expect(provider_manager).to receive(:mark_rate_limited).with("current_provider")

        instance.send(:handle_rate_limit, {})
      end

      context "when provider switch succeeds" do
        before do
          allow(provider_manager).to receive(:switch_provider).and_return("new_provider")
        end

        it "switches to new provider" do
          expect(mock_tui).to receive(:show_message).with("🔄 Switched to provider: new_provider", :info)

          instance.send(:handle_rate_limit, {})

          expect(instance.instance_variable_get(:@current_provider)).to eq("new_provider")
          expect(instance.instance_variable_get(:@state)).to eq("running")
        end
      end

      context "when no providers available" do
        before do
          allow(provider_manager).to receive(:switch_provider).and_return(nil)
        end

        it "waits for rate limit reset" do
          expect(instance).to receive(:wait_for_rate_limit_reset)

          instance.send(:handle_rate_limit, {})
        end
      end
    end

    describe "#wait_for_rate_limit_reset" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
      let(:instance) { create_instance(tui: mock_tui, provider_manager: provider_manager) }

      before do
        allow(mock_tui).to receive(:show_message)
        allow(instance).to receive(:sleep_until_reset)
      end

      context "when reset time is available" do
        let(:reset_time) { Time.now + 60 }

        before do
          allow(provider_manager).to receive(:next_reset_time).and_return(reset_time)
        end

        it "shows reset time message" do
          expect(mock_tui).to receive(:show_message).with("⏰ Waiting for rate limit reset at #{reset_time}", :warning)

          instance.send(:wait_for_rate_limit_reset)
        end

        it "sleeps until reset and sets state to running" do
          expect(instance).to receive(:sleep_until_reset).with(reset_time)

          instance.send(:wait_for_rate_limit_reset)

          expect(instance.instance_variable_get(:@state)).to eq("running")
        end
      end

      context "when no reset time available" do
        before do
          allow(provider_manager).to receive(:next_reset_time).and_return(nil)
        end

        it "raises error and sets state to error" do
          expect { instance.send(:wait_for_rate_limit_reset) }.to raise_error("All providers rate limited with no reset time available")

          expect(instance.instance_variable_get(:@state)).to eq("error")
        end
      end
    end

    describe "#sleep_until_reset" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:test_sleeper) { double("Sleeper", sleep: nil) }
      let(:instance) { create_instance(tui: mock_tui, sleeper: test_sleeper) }

      before do
        instance.instance_variable_set(:@state, "waiting_for_rate_limit")
        allow(mock_tui).to receive(:show_message)
        # sleeper already stubbed
      end

      it "shows countdown messages and sleeps" do
        reset_time = Time.now + 3
        allow(Time).to receive(:now).and_return(Time.now, reset_time - 2, reset_time - 1, reset_time + 1)

        expect(mock_tui).to receive(:show_message).with(/Rate limit reset in \d+ seconds/, :info).at_least(:once)
        sleeper = instance.instance_variable_get(:@sleeper)
        expect(sleeper).to receive(:sleep).with(1).at_least(:once)

        instance.send(:sleep_until_reset, reset_time)
      end
    end

    describe "#cleanup" do
      let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
      let(:instance) { create_instance(tui: mock_tui) }

      before do
        jobs = {"job1" => {}, "job2" => {}, "job3" => {}}
        allow(mock_tui).to receive(:instance_variable_get).with(:@jobs).and_return(jobs)
        allow(mock_tui).to receive(:remove_job)
      end

      it "removes all remaining jobs" do
        expect(mock_tui).to receive(:remove_job).with("job1")
        expect(mock_tui).to receive(:remove_job).with("job2")
        expect(mock_tui).to receive(:remove_job).with("job3")

        instance.send(:cleanup)
      end
    end

    describe "#get_completion_message" do
      let(:instance) { create_instance }

      it "returns completed message for completed state" do
        instance.instance_variable_set(:@state, "completed")
        expect(instance.send(:get_completion_message)).to eq("Harness completed successfully")
      end

      it "returns stopped message for stopped state" do
        instance.instance_variable_set(:@state, "stopped")
        expect(instance.send(:get_completion_message)).to eq("Harness stopped by user")
      end

      it "returns error message for error state" do
        instance.instance_variable_set(:@state, "error")
        expect(instance.send(:get_completion_message)).to eq("Harness encountered an error")
      end

      it "returns default message for other states" do
        instance.instance_variable_set(:@state, "unknown")
        expect(instance.send(:get_completion_message)).to eq("Harness finished")
      end
    end
  end
end
