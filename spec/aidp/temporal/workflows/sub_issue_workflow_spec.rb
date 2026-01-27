# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::SubIssueWorkflow do
  let(:workflow) { described_class.new }
  let(:mock_workflow_info) { double("WorkflowInfo", workflow_id: "test-workflow", run_id: "test-run", task_queue: "test-queue") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(mock_workflow_info)
  end

  describe "#needs_decomposition?" do
    before do
      workflow.instance_variable_set(:@max_iterations, 20)
    end

    it "returns true when estimated iterations exceed max" do
      analysis = {
        result: {
          estimated_iterations: 25,
          sub_tasks: []
        }
      }

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be true
    end

    it "returns true when sub_tasks count is 3 or more" do
      analysis = {
        result: {
          estimated_iterations: 5,
          sub_tasks: [{}, {}, {}]
        }
      }

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be true
    end

    it "returns false when below thresholds" do
      analysis = {
        result: {
          estimated_iterations: 10,
          sub_tasks: [{}, {}]
        }
      }

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be false
    end

    it "handles missing result hash" do
      analysis = {}

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be false
    end

    it "handles missing estimated_iterations" do
      analysis = {
        result: {
          sub_tasks: []
        }
      }

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be false
    end

    it "handles missing sub_tasks" do
      analysis = {
        result: {
          estimated_iterations: 5
        }
      }

      result = workflow.send(:needs_decomposition?, analysis)

      expect(result).to be false
    end
  end

  describe "#build_success_result" do
    before do
      workflow.instance_variable_set(:@sub_issue_id, "test-123")
      workflow.instance_variable_set(:@depth, 2)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds result with all fields" do
      result = workflow.send(:build_success_result, {strategy: :direct})

      expect(result[:status]).to eq("completed")
      expect(result[:sub_issue_id]).to eq("test-123")
      expect(result[:depth]).to eq(2)
      expect(result[:result]).to eq({strategy: :direct})
      expect(result[:started_at]).to eq("2025-01-01T00:00:00Z")
      expect(result[:completed_at]).to be_a(String)
    end
  end

  describe "#build_error_result" do
    before do
      workflow.instance_variable_set(:@sub_issue_id, "test-456")
      workflow.instance_variable_set(:@depth, 1)
      workflow.instance_variable_set(:@state, :analyzing)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds error result with message" do
      result = workflow.send(:build_error_result, "Test error")

      expect(result[:status]).to eq("error")
      expect(result[:sub_issue_id]).to eq("test-456")
      expect(result[:depth]).to eq(1)
      expect(result[:error]).to eq("Test error")
      expect(result[:state]).to eq(:analyzing)
    end
  end

  describe "#build_canceled_result" do
    before do
      workflow.instance_variable_set(:@sub_issue_id, "test-789")
      workflow.instance_variable_set(:@depth, 0)
      workflow.instance_variable_set(:@state, :implementing)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds canceled result" do
      result = workflow.send(:build_canceled_result)

      expect(result[:status]).to eq("canceled")
      expect(result[:sub_issue_id]).to eq("test-789")
      expect(result[:depth]).to eq(0)
      expect(result[:state]).to eq(:implementing)
    end
  end

  describe "#transition_to" do
    before do
      workflow.instance_variable_set(:@state, :init)
    end

    it "changes state and logs transition" do
      workflow.send(:transition_to, :analyzing)

      expect(workflow.instance_variable_get(:@state)).to eq(:analyzing)
    end
  end

  describe "#activity_options" do
    it "delegates to class method" do
      options = workflow.send(:activity_options, start_to_close_timeout: 200)

      expect(options[:start_to_close_timeout]).to eq(200)
      expect(options).to have_key(:retry_policy)
    end
  end

  describe "#execute" do
    before do
      allow(workflow).to receive(:log_workflow)
    end

    it "returns error when max recursion depth reached" do
      result = workflow.execute(
        project_dir: "/tmp/project",
        sub_issue_id: "sub-1",
        task_description: "desc",
        depth: described_class::MAX_RECURSION_DEPTH
      )

      expect(result[:status]).to eq("error")
      expect(result[:error]).to include("Maximum recursion depth")
    end

    it "executes child workflows when decomposition needed" do
      allow(workflow).to receive(:analyze_sub_task).and_return({success: true, result: {sub_tasks: []}})
      allow(workflow).to receive(:needs_decomposition?).and_return(true)
      allow(workflow).to receive(:execute_child_workflows).and_return({strategy: :decomposed})

      result = workflow.execute(
        project_dir: "/tmp/project",
        sub_issue_id: "sub-2",
        task_description: "desc"
      )

      expect(result[:status]).to eq("completed")
      expect(result[:result][:strategy]).to eq(:decomposed)
    end

    it "executes implementation when no decomposition" do
      allow(workflow).to receive(:analyze_sub_task).and_return({success: true, result: {sub_tasks: []}})
      allow(workflow).to receive(:needs_decomposition?).and_return(false)
      allow(workflow).to receive(:execute_implementation).and_return({strategy: :direct})

      result = workflow.execute(
        project_dir: "/tmp/project",
        sub_issue_id: "sub-3",
        task_description: "desc"
      )

      expect(result[:status]).to eq("completed")
      expect(result[:result][:strategy]).to eq(:direct)
    end

    it "returns canceled when canceled error raised" do
      allow(workflow).to receive(:analyze_sub_task).and_raise(Temporalio::Error::CanceledError.new("canceled"))

      result = workflow.execute(
        project_dir: "/tmp/project",
        sub_issue_id: "sub-4",
        task_description: "desc"
      )

      expect(result[:status]).to eq("canceled")
    end
  end

  describe "#execute_child_workflows" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@sub_issue_id, "sub-5")
      workflow.instance_variable_set(:@task_description, "desc")
      workflow.instance_variable_set(:@context, {})
      workflow.instance_variable_set(:@parent_workflow_id, "parent")
      workflow.instance_variable_set(:@depth, 0)
      allow(workflow).to receive(:log_workflow)
    end

    it "aggregates child workflow results" do
      handle1 = instance_double("Handle", result: {status: "completed"})
      handle2 = instance_double("Handle", result: {status: "failed"})
      allow(workflow).to receive(:child_workflow_options).and_return({})
      allow(Temporalio::Workflow).to receive(:execute_child_workflow).and_return(handle1, handle2)

      analysis = {result: {sub_tasks: [{description: "a"}, {description: "b"}]}}

      result = workflow.send(:execute_child_workflows, analysis)

      expect(result[:child_count]).to eq(2)
      expect(result[:all_successful]).to be false
    end
  end

  describe "#execute_implementation" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@sub_issue_id, "sub-6")
      workflow.instance_variable_set(:@task_description, "desc")
      workflow.instance_variable_set(:@context, {})
      workflow.instance_variable_set(:@max_iterations, 5)
    end

    it "runs work loop child workflow" do
      handle = instance_double("Handle", result: {status: "completed"})
      allow(workflow).to receive(:child_workflow_options).and_return({})
      allow(Temporalio::Workflow).to receive(:execute_child_workflow).and_return(handle)

      result = workflow.send(:execute_implementation, {result: {}})

      expect(result[:strategy]).to eq(:direct)
      expect(result[:work_loop_result]).to eq({status: "completed"})
    end
  end
end
