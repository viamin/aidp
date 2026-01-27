# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::WorkLoopWorkflow do
  let(:workflow) { described_class.new }
  let(:mock_workflow_info) { double("WorkflowInfo", workflow_id: "test-workflow", run_id: "test-run", task_queue: "test-queue") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(mock_workflow_info)
  end

  describe "#drain_instruction_queue" do
    it "returns copy of instructions and clears queue" do
      workflow.instance_variable_set(:@instruction_queue, ["inst1", "inst2"])

      result = workflow.send(:drain_instruction_queue)

      expect(result).to eq(["inst1", "inst2"])
      expect(workflow.instance_variable_get(:@instruction_queue)).to be_empty
    end

    it "handles empty queue" do
      workflow.instance_variable_set(:@instruction_queue, [])

      result = workflow.send(:drain_instruction_queue)

      expect(result).to eq([])
    end
  end

  describe "#handle_escalation" do
    before do
      workflow.instance_variable_set(:@consecutive_failures, 5)
      workflow.instance_variable_set(:@escalate_requested, false)
    end

    it "sets escalate flag and resets failure count" do
      workflow.send(:handle_escalation)

      expect(workflow.instance_variable_get(:@escalate_requested)).to be true
      expect(workflow.instance_variable_get(:@consecutive_failures)).to eq(0)
    end
  end

  describe "#build_result" do
    before do
      workflow.instance_variable_set(:@step_name, "test-step")
      workflow.instance_variable_set(:@iteration, 5)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds successful result" do
      result_data = {
        success: true,
        reason: "completed",
        test_results: {all_passing: true}
      }

      result = workflow.send(:build_result, result_data)

      expect(result[:status]).to eq("completed")
      expect(result[:success]).to be true
      expect(result[:iterations]).to eq(5)
      expect(result[:step_name]).to eq("test-step")
    end

    it "builds failed result" do
      result_data = {
        success: false,
        reason: "max_iterations",
        test_results: {all_passing: false}
      }

      result = workflow.send(:build_result, result_data)

      expect(result[:status]).to eq("failed")
      expect(result[:success]).to be false
      expect(result[:reason]).to eq("max_iterations")
    end
  end

  describe "#build_canceled_result" do
    before do
      workflow.instance_variable_set(:@step_name, "canceled-step")
      workflow.instance_variable_set(:@iteration, 3)
      workflow.instance_variable_set(:@state, :apply_patch)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds canceled result with state" do
      result = workflow.send(:build_canceled_result)

      expect(result[:status]).to eq("canceled")
      expect(result[:step_name]).to eq("canceled-step")
      expect(result[:iterations]).to eq(3)
      expect(result[:state]).to eq(:apply_patch)
    end
  end

  describe "#activity_options" do
    it "delegates to class method" do
      options = workflow.send(:activity_options, start_to_close_timeout: 300)

      expect(options[:start_to_close_timeout]).to eq(300)
      expect(options).to have_key(:retry_policy)
    end

    it "returns default options when no overrides" do
      options = workflow.send(:activity_options)

      expect(options[:start_to_close_timeout]).to eq(600)
      expect(options[:heartbeat_timeout]).to eq(60)
    end
  end

  describe "#transition_to" do
    before do
      workflow.instance_variable_set(:@state, :ready)
      workflow.instance_variable_set(:@iteration, 1)
    end

    it "changes state and logs transition" do
      workflow.send(:transition_to, :apply_patch)

      expect(workflow.instance_variable_get(:@state)).to eq(:apply_patch)
    end
  end

  describe "#run_agent_activity" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@step_name, "test-step")
      workflow.instance_variable_set(:@iteration, 1)
      workflow.instance_variable_set(:@instruction_queue, ["do this"])
      workflow.instance_variable_set(:@escalate_requested, true)
    end

    it "executes activity and resets escalation flag" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return({success: true})

      result = workflow.send(:run_agent_activity)

      expect(result[:success]).to be true
      expect(workflow.instance_variable_get(:@escalate_requested)).to be false
    end
  end

  describe "#run_test_activity" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@iteration, 2)
    end

    it "executes test activity" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return({all_passing: true})

      result = workflow.send(:run_test_activity)

      expect(result[:all_passing]).to be true
    end
  end

  describe "#run_work_loop" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@step_name, "test-step")
      workflow.instance_variable_set(:@step_spec, {})
      workflow.instance_variable_set(:@context, {})
      workflow.instance_variable_set(:@max_iterations, 2)
      workflow.instance_variable_set(:@checkpoint_interval, 1)
      workflow.instance_variable_set(:@state, :ready)
      workflow.instance_variable_set(:@iteration, 0)
      workflow.instance_variable_set(:@paused, false)
      workflow.instance_variable_set(:@escalate_requested, false)
      workflow.instance_variable_set(:@consecutive_failures, 0)
      workflow.instance_variable_set(:@instruction_queue, [])
      allow(workflow).to receive(:cancellation_requested?).and_return(false)
      allow(workflow).to receive(:log_workflow)
    end

    it "returns failure when prompt creation fails" do
      allow(workflow).to receive(:create_initial_prompt).and_return({success: false, error: "bad"})

      result = workflow.send(:run_work_loop)

      expect(result[:success]).to be false
      expect(result[:reason]).to eq("prompt_creation_failed")
    end

    it "completes successfully when tests pass" do
      allow(workflow).to receive(:create_initial_prompt).and_return({success: true})
      allow(workflow).to receive(:run_agent_activity).and_return({success: true})
      allow(workflow).to receive(:run_test_activity).and_return({all_passing: true, partial_pass: false})

      result = workflow.send(:run_work_loop)

      expect(result[:success]).to be true
      expect(result[:iterations]).to eq(1)
    end

    it "handles failure then continues to success" do
      allow(workflow).to receive(:create_initial_prompt).and_return({success: true})
      allow(workflow).to receive(:run_agent_activity).and_return({success: true})
      allow(workflow).to receive(:run_test_activity).and_return(
        {all_passing: false, partial_pass: false},
        {all_passing: true, partial_pass: false}
      )
      allow(workflow).to receive(:handle_failure)
      allow(workflow).to receive(:prepare_next_iteration)
      allow(workflow).to receive(:record_checkpoint)

      result = workflow.send(:run_work_loop)

      expect(workflow).to have_received(:handle_failure).once
      expect(workflow).to have_received(:prepare_next_iteration).once
      expect(workflow).to have_received(:record_checkpoint).once
      expect(result[:success]).to be true
    end

    it "returns failure when max iterations exceeded" do
      workflow.instance_variable_set(:@max_iterations, 0)
      allow(workflow).to receive(:create_initial_prompt).and_return({success: true})

      result = workflow.send(:run_work_loop)

      expect(result[:success]).to be false
      expect(result[:reason]).to eq("max_iterations")
    end
  end

  describe "#execute" do
    it "returns canceled result when canceled" do
      allow(workflow).to receive(:run_work_loop).and_raise(Temporalio::Error::CanceledError.new("canceled"))

      result = workflow.execute(project_dir: "/tmp/project", step_name: "test")

      expect(result[:status]).to eq("canceled")
    end
  end
end
