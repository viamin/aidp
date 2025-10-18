# frozen_string_literal: true

RSpec.describe Aidp::Concurrency::Wait do
  let(:config) { Aidp::Concurrency.configuration }

  before do
    # Reset configuration to defaults
    Aidp::Concurrency.configuration = Aidp::Concurrency::Configuration.new
  end

  describe ".until" do
    it "returns immediately when condition is already true" do
      result = described_class.until(timeout: 1) { true }
      expect(result).to be true
    end

    it "polls until condition becomes true" do
      counter = 0
      result = described_class.until(timeout: 5, interval: 0.1) do
        counter += 1
        counter >= 3
      end

      expect(result).to be true
      expect(counter).to be >= 3
    end

    it "raises TimeoutError when timeout is exceeded" do
      expect {
        described_class.until(timeout: 0.3, interval: 0.1) { false }
      }.to raise_error(Aidp::Concurrency::TimeoutError, /Condition not met/)
    end

    it "respects custom error message" do
      expect {
        described_class.until(timeout: 0.2, message: "Custom failure message") { false }
      }.to raise_error(Aidp::Concurrency::TimeoutError, /Custom failure message/)
    end

    it "uses default configuration values" do
      config.default_timeout = 0.5
      config.default_interval = 0.1

      counter = 0
      expect {
        described_class.until {
          counter += 1
          false
        }
      }.to raise_error(Aidp::Concurrency::TimeoutError)

      expect(counter).to be >= 3 # Should have polled multiple times
    end

    it "requires a block" do
      expect {
        described_class.until(timeout: 1)
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "returns the truthy value from the condition" do
      result = described_class.until(timeout: 1) { "success" }
      expect(result).to eq("success")
    end

    it "stops checking once condition is met" do
      counter = 0
      described_class.until(timeout: 1, interval: 0.05) do
        counter += 1
        counter == 2
      end

      # Give it a bit more time to ensure it doesn't keep running
      sleep 0.15
      expect(counter).to eq(2)
    end
  end

  describe ".for_file" do
    let(:tmpfile) { "/tmp/aidp_test_#{Process.pid}_#{rand(10000)}" }

    after do
      File.delete(tmpfile) if File.exist?(tmpfile)
    end

    it "returns path when file exists immediately" do
      File.write(tmpfile, "test")
      result = described_class.for_file(tmpfile, timeout: 1)
      expect(result).to eq(tmpfile)
    end

    it "waits for file to be created" do
      Thread.new do
        sleep 0.2
        File.write(tmpfile, "delayed")
      end

      result = described_class.for_file(tmpfile, timeout: 2, interval: 0.05)
      expect(result).to eq(tmpfile)
      expect(File.exist?(tmpfile)).to be true
    end

    it "raises TimeoutError if file never appears" do
      expect {
        described_class.for_file(tmpfile, timeout: 0.3, interval: 0.05)
      }.to raise_error(Aidp::Concurrency::TimeoutError, /File not found/)
    end
  end

  describe ".for_port" do
    it "returns true when port is already open" do
      server = TCPServer.new("localhost", 0)
      port = server.addr[1]

      begin
        result = described_class.for_port("localhost", port, timeout: 1)
        expect(result).to be true
      ensure
        server.close
      end
    end

    it "waits for port to open" do
      server = nil
      port_num = rand(9876..10875)

      Thread.new do
        sleep 0.2
        server = TCPServer.new("localhost", port_num)
      end

      begin
        result = described_class.for_port("localhost", port_num, timeout: 2, interval: 0.05)
        expect(result).to be true
      ensure
        server&.close
      end
    end

    it "raises TimeoutError if port never opens" do
      port_num = rand(9876..10875)
      expect {
        described_class.for_port("localhost", port_num, timeout: 0.3, interval: 0.05)
      }.to raise_error(Aidp::Concurrency::TimeoutError, /Port.*not open/)
    end
  end

  describe ".for_process_exit" do
    it "waits for process to exit and returns status" do
      pid = spawn("sleep 0.2")

      status = described_class.for_process_exit(pid, timeout: 2, interval: 0.05)
      expect(status).to be_a(Process::Status)
      expect(status.success?).to be true
    end

    it "returns immediately if process already exited" do
      pid = spawn("exit 0")
      sleep 0.1 # Ensure process has exited

      status = described_class.for_process_exit(pid, timeout: 1, interval: 0.05)
      expect(status).to be_a(Process::Status)
      expect(status.success?).to be true
    end

    it "raises TimeoutError if process doesn't exit in time" do
      pid = spawn("sleep 10")

      begin
        expect {
          described_class.for_process_exit(pid, timeout: 0.3, interval: 0.05)
        }.to raise_error(Aidp::Concurrency::TimeoutError, /did not exit/)
      ensure
        begin
          Process.kill("TERM", pid)
        rescue
          nil
        end
        begin
          Process.waitpid(pid, Process::WNOHANG)
        rescue
          nil
        end
      end
    end
  end
end
