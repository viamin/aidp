# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/temporal/worker"

RSpec.describe Aidp::Temporal::Worker do
  let(:connection) { instance_double(Aidp::Temporal::Connection) }
  let(:mock_client) { instance_double("Temporalio::Client") }
  let(:mock_temporal_worker) { instance_double("Temporalio::Worker") }

  before do
    allow(connection).to receive(:connect).and_return(mock_client)
    allow(Temporalio::Worker).to receive(:new).and_return(mock_temporal_worker)
  end

  describe "#initialize" do
    it "accepts connection and config" do
      worker = described_class.new(connection: connection, config: {task_queue: "test-queue"})

      expect(worker.connection).to eq(connection)
      expect(worker.task_queue).to eq("test-queue")
    end

    it "uses default task queue when not specified" do
      worker = described_class.new(connection: connection)

      expect(worker.task_queue).to eq("aidp-workflows")
    end

    it "normalizes config with string keys" do
      worker = described_class.new(connection: connection, config: {"task_queue" => "string-queue"})

      expect(worker.task_queue).to eq("string-queue")
    end
  end

  describe "#register_workflows" do
    let(:worker) { described_class.new(connection: connection) }

    it "registers workflow classes" do
      workflow_class = Class.new

      result = worker.register_workflows(workflow_class)

      expect(result).to eq(worker)
    end

    it "allows chaining" do
      workflow1 = Class.new
      workflow2 = Class.new

      worker.register_workflows(workflow1).register_workflows(workflow2)

      # No error means success
    end
  end

  describe "#register_activities" do
    let(:worker) { described_class.new(connection: connection) }

    it "registers activity classes" do
      activity_class = Class.new

      result = worker.register_activities(activity_class)

      expect(result).to eq(worker)
    end
  end

  describe "#running?" do
    let(:worker) { described_class.new(connection: connection) }

    it "returns false initially" do
      expect(worker.running?).to be false
    end
  end

  describe "#shutdown_requested?" do
    let(:worker) { described_class.new(connection: connection) }

    it "returns false initially" do
      expect(worker.shutdown_requested?).to be false
    end
  end

  describe "#shutdown" do
    let(:worker) { described_class.new(connection: connection) }

    it "does nothing when not running" do
      expect { worker.shutdown }.not_to raise_error
    end
  end

  describe "#run" do
    let(:worker) { described_class.new(connection: connection, config: {task_queue: "test"}) }

    it "creates worker with correct options" do
      allow(mock_temporal_worker).to receive(:run)

      worker.register_workflows(Class.new)
      worker.register_activities(Class.new)

      expect(Temporalio::Worker).to receive(:new).with(
        hash_including(
          client: mock_client,
          task_queue: "test"
        )
      ).and_return(mock_temporal_worker)

      worker.run
    end

    it "sets running state while executing" do
      allow(mock_temporal_worker).to receive(:run) do
        expect(worker.running?).to be true
      end

      worker.run

      expect(worker.running?).to be false
    end

    it "re-raises errors" do
      allow(mock_temporal_worker).to receive(:run).and_raise(StandardError.new("test error"))

      expect { worker.run }.to raise_error(StandardError, "test error")
    end
  end
end
