# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/workflow_state"

RSpec.describe Aidp::Harness::State::WorkflowState do
  let(:persistence) { instance_double("Persistence") }
  let(:project_dir) { "/test/project" }
  let(:mode) { :execute }
  let(:workflow_state) { described_class.new(persistence, project_dir, mode) }
  let(:progress_tracker) { instance_double("ProgressTracker") }

  before do
    allow(persistence).to receive(:load_state).and_return({})
    allow(persistence).to receive(:save_state)
    allow(persistence).to receive(:has_state?).and_return(false)
    allow(persistence).to receive(:clear_state)

    # Mock the progress tracker creation
    allow_any_instance_of(described_class).to receive(:create_progress_tracker).and_return(progress_tracker)
    allow(progress_tracker).to receive(:completed_steps).and_return([])
    allow(progress_tracker).to receive(:current_step).and_return(nil)
    allow(progress_tracker).to receive(:step_completed?).and_return(false)
    allow(progress_tracker).to receive(:mark_step_completed)
    allow(progress_tracker).to receive(:mark_step_in_progress)
    allow(progress_tracker).to receive(:next_step).and_return(nil)
    allow(progress_tracker).to receive(:started_at).and_return(nil)
    allow(progress_tracker).to receive(:reset)
  end

  describe "#initialize" do
    it "initializes with persistence, project_dir, and mode" do
      expect(workflow_state).to be_a(described_class)
    end

    context "with unsupported mode" do
      it "raises ArgumentError when creating with invalid mode" do
        # Need to prevent the mocking to allow real error
        allow_any_instance_of(described_class).to receive(:create_progress_tracker).and_call_original

        expect {
          described_class.new(persistence, project_dir, :invalid_mode)
        }.to raise_error(ArgumentError, /Unsupported mode/)
      end
    end
  end

  describe "#completed_steps" do
    before do
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1", "step2"])
    end

    it "delegates to progress tracker" do
      expect(workflow_state.completed_steps).to eq(["step1", "step2"])
    end
  end

  describe "#current_step" do
    before do
      allow(progress_tracker).to receive(:current_step).and_return("step3")
    end

    it "delegates to progress tracker" do
      expect(workflow_state.current_step).to eq("step3")
    end
  end

  describe "#step_completed?" do
    before do
      allow(progress_tracker).to receive(:step_completed?).with("step1").and_return(true)
      allow(progress_tracker).to receive(:step_completed?).with("step2").and_return(false)
    end

    it "returns true for completed step" do
      expect(workflow_state.step_completed?("step1")).to be true
    end

    it "returns false for incomplete step" do
      expect(workflow_state.step_completed?("step2")).to be false
    end
  end

  describe "#mark_step_completed" do
    it "marks step as completed in progress tracker" do
      expect(progress_tracker).to receive(:mark_step_completed).with("step1")
      workflow_state.mark_step_completed("step1")
    end

    it "updates harness state" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:current_step]).to be_nil
        expect(state[:last_step_completed]).to eq("step1")
        expect(state[:last_updated]).to be_a(Time)
      end

      workflow_state.mark_step_completed("step1")
    end
  end

  describe "#mark_step_in_progress" do
    it "marks step as in progress in progress tracker" do
      expect(progress_tracker).to receive(:mark_step_in_progress).with("step2")
      workflow_state.mark_step_in_progress("step2")
    end

    it "updates harness state with current step" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:current_step]).to eq("step2")
        expect(state[:last_updated]).to be_a(Time)
      end

      workflow_state.mark_step_in_progress("step2")
    end
  end

  describe "#next_step" do
    before do
      allow(progress_tracker).to receive(:next_step).and_return("next_step")
    end

    it "delegates to progress tracker" do
      expect(workflow_state.next_step).to eq("next_step")
    end
  end

  describe "#total_steps" do
    it "returns count of steps from steps spec" do
      # Execute mode has specific steps defined
      expect(workflow_state.total_steps).to be > 0
    end
  end

  describe "#all_steps_completed?" do
    context "when all steps are completed" do
      before do
        total = workflow_state.total_steps
        allow(progress_tracker).to receive(:completed_steps).and_return(Array.new(total))
      end

      it "returns true" do
        expect(workflow_state.all_steps_completed?).to be true
      end
    end

    context "when not all steps are completed" do
      before do
        allow(progress_tracker).to receive(:completed_steps).and_return(["step1"])
      end

      it "returns false" do
        expect(workflow_state.all_steps_completed?).to be false
      end
    end
  end

  describe "#progress_percentage" do
    context "when all steps are completed" do
      before do
        total = workflow_state.total_steps
        allow(progress_tracker).to receive(:completed_steps).and_return(Array.new(total))
      end

      it "returns 100.0" do
        expect(workflow_state.progress_percentage).to eq(100.0)
      end
    end

    context "when some steps are completed" do
      before do
        total = workflow_state.total_steps
        completed_count = (total / 2.0).ceil
        allow(progress_tracker).to receive(:completed_steps).and_return(Array.new(completed_count))
      end

      it "returns percentage between 0 and 100" do
        percentage = workflow_state.progress_percentage
        expect(percentage).to be_between(0, 100)
        expect(percentage).to be_a(Float)
      end
    end
  end

  describe "#session_duration" do
    context "when session has not started" do
      before do
        allow(progress_tracker).to receive(:started_at).and_return(nil)
      end

      it "returns 0" do
        expect(workflow_state.session_duration).to eq(0)
      end
    end

    context "when session has started" do
      before do
        allow(progress_tracker).to receive(:started_at).and_return(Time.now - 60)
      end

      it "returns duration in seconds" do
        duration = workflow_state.session_duration
        expect(duration).to be >= 60
        expect(duration).to be < 65  # Account for small processing time
      end
    end
  end

  describe "#reset_all" do
    it "resets progress tracker" do
      expect(progress_tracker).to receive(:reset)
      workflow_state.reset_all
    end

    it "clears persistence state" do
      expect(persistence).to receive(:clear_state)
      workflow_state.reset_all
    end
  end

  describe "#progress_summary" do
    before do
      allow(progress_tracker).to receive(:completed_steps).and_return(["step1", "step2"])
      allow(progress_tracker).to receive(:current_step).and_return("step3")
      allow(progress_tracker).to receive(:next_step).and_return("step4")
      allow(progress_tracker).to receive(:started_at).and_return(Time.now - 120)
    end

    it "returns comprehensive progress summary" do
      summary = workflow_state.progress_summary

      expect(summary[:mode]).to eq(:execute)
      expect(summary[:completed_steps]).to eq(2)
      expect(summary[:total_steps]).to be > 0
      expect(summary[:current_step]).to eq("step3")
      expect(summary[:next_step]).to eq("step4")
      expect(summary[:all_completed]).to be false
      expect(summary[:started_at]).to be_a(Time)
      expect(summary[:harness_state]).to be_a(Hash)
      expect(summary[:progress_percentage]).to be_a(Float)
      expect(summary[:session_duration]).to be >= 120
    end
  end
end
