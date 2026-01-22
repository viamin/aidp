# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Temporal::WorkflowClient do
  let(:connection) { instance_double(Aidp::Temporal::Connection) }
  let(:client) { described_class.new(connection: connection) }
  let(:temporal_client) { instance_double(Temporalio::Client) }

  before do
    allow(connection).to receive(:connect).and_return(temporal_client)
  end

  describe "#start_workflow" do
    let(:workflow_class) {
      Class.new {
        def self.name
          "TestWorkflow"
        end
      }
    }
    let(:input) { {key: "value"} }
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle, id: "test_workflow_123", result_run_id: "run_123") }

    before do
      allow(temporal_client).to receive(:start_workflow).and_return(workflow_handle)
    end

    it "starts a workflow and returns the handle" do
      result = client.start_workflow(workflow_class, input)

      expect(result).to eq(workflow_handle)
      expect(temporal_client).to have_received(:start_workflow).with(
        workflow_class,
        input,
        hash_including(
          id: match(/test_\d{8}_\d{6}_[a-f0-9]+/),
          task_queue: "aidp-workflows",
          execution_timeout: 86400
        )
      )
    end

    it "allows custom workflow_id" do
      client.start_workflow(workflow_class, input, workflow_id: "custom_id")

      expect(temporal_client).to have_received(:start_workflow).with(
        workflow_class,
        input,
        hash_including(id: "custom_id")
      )
    end

    it "allows custom task_queue" do
      client.start_workflow(workflow_class, input, task_queue: "custom_queue")

      expect(temporal_client).to have_received(:start_workflow).with(
        workflow_class,
        input,
        hash_including(task_queue: "custom_queue")
      )
    end
  end

  describe "#execute_workflow" do
    let(:workflow_class) {
      Class.new {
        def self.name
          "TestWorkflow"
        end
      }
    }
    let(:input) { {key: "value"} }
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle, id: "test_123", result_run_id: "run_123") }
    let(:result) { {status: "completed"} }

    before do
      allow(temporal_client).to receive(:start_workflow).and_return(workflow_handle)
      allow(workflow_handle).to receive(:result).and_return(result)
    end

    it "starts a workflow and waits for result" do
      workflow_result = client.execute_workflow(workflow_class, input)

      expect(workflow_result).to eq(result)
      expect(workflow_handle).to have_received(:result)
    end
  end

  describe "#get_workflow" do
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }

    before do
      allow(temporal_client).to receive(:workflow_handle).and_return(workflow_handle)
    end

    it "returns a workflow handle by ID" do
      result = client.get_workflow("workflow_123")

      expect(result).to eq(workflow_handle)
      expect(temporal_client).to have_received(:workflow_handle).with("workflow_123", run_id: nil)
    end

    it "accepts run_id parameter" do
      client.get_workflow("workflow_123", run_id: "run_456")

      expect(temporal_client).to have_received(:workflow_handle).with("workflow_123", run_id: "run_456")
    end
  end

  describe "#signal_workflow" do
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }

    before do
      allow(temporal_client).to receive(:workflow_handle).and_return(workflow_handle)
      allow(workflow_handle).to receive(:signal)
    end

    it "sends a signal to a workflow" do
      client.signal_workflow("workflow_123", "pause")

      expect(workflow_handle).to have_received(:signal).with("pause")
    end

    it "passes signal arguments" do
      client.signal_workflow("workflow_123", "inject_instruction", "test instruction")

      expect(workflow_handle).to have_received(:signal).with("inject_instruction", "test instruction")
    end
  end

  describe "#cancel_workflow" do
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }

    before do
      allow(temporal_client).to receive(:workflow_handle).and_return(workflow_handle)
      allow(workflow_handle).to receive(:cancel)
    end

    it "cancels a workflow" do
      client.cancel_workflow("workflow_123")

      expect(workflow_handle).to have_received(:cancel)
    end
  end

  describe "#terminate_workflow" do
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }

    before do
      allow(temporal_client).to receive(:workflow_handle).and_return(workflow_handle)
      allow(workflow_handle).to receive(:terminate)
    end

    it "terminates a workflow" do
      client.terminate_workflow("workflow_123")

      expect(workflow_handle).to have_received(:terminate).with(nil)
    end

    it "passes termination reason" do
      client.terminate_workflow("workflow_123", reason: "test reason")

      expect(workflow_handle).to have_received(:terminate).with("test reason")
    end
  end

  describe "#workflow_running?" do
    let(:workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }
    let(:workflow_description) { instance_double(Temporalio::Client::WorkflowExecution, status: status) }
    let(:status) { :running }

    before do
      allow(temporal_client).to receive(:workflow_handle).and_return(workflow_handle)
      allow(workflow_handle).to receive(:describe).and_return(workflow_description)
    end

    context "when workflow is running" do
      let(:status) { :running }

      it "returns true" do
        expect(client.workflow_running?("workflow_123")).to be true
      end
    end

    context "when workflow is completed" do
      let(:status) { :completed }

      it "returns false" do
        expect(client.workflow_running?("workflow_123")).to be false
      end
    end

    context "when workflow is not found" do
      before do
        not_found_error = Temporalio::Error::RPCError.new(
          "workflow not found",
          code: Temporalio::Error::RPCError::Code::NOT_FOUND,
          raw_grpc_status: nil
        )
        allow(workflow_handle).to receive(:describe).and_raise(not_found_error)
      end

      it "returns false" do
        expect(client.workflow_running?("workflow_123")).to be false
      end
    end
  end
end
