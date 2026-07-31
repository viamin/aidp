# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::ExecuteCliCommandActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:runner) { instance_double(Aidp::StrategyExecution::CliProtocol::Runner) }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token") }

  let(:base_input) do
    {
      project_dir: project_dir,
      command: "bin/agent",
      role: "agent",
      request: {task: {id: "task-1"}}
    }
  end

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Temporalio::Activity).to receive(:heartbeat)
    allow(Aidp::StrategyExecution::CliProtocol::Runner).to receive(:new)
      .with(project_dir: project_dir).and_return(runner)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    it "delegates to the CLI runner and returns its result" do
      allow(runner).to receive(:execute).and_return({success: true, summary: "done"})

      result = activity.execute(base_input)

      expect(runner).to have_received(:execute).with(
        command: "bin/agent",
        role: "agent",
        request: {task: {id: "task-1"}}
      )
      expect(result[:success]).to be true
      expect(result[:summary]).to eq("done")
    end

    it "defaults a missing request to an empty hash" do
      allow(runner).to receive(:execute).and_return({success: true})

      activity.execute(base_input.reject { |key| key == :request })

      expect(runner).to have_received(:execute).with(
        command: "bin/agent",
        role: "agent",
        request: {}
      )
    end

    it "sends periodic heartbeats while the CLI command runs" do
      allow(activity).to receive(:heartbeat_interval_seconds).and_return(0.01)

      heartbeats = Queue.new
      allow(Temporalio::Activity).to receive(:heartbeat) { |*details| heartbeats.push(details) }

      # Block the runner until two heartbeats arrive from the background thread,
      # proving it heartbeats concurrently with the long-running command.
      allow(runner).to receive(:execute) do
        heartbeats.pop
        heartbeats.pop
        {success: true}
      end

      result = activity.execute(base_input)

      expect(result[:success]).to be true
      expect(heartbeats).to be_empty
    end

    it "stops the heartbeat thread when the runner raises" do
      allow(activity).to receive(:heartbeat_interval_seconds).and_return(0.01)
      allow(runner).to receive(:execute)
        .and_raise(Aidp::StrategyExecution::CliProtocol::ProtocolError, "boom")

      expect { activity.execute(base_input) }.to raise_error(Aidp::StrategyExecution::CliProtocol::ProtocolError)
    end
  end
end
