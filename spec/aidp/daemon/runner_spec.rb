# frozen_string_literal: true

require "spec_helper"
require "aidp/daemon/runner"

RSpec.describe Aidp::Daemon::Runner do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { {test: true} }
  let(:options) { {interval: 0.01} }
  let(:process_manager) {
    double("ProcessManager",
      running?: false,
      pid: 1234,
      write_pid: true,
      log_file_path: File.join(project_dir, "daemon.log"),
      socket_exists?: true,
      socket_path: File.join(project_dir, "daemon.sock"),
      remove_socket: true,
      remove_pid: true)
  }

  before do
    allow(Aidp::Daemon::ProcessManager).to receive(:new).and_return(process_manager)
    allow(Aidp.logger).to receive(:info)
    allow(Aidp.logger).to receive(:error)
  end

  after { FileUtils.rm_rf(project_dir) }

  describe "#status_response" do
    it "returns running status" do
      runner = described_class.new(project_dir, config, options)
      status = runner.send(:status_response)
      expect(status[:status]).to eq("running")
    end
  end

  describe "#stop_response" do
    it "returns stopping status" do
      runner = described_class.new(project_dir, config, options)
      resp = runner.send(:stop_response)
      expect(resp[:status]).to eq("stopping")
    end
  end

  describe "#attach_response" do
    it "returns attached status" do
      runner = described_class.new(project_dir, config, options)
      resp = runner.send(:attach_response)
      expect(resp[:status]).to eq("attached")
    end
  end

  describe "daemon lifecycle" do
    it "returns already running when process manager reports running" do
      allow(process_manager).to receive(:running?).and_return(true)
      runner = described_class.new(project_dir, config, options)
      result = runner.start_daemon
      expect(result[:message]).to match(/already running/)
    end
  end

  describe "#handle_ipc_client" do
    it "responds to status command" do
      runner = described_class.new(project_dir, config, options)
      client = StringIO.new("status\n")
      allow(client).to receive(:puts)
      allow(client).to receive(:close)
      runner.send(:handle_ipc_client, client)
    end

    it "responds to stop command" do
      runner = described_class.new(project_dir, config, options)
      client = StringIO.new("stop\n")
      allow(client).to receive(:puts)
      allow(client).to receive(:close)
      runner.send(:handle_ipc_client, client)
    end

    it "responds to attach command" do
      runner = described_class.new(project_dir, config, options)
      client = StringIO.new("attach\n")
      allow(client).to receive(:puts)
      allow(client).to receive(:close)
      runner.send(:handle_ipc_client, client)
    end

    it "responds to unknown command" do
      runner = described_class.new(project_dir, config, options)
      client = StringIO.new("bogus\n")
      allow(client).to receive(:puts)
      allow(client).to receive(:close)
      runner.send(:handle_ipc_client, client)
    end
  end
end
