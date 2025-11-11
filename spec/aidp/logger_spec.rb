# frozen_string_literal: true

require "spec_helper"
require "aidp/logger"
require "tmpdir"
require "json"
require "pathname"

RSpec.describe Aidp::Logger do
  let(:project_dir) { Dir.mktmpdir }
  let(:config) { {} }
  let(:logger) { described_class.new(project_dir, config) }
  let(:log_relative_path) do
    value = ENV["AIDP_LOG_FILE"].to_s.strip
    value.empty? ? ".aidp/logs/aidp.log" : value
  end
  let(:info_log) do
    path = log_relative_path
    Pathname.new(path).absolute? ? path : File.join(project_dir, path)
  end

  around do |example|
    original = ENV["AIDP_LOG_FILE"]
    ENV.delete("AIDP_LOG_FILE")
    example.run
  ensure
    if original
      ENV["AIDP_LOG_FILE"] = original
    else
      ENV.delete("AIDP_LOG_FILE")
    end
  end

  after do
    logger.close
    FileUtils.rm_rf(project_dir)
  end

  describe "log levels" do
    it "defaults to info level" do
      # Clear DEBUG env var for this test
      original_debug = ENV["DEBUG"]
      ENV.delete("DEBUG")
      ENV.delete("AIDP_DEBUG")
      clean_logger = described_class.new(project_dir)
      expect(clean_logger.level).to eq(:info)
      clean_logger.close
    ensure
      ENV["DEBUG"] = original_debug if original_debug
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

    it "treats DEBUG=1 as debug level when no explicit level provided" do
      ENV["DEBUG"] = "1"
      logger_from_debug = described_class.new(project_dir)
      expect(logger_from_debug.level).to eq(:debug)
      logger_from_debug.close
    ensure
      ENV.delete("DEBUG")
    end

    it "treats AIDP_DEBUG=1 as debug level when no explicit level provided" do
      ENV["AIDP_DEBUG"] = "1"
      logger_from_aidp_debug = described_class.new(project_dir)
      expect(logger_from_aidp_debug.level).to eq(:debug)
      logger_from_aidp_debug.close
    ensure
      ENV.delete("AIDP_DEBUG")
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

  describe "custom log file path" do
    it "uses AIDP_LOG_FILE environment variable when set" do
      original = ENV["AIDP_LOG_FILE"]
      ENV["AIDP_LOG_FILE"] = "aidp.env.log"

      env_logger = described_class.new(project_dir)
      env_logger.info("test", "env path")
      env_logger.close

      expect(File.exist?(File.join(project_dir, "aidp.env.log"))).to be true
    ensure
      ENV["AIDP_LOG_FILE"] = original
      FileUtils.rm_f(File.join(project_dir, "aidp.env.log"))
    end

    it "uses file path from config when provided" do
      relative_path = "custom/aidp.config.log"
      config_logger = described_class.new(project_dir, file: relative_path)
      config_logger.info("test", "config path")
      config_logger.close

      expect(File.exist?(File.join(project_dir, relative_path))).to be true
    ensure
      FileUtils.rm_rf(File.join(project_dir, "custom"))
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

  describe "comprehensive JSON logging format testing" do
    let(:json_config) { {json: true, level: "debug"} }
    let(:json_logger) { described_class.new(project_dir, json_config) }

    after do
      json_logger&.close
    end

    describe "JSON format structure" do
      it "produces valid JSON with all required fields" do
        json_logger.info("test_component", "test message", user_id: 123, action: "login")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        expect(json_lines).not_to be_empty

        parsed = JSON.parse(json_lines.first)
        expect(parsed["ts"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
        expect(parsed["level"]).to eq("info")
        expect(parsed["component"]).to eq("test_component")
        expect(parsed["msg"]).to eq("test message")
        expect(parsed["user_id"]).to eq(123)
        expect(parsed["action"]).to eq("login")
      end

      it "handles all log levels in JSON format" do
        json_logger.debug("comp", "debug msg", level: "debug")
        json_logger.info("comp", "info msg", level: "info")
        json_logger.warn("comp", "warn msg", level: "warn")
        json_logger.error("comp", "error msg", level: "error")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        expect(json_lines.size).to eq(4)

        levels = json_lines.map { |line| JSON.parse(line)["level"] }
        expect(levels).to eq(["debug", "info", "warn", "error"])
      end

      it "properly formats timestamps in ISO8601 UTC format" do
        freeze_time = Time.parse("2024-10-24T15:30:45.123Z")
        allow(Time).to receive(:now).and_return(freeze_time)

        json_logger.info("test", "timestamp test")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["ts"]).to eq("2024-10-24T15:30:45.123Z")
      end
    end

    describe "JSON metadata handling" do
      it "includes complex metadata structures" do
        metadata = {
          string_val: "text",
          integer_val: 42,
          float_val: 3.14,
          boolean_val: true,
          nil_val: nil,
          array_val: [1, 2, "three"],
          hash_val: {nested: "value", count: 5}
        }

        json_logger.info("test", "complex metadata", **metadata)
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["string_val"]).to eq("text")
        expect(parsed["integer_val"]).to eq(42)
        expect(parsed["float_val"]).to eq(3.14)
        expect(parsed["boolean_val"]).to eq(true)
        expect(parsed["nil_val"]).to be_nil
        expect(parsed["array_val"]).to eq([1, 2, "three"])
        expect(parsed["hash_val"]).to eq({"nested" => "value", "count" => 5})
      end

      it "handles metadata with special characters and unicode" do
        json_logger.info("test", "unicode test",
          special_chars: "!@#$%^&*()",
          unicode: "Hello 世界 🌍",
          quotes: 'single "double" quotes',
          newlines: "line1\nline2\ttab")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["special_chars"]).to eq("!@#$%^&*()")
        expect(parsed["unicode"]).to eq("Hello 世界 🌍")
        expect(parsed["quotes"]).to eq('single "double" quotes')
        expect(parsed["newlines"]).to eq("line1\nline2\ttab")
      end

      it "handles empty and large metadata gracefully" do
        # Empty metadata
        json_logger.info("test", "empty metadata")

        # Large metadata
        large_metadata = {}
        50.times { |i| large_metadata["key_#{i}"] = "value_#{i}" }
        json_logger.info("test", "large metadata", **large_metadata)
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        expect(json_lines.size).to eq(2)

        # First log (empty metadata)
        parsed1 = JSON.parse(json_lines.first)
        expect(parsed1.keys).to contain_exactly("ts", "level", "component", "msg")

        # Second log (large metadata)
        parsed2 = JSON.parse(json_lines.last)
        expect(parsed2.keys.size).to eq(54) # 4 standard + 50 metadata
        expect(parsed2["key_25"]).to eq("value_25")
      end
    end

    describe "JSON redaction functionality" do
      it "redacts secrets in message field" do
        json_logger.info("auth", "User login with api_key=secret123 and token=abc456", user: "john")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["msg"]).to include("api_key=<REDACTED>")
        expect(parsed["msg"]).to include("token=<REDACTED>")
        expect(parsed["msg"]).not_to include("secret123")
        expect(parsed["msg"]).not_to include("abc456")
        expect(parsed["user"]).to eq("john")
      end

      it "redacts secrets in metadata string values" do
        json_logger.info("auth", "Authentication attempt",
          request_body: "password=mysecret&username=admin",
          auth_header: "Bearer jwt_token_12345",
          api_config: "api-key: secret789")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["request_body"]).to include("password=<REDACTED>")
        expect(parsed["request_body"]).not_to include("mysecret")
        expect(parsed["auth_header"]).to eq("<REDACTED>")
        expect(parsed["api_config"]).to include("api-key=<REDACTED>")
        expect(parsed["api_config"]).not_to include("secret789")
      end

      it "preserves non-secret metadata while redacting secrets" do
        json_logger.info("mixed", "Mixed content",
          safe_data: "public information",
          user_count: 42,
          credentials_string: "credentials=user:password123",  # String with pattern
          config_file: "host=localhost password=secret123",  # password= pattern
          public_key: "ssh-rsa AAAAB3NzaC1yc2E...",
          private_info: "secret=hidden_value")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        # Preserved
        expect(parsed["safe_data"]).to eq("public information")
        expect(parsed["user_count"]).to eq(42)
        expect(parsed["public_key"]).to eq("ssh-rsa AAAAB3NzaC1yc2E...")

        # Redacted (only strings with patterns are redacted)
        expect(parsed["credentials_string"]).to include("credentials=<REDACTED>")
        expect(parsed["config_file"]).to include("password=<REDACTED>")
        expect(parsed["private_info"]).to include("secret=<REDACTED>")
        expect(parsed["private_info"]).not_to include("hidden_value")
      end

      it "handles redaction in string metadata correctly" do
        json_logger.info("security", "Multiple secrets in message: api_key=key0 token=token0",
          config: "api_key=key1 token=token1 password=pass1",
          auth_header: "Bearer token_xyz",
          db_config: "credentials=user:secret123",
          safe_data: "normal data without secrets")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        # Message redaction
        expect(parsed["msg"]).to include("api_key=<REDACTED>")
        expect(parsed["msg"]).to include("token=<REDACTED>")
        expect(parsed["msg"]).not_to include("key0")
        expect(parsed["msg"]).not_to include("token0")

        # String metadata redaction
        expect(parsed["config"]).to include("api_key=<REDACTED>")
        expect(parsed["config"]).to include("token=<REDACTED>")
        expect(parsed["config"]).to include("password=<REDACTED>")
        expect(parsed["auth_header"]).to eq("<REDACTED>")
        expect(parsed["db_config"]).to include("credentials=<REDACTED>")
        expect(parsed["safe_data"]).to eq("normal data without secrets")
      end
    end

    describe "JSON error cases and edge cases" do
      it "handles JSON serialization errors gracefully" do
        # Create an object that can't be serialized to JSON
        circular_ref = {}
        circular_ref[:self] = circular_ref

        expect {
          json_logger.info("test", "circular reference", data: circular_ref)
        }.to raise_error(JSON::NestingError)

        # Logger should still be functional for normal objects
        expect {
          json_logger.info("test", "normal message", data: "safe")
        }.not_to raise_error
      end

      it "handles very long log messages" do
        long_message = "x" * 10000
        long_value = "y" * 5000

        json_logger.info("stress", long_message, long_field: long_value)
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        parsed = JSON.parse(json_lines.first)

        expect(parsed["msg"]).to eq(long_message)
        expect(parsed["long_field"]).to eq(long_value)
      end

      it "handles concurrent logging correctly" do
        threads = []

        5.times do |i|
          threads << Thread.new do
            10.times do |j|
              json_logger.info("thread_#{i}", "message_#{j}", thread_id: i, iteration: j)
            end
          end
        end

        threads.each(&:join)
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }

        # Should have 50 log entries total
        expect(json_lines.size).to eq(50)

        # All should be valid JSON
        json_lines.each do |line|
          expect { JSON.parse(line) }.not_to raise_error
        end
      end

      it "maintains JSON format integrity with malformed input" do
        json_logger.info("malformed", "message with unescaped quotes \" and \\ backslashes",
          json_like: '{"invalid": json}',
          control_chars: "\x00\x01\x02\x03",
          backslashes: "C:\\Windows\\Path")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }

        # Should still be parseable JSON
        expect { JSON.parse(json_lines.first) }.not_to raise_error

        parsed = JSON.parse(json_lines.first)
        expect(parsed["backslashes"]).to eq("C:\\Windows\\Path")
      end
    end

    describe "JSON format performance" do
      it "performs efficiently with large metadata sets" do
        large_metadata = {}
        100.times { |i| large_metadata["field_#{i}"] = "value_#{i}_with_some_content" }

        start_time = Time.now

        20.times do |i|
          json_logger.info("perf_test", "Performance test #{i}", **large_metadata)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        json_logger.close

        # Should complete within reasonable time (< 1 second for 20 large logs)
        expect(execution_time).to be < 1.0

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        expect(json_lines.size).to eq(20)

        # Verify one of the logs
        parsed = JSON.parse(json_lines.first)
        expect(parsed.keys.size).to eq(104) # 4 standard + 100 metadata
      end

      it "handles rapid sequential logging efficiently" do
        start_time = Time.now

        1000.times do |i|
          json_logger.info("rapid", "Message #{i}", count: i, timestamp: Time.now.to_f)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        json_logger.close

        # Should complete within reasonable time (< 2 seconds for 1000 logs)
        expect(execution_time).to be < 2.0

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }
        expect(json_lines.size).to eq(1000)
      end
    end

    describe "JSON compatibility and standards" do
      it "produces RFC 7159 compliant JSON" do
        json_logger.info("rfc", "RFC compliance test",
          null_value: nil,
          boolean_true: true,
          boolean_false: false,
          number_int: 42,
          number_float: 3.14159,
          string_empty: "",
          string_unicode: "Hello 🌍")
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }

        # Should parse with strict JSON parser
        parsed = JSON.parse(json_lines.first)

        expect(parsed["null_value"]).to be_nil
        expect(parsed["boolean_true"]).to eq(true)
        expect(parsed["boolean_false"]).to eq(false)
        expect(parsed["number_int"]).to eq(42)
        expect(parsed["number_float"]).to eq(3.14159)
        expect(parsed["string_empty"]).to eq("")
        expect(parsed["string_unicode"]).to eq("Hello 🌍")
      end

      it "handles JSON edge cases consistently" do
        json_logger.info("edge", "Edge cases",
          empty_string: "",
          whitespace: "   \t\n  ",
          zero_number: 0,
          negative_number: -42,
          scientific: 1.23e-4,
          very_large: 9_999_999_999_999)
        json_logger.close

        content = File.read(info_log)
        json_lines = content.lines.select { |l| l.strip.start_with?("{") }

        # Should still be valid JSON even with edge cases
        expect { JSON.parse(json_lines.first) }.not_to raise_error
      end
    end
  end
end
