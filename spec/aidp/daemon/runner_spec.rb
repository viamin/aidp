# frozen_string_literal: true

require "spec_helper"
require "json"
require "fileutils"

class FakeIpcClient
  attr_reader :written

  def initialize(command)
    @command = command
    @written = +""
    @read = false
  end

  def gets
    return nil if @read

    @read = true
    "#{@command}\n"
  end

  def puts(message)
    string = message.to_s
    string = "#{string}\n" unless string.end_with?("\n")
    @written << string
  end

  def close
  end

  def response_line
    @written.lines.last.to_s.strip
  end
end

RSpec.describe Aidp::Daemon::Runner do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { double("Config") }
  let(:options) { {interval: 1} }
  let(:process_manager) do
    instance_double(
      Aidp::Daemon::ProcessManager,
      running?: process_running,
      socket_exists?: socket_exists,
      pid: 1234,
      log_file_path: "/tmp/daemon.log",
      socket_path: File.join(project_dir, ".aidp/daemon/aidp.sock"),
      write_pid: nil
    )
  end
  let(:logger) { double("Logger") }
  let(:runner) { described_class.new(project_dir, config, options, process_manager: process_manager) }

  before do
    allow(Aidp).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info).and_return("activity")
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
    allow(process_manager).to receive(:remove_socket)
    allow(process_manager).to receive(:remove_pid)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#attach" do
    context "when daemon is not running" do
      let(:process_running) { false }
      let(:socket_exists) { false }

      it "returns failure message" do
        expect(runner.attach).to include(success: false, message: /No daemon running/)
      end
    end

    context "when socket is missing" do
      let(:process_running) { true }
      let(:socket_exists) { false }

      it "returns failure about the socket" do
        expect(runner.attach).to include(success: false, message: /socket not available/)
      end
    end

    context "when daemon is running" do
      let(:process_running) { true }
      let(:socket_exists) { true }

      it "returns success with activity info" do
        expect(runner.attach).to include(success: true, pid: 1234, activity: "activity")
      end
    end
  end

  describe "#start_daemon" do
    let(:process_running) { false }
    let(:socket_exists) { true }

    it "returns failure when daemon already running" do
      allow(process_manager).to receive(:running?).and_return(true)
      expect(runner).not_to receive(:fork)
      result = runner.start_daemon
      expect(result).to include(success: false, message: /already running/)
    end

    it "starts daemon and waits for readiness" do
      allow(runner).to receive(:fork).and_yield
      allow(Process).to receive(:daemon)
      allow(runner).to receive(:run_daemon)
      allow(Process).to receive(:detach)
      allow(Aidp::Concurrency::Wait).to receive(:until).and_return(true)

      result = runner.start_daemon(mode: :work_loop)

      expect(result).to include(success: true, message: /work_loop/)
      expect(Process).to have_received(:daemon).with(true)
      expect(runner).to have_received(:run_daemon).with(:work_loop)
      expect(Aidp::Concurrency::Wait).to have_received(:until)
    end

    it "returns timeout error when daemon does not start" do
      allow(runner).to receive(:fork).and_yield
      allow(Process).to receive(:daemon)
      allow(runner).to receive(:run_daemon)
      allow(Process).to receive(:detach)
      allow(Aidp::Concurrency::Wait).to receive(:until).and_raise(Aidp::Concurrency::TimeoutError)

      result = runner.start_daemon

      expect(result).to include(success: false, message: /Failed to start daemon/)
    end
  end

  describe "#run_daemon" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    before do
      allow(runner).to receive(:setup_signal_handlers)
      allow(runner).to receive(:start_ipc_server)
    end

    it "invokes watch mode loop" do
      allow(runner).to receive(:run_watch_mode)
      runner.send(:run_daemon, :watch)
      expect(runner).to have_received(:run_watch_mode)
    end

    it "logs error for unknown mode" do
      runner.send(:run_daemon, :unknown)
      expect(logger).to have_received(:error).with("daemon_error", /Unknown mode/)
    end
  end

  describe "#setup_signal_handlers" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    it "traps TERM and INT signals" do
      allow(Signal).to receive(:trap).and_return(true)
      runner.instance_variable_set(:@running, true)

      expect(Signal).to receive(:trap).with("TERM").and_yield
      expect(Signal).to receive(:trap).with("INT").and_yield

      runner.send(:setup_signal_handlers)
      expect(runner.instance_variable_get(:@running)).to be false
    end
  end

  describe "#start_ipc_server" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    it "accepts clients while running" do
      server = instance_double(UNIXServer)
      client = instance_double("Client", gets: nil, close: nil)
      allow(UNIXServer).to receive(:new).and_return(server)
      allow(server).to receive(:accept_nonblock) do
        runner.instance_variable_set(:@running, false)
        client
      end
      allow(Thread).to receive(:new).and_yield
      allow(runner).to receive(:handle_ipc_client)

      runner.instance_variable_set(:@running, true)
      runner.send(:start_ipc_server)

      expect(UNIXServer).to have_received(:new).with(process_manager.socket_path)
      expect(runner).to have_received(:handle_ipc_client).with(client)
    end

    it "logs errors when socket fails to start" do
      allow(UNIXServer).to receive(:new).and_raise(StandardError, "boom")
      runner.send(:start_ipc_server)
      expect(logger).to have_received(:error).with("ipc_error", /Failed to start IPC server/)
    end
  end

  describe "IPC helpers" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    it "returns watch mode status when watch runner is active" do
      runner.instance_variable_set(:@watch_runner, double("WatchRunner"))
      response = runner.send(:status_response)
      expect(response[:mode]).to eq("watch")
      expect(response[:status]).to eq("running")
    end

    it "stops the runner when stop command is processed" do
      runner.instance_variable_set(:@running, true)
      expect(runner.send(:stop_response)).to eq(status: "stopping")
      expect(runner.instance_variable_get(:@running)).to be false
    end

    it "returns attach payload" do
      expect(runner.send(:attach_response)).to include(status: "attached", activity: "activity")
    end

    def ipc_client(command)
      StringIO.new("#{command}\n", "r+")
    end

    it "handles IPC commands end-to-end" do
      runner.instance_variable_set(:@watch_runner, double("Watch"))
      client = FakeIpcClient.new("status")
      runner.send(:handle_ipc_client, client)
      response = JSON.parse(client.response_line)
      expect(response["mode"]).to eq("watch")
    end

    it "returns error for unknown IPC commands" do
      client = FakeIpcClient.new("unknown")
      runner.send(:handle_ipc_client, client)
      response = JSON.parse(client.response_line)
      expect(response["error"]).to include("Unknown command")
    end

    it "handles client errors gracefully" do
      client = instance_double("Client", gets: "status\n", close: nil)
      allow(client).to receive(:puts).and_raise(IOError)
      allow(runner).to receive(:status_response).and_return({})

      runner.send(:handle_ipc_client, client)

      expect(logger).to have_received(:error).with("ipc_error", /Error handling client/)
      expect(client).to have_received(:close)
    end
  end

  describe "#cleanup" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    it "shuts down components gracefully" do
      work_loop_runner = instance_double("WorkLoopRunner", cancel: nil)
      ipc_server = instance_double("UNIXServer", close: nil)
      runner.instance_variable_set(:@work_loop_runner, work_loop_runner)
      runner.instance_variable_set(:@ipc_server, ipc_server)
      runner.send(:cleanup)
      expect(work_loop_runner).to have_received(:cancel).with(save_checkpoint: true)
      expect(ipc_server).to have_received(:close)
      expect(process_manager).to have_received(:remove_socket)
      expect(process_manager).to have_received(:remove_pid)
    end
  end

  describe "mode execution" do
    let(:process_running) { true }
    let(:socket_exists) { true }

    describe "#run_work_loop_mode" do
      it "logs heartbeats until stopped" do
        allow(runner).to receive(:sleep) do
          runner.instance_variable_set(:@running, false)
        end
        runner.instance_variable_set(:@running, true)
        runner.send(:run_work_loop_mode)
        expect(runner).to have_received(:sleep).with(10)
      end
    end

    describe "#run_watch_mode" do
      let(:watch_runner) { double("WatchRunner") }

      before do
        allow(Aidp::Watch::Runner).to receive(:new).and_return(watch_runner)
        allow(watch_runner).to receive(:run_cycle)
      end

      it "executes a watch cycle when running" do
        allow(runner).to receive(:sleep) do
          runner.instance_variable_set(:@running, false)
        end
        allow(watch_runner).to receive(:run_cycle) do
          runner.instance_variable_set(:@running, false)
        end
        runner.instance_variable_set(:@running, true)
        runner.send(:run_watch_mode)
        expect(watch_runner).to have_received(:run_cycle).once
      end

      it "continues after watch errors" do
        call_count = 0
        allow(runner).to receive(:sleep) do |duration|
          next if duration == 30

          runner.instance_variable_set(:@running, false)
        end
        allow(watch_runner).to receive(:run_cycle) do
          call_count += 1
          raise "boom" if call_count == 1
          runner.instance_variable_set(:@running, false)
        end
        runner.instance_variable_set(:@running, true)
        runner.send(:run_watch_mode)
        expect(runner).to have_received(:sleep).with(30)
        expect(watch_runner).to have_received(:run_cycle).at_least(:twice)
      end
    end
  end
end
