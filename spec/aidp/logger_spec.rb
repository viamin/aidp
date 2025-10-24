# frozen_string_literal: true

require "spec_helper"
require "aidp/logger"
require "tmpdir"
require "json"

RSpec.describe Aidp::Logger do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { {} }
  let(:logger) { described_class.new(project_dir, config) }
  let(:info_log) { File.join(project_dir, ".aidp/logs/aidp.log") }

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
    it "logs error messages to the log file" do
      logger.error("test", "error message")
      logger.close

      expect(File.exist?(info_log)).to be true
      info_content = File.read(info_log)
      expect(info_content).to include("ERROR")
      expect(info_content).to include("error message")
    end
  end

  describe "#debug" do
    context "when level is debug" do
      let(:config) { {level: "debug"} }

      it "logs debug messages to the log file" do
        logger.debug("test", "debug message")
        logger.close

        info_content = File.read(info_log)
        expect(info_content).to include("DEBUG")
        expect(info_content).to include("debug message")
      end
    end

    context "when level is info" do
      let(:config) { {level: "info"} }

      it "does not log debug messages" do
        logger.debug("test", "debug message")
        logger.close

        if File.exist?(info_log)
          content = File.read(info_log)
          expect(content).not_to include("debug message")
        else
          expect(File.exist?(info_log)).to be false
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

  describe "log directory creation" do
    it "creates .aidp/logs directory" do
      logger
      log_dir = File.join(project_dir, ".aidp/logs")
      expect(Dir.exist?(log_dir)).to be true
    end
  end

  describe "fallback to STDERR when file creation fails" do
    let(:readonly_dir) { Dir.mktmpdir }
    let(:log_path) { File.join(readonly_dir, ".aidp/logs/aidp.log") }

    after do
      FileUtils.chmod(0o755, readonly_dir) if Dir.exist?(readonly_dir)
      FileUtils.rm_rf(readonly_dir)
    end

    it "falls back to STDERR when log file cannot be created" do
      # Create directory structure then make it readonly
      FileUtils.mkdir_p(File.dirname(log_path))
      FileUtils.chmod(0o444, File.dirname(log_path))

      # Capture stderr
      original_stderr = $stderr
      $stderr = StringIO.new

      # Capture Kernel.warn calls
      expect(Kernel).to receive(:warn).with(/Failed to create log file/)

      fallback_logger = described_class.new(readonly_dir, {})

      # Should log to stderr successfully
      fallback_logger.info("test", "fallback message")

      fallback_logger.close
      $stderr = original_stderr
    end

    it "includes structured error message in fallback warning" do
      FileUtils.mkdir_p(File.dirname(log_path))
      FileUtils.chmod(0o444, File.dirname(log_path))

      warning_message = nil
      allow(Kernel).to receive(:warn) do |msg|
        warning_message = msg
      end

      described_class.new(readonly_dir, {})

      expect(warning_message).to include("AIDP Logger")
      expect(warning_message).to include("Failed to create log file")
      expect(warning_message).to include("Falling back to STDERR")
    end
  end

  describe "redaction in metadata" do
    it "redacts secrets when formatted as key=value in message" do
      logger.info("test", "api_key=secret123 user=john")
      logger.close

      content = File.read(info_log)
      expect(content).to include("api_key=<REDACTED>")
      expect(content).not_to include("secret123")
    end

    it "does NOT currently redact plain values in metadata (known limitation)" do
      # Current implementation only redacts string values that contain pattern like "api_key=value"
      # Plain values without the key prefix are not redacted
      logger.info("test", "safe message", token: "secret123", user: "john")
      logger.close

      content = File.read(info_log)
      # This is the current behavior - metadata values are passed through redact()
      # but don't match patterns since they're just values without keys
      expect(content).to include("token=secret123") # Current behavior
      expect(content).to include("user=john")
    end

    it "redacts multiple secrets in same message" do
      logger.info("test", "token=abc123 password=def456")
      logger.close

      content = File.read(info_log)
      expect(content).to include("token=<REDACTED>")
      expect(content).to include("password=<REDACTED>")
      expect(content).not_to include("abc123")
      expect(content).not_to include("def456")
    end

    it "redacts secrets in JSON format" do
      json_logger = described_class.new(project_dir, json: true)
      json_logger.info("test", "message with token=abc123")
      json_logger.close

      content = File.read(info_log)
      # Skip logger header line and parse JSON
      json_lines = content.lines.select { |l| l.strip.start_with?("{") }
      parsed = JSON.parse(json_lines.first)
      # Message is redacted
      expect(parsed["msg"]).to include("token=<REDACTED>")
      expect(content).not_to include("abc123")
    end

    it "handles non-string metadata values safely" do
      logger.info("test", "message", count: 42, enabled: true, data: nil)
      logger.close

      content = File.read(info_log)
      expect(content).to include("count=42")
      expect(content).to include("enabled=true")
    end
  end

  describe "redaction patterns" do
    it "redacts api-key with hyphen" do
      logger.info("test", "api-key=secret456")
      logger.close

      content = File.read(info_log)
      expect(content).to include("api-key=<REDACTED>")
    end

    it "redacts apikey without separator" do
      logger.info("test", "apikey=secret789")
      logger.close

      content = File.read(info_log)
      expect(content).to include("apikey=<REDACTED>")
    end

    it "redacts secret in various formats" do
      logger.info("test", "secret: mysecret")
      logger.close

      content = File.read(info_log)
      expect(content).to include("secret=<REDACTED>")
    end

    it "redacts credentials" do
      logger.info("test", "credentials=user:pass123")
      logger.close

      content = File.read(info_log)
      expect(content).to include("credentials=<REDACTED>")
    end

    it "preserves non-secret content" do
      logger.info("test", "normal message with no secrets", id: "123", name: "test")
      logger.close

      content = File.read(info_log)
      expect(content).to include("normal message with no secrets")
      expect(content).to include("id=123")
      expect(content).to include("name=test")
    end
  end

  describe "module-level logger" do
    before do
      # Reset module-level logger
      Aidp.instance_variable_set(:@logger, nil)
    end

    after do
      Aidp.logger.close if Aidp.instance_variable_get(:@logger)
      Aidp.instance_variable_set(:@logger, nil)
    end

    it "creates default logger when not set up" do
      expect(Aidp.logger).to be_a(Aidp::Logger)
    end

    it "uses setup logger when configured" do
      Aidp.setup_logger(project_dir, level: "debug")
      expect(Aidp.logger.level).to eq(:debug)
    end

    it "provides convenience logging methods" do
      Aidp.setup_logger(project_dir)

      expect { Aidp.log_info("test", "info") }.not_to raise_error
      expect { Aidp.log_error("test", "error") }.not_to raise_error
      expect { Aidp.log_warn("test", "warn") }.not_to raise_error
      expect { Aidp.log_debug("test", "debug") }.not_to raise_error
    end
  end
end
