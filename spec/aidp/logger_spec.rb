# frozen_string_literal: true

require "spec_helper"
require "aidp/logger"
require "tmpdir"
require "json"

RSpec.describe Aidp::AidpLogger do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { {} }
  let(:logger) { described_class.new(project_dir, config) }
  let(:info_log) { File.join(project_dir, ".aidp/logs/aidp.log") }
  let(:debug_log) { File.join(project_dir, ".aidp/logs/aidp_debug.log") }

  after do
    logger.close
    FileUtils.rm_rf(project_dir)
  end

  describe "log levels" do
    it "defaults to info level" do
      expect(logger.level).to eq(:info)
    end

    it "respects config level" do
      logger_with_level = described_class.new(project_dir, level: "debug")
      expect(logger_with_level.level).to eq(:debug)
      logger_with_level.close
    end

    it "respects ENV variable over config" do
      ENV["AIDP_LOG_LEVEL"] = "error"
      logger_from_env = described_class.new(project_dir, level: "debug")
      expect(logger_from_env.level).to eq(:error)
      logger_from_env.close
      ENV.delete("AIDP_LOG_LEVEL")
    end
  end

  describe "#info" do
    it "logs to info log file" do
      logger.info("test_component", "test message")
      logger.close

      expect(File.exist?(info_log)).to be true
      content = File.read(info_log)
      expect(content).to include("INFO")
      expect(content).to include("test_component")
      expect(content).to include("test message")
    end

    it "includes metadata" do
      logger.info("component", "message", key: "value", id: 123)
      logger.close

      content = File.read(info_log)
      expect(content).to include("key=value")
      expect(content).to include("id=123")
    end

    it "includes ISO-8601 timestamp" do
      logger.info("test", "message")
      logger.close

      content = File.read(info_log)
      expect(content).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
    end
  end

  describe "#error" do
    it "logs to both info and debug logs" do
      logger.error("test", "error message")
      logger.close

      expect(File.exist?(info_log)).to be true
      expect(File.exist?(debug_log)).to be true

      info_content = File.read(info_log)
      debug_content = File.read(debug_log)

      expect(info_content).to include("ERROR")
      expect(debug_content).to include("ERROR")
    end
  end

  describe "#debug" do
    context "when level is debug" do
      let(:config) { {level: "debug"} }

      it "logs to debug log only" do
        logger.debug("test", "debug message")
        logger.close

        expect(File.exist?(debug_log)).to be true
        debug_content = File.read(debug_log)
        expect(debug_content).to include("DEBUG")
        expect(debug_content).to include("debug message")
      end
    end

    context "when level is info" do
      let(:config) { {level: "info"} }

      it "does not log debug messages" do
        logger.debug("test", "debug message")
        logger.close

        if File.exist?(debug_log)
          debug_content = File.read(debug_log)
          expect(debug_content).not_to include("debug message")
        end
      end
    end
  end

  describe "JSON format" do
    let(:config) { {json: true} }

    it "outputs JSONL format when enabled" do
      logger.info("component", "message", key: "value")
      logger.close

      content = File.read(info_log)
      lines = content.strip.split("\n")
      json_line = lines.find { |l| l.start_with?("{") }
      parsed = JSON.parse(json_line)

      expect(parsed["level"]).to eq("info")
      expect(parsed["component"]).to eq("component")
      expect(parsed["msg"]).to eq("message")
      expect(parsed["key"]).to eq("value")
      expect(parsed["ts"]).to match(/\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "redaction" do
    it "redacts API keys" do
      logger.info("test", "api_key=secret123")
      logger.close

      content = File.read(info_log)
      expect(content).to include("api_key=<REDACTED>")
      expect(content).not_to include("secret123")
    end

    it "redacts tokens" do
      logger.info("test", "token: abc123def456")
      logger.close

      content = File.read(info_log)
      expect(content).to include("token=<REDACTED>")
    end

    it "redacts Bearer tokens" do
      logger.info("test", "Authorization: Bearer abc123xyz789")
      logger.close

      content = File.read(info_log)
      expect(content).to include("<REDACTED>")
      expect(content).not_to include("abc123xyz789")
    end

    it "redacts passwords" do
      logger.info("test", "password=mysecret")
      logger.close

      content = File.read(info_log)
      expect(content).to include("password=<REDACTED>")
      expect(content).not_to include("mysecret")
    end

    it "redacts GitHub tokens" do
      logger.info("test", "token ghp_abcdefghijklmnopqrstuvwxyz1234567890")
      logger.close

      content = File.read(info_log)
      expect(content).to include("<REDACTED>")
      expect(content).not_to include("ghp_abcdefghijklmnopqrstuvwxyz1234567890")
    end

    it "redacts AWS keys" do
      logger.info("test", "AWS key AKIAIOSFODNN7EXAMPLE")
      logger.close

      content = File.read(info_log)
      expect(content).to include("<REDACTED>")
      expect(content).not_to include("AKIAIOSFODNN7EXAMPLE")
    end
  end

  describe "log rotation" do
    let(:config) { {max_size_mb: 0.001, max_backups: 3} } # 1KB max

    it "rotates logs when size limit reached" do
      # Write enough data to trigger rotation
      200.times do |i|
        logger.info("test", "message #{i} with lots of text to fill up space")
      end
      logger.close

      log_files = Dir.glob(File.join(project_dir, ".aidp/logs/aidp.log*"))
      expect(log_files.size).to be > 1
    end
  end

  describe "migration from old location" do
    let(:old_debug_dir) { File.join(project_dir, ".aidp/debug_logs") }
    let(:old_debug_log) { File.join(old_debug_dir, "aidp_debug.log") }

    before do
      FileUtils.mkdir_p(old_debug_dir)
      File.write(old_debug_log, "Old debug log content\n")
    end

    it "migrates old debug log to new location" do
      logger # Initialize logger (triggers migration)
      logger.close

      expect(File.exist?(debug_log)).to be true
      expect(File.exist?(old_debug_log)).to be false

      content = File.read(debug_log)
      expect(content).to include("Old debug log content")
    end

    it "logs migration notice" do
      logger
      logger.close

      content = File.read(info_log)
      expect(content).to include("migration")
      expect(content).to include("Logs migrated")
    end

    it "does not migrate if new log already exists" do
      FileUtils.mkdir_p(File.dirname(debug_log))
      File.write(debug_log, "New debug log\n")

      logger
      logger.close

      content = File.read(debug_log)
      expect(content).not_to include("Old debug log content")
      expect(File.exist?(old_debug_log)).to be true
    end
  end

  describe "log directory creation" do
    it "creates .aidp/logs directory" do
      logger
      log_dir = File.join(project_dir, ".aidp/logs")
      expect(Dir.exist?(log_dir)).to be true
    end
  end
end
