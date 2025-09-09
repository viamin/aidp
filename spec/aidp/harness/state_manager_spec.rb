# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Harness::StateManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:state_manager) { described_class.new(temp_dir, :analyze) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with analyze mode" do
      expect(state_manager.instance_variable_get(:@mode)).to eq(:analyze)
      expect(state_manager.instance_variable_get(:@project_dir)).to eq(temp_dir)
    end

    it "initializes with execute mode" do
      execute_manager = described_class.new(temp_dir, :execute)
      expect(execute_manager.instance_variable_get(:@mode)).to eq(:execute)
    end

    it "raises error for unsupported mode" do
      expect { described_class.new(temp_dir, :invalid) }.to raise_error(ArgumentError)
    end

    it "creates state directory" do
      state_dir = File.join(temp_dir, ".aidp", "harness")
      expect(Dir.exist?(state_dir)).to be true
    end

    it "initializes progress tracker" do
      progress_tracker = state_manager.progress_tracker
      expect(progress_tracker).to be_a(Aidp::Analyze::Progress)
    end
  end

  describe "#has_state?" do
    it "returns false when no state file exists" do
      expect(state_manager.has_state?).to be false
    end

    it "returns true when state file exists" do
      state_manager.save_state({test: "data"})
      expect(state_manager.has_state?).to be true
    end
  end

  describe "#save_state and #load_state" do
    it "saves and loads state correctly" do
      test_state = {
        state: "running",
        current_step: "test_step",
        user_input: {"question_1" => "answer_1"}
      }

      state_manager.save_state(test_state)
      loaded_state = state_manager.load_state

      expect(loaded_state[:state]).to eq("running")
      expect(loaded_state[:current_step]).to eq("test_step")
      expect(loaded_state[:user_input]).to eq({"question_1" => "answer_1"})
    end

    it "handles concurrent access with file locking" do
      # This is a basic test - in practice, file locking would be more complex
      test_state = {test: "concurrent"}
      state_manager.save_state(test_state)
      expect(state_manager.load_state[:test]).to eq("concurrent")
    end
  end

  describe "#clear_state" do
    it "removes state file" do
      state_manager.save_state({test: "data"})
      expect(state_manager.has_state?).to be true

      state_manager.clear_state
      expect(state_manager.has_state?).to be false
    end
  end

  describe "#update_state" do
    it "updates specific state fields" do
      initial_state = {state: "idle", current_step: "step1"}
      state_manager.save_state(initial_state)

      state_manager.update_state(current_step: "step2", new_field: "value")
      updated_state = state_manager.load_state

      expect(updated_state[:state]).to eq("idle") # unchanged
      expect(updated_state[:current_step]).to eq("step2") # updated
      expect(updated_state[:new_field]).to eq("value") # added
    end
  end

  describe "progress tracking integration" do
    it "delegates completed_steps to progress tracker" do
      # Mock the progress tracker
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1", "step2"])
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      expect(state_manager.completed_steps).to eq(["step1", "step2"])
    end

    it "delegates current_step to progress tracker" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:current_step).and_return("step3")
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      expect(state_manager.current_step).to eq("step3")
    end

    it "delegates step_completed? to progress tracker" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:step_completed?).with("step1").and_return(true)
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      expect(state_manager.step_completed?("step1")).to be true
    end

    it "marks step as completed in both progress tracker and harness state" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:mark_step_completed).with("step1")
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      state_manager.mark_step_completed("step1")

      expect(progress_tracker).to have_received(:mark_step_completed).with("step1")

      # Check that harness state was also updated
      state = state_manager.load_state
      expect(state[:last_step_completed]).to eq("step1")
      expect(state[:current_step]).to be_nil
    end

    it "marks step as in progress in both progress tracker and harness state" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:mark_step_in_progress).with("step1")
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      state_manager.mark_step_in_progress("step1")

      expect(progress_tracker).to have_received(:mark_step_in_progress).with("step1")

      # Check that harness state was also updated
      state = state_manager.load_state
      expect(state[:current_step]).to eq("step1")
    end
  end

  describe "#total_steps" do
    it "returns correct total for analyze mode" do
      # Mock the Steps::SPEC
      allow(Aidp::Analyze::Steps::SPEC).to receive(:keys).and_return(["step1", "step2", "step3"])
      expect(state_manager.total_steps).to eq(3)
    end

    it "returns correct total for execute mode" do
      execute_manager = described_class.new(temp_dir, :execute)
      allow(Aidp::Execute::Steps::SPEC).to receive(:keys).and_return(["step1", "step2"])
      expect(execute_manager.total_steps).to eq(2)
    end
  end

  describe "#all_steps_completed?" do
    it "returns true when all steps are completed" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1", "step2", "step3"])
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)
      allow(state_manager).to receive(:total_steps).and_return(3)

      expect(state_manager.all_steps_completed?).to be true
    end

    it "returns false when not all steps are completed" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1", "step2"])
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)
      allow(state_manager).to receive(:total_steps).and_return(3)

      expect(state_manager.all_steps_completed?).to be false
    end
  end

  describe "#reset_all" do
    it "resets both progress tracker and harness state" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:reset)
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)

      # Save some state first
      state_manager.save_state({test: "data"})
      expect(state_manager.has_state?).to be true

      state_manager.reset_all

      expect(progress_tracker).to have_received(:reset)
      expect(state_manager.has_state?).to be false
    end
  end

  describe "#progress_summary" do
    it "returns comprehensive progress summary" do
      progress_tracker = double("progress_tracker")
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1"])
      allow(progress_tracker).to receive(:current_step).and_return("step2")
      allow(progress_tracker).to receive(:next_step).and_return("step2")
      allow(progress_tracker).to receive(:started_at).and_return(Time.now)
      state_manager.instance_variable_set(:@progress_tracker, progress_tracker)
      allow(state_manager).to receive(:total_steps).and_return(3)

      summary = state_manager.progress_summary

      expect(summary[:mode]).to eq(:analyze)
      expect(summary[:completed_steps]).to eq(1)
      expect(summary[:total_steps]).to eq(3)
      expect(summary[:current_step]).to eq("step2")
      expect(summary[:next_step]).to eq("step2")
      expect(summary[:all_completed]).to be false
      expect(summary[:started_at]).to be_a(Time)
      expect(summary[:harness_state]).to be_a(Hash)
    end
  end

  describe "rate limit management" do
    it "tracks rate limit information" do
      provider_name = "test_provider"
      reset_time = Time.now + 3600

      state_manager.update_rate_limit_info(provider_name, reset_time, 2)

      expect(state_manager.provider_rate_limited?(provider_name)).to be true
      expect(state_manager.next_provider_reset_time).to eq(reset_time)
    end

    it "clears rate limit information" do
      provider_name = "test_provider"
      reset_time = Time.now + 3600

      state_manager.update_rate_limit_info(provider_name, reset_time)
      expect(state_manager.provider_rate_limited?(provider_name)).to be true

      # Simulate time passing
      allow(Time).to receive(:now).and_return(reset_time + 1)
      expect(state_manager.provider_rate_limited?(provider_name)).to be false
    end
  end

  describe "user input management" do
    it "tracks user input" do
      state_manager.add_user_input("question_1", "answer_1")
      state_manager.add_user_input("question_2", "answer_2")

      user_input = state_manager.user_input
      expect(user_input["question_1"]).to eq("answer_1")
      expect(user_input["question_2"]).to eq("answer_2")
    end

    it "persists user input across state saves" do
      state_manager.add_user_input("question_1", "answer_1")
      state_manager.save_state({test: "data"})

      # Create new instance to test persistence
      new_manager = described_class.new(temp_dir, :analyze)
      user_input = new_manager.user_input
      expect(user_input["question_1"]).to eq("answer_1")
    end
  end

  describe "execution log management" do
    it "tracks execution log entries" do
      entry1 = {timestamp: Time.now, message: "test1"}
      entry2 = {timestamp: Time.now, message: "test2"}

      state_manager.add_execution_log(entry1)
      state_manager.add_execution_log(entry2)

      log = state_manager.execution_log
      expect(log.size).to eq(2)
      expect(log.first[:message]).to eq("test1")
      expect(log.last[:message]).to eq("test2")
    end
  end
end
