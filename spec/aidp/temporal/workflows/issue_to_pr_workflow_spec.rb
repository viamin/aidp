# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::IssueToPrWorkflow do
  let(:workflow) { described_class.new }
  let(:mock_workflow_info) { double("WorkflowInfo", workflow_id: "test-workflow", run_id: "test-run", task_queue: "test-queue") }

  before do
    allow(Temporalio::Workflow).to receive(:info).and_return(mock_workflow_info)
  end

  describe "#drain_injected_instructions" do
    it "returns copy of instructions and clears array" do
      workflow.instance_variable_set(:@injected_instructions, ["fix this", "update that"])

      result = workflow.send(:drain_injected_instructions)

      expect(result).to eq(["fix this", "update that"])
      expect(workflow.instance_variable_get(:@injected_instructions)).to be_empty
    end

    it "handles empty instructions" do
      workflow.instance_variable_set(:@injected_instructions, [])

      result = workflow.send(:drain_injected_instructions)

      expect(result).to eq([])
    end
  end

  describe "#activity_options" do
    it "delegates to class method with overrides" do
      options = workflow.send(:activity_options, start_to_close_timeout: 500)

      expect(options[:start_to_close_timeout]).to eq(500)
      expect(options).to have_key(:retry_policy)
    end

    it "returns defaults when no overrides" do
      options = workflow.send(:activity_options)

      expect(options[:start_to_close_timeout]).to eq(600)
      expect(options[:heartbeat_timeout]).to eq(60)
    end
  end

  describe "#build_success_result" do
    before do
      workflow.instance_variable_set(:@issue_number, 123)
      workflow.instance_variable_set(:@iteration, 10)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds success result with PR info" do
      pr_result = {
        pr_url: "https://github.com/user/repo/pull/1",
        pr_number: 1
      }

      result = workflow.send(:build_success_result, pr_result)

      expect(result[:status]).to eq("completed")
      expect(result[:issue_number]).to eq(123)
      expect(result[:pr_url]).to eq("https://github.com/user/repo/pull/1")
      expect(result[:pr_number]).to eq(1)
      expect(result[:iterations]).to eq(10)
    end
  end

  describe "#build_error_result" do
    before do
      workflow.instance_variable_set(:@issue_number, 456)
      workflow.instance_variable_set(:@state, :implementing)
      workflow.instance_variable_set(:@iteration, 5)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds error result with message" do
      result = workflow.send(:build_error_result, "Analysis failed")

      expect(result[:status]).to eq("error")
      expect(result[:issue_number]).to eq(456)
      expect(result[:error]).to eq("Analysis failed")
      expect(result[:state]).to eq(:implementing)
      expect(result[:iteration]).to eq(5)
    end
  end

  describe "#build_canceled_result" do
    before do
      workflow.instance_variable_set(:@issue_number, 789)
      workflow.instance_variable_set(:@state, :planning)
      workflow.instance_variable_set(:@iteration, 2)
      workflow.instance_variable_set(:@started_at, "2025-01-01T00:00:00Z")
    end

    it "builds canceled result" do
      result = workflow.send(:build_canceled_result)

      expect(result[:status]).to eq("canceled")
      expect(result[:issue_number]).to eq(789)
      expect(result[:state]).to eq(:planning)
      expect(result[:iteration]).to eq(2)
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

  describe "#run_analysis_phase" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@issue_number, 101)
      workflow.instance_variable_set(:@issue_url, "https://example.com/issue/101")
    end

    it "executes analyze activity" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return({success: true})

      result = workflow.send(:run_analysis_phase)

      expect(result[:success]).to be true
    end
  end

  describe "#run_planning_phase" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@issue_number, 101)
    end

    it "executes planning activity" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return({success: true})

      result = workflow.send(:run_planning_phase, {result: {}})

      expect(result[:success]).to be true
    end
  end

  describe "#run_create_pr_phase" do
    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@issue_number, 101)
    end

    it "executes create PR activity" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return({success: true, pr_url: "url"})

      result = workflow.send(:run_create_pr_phase, {result: {}, iterations: 2})

      expect(result[:success]).to be true
    end
  end

  describe "#run_implementation_loop" do
    let(:plan) { {result: {title: "Plan"}} }

    before do
      workflow.instance_variable_set(:@project_dir, "/tmp/project")
      workflow.instance_variable_set(:@issue_number, 101)
      workflow.instance_variable_set(:@max_iterations, 2)
      workflow.instance_variable_set(:@paused, false)
      workflow.instance_variable_set(:@iteration, 0)
      workflow.instance_variable_set(:@injected_instructions, [])
      allow(workflow).to receive(:log_workflow)
      allow(workflow).to receive(:cancellation_requested?).and_return(false)
    end

    it "returns success when tests pass" do
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return(
        {success: true, tests_passing: true, result: {agent_output: "ok"}}
      )

      result = workflow.send(:run_implementation_loop, plan)

      expect(result[:success]).to be true
      expect(result[:iterations]).to eq(1)
    end

    it "returns error when max iterations exceeded" do
      workflow.instance_variable_set(:@max_iterations, 0)

      result = workflow.send(:run_implementation_loop, plan)

      expect(result[:success]).to be false
      expect(result[:reason]).to eq("max_iterations_exceeded")
    end

    it "waits while paused before continuing" do
      workflow.instance_variable_set(:@paused, true)
      allow(workflow).to receive(:workflow_sleep) { workflow.instance_variable_set(:@paused, false) }
      allow(Temporalio::Workflow).to receive(:execute_activity).and_return(
        {success: true, tests_passing: true, result: {}}
      )

      result = workflow.send(:run_implementation_loop, plan)

      expect(result[:success]).to be true
    end
  end

  describe "#execute" do
    it "runs full workflow successfully" do
      allow(workflow).to receive(:run_analysis_phase).and_return({success: true, result: {}})
      allow(workflow).to receive(:run_planning_phase).and_return({success: true, result: {}})
      allow(workflow).to receive(:run_implementation_loop).and_return(
        {success: true, iterations: 2, result: {}}
      )
      allow(workflow).to receive(:run_create_pr_phase).and_return(
        {success: true, pr_url: "url", pr_number: 1}
      )

      result = workflow.execute(project_dir: "/tmp/project", issue_number: 1)

      expect(result[:status]).to eq("completed")
      expect(result[:pr_number]).to eq(1)
    end

    it "returns error when analysis fails" do
      allow(workflow).to receive(:run_analysis_phase).and_return({success: false})

      result = workflow.execute(project_dir: "/tmp/project", issue_number: 1)

      expect(result[:status]).to eq("error")
    end

    it "returns canceled when canceled" do
      allow(workflow).to receive(:run_analysis_phase).and_raise(Temporalio::Error::CanceledError.new("canceled"))

      result = workflow.execute(project_dir: "/tmp/project", issue_number: 1)

      expect(result[:status]).to eq("canceled")
    end
  end
end
