# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/aidp/orchestration_adapter"

RSpec.describe Aidp::OrchestrationAdapter do
  let(:project_dir) { Dir.mktmpdir }
  let(:adapter) { described_class.new(project_dir: project_dir) }

  before do
    # Reset Temporal configuration cache to avoid test pollution
    Aidp::Temporal.reset! if defined?(Aidp::Temporal)
  end

  after do
    Aidp::Temporal.reset! if defined?(Aidp::Temporal)
    FileUtils.rm_rf(project_dir)
  end

  describe "#temporal_enabled?" do
    context "when Temporal is not configured" do
      it "returns false" do
        expect(adapter.temporal_enabled?).to be false
      end
    end

    context "when Temporal is configured" do
      before do
        config_dir = File.join(project_dir, ".aidp")
        FileUtils.mkdir_p(config_dir)
        File.write(File.join(config_dir, "aidp.yml"), <<~YAML)
          temporal:
            enabled: true
            target_host: "localhost:7233"
        YAML
      end

      it "returns true" do
        expect(adapter.temporal_enabled?).to be true
      end
    end

    context "when Temporal is explicitly disabled" do
      before do
        config_dir = File.join(project_dir, ".aidp")
        FileUtils.mkdir_p(config_dir)
        File.write(File.join(config_dir, "aidp.yml"), <<~YAML)
          temporal:
            enabled: false
        YAML
      end

      it "returns false" do
        expect(adapter.temporal_enabled?).to be false
      end
    end
  end

  describe "#start_issue_workflow" do
    context "when Temporal is disabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(false)
      end

      it "starts a legacy workflow" do
        allow(adapter).to receive(:start_legacy_issue_workflow).and_return(
          type: :legacy,
          job_id: "test_job_123",
          issue_number: 123,
          status: "started"
        )

        result = adapter.start_issue_workflow(123)

        expect(result[:type]).to eq(:legacy)
        expect(result[:issue_number]).to eq(123)
        expect(adapter).to have_received(:start_legacy_issue_workflow).with(123, {})
      end
    end

    context "when Temporal is enabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(true)
      end

      it "starts a Temporal workflow" do
        allow(adapter).to receive(:start_temporal_issue_workflow).and_return(
          type: :temporal,
          workflow_id: "workflow_123",
          issue_number: 123,
          status: "started"
        )

        result = adapter.start_issue_workflow(123)

        expect(result[:type]).to eq(:temporal)
        expect(result[:issue_number]).to eq(123)
        expect(adapter).to have_received(:start_temporal_issue_workflow).with(123, {})
      end
    end
  end

  describe "#start_work_loop" do
    let(:step_name) { "test_step" }
    let(:step_spec) { {description: "Test step"} }
    let(:context) { {key: "value"} }

    context "when Temporal is disabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(false)
      end

      it "starts a legacy work loop" do
        allow(adapter).to receive(:start_legacy_work_loop).and_return(
          type: :legacy,
          job_id: "test_job_123",
          step_name: step_name,
          status: "started"
        )

        result = adapter.start_work_loop(step_name, step_spec, context)

        expect(result[:type]).to eq(:legacy)
        expect(result[:step_name]).to eq(step_name)
      end
    end

    context "when Temporal is enabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(true)
      end

      it "starts a Temporal work loop workflow" do
        allow(adapter).to receive(:start_temporal_work_loop).and_return(
          type: :temporal,
          workflow_id: "workflow_123",
          step_name: step_name,
          status: "started"
        )

        result = adapter.start_work_loop(step_name, step_spec, context)

        expect(result[:type]).to eq(:temporal)
        expect(result[:step_name]).to eq(step_name)
      end
    end
  end

  describe "#workflow_status" do
    context "when Temporal is disabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(false)
      end

      it "returns legacy job status" do
        allow(adapter).to receive(:legacy_job_status).and_return(
          type: :legacy,
          job_id: "test_job",
          status: "running"
        )

        result = adapter.workflow_status("test_job")

        expect(result[:type]).to eq(:legacy)
        expect(result[:status]).to eq("running")
      end
    end
  end

  describe "#cancel_workflow" do
    context "when Temporal is disabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(false)
      end

      it "cancels legacy job" do
        allow(adapter).to receive(:cancel_legacy_job).and_return(
          type: :legacy,
          job_id: "test_job",
          status: "canceled"
        )

        result = adapter.cancel_workflow("test_job")

        expect(result[:type]).to eq(:legacy)
        expect(result[:status]).to eq("canceled")
      end
    end
  end

  describe "#list_workflows" do
    context "when Temporal is disabled" do
      before do
        allow(adapter).to receive(:temporal_enabled?).and_return(false)
      end

      it "lists legacy jobs" do
        allow(adapter).to receive(:list_legacy_jobs).and_return([
          {type: :legacy, job_id: "job1", status: "running"},
          {type: :legacy, job_id: "job2", status: "completed"}
        ])

        result = adapter.list_workflows

        expect(result.length).to eq(2)
        expect(result.first[:type]).to eq(:legacy)
      end
    end
  end

  describe "temporal implementations" do
    let(:handle) { instance_double("Handle", id: "workflow-1") }

    before do
      allow(adapter).to receive(:temporal_enabled?).and_return(true)
    end

    it "starts temporal issue workflow with options" do
      allow(Aidp::Temporal).to receive(:start_workflow).and_return(handle)

      result = adapter.send(:start_temporal_issue_workflow, 123, {
        max_iterations: 10,
        workflow_id: "wf-123",
        task_queue: "queue-1"
      })

      expect(result[:type]).to eq(:temporal)
      expect(result[:workflow_id]).to eq("workflow-1")
      expect(Aidp::Temporal).to have_received(:start_workflow).with(
        Aidp::Temporal::Workflows::IssueToPrWorkflow,
        hash_including(issue_number: 123, max_iterations: 10),
        project_dir: project_dir,
        workflow_id: "wf-123",
        task_queue: "queue-1"
      )
    end

    it "starts temporal work loop with options" do
      allow(Aidp::Temporal).to receive(:start_workflow).and_return(handle)

      result = adapter.send(:start_temporal_work_loop, "step", {}, {}, {
        workflow_id: "wf-456"
      })

      expect(result[:type]).to eq(:temporal)
      expect(result[:workflow_id]).to eq("workflow-1")
    end

    it "returns not_found when workflow status is missing" do
      error = Temporalio::Error::RPCError.new(
        "not found",
        code: Temporalio::Error::RPCError::Code::NOT_FOUND,
        raw_grpc_status: double("grpc")
      )
      allow(Aidp::Temporal).to receive(:workflow_status).and_raise(error)

      result = adapter.send(:temporal_workflow_status, "missing")

      expect(result[:status]).to eq("not_found")
    end

    it "returns temporal workflow status" do
      desc = double(
        status: :running,
        workflow_type: "IssueToPrWorkflow",
        start_time: Time.now,
        close_time: nil
      )
      allow(Aidp::Temporal).to receive(:workflow_status).and_return(desc)

      result = adapter.send(:temporal_workflow_status, "wf-1")

      expect(result[:status]).to eq("running")
      expect(result[:workflow_type]).to eq("IssueToPrWorkflow")
    end

    it "cancels temporal workflow" do
      allow(Aidp::Temporal).to receive(:cancel_workflow)

      result = adapter.send(:cancel_temporal_workflow, "wf-1")

      expect(result[:status]).to eq("canceled")
      expect(Aidp::Temporal).to have_received(:cancel_workflow).with("wf-1", project_dir: project_dir)
    end

    it "lists temporal workflows" do
      client = instance_double("Client", list_workflows: [
        double(id: "wf-1", workflow_type: "IssueToPrWorkflow", status: :running, start_time: Time.now)
      ])
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      result = adapter.send(:list_temporal_workflows)

      expect(result.length).to eq(1)
      expect(result.first[:type]).to eq(:temporal)
    end

    it "returns empty list on temporal list failure" do
      client = instance_double("Client")
      allow(client).to receive(:list_workflows).and_raise(StandardError.new("boom"))
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)
      allow(Aidp).to receive(:log_error)

      result = adapter.send(:list_temporal_workflows)

      expect(result).to eq([])
      expect(Aidp).to have_received(:log_error).with("orchestration_adapter", "list_temporal_failed", error: "boom")
    end
  end

  describe "legacy implementations" do
    let(:runner) { instance_double(Aidp::Jobs::BackgroundRunner) }

    before do
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(runner)
    end

    it "starts legacy issue workflow" do
      allow(runner).to receive(:start).and_return("job-1")

      result = adapter.send(:start_legacy_issue_workflow, 111, {})

      expect(result[:type]).to eq(:legacy)
      expect(result[:job_id]).to eq("job-1")
    end

    it "starts legacy work loop" do
      allow(runner).to receive(:start).and_return("job-2")

      result = adapter.send(:start_legacy_work_loop, "step", {}, {}, {})

      expect(result[:type]).to eq(:legacy)
      expect(result[:job_id]).to eq("job-2")
    end

    it "returns legacy status when available" do
      allow(runner).to receive(:job_status).and_return({status: "running", running: true})

      result = adapter.send(:legacy_job_status, "job-3")

      expect(result[:status]).to eq("running")
    end

    it "returns not_found when legacy job missing" do
      allow(runner).to receive(:job_status).and_return(nil)

      result = adapter.send(:legacy_job_status, "job-4")

      expect(result[:status]).to eq("not_found")
    end

    it "cancels legacy job" do
      allow(runner).to receive(:stop_job).and_return({success: true, message: "stopped"})

      result = adapter.send(:cancel_legacy_job, "job-5")

      expect(result[:status]).to eq("canceled")
      expect(result[:message]).to eq("stopped")
    end
  end
end
