# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::StrategyExecutionWorkflow do
  let(:workflow) { described_class.new }
  let(:workflow_info) { double("WorkflowInfo", workflow_id: "wf-parent", run_id: "wf-parent-run", task_queue: "aidp-workflows") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(workflow_info)
  end

  describe "#execute" do
    it "fans out branches, selects the highest score, and recurses into subtasks" do
      strategy_record = {id: "strategy-1"}
      task_record = {id: "task-1", description: "Implement feature"}
      run_record = {id: "run-1"}

      allow(workflow).to receive(:register_strategy).and_return(strategy_record)
      allow(workflow).to receive(:ensure_task).and_return(task_record)
      allow(workflow).to receive(:start_run).and_return(run_record)
      allow(workflow).to receive(:complete_run)

      branch_handle_a = instance_double("Handle", result: {branch_key: "branch_0", aggregate_score: 0.3, subtasks: []})
      branch_handle_b = instance_double("Handle", result: {
        branch_key: "branch_1",
        aggregate_score: 0.9,
        subtasks: [{description: "child task"}]
      })
      child_handle = instance_double("Handle", result: {status: "completed", run_id: "child-run"})

      allow(Temporalio::Workflow).to receive(:execute_child_workflow).and_return(
        branch_handle_a,
        branch_handle_b,
        child_handle
      )

      result = workflow.execute(
        project_dir: "/tmp/project",
        strategy: {
          name: "fanout",
          fanout: 2,
          max_depth: 2,
          agents: {coder: ["bin/a", "bin/b"]}
        },
        task: {description: "Implement feature"}
      )

      expect(result[:winning_branch][:branch_key]).to eq("branch_1")
      expect(result[:merged_children].first[:run_id]).to eq("child-run")
      expect(result[:branch_count]).to eq(2)
    end

    it "creates a fresh task row for replayed inputs so lineage is preserved" do
      strategy_record = {id: "strategy-1"}
      task_record = {id: "task-new", description: "Replay me"}
      run_record = {id: "run-new"}

      allow(workflow).to receive(:register_strategy).and_return(strategy_record)
      allow(workflow).to receive(:start_run).and_return(run_record)
      allow(workflow).to receive(:complete_run)

      created_tasks = []
      allow(workflow).to receive(:execute_store) do |operation, payload|
        if operation == "create_task"
          created_tasks << payload
          task_record
        end
      end

      branch_handle = instance_double("Handle", result: {branch_key: "branch_0", aggregate_score: 0.5, subtasks: []})
      allow(Temporalio::Workflow).to receive(:execute_child_workflow).and_return(branch_handle)

      workflow.execute(
        project_dir: "/tmp/project",
        strategy: {
          name: "fanout",
          fanout: 1,
          agents: {coder: "bin/coder"}
        },
        task: {description: "Replay me", source_run_id: "run-original"}
      )

      expect(created_tasks.length).to eq(1)
      expect(created_tasks.first[:source_run_id]).to eq("run-original")
    end
  end

  describe "#activity_options" do
    it "delegates to the class-level default activity options" do
      expect(workflow.send(:activity_options, start_to_close_timeout: 60)).to eq(
        described_class.activity_options(start_to_close_timeout: 60)
      )
    end
  end
end
