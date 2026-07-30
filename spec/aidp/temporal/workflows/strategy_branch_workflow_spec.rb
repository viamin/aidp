# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::StrategyBranchWorkflow do
  let(:workflow) { described_class.new }
  let(:workflow_info) { double("WorkflowInfo", workflow_id: "wf-branch", run_id: "wf-branch-run", task_queue: "aidp-workflows") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(workflow_info)
    allow(workflow).to receive(:activity_options).and_return({})
  end

  describe "#execute" do
    it "uses pass/fail-only evaluator results in the aggregate score" do
      allow(workflow).to receive(:execute_activity).with(
        "start_run",
        hash_including(task_id: "task-1", strategy_id: "strategy-1")
      ).and_return({id: "run-1"})
      allow(workflow).to receive(:execute_activity).with(
        "record_evaluation",
        hash_including(run_id: "run-1", evaluator_name: "tests", passed: true, score: nil)
      ).and_return(nil)
      allow(workflow).to receive(:execute_activity).with(
        "complete_run",
        hash_including(run_id: "run-1", status: "completed")
      ).and_return(nil)

      allow(Temporalio::Workflow).to receive(:execute_activity).and_return(
        {output: "implemented", summary: "agent summary"},
        {passed: true, summary: "tests passed"}
      )

      result = workflow.execute(
        project_dir: "/tmp/project",
        task: {id: "task-1", description: "Implement feature"},
        task_id: "task-1",
        strategy: {
          name: "fanout",
          fanout: 1,
          max_depth: 1,
          agents: {coder: ["bin/a"]},
          evaluators: [{name: "tests", command: "bin/tests"}]
        },
        strategy_id: "strategy-1",
        branch: {key: "branch-1", name: "Branch 1", command: "bin/a"}
      )

      expect(result[:aggregate_score]).to eq(1.1)
      expect(result[:evaluations]).to include(hash_including(name: "tests", passed: true))
    end
  end
end
