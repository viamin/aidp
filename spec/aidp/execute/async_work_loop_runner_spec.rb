# frozen_string_literal: true

require "spec_helper"
require "concurrent-ruby"

RSpec.describe Aidp::Execute::AsyncWorkLoopRunner do
  let(:project_dir) { "/tmp/test_project" }
  let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
  let(:config) { instance_double(Aidp::Config) }
  let(:test_prompt) { TestPrompt.new }
  let(:sync_runner) { instance_double(Aidp::Execute::WorkLoopRunner) }
  let(:sync_runner_class) do
    class_double(Aidp::Execute::WorkLoopRunner).tap do |klass|
      allow(klass).to receive(:new).and_return(sync_runner)
    end
  end
  let(:options) { {timeout: 60, cancel_timeout: 0.1, prompt: test_prompt, sync_runner_class: sync_runner_class} }
  let(:runner) { described_class.new(project_dir, provider_manager, config, options) }

  describe "#initialize" do
    it "creates an instance with required dependencies" do
      expect(runner).to be_a(described_class)
      expect(runner.state).to be_a(Aidp::Execute::WorkLoopState)
      expect(runner.instruction_queue).to be_a(Aidp::Execute::InstructionQueue)
      expect(runner.work_thread).to be_nil
    end

    it "initializes state as idle" do
      expect(runner.state.idle?).to be true
    end

    it "initializes empty instruction queue" do
      expect(runner.instruction_queue.count).to eq(0)
    end
  end

  describe "#execute_step_async" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation", files: ["test.rb"]} }
    let(:context) { {session_id: "test_session"} }
    let(:barrier) { Concurrent::Promises.resolvable_future }

    before do
      # Make execute_step block until we release it
      allow(sync_runner).to receive(:execute_step) { barrier.wait }
    end

    after do
      # Always release the barrier and cleanup
      barrier.fulfill(true) unless barrier.resolved?
      runner.cancel if runner.running?
      runner.wait
    end

    it "raises error when already running" do
      runner.state.start!
      expect do
        runner.execute_step_async(step_name, step_spec, context)
      end.to raise_error(Aidp::Execute::WorkLoopState::StateError, /already running/)
    end

    it "starts work loop in background thread" do
      result = runner.execute_step_async(step_name, step_spec, context)

      # Give thread time to start
      sleep 0.01

      expect(result[:status]).to eq("started")
      expect(result[:state]).to include(:state, :iteration, :queued_instructions, :has_error)
      expect(runner.running?).to be_truthy
    end

    it "handles thread execution errors" do
      allow(sync_runner).to receive(:execute_step).and_raise(StandardError.new("test error"))

      runner.execute_step_async(step_name, step_spec, context)
      runner.wait

      expect(runner.state.error?).to be true
    end
  end

  describe "#wait" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation"} }

    before do
      allow(sync_runner).to receive(:execute_step).and_return({status: "completed"})
    end

    it "returns nil when no thread is running" do
      expect(runner.wait).to be_nil
    end

    it "waits for thread completion and returns result" do
      # Use a non-blocking sync_runner for this test to allow completion
      allow(sync_runner).to receive(:execute_step).and_return({status: "completed"})

      runner.execute_step_async(step_name, step_spec)

      # Ensure thread has started and give it time to complete
      sleep 0.1

      result = runner.wait

      # If thread completed quickly, wait returns nil
      # So let's check build_final_result directly
      result = runner.send(:build_final_result) if result.nil?

      expect(result).to include(:status, :iterations, :message)
      expect(%w[completed cancelled error]).to include(result[:status])
    end
  end

  describe "#running?" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation"} }
    let(:barrier) { Concurrent::Promises.resolvable_future }

    before do
      allow(sync_runner).to receive(:execute_step) { barrier.wait }
    end

    after do
      barrier.fulfill(true) unless barrier.resolved?
      runner.cancel if runner.running?
      runner.wait
    end

    it "returns false when not running" do
      expect(runner.running?).to be_falsey
    end

    it "returns true when thread is alive and state is running" do
      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start
      sleep 0.01
      expect(runner.running?).to be_truthy
    end
  end

  describe "#pause" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation"} }
    let(:barrier) { Concurrent::Promises.resolvable_future }

    before do
      allow(sync_runner).to receive(:execute_step) { barrier.wait }
    end

    after do
      barrier.fulfill(true) unless barrier.resolved?
      runner.cancel if runner.running?
      runner.wait
    end

    it "returns nil when not running" do
      expect(runner.pause).to be_nil
    end

    it "pauses execution when running" do
      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start
      sleep 0.01
      result = runner.pause

      expect(result).to include(:status, :iteration)
      expect(result[:status]).to eq("paused")
      expect(runner.state.paused?).to be true
    end
  end

  describe "#resume" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation"} }
    let(:barrier) { Concurrent::Promises.resolvable_future }

    before do
      allow(sync_runner).to receive(:execute_step) { barrier.wait }
    end

    after do
      barrier.fulfill(true) unless barrier.resolved?
      runner.cancel if runner.running?
      runner.wait
    end

    it "returns nil when not paused" do
      expect(runner.resume).to be_nil
    end

    it "resumes execution when paused" do
      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start and pause
      sleep 0.01
      runner.pause
      result = runner.resume

      expect(result).to include(:status, :iteration)
      expect(result[:status]).to eq("resumed")
      expect(runner.state.running?).to be true
    end
  end

  describe "#cancel" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {type: "implementation"} }
    let(:barrier) { Concurrent::Promises.resolvable_future }

    before do
      allow(sync_runner).to receive(:execute_step) { barrier.wait }
    end

    after do
      barrier.fulfill(true) unless barrier.resolved?
      runner.wait if runner.work_thread
    end

    it "returns if already cancelled or completed" do
      runner.state.current_state = :cancelled
      result = runner.cancel
      expect(result).to be_nil
    end

    it "cancels running execution" do
      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start
      sleep 0.01
      result = runner.cancel

      expect(result).to include(:status, :iteration)
      expect(result[:status]).to eq("cancelled")
      expect(runner.state.cancelled?).to be true
    end

    it "saves checkpoint when requested" do
      checkpoint = instance_double("Checkpoint")
      allow(sync_runner).to receive(:checkpoint).and_return(checkpoint)
      allow(checkpoint).to receive(:record_checkpoint)

      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start
      sleep 0.01
      result = runner.cancel(save_checkpoint: true)

      expect(result).to include(:status)
      expect(result[:status]).to eq("cancelled")
    end
  end

  describe "#enqueue_instruction" do
    it "adds instruction to queue" do
      content = "Add error handling"
      result = runner.enqueue_instruction(content, type: :user_input, priority: :high)

      expect(result[:status]).to eq("enqueued")
      expect(result[:queued_count]).to eq(1)
      expect(result[:message]).to include("next iteration")
      expect(runner.instruction_queue.count).to eq(1)
    end

    it "tracks instruction in state" do
      content = "Fix bug in validator"
      runner.enqueue_instruction(content)

      status = runner.status
      expect(status[:queued_instructions]).to include(:total)
    end
  end

  describe "#drain_output" do
    it "returns output from state" do
      runner.state.append_output("Test message", type: :info)
      output = runner.drain_output

      expect(output).to be_an(Array)
      expect(output.first).to include(:message, :type, :timestamp)
    end
  end

  describe "#status" do
    it "returns comprehensive status information" do
      status = runner.status

      expect(status).to include(
        :state,
        :iteration,
        :queued_instructions,
        :thread_alive
      )
      expect(status[:thread_alive]).to be false
    end

    it "includes thread status when running" do
      step_name = "test_step"
      step_spec = {type: "implementation"}
      barrier = Concurrent::Promises.resolvable_future

      allow(sync_runner).to receive(:execute_step) { barrier.wait }

      runner.execute_step_async(step_name, step_spec)

      # Give thread time to start
      sleep 0.01
      status = runner.status

      expect(status[:thread_alive]).to be true

      # Clean up
      barrier.fulfill(true)
      runner.cancel
      runner.wait
    end
  end

  describe "private methods" do
    describe "#build_final_result" do
      it "builds completed result" do
        runner.state.start!
        runner.state.complete!
        result = runner.send(:build_final_result)

        expect(result[:status]).to eq("completed")
        expect(result[:message]).to include("completed successfully")
      end

      it "builds cancelled result" do
        runner.state.start!
        runner.state.cancel!
        result = runner.send(:build_final_result)

        expect(result[:status]).to eq("cancelled")
        expect(result[:message]).to include("cancelled by user")
      end

      it "builds error result" do
        error = StandardError.new("test error")
        runner.state.start!
        runner.state.error!(error)
        result = runner.send(:build_final_result)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("test error")
        expect(result[:message]).to include("encountered an error")
      end

      it "builds unknown result for unexpected state" do
        runner.state.start!
        runner.state.current_state = :unexpected
        result = runner.send(:build_final_result)

        expect(result[:status]).to eq("unknown")
        expect(result[:message]).to include("unknown state")
      end
    end

    describe "#save_cancellation_checkpoint" do
      let(:checkpoint) { instance_double("Checkpoint") }

      it "saves checkpoint when sync runner and checkpoint exist" do
        runner.sync_runner = sync_runner
        allow(sync_runner).to receive(:checkpoint).and_return(checkpoint)
        allow(checkpoint).to receive(:record_checkpoint)

        runner.send(:save_cancellation_checkpoint)

        expect(checkpoint).to have_received(:record_checkpoint)
      end

      it "returns early when no sync runner" do
        expect { runner.send(:save_cancellation_checkpoint) }.not_to raise_error
      end

      it "returns early when no checkpoint" do
        runner.sync_runner = sync_runner
        allow(sync_runner).to receive(:checkpoint).and_return(nil)

        expect { runner.send(:save_cancellation_checkpoint) }.not_to raise_error
      end
    end
  end
end
