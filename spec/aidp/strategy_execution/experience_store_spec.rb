# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::StrategyExecution::ExperienceStore do
  let(:project_dir) { Dir.mktmpdir }
  let(:store) { described_class.new(project_dir: project_dir) }
  let(:strategy) do
    Aidp::StrategyExecution::StrategySpec.from_hash(
      name: "replayable",
      agents: {coder: "bin/coder"},
      evaluators: [{name: "tests", command: "bin/tests"}]
    )
  end

  after do
    Aidp::Database.close(project_dir)
    FileUtils.rm_rf(project_dir)
  end

  it "records replayable runs with evaluations and artifacts" do
    strategy_record = store.register_strategy(strategy)
    task = store.create_task(description: "Fix the failing spec", input_payload: {issue: 123})
    run = store.start_run(
      task_id: task[:id],
      strategy_id: strategy_record[:id],
      workflow_id: "wf-1",
      depth: 0,
      input_payload: {foo: "bar"}
    )

    store.record_evaluation(
      run_id: run[:id],
      evaluator_name: "tests",
      score: 0.9,
      passed: true,
      summary: "looks good"
    )
    store.record_artifact(run_id: run[:id], role: "agent", path: "/tmp/output.patch")
    store.complete_run(run_id: run[:id], status: "completed", output_payload: {summary: "winner"})

    bundle = store.replay_bundle(run[:id])
    details = store.run_details(run[:id])

    expect(bundle[:task][:description]).to eq("Fix the failing spec")
    expect(details[:evaluations].first[:evaluator_name]).to eq("tests")
    expect(details[:artifacts].first[:path]).to eq("/tmp/output.patch")
    expect(details[:status]).to eq("completed")
  end

  it "preserves start metadata when a run completes" do
    strategy_record = store.register_strategy(strategy)
    task = store.create_task(description: "Keep audit trail intact")
    run = store.start_run(
      task_id: task[:id],
      strategy_id: strategy_record[:id],
      workflow_id: "wf-2",
      depth: 1,
      input_payload: {},
      metadata: {workflow_type: "Aidp::Temporal::Workflows::StrategyBranchWorkflow"}
    )

    store.complete_run(
      run_id: run[:id],
      status: "completed",
      output_payload: {summary: "done"},
      metadata: {branch_key: "branch-1"}
    )

    details = store.run_details(run[:id])

    expect(details[:metadata]).to include(
      workflow_type: "Aidp::Temporal::Workflows::StrategyBranchWorkflow",
      branch_key: "branch-1"
    )
  end
end
