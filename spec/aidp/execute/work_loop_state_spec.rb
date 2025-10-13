# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_state"

RSpec.describe Aidp::Execute::WorkLoopState do
  let(:state) { described_class.new }

  describe "initial state" do
    it "starts in idle state" do
      expect(state).to be_idle
      expect(state.current_state).to eq(:idle)
    end

    it "has zero iterations" do
      expect(state.iteration).to eq(0)
    end

    it "has empty queues" do
      expect(state.queued_instructions).to be_empty
      expect(state.queued_count).to eq(0)
    end
  end

  describe "state transitions" do
    describe "#start!" do
      it "transitions from idle to running" do
        expect { state.start! }.to change(state, :current_state).from(:idle).to(:running)
      end

      it "raises error if not idle" do
        state.start!
        expect { state.start! }.to raise_error(Aidp::Execute::WorkLoopState::StateError)
      end
    end

    describe "#pause!" do
      before { state.start! }

      it "transitions from running to paused" do
        expect { state.pause! }.to change(state, :current_state).from(:running).to(:paused)
      end

      it "raises error if not running" do
        state.pause!
        expect { state.pause! }.to raise_error(Aidp::Execute::WorkLoopState::StateError)
      end
    end

    describe "#resume!" do
      before do
        state.start!
        state.pause!
      end

      it "transitions from paused to running" do
        expect { state.resume! }.to change(state, :current_state).from(:paused).to(:running)
      end

      it "raises error if not paused" do
        state.resume!
        expect { state.resume! }.to raise_error(Aidp::Execute::WorkLoopState::StateError)
      end
    end

    describe "#cancel!" do
      before { state.start! }

      it "transitions to cancelled" do
        expect { state.cancel! }.to change(state, :current_state).to(:cancelled)
      end

      it "can cancel from paused state" do
        state.pause!
        expect { state.cancel! }.to change(state, :current_state).to(:cancelled)
      end
    end

    describe "#complete!" do
      before { state.start! }

      it "transitions to completed" do
        expect { state.complete! }.to change(state, :current_state).to(:completed)
      end
    end

    describe "#error!" do
      before { state.start! }

      it "transitions to error state" do
        error = StandardError.new("test error")
        expect { state.error!(error) }.to change(state, :current_state).to(:error)
      end

      it "stores the error" do
        error = StandardError.new("test error")
        state.error!(error)
        expect(state.last_error).to eq(error)
      end
    end
  end

  describe "iteration management" do
    before { state.start! }

    it "increments iteration count" do
      expect { state.increment_iteration! }.to change(state, :iteration).from(0).to(1)
    end

    it "can increment multiple times" do
      5.times { state.increment_iteration! }
      expect(state.iteration).to eq(5)
    end
  end

  describe "instruction queueing" do
    it "enqueues instructions" do
      state.enqueue_instruction("test instruction")
      expect(state.queued_count).to eq(1)
    end

    it "dequeues all instructions" do
      state.enqueue_instruction("first")
      state.enqueue_instruction("second")

      instructions = state.dequeue_instructions
      expect(instructions).to eq(["first", "second"])
      expect(state.queued_count).to eq(0)
    end

    it "returns empty array when no instructions" do
      expect(state.dequeue_instructions).to eq([])
    end
  end

  describe "guard updates" do
    it "requests guard updates" do
      state.request_guard_update("max_lines", "500")
      updates = state.pending_guard_updates
      expect(updates).to eq({"max_lines" => "500"})
    end

    it "clears updates after retrieval" do
      state.request_guard_update("max_lines", "500")
      state.pending_guard_updates
      expect(state.pending_guard_updates).to be_empty
    end
  end

  describe "config reload" do
    it "requests config reload" do
      state.request_config_reload
      expect(state.config_reload_requested?).to be true
    end

    it "clears reload flag after check" do
      state.request_config_reload
      state.config_reload_requested?
      expect(state.config_reload_requested?).to be false
    end
  end

  describe "output buffering" do
    it "appends output messages" do
      state.append_output("test message", type: :info)
      output = state.drain_output
      expect(output.size).to eq(1)
      expect(output.first[:message]).to eq("test message")
      expect(output.first[:type]).to eq(:info)
    end

    it "clears output after draining" do
      state.append_output("test")
      state.drain_output
      expect(state.drain_output).to be_empty
    end

    it "handles multiple output entries" do
      state.append_output("first", type: :info)
      state.append_output("second", type: :error)
      output = state.drain_output
      expect(output.size).to eq(2)
    end
  end

  describe "#summary" do
    before { state.start! }

    it "returns state summary" do
      state.increment_iteration!
      state.enqueue_instruction("test")

      summary = state.summary
      expect(summary[:state]).to eq("RUNNING")
      expect(summary[:iteration]).to eq(1)
      expect(summary[:queued_instructions]).to eq(1)
      expect(summary[:has_error]).to be false
    end

    it "includes error status" do
      state.error!(StandardError.new("test"))
      summary = state.summary
      expect(summary[:has_error]).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do
        Thread.new do
          10.times { state.enqueue_instruction("test") }
        end
      end

      threads.each(&:join)
      expect(state.queued_count).to eq(100)
    end
  end
end
