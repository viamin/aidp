# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::ManageExperienceStoreActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:store) { instance_double(Aidp::StrategyExecution::ExperienceStore) }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Aidp::StrategyExecution::ExperienceStore).to receive(:new)
      .with(project_dir: project_dir).and_return(store)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    it "registers a normalized strategy" do
      strategy_hash = {"name" => "fanout", "agents" => {"coder" => "bin/coder"}}
      strategy_spec = instance_double(Aidp::StrategyExecution::StrategySpec)
      result = {id: 7}

      allow(Aidp::StrategyExecution::StrategySpec).to receive(:from_hash)
        .with(strategy_hash).and_return(strategy_spec)
      allow(store).to receive(:register_strategy).with(strategy_spec).and_return(result)

      returned = activity.execute(
        project_dir: project_dir,
        operation: "register_strategy",
        payload: {strategy: strategy_hash}
      )

      expect(returned).to eq(result)
    end

    it "creates tasks with the provided payload" do
      payload = {
        title: "Title",
        description: "Task body",
        input_payload: {goal: "ship"},
        context: {source: "spec"},
        source_run_id: 12
      }
      result = {id: 3}
      allow(store).to receive(:create_task).with(**payload).and_return(result)

      returned = activity.execute(project_dir: project_dir, operation: "create_task", payload: payload)

      expect(returned).to eq(result)
    end

    it "starts runs with the provided payload" do
      payload = {
        task_id: 1,
        strategy_id: 2,
        workflow_id: "wf-1",
        depth: 0,
        input_payload: {task: "data"},
        parent_run_id: 9,
        branch_key: "branch_0",
        metadata: {source: "workflow"}
      }
      result = {id: 4}
      allow(store).to receive(:start_run).with(**payload).and_return(result)

      returned = activity.execute(project_dir: project_dir, operation: "start_run", payload: payload)

      expect(returned).to eq(result)
    end

    it "completes runs with the provided payload" do
      payload = {
        run_id: 4,
        status: "completed",
        output_payload: {summary: "done"},
        metadata: {state: "merge"}
      }
      result = {id: 4, status: "completed"}
      allow(store).to receive(:complete_run).with(**payload).and_return(result)

      returned = activity.execute(project_dir: project_dir, operation: "complete_run", payload: payload)

      expect(returned).to eq(result)
    end

    it "records evaluations and returns success" do
      payload = {
        run_id: 4,
        evaluator_name: "tests",
        score: 0.9,
        passed: true,
        summary: "green",
        metadata: {attempt: 1}
      }
      allow(store).to receive(:record_evaluation).with(**payload)

      returned = activity.execute(project_dir: project_dir, operation: "record_evaluation", payload: payload)

      expect(returned).to eq(success: true)
    end

    it "records artifacts and returns success" do
      payload = {
        run_id: 4,
        role: "winner",
        path: "tmp/output.json",
        metadata: {kind: "report"}
      }
      allow(store).to receive(:record_artifact).with(**payload)

      returned = activity.execute(project_dir: project_dir, operation: "record_artifact", payload: payload)

      expect(returned).to eq(success: true)
    end

    it "loads task details" do
      allow(store).to receive(:task_details).with(5).and_return({id: 5})

      returned = activity.execute(
        project_dir: project_dir,
        operation: "task_details",
        payload: {task_id: 5}
      )

      expect(returned).to eq(id: 5)
    end

    it "loads replay bundles" do
      allow(store).to receive(:replay_bundle).with(8).and_return({run: {id: 8}})

      returned = activity.execute(
        project_dir: project_dir,
        operation: "replay_bundle",
        payload: {run_id: 8}
      )

      expect(returned).to eq(run: {id: 8})
    end

    it "loads run details" do
      allow(store).to receive(:run_details).with(11).and_return({id: 11, status: "completed"})

      returned = activity.execute(
        project_dir: project_dir,
        operation: "run_details",
        payload: {run_id: 11}
      )

      expect(returned).to eq(id: 11, status: "completed")
    end

    it "returns an error result for unknown operations" do
      returned = activity.execute(
        project_dir: project_dir,
        operation: "bogus",
        payload: {run_id: 4}
      )

      expect(returned).to eq(success: false, error: "Unknown operation: bogus")
    end

    it "defaults a missing payload to an empty hash for unknown operations" do
      returned = activity.execute(project_dir: project_dir, operation: "bogus")

      expect(returned).to eq(success: false, error: "Unknown operation: bogus")
    end
  end
end
