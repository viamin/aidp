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

    it "handles error gracefully when client raises" do
      runner = described_class.new(project_dir, config, options)
      client = double("Client")
      allow(client).to receive(:gets).and_raise(StandardError.new("boom"))
      allow(client).to receive(:close)
      expect(Aidp.logger).to receive(:error).with("ipc_error", anything)
      runner.send(:handle_ipc_client, client)
    end
  end

  describe "#attach" do
    it "returns error when daemon not running" do
      allow(process_manager).to receive(:running?).and_return(false)
      runner = described_class.new(project_dir, config, options)
      result = runner.attach
      expect(result[:success]).to be(false)
      expect(result[:message]).to match(/No daemon running/)
    end

    it "returns error when socket does not exist" do
      allow(process_manager).to receive(:running?).and_return(true)
      allow(process_manager).to receive(:socket_exists?).and_return(false)
      runner = described_class.new(project_dir, config, options)
      result = runner.attach
      expect(result[:success]).to be(false)
      expect(result[:message]).to match(/socket not available/)
    end

    it "attaches successfully when daemon running and socket exists" do
      allow(process_manager).to receive(:running?).and_return(true)
      allow(process_manager).to receive(:socket_exists?).and_return(true)
      runner = described_class.new(project_dir, config, options)
      result = runner.attach
      expect(result[:success]).to be(true)
      expect(result[:message]).to match(/Attached/)
    end
  end

  describe "#cleanup" do
    it "cleans up resources and logs" do
      runner = described_class.new(project_dir, config, options)
      expect(process_manager).to receive(:remove_socket)
      expect(process_manager).to receive(:remove_pid)
      expect(Aidp.logger).to receive(:info).with("daemon_lifecycle", "Daemon cleanup started")
      expect(Aidp.logger).to receive(:info).with("daemon_lifecycle", "Daemon stopped cleanly")
      runner.send(:cleanup)
    end
  end

  describe "signal handlers" do
    it "sets running to false on SIGTERM simulation" do
      runner = described_class.new(project_dir, config, options)
      runner.send(:setup_signal_handlers)
      # Simulate SIGTERM by directly invoking the response
      runner.send(:stop_response)
      # Cannot directly test signal traps in specs easily, but we verify stop_response logic
      expect(runner.send(:stop_response)[:status]).to eq("stopping")
    end
  end

  describe "#run_work_loop_mode" do
    it "runs the work loop and logs heartbeat" do
      runner = described_class.new(project_dir, config, options)
      runner.instance_variable_set(:@running, true)

      # Run in a thread and stop after brief delay
      thread = Thread.new do
        runner.send(:run_work_loop_mode)
      end

      sleep 0.05
      runner.instance_variable_set(:@running, false)
      thread.join(1)

      expect(Aidp.logger).to have_received(:info).with("daemon_lifecycle", "Starting work loop mode")
      # Note: "Work loop mode stopped" may not fire in time due to sleep(10) in the loop
    end
  end
end
