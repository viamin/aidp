# frozen_string_literal: true

require "spec_helper"
require "aidp/daemon/process_manager"
require "tmpdir"

RSpec.describe Aidp::Daemon::ProcessManager do
  let(:project_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(project_dir) }
  let(:pid_file) { File.join(project_dir, ".aidp/daemon/aidp.pid") }
  let(:socket_file) { File.join(project_dir, ".aidp/daemon/aidp.sock") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#running?" do
    context "when no PID file exists" do
      it "returns false" do
        expect(manager.running?).to be false
      end
    end

    context "when PID file exists with running process" do
      before do
        manager.write_pid(Process.pid)
      end

      it "returns true" do
        expect(manager.running?).to be true
      end
    end

    context "when PID file exists with non-existent process" do
      before do
        manager.write_pid(999999) # Non-existent PID
      end

      it "returns false" do
        expect(manager.running?).to be false
      end

      it "cleans up stale files" do
        manager.running?
        expect(File.exist?(pid_file)).to be false
      end
    end
  end

  describe "#pid" do
    context "when daemon is not running" do
      it "returns nil" do
        expect(manager.pid).to be_nil
      end
    end

    context "when daemon is running" do
      before do
        manager.write_pid(12345)
        allow(manager).to receive(:running?).and_return(true)
      end

      it "returns the PID" do
        expect(manager.pid).to eq(12345)
      end
    end
  end

  describe "#status" do
    context "when daemon is not running" do
      it "returns not running status" do
        status = manager.status
        expect(status[:running]).to be false
        expect(status[:pid]).to be_nil
      end
    end

    context "when daemon is running" do
      before do
        manager.write_pid(Process.pid)
        FileUtils.touch(socket_file)
      end

      it "returns running status" do
        status = manager.status
        expect(status[:running]).to be true
        expect(status[:pid]).to eq(Process.pid)
        expect(status[:socket]).to be true
      end
    end
  end

  describe "#write_pid" do
    it "creates PID file with process ID" do
      manager.write_pid(12345)
      expect(File.exist?(pid_file)).to be true
      expect(File.read(pid_file)).to eq("12345")
    end

    it "uses current process if no PID provided" do
      manager.write_pid
      expect(File.read(pid_file)).to eq(Process.pid.to_s)
    end
  end

  describe "#remove_pid" do
    before do
      manager.write_pid(12345)
    end

    it "removes PID file" do
      manager.remove_pid
      expect(File.exist?(pid_file)).to be false
    end

    it "doesn't error if file doesn't exist" do
      manager.remove_pid
      expect { manager.remove_pid }.not_to raise_error
    end
  end

  describe "#stop" do
    context "when daemon is not running" do
      it "returns failure message" do
        result = manager.stop
        expect(result[:success]).to be false
        expect(result[:message]).to include("not running")
      end
    end

    context "when daemon is running" do
      let(:daemon_pid) do
        fork do
          loop { sleep 0.1 }
        end
      end

      before do
        manager.write_pid(daemon_pid)
      end

      after do
        begin
          Process.kill("KILL", daemon_pid)
        rescue
          nil
        end
        begin
          Process.wait(daemon_pid)
        rescue
          nil
        end
      end

      it "stops daemon gracefully" do
        result = manager.stop(timeout: 2)
        expect(result[:success]).to be true
        expect(result[:message]).to match(/stopped|killed/)
      end

      it "cleans up files after stop" do
        manager.stop(timeout: 2)
        expect(File.exist?(pid_file)).to be false
      end
    end
  end

  describe "#socket_path" do
    it "returns socket file path" do
      expect(manager.socket_path).to eq(socket_file)
    end
  end

  describe "#socket_exists?" do
    it "returns false when socket doesn't exist" do
      expect(manager.socket_exists?).to be false
    end

    it "returns true when socket exists" do
      FileUtils.mkdir_p(File.dirname(socket_file))
      FileUtils.touch(socket_file)
      expect(manager.socket_exists?).to be true
    end
  end

  describe "#remove_socket" do
    before do
      FileUtils.mkdir_p(File.dirname(socket_file))
      FileUtils.touch(socket_file)
    end

    it "removes socket file" do
      manager.remove_socket
      expect(File.exist?(socket_file)).to be false
    end
  end

  describe "#log_file_path" do
    it "returns log file path" do
      expected_path = File.join(project_dir, ".aidp/daemon/daemon.log")
      expect(manager.log_file_path).to eq(expected_path)
    end
  end
end
