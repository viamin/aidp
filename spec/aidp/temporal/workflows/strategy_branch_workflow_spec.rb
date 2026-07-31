# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::StrategyBranchWorkflow do
  let(:workflow) { described_class.new }
  let(:workflow_info) { double("WorkflowInfo", workflow_id: "wf-branch", run_id: "wf-branch-run", task_queue: "aidp-workflows") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(workflow_info)
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
        {success: true, output: "implemented", summary: "agent summary"},
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

    it "fails immediately when the agent reports success false" do
      allow(workflow).to receive(:execute_activity).with(
        "start_run",
        hash_including(task_id: "task-1", strategy_id: "strategy-1")
      ).and_return({id: "run-1"})
      expect(workflow).to receive(:execute_activity).with(
        "complete_run",
        hash_including(run_id: "run-1", status: "failed", output_payload: hash_including(error: "agent failed"))
      ).once.and_return(nil)
      allow(workflow).to receive(:execute_evaluators)
      allow(workflow).to receive(:record_artifacts)

      allow(Temporalio::Workflow).to receive(:execute_activity).and_return(
        {success: false, error: "agent failed", artifacts: ["ignored.patch"]}
      )

      expect do
        workflow.execute(
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
      end.to raise_error(Aidp::StrategyExecution::CliProtocol::ProtocolError, "agent failed")

      expect(workflow).not_to have_received(:execute_evaluators)
      expect(workflow).not_to have_received(:record_artifacts)
    end
  end

  describe "#activity_options" do
    it "delegates to the class-level default activity options" do
      allow(workflow).to receive(:activity_options).and_call_original

      expect(workflow.send(:activity_options, start_to_close_timeout: 60)).to eq(
        described_class.activity_options(start_to_close_timeout: 60)
      )
    end
  end

  describe "#store_activity_options" do
    it "disables retries for non-idempotent branch-side writes" do
      start_options = workflow.send(:store_activity_options, "start_run")
      evaluation_options = workflow.send(:store_activity_options, "record_evaluation")
      artifact_options = workflow.send(:store_activity_options, "record_artifact")

      expect(start_options[:retry_policy][:maximum_attempts]).to eq(1)
      expect(evaluation_options[:retry_policy][:maximum_attempts]).to eq(1)
      expect(artifact_options[:retry_policy][:maximum_attempts]).to eq(1)
      expect(evaluation_options[:retry_policy][:initial_interval]).to eq(1)
    end

    it "keeps the default retry policy for idempotent branch store operations" do
      options = workflow.send(:store_activity_options, "complete_run")

      expect(options).to eq(described_class.activity_options(start_to_close_timeout: 60))
    end
  end

  describe "#cli_activity_options" do
    it "disables retries for side-effecting CLI invocations" do
      options = workflow.send(
        :cli_activity_options,
        start_to_close_timeout: 900,
        heartbeat_timeout: 120
      )

      expect(options[:retry_policy][:maximum_attempts]).to eq(1)
      expect(options[:retry_policy][:initial_interval]).to eq(1)
      expect(options[:start_to_close_timeout]).to eq(900)
      expect(options[:heartbeat_timeout]).to eq(120)
    end
  end

  describe "long-running CLI activity timeouts" do
    let(:strategy_input) do
      {
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
      }
    end

    it "pairs a heartbeat timeout with the raised agent and evaluator budgets" do
      allow(workflow).to receive(:execute_activity).and_return({id: "run-1"}, nil, nil)
      allow(workflow).to receive(:activity_options).and_call_original

      cli_options = []
      allow(Temporalio::Workflow).to receive(:execute_activity) do |activity_class, _input, **opts|
        cli_options << opts if activity_class == Aidp::Temporal::Activities::ExecuteCliCommandActivity
        {success: true, output: "done", passed: true}
      end

      workflow.execute(strategy_input)

      expect(cli_options.length).to eq(2) # one agent + one evaluator
      cli_options.each do |opts|
        expect(opts[:heartbeat_timeout]).to eq(120)
        expect(opts[:retry_policy][:maximum_attempts]).to eq(1)
      end
      expect(cli_options).to include(hash_including(start_to_close_timeout: 900)) # agent
      expect(cli_options).to include(hash_including(start_to_close_timeout: 300)) # evaluator
    end
  end
end
