# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::StrategyExecutionWorkflow do
  let(:workflow) { described_class.new }
  let(:workflow_info) { double("WorkflowInfo", workflow_id: "wf-parent", task_queue: "aidp-workflows") }

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
  end
end
