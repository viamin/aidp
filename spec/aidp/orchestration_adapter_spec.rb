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
end
