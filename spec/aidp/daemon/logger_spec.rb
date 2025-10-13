# frozen_string_literal: true

require "spec_helper"
require "aidp/daemon/logger"
require "tmpdir"

RSpec.describe Aidp::Daemon::DaemonLogger do
  let(:project_dir) { Dir.mktmpdir }
  let(:daemon_logger) { described_class.new(project_dir) }
  let(:log_file) { File.join(project_dir, ".aidp/logs/current.log") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#log_event" do
    it "logs structured event to file" do
      daemon_logger.log_event(:info, "test_event", "Test message", key: "value")

      expect(File.exist?(log_file)).to be true
      content = File.read(log_file)
      expect(content).to include("INFO")
      expect(content).to include("test_event")
      expect(content).to include("Test message")
      expect(content).to include("key=value")
    end

    it "includes timestamp in log" do
      daemon_logger.log_event(:info, "test", "message")
      content = File.read(log_file)
      expect(content).to match(/\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  describe "convenience methods" do
    it "#info logs INFO level event" do
      daemon_logger.info("test", "Info message")
      content = File.read(log_file)
      expect(content).to include("INFO")
      expect(content).to include("Info message")
    end

    it "#warn logs WARN level event" do
      daemon_logger.warn("test", "Warning message")
      content = File.read(log_file)
      expect(content).to include("WARN")
      expect(content).to include("Warning message")
    end

    it "#error logs ERROR level event" do
      daemon_logger.error("test", "Error message")
      content = File.read(log_file)
      expect(content).to include("ERROR")
      expect(content).to include("Error message")
    end

    it "#debug logs DEBUG level event" do
      daemon_logger.logger.level = Logger::DEBUG
      daemon_logger.debug("test", "Debug message")
      content = File.read(log_file)
      expect(content).to include("DEBUG")
      expect(content).to include("Debug message")
    end
  end

  describe "#log_iteration" do
    it "logs work loop iteration with metadata" do
      daemon_logger.log_iteration("test_step", 5, "running", extra: "data")

      content = File.read(log_file)
      expect(content).to include("work_loop_iteration")
      expect(content).to include("Iteration 5")
      expect(content).to include("test_step")
      expect(content).to include("step=test_step")
      expect(content).to include("iteration=5")
    end
  end

  describe "#log_lifecycle" do
    it "logs daemon lifecycle event" do
      daemon_logger.log_lifecycle("Daemon started", pid: 12345)

      content = File.read(log_file)
      expect(content).to include("daemon_lifecycle")
      expect(content).to include("Daemon started")
      expect(content).to include("pid=12345")
    end
  end

  describe "#log_watch" do
    it "logs watch mode event" do
      daemon_logger.log_watch("Watch cycle completed", issues: 5)

      content = File.read(log_file)
      expect(content).to include("watch_mode")
      expect(content).to include("Watch cycle completed")
      expect(content).to include("issues=5")
    end
  end

  describe "#recent_entries" do
    before do
      5.times do |i|
        daemon_logger.info("test", "Message #{i}")
      end
    end

    it "returns recent log entries" do
      entries = daemon_logger.recent_entries(count: 5)
      expect(entries.size).to eq(5)
    end

    it "parses log entries into structured format" do
      entries = daemon_logger.recent_entries(count: 1)
      entry = entries.first

      expect(entry[:level]).to eq("INFO")
      expect(entry[:event]).to eq("test")
      expect(entry[:message]).to include("Message")
    end

    it "limits number of entries returned" do
      entries = daemon_logger.recent_entries(count: 3)
      expect(entries.size).to eq(3)
    end

    it "returns most recent entries" do
      entries = daemon_logger.recent_entries(count: 2)
      expect(entries.last[:message]).to include("Message 4")
    end
  end

  describe "#activity_summary" do
    before do
      daemon_logger.info("work_loop_iteration", "Iteration 1")
      daemon_logger.info("work_loop_iteration", "Iteration 2")
      daemon_logger.warn("watch_mode", "Watch cycle")
      daemon_logger.error("daemon_error", "Error occurred")
    end

    it "returns activity summary" do
      summary = daemon_logger.activity_summary

      expect(summary[:total_events]).to eq(4)
    end

    it "groups events by type" do
      summary = daemon_logger.activity_summary

      expect(summary[:by_event_type]["work_loop_iteration"]).to eq(2)
      expect(summary[:by_event_type]["watch_mode"]).to eq(1)
      expect(summary[:by_event_type]["daemon_error"]).to eq(1)
    end

    it "groups events by level" do
      summary = daemon_logger.activity_summary

      expect(summary[:by_level]["INFO"]).to eq(2)
      expect(summary[:by_level]["WARN"]).to eq(1)
      expect(summary[:by_level]["ERROR"]).to eq(1)
    end

    it "includes recent entries" do
      summary = daemon_logger.activity_summary

      expect(summary[:recent]).to be_an(Array)
      expect(summary[:recent].size).to be <= 10
    end

    it "filters by time" do
      summary = daemon_logger.activity_summary(since: Time.now + 1)
      expect(summary[:total_events]).to eq(0)
    end
  end

  describe "log rotation" do
    it "rotates logs when size limit reached" do
      # Write enough data to trigger rotation
      large_message = "x" * 1000
      (described_class::MAX_LOG_SIZE / 1000 + 10).times do
        daemon_logger.info("test", large_message)
      end

      log_dir = File.join(project_dir, ".aidp/logs")
      log_files = Dir.glob(File.join(log_dir, "current.log*"))

      expect(log_files.size).to be > 1
    end
  end
end
