# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::DebugMixin do
  let(:test_class) do
    Class.new do
      include Aidp::DebugMixin
    end
  end

  let(:instance) { test_class.new }
  let(:logger) { instance_double(Aidp::Logger) }

  before do
    allow(Aidp::DebugMixin).to receive(:shared_logger).and_return(logger)
    allow(logger).to receive(:log)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
  end

  describe ".debug_enabled?" do
    after { ENV.delete("DEBUG") }

    it "returns true when DEBUG env is set to positive value" do
      ENV["DEBUG"] = "1"
      expect(test_class.debug_enabled?).to be true
    end

    it "returns falsy when DEBUG env is not set" do
      ENV.delete("DEBUG")
      expect(test_class.debug_enabled?).to be_falsy
    end

    it "returns false when DEBUG env is 0" do
      ENV["DEBUG"] = "0"
      expect(test_class.debug_enabled?).to be false
    end
  end

  describe ".debug_level" do
    after { ENV.delete("DEBUG") }

    it "returns DEBUG_OFF when env not set" do
      ENV.delete("DEBUG")
      expect(test_class.debug_level).to eq(Aidp::DebugMixin::DEBUG_OFF)
    end

    it "returns integer value from env" do
      ENV["DEBUG"] = "2"
      expect(test_class.debug_level).to eq(2)
    end
  end

  describe "#debug_enabled?" do
    after { ENV.delete("DEBUG") }

    it "delegates to class method" do
      ENV["DEBUG"] = "1"
      expect(instance.debug_enabled?).to be true
    end
  end

  describe "#debug_level" do
    after { ENV.delete("DEBUG") }

    it "delegates to class method" do
      ENV["DEBUG"] = "2"
      expect(instance.debug_level).to eq(2)
    end
  end

  describe "#debug_basic?" do
    after { ENV.delete("DEBUG") }

    it "returns true when debug level is DEBUG_BASIC" do
      ENV["DEBUG"] = "1"
      expect(instance.debug_basic?).to be true
    end

    it "returns true when debug level is DEBUG_VERBOSE" do
      ENV["DEBUG"] = "2"
      expect(instance.debug_basic?).to be true
    end

    it "returns false when debug is off" do
      ENV["DEBUG"] = "0"
      expect(instance.debug_basic?).to be false
    end
  end

  describe "#debug_verbose?" do
    after { ENV.delete("DEBUG") }

    it "returns true when debug level is DEBUG_VERBOSE" do
      ENV["DEBUG"] = "2"
      expect(instance.debug_verbose?).to be true
    end

    it "returns false when debug level is DEBUG_BASIC" do
      ENV["DEBUG"] = "1"
      expect(instance.debug_verbose?).to be false
    end

    it "returns false when debug is off" do
      ENV["DEBUG"] = "0"
      expect(instance.debug_verbose?).to be false
    end
  end

  describe "#debug_log" do
    after { ENV.delete("DEBUG") }

    it "does not log when debug is disabled" do
      ENV["DEBUG"] = "0"
      instance.debug_log("test message")
      expect(logger).not_to have_received(:log)
    end

    it "logs message without data when debug is enabled" do
      ENV["DEBUG"] = "1"
      instance.debug_log("test message", level: :info)
      expect(logger).to have_received(:log).with(:info, anything, "test message")
    end

    it "logs message with data when debug is enabled and data provided" do
      ENV["DEBUG"] = "1"
      instance.debug_log("test message", level: :warn, data: {key: "value"})
      expect(logger).to have_received(:log).with(:warn, anything, "test message", key: "value")
    end
  end

  describe "#debug_command" do
    after { ENV.delete("DEBUG") }

    it "does not log when debug_basic is false" do
      ENV["DEBUG"] = "0"
      instance.debug_command("cmd", args: ["arg1"])
      expect(logger).not_to have_received(:info)
    end

    it "logs command execution" do
      ENV["DEBUG"] = "1"
      instance.debug_command("cmd", args: ["arg1", "arg2"])
      expect(logger).to have_received(:info).with(anything, /Executing command: cmd arg1 arg2/)
    end

    it "logs short input" do
      ENV["DEBUG"] = "1"
      instance.debug_command("cmd", input: "short input")
      expect(logger).to have_received(:info).with(anything, /Input: short input/)
    end

    it "logs truncated input for long strings" do
      ENV["DEBUG"] = "1"
      long_input = "a" * 250
      instance.debug_command("cmd", input: long_input)
      expect(logger).to have_received(:info).with(anything, /Input \(truncated\):/)
    end

    it "logs file path when input is existing file" do
      ENV["DEBUG"] = "1"
      file_path = "/tmp/test.txt"
      allow(File).to receive(:exist?).with(file_path).and_return(true)
      instance.debug_command("cmd", input: file_path)
      expect(logger).to have_received(:info).with(anything, /Input file: #{file_path}/)
    end

    it "logs error output when present" do
      ENV["DEBUG"] = "1"
      instance.debug_command("cmd", error: "error message")
      expect(logger).to have_received(:error).with(anything, /Error output: error message/)
    end

    it "does not log error when empty" do
      ENV["DEBUG"] = "1"
      instance.debug_command("cmd", error: "")
      expect(logger).not_to have_received(:error)
    end

    it "filters out Claude CLI sandbox debug messages" do
      ENV["DEBUG"] = "1"
      sandbox_error = "[SandboxDebug] [Sandbox Linux] Seccomp filtering not available (missing binaries for arm64). " \
                      "Sandbox will run without Unix socket blocking (allowAllUnixSockets mode). " \
                      "This is less restrictive but still provides filesystem and network isolation.\n"
      instance.debug_command("claude", error: sandbox_error)
      expect(logger).not_to have_received(:error)
    end

    it "filters out sandbox messages but keeps real errors" do
      ENV["DEBUG"] = "1"
      mixed_error = "[SandboxDebug] [Sandbox Linux] Seccomp filtering not available\n" \
                    "Real error: Authentication failed\n"
      instance.debug_command("claude", error: mixed_error)
      expect(logger).to have_received(:error).with(anything, /Real error: Authentication failed/)
      expect(logger).not_to have_received(:error).with(anything, /SandboxDebug/)
    end

    it "logs output in verbose mode" do
      ENV["DEBUG"] = "2"
      instance.debug_command("cmd", output: "command output")
      expect(logger).to have_received(:debug).with(anything, /Output: command output/)
    end

    it "does not log output when not verbose" do
      ENV["DEBUG"] = "1"
      instance.debug_command("cmd", output: "command output")
      expect(logger).not_to have_received(:debug)
    end

    it "logs exit code in verbose mode" do
      ENV["DEBUG"] = "2"
      instance.debug_command("cmd", exit_code: 42)
      expect(logger).to have_received(:debug).with(anything, /Exit code: 42/)
    end
  end

  describe "#debug_step" do
    after { ENV.delete("DEBUG") }

    it "does not log when debug_basic is false" do
      ENV["DEBUG"] = "0"
      instance.debug_step("step", "action")
      expect(logger).not_to have_received(:info)
    end

    it "logs step execution" do
      ENV["DEBUG"] = "1"
      instance.debug_step("test_step", "Starting")
      expect(logger).to have_received(:info).with(anything, /Starting: test_step/)
    end

    it "logs step with details" do
      ENV["DEBUG"] = "1"
      instance.debug_step("test_step", "Starting", foo: "bar")
      expect(logger).to have_received(:info).with(anything, /Starting: test_step/, foo: "bar")
    end
  end

  describe "#debug_provider" do
    after { ENV.delete("DEBUG") }

    it "does not log when debug_basic is false" do
      ENV["DEBUG"] = "0"
      instance.debug_provider("claude", "sending")
      expect(logger).not_to have_received(:info)
    end

    it "logs provider action" do
      ENV["DEBUG"] = "1"
      instance.debug_provider("claude", "Sending request")
      expect(logger).to have_received(:info).with(/provider_claude/, /Sending request/)
    end

    it "logs provider action with details" do
      ENV["DEBUG"] = "1"
      instance.debug_provider("claude", "Sending", tokens: 100)
      expect(logger).to have_received(:info).with(/provider_claude/, anything, tokens: 100)
    end
  end

  describe "#debug_error" do
    let(:error) { StandardError.new("test error") }

    before do
      error.set_backtrace(["line1", "line2", "line3"])
    end

    after { ENV.delete("DEBUG") }

    it "does not log when debug_basic is false" do
      ENV["DEBUG"] = "0"
      instance.debug_error(error)
      expect(logger).not_to have_received(:error)
    end

    it "logs error message" do
      ENV["DEBUG"] = "1"
      instance.debug_error(error)
      expect(logger).to have_received(:error).with(anything, /Error: StandardError: test error/, hash_including(error: "StandardError"))
    end

    it "logs error with context" do
      ENV["DEBUG"] = "1"
      instance.debug_error(error, command: "test_cmd")
      expect(logger).to have_received(:error).with(anything, anything, hash_including(command: "test_cmd"))
    end

    it "logs backtrace in verbose mode" do
      ENV["DEBUG"] = "2"
      instance.debug_error(error)
      expect(logger).to have_received(:debug).with(anything, /Backtrace:/)
    end

    it "does not log backtrace when not verbose" do
      ENV["DEBUG"] = "1"
      instance.debug_error(error)
      expect(logger).not_to have_received(:debug)
    end
  end

  describe "#debug_timing" do
    after { ENV.delete("DEBUG") }

    it "does not log when debug_verbose is false" do
      ENV["DEBUG"] = "1"
      instance.debug_timing("operation", 1.5)
      expect(logger).not_to have_received(:debug)
    end

    it "logs timing in verbose mode" do
      ENV["DEBUG"] = "2"
      instance.debug_timing("test operation", 1.5)
      expect(logger).to have_received(:debug).with(anything, /test operation: 1.5s/, hash_including(duration: 1.5))
    end

    it "logs timing with details in verbose mode" do
      ENV["DEBUG"] = "2"
      instance.debug_timing("test operation", 2.3, exit_code: 0)
      expect(logger).to have_received(:debug).with(anything, anything, hash_including(duration: 2.3, exit_code: 0))
    end
  end

  describe "#component_name" do
    it "returns downcased class name segment" do
      named_class = Class.new do
        include Aidp::DebugMixin

        def self.name
          "Aidp::Test::MyComponent"
        end
      end
      instance = named_class.new
      expect(instance.send(:component_name)).to eq("my_component")
    end

    it "returns 'anonymous' for anonymous classes" do
      anon_class = Class.new do
        include Aidp::DebugMixin

        def self.name
          nil
        end
      end
      instance = anon_class.new
      expect(instance.send(:component_name)).to eq("anonymous")
    end

    it "returns 'anonymous' for empty class names" do
      empty_class = Class.new do
        include Aidp::DebugMixin

        def self.name
          ""
        end
      end
      instance = empty_class.new
      expect(instance.send(:component_name)).to eq("anonymous")
    end

    it "returns 'anonymous' when error occurs" do
      error_class = Class.new do
        include Aidp::DebugMixin

        def self.name
          raise "error"
        end
      end
      instance = error_class.new
      expect(instance.send(:component_name)).to eq("anonymous")
    end

    it "memoizes the component name" do
      instance = test_class.new
      first_call = instance.send(:component_name)
      second_call = instance.send(:component_name)
      expect(first_call).to equal(second_call) # Same object identity
    end
  end

  describe "#debug_execute_command" do
    let(:command) { "echo" }
    let(:args) { ["hello"] }
    let(:input) { "test input" }
    let(:timeout) { 30 }

    before do
      allow(instance).to receive(:debug_log)
      allow(instance).to receive(:debug_command)
      allow(instance).to receive(:debug_timing)
      allow(instance).to receive(:debug_error)
    end

    it "uses null printer" do
      expect(TTY::Command).to receive(:new).with(printer: :null).and_call_original

      instance.debug_execute_command(command, args: args, input: input, timeout: timeout)
    end

    context "with input from file" do
      let(:file_path) { "/tmp/test_file" }
      let(:file_content) { "file content" }

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it "reads input from file" do
        instance.debug_execute_command(command, args: args, input: file_path, timeout: timeout)

        expect(instance).to have_received(:debug_log).with(
          "📁 Reading input from file: #{file_path}",
          level: :info
        )
      end
    end

    context "when command succeeds" do
      it "logs timing information" do
        instance.debug_execute_command(command, args: args, timeout: timeout)

        expect(instance).to have_received(:debug_timing).with(
          "Command execution",
          anything,
          {exit_code: 0}
        )
      end

      it "logs command details" do
        instance.debug_execute_command(command, args: args, timeout: timeout)

        expect(instance).to have_received(:debug_command).with(
          command,
          args: args,
          input: nil,
          output: anything,
          error: anything,
          exit_code: 0
        )
      end
    end

    context "when command fails" do
      let(:failing_command) { "false" } # Command that always fails

      it "logs error information" do
        begin
          instance.debug_execute_command(failing_command, args: [], timeout: timeout)
        rescue TTY::Command::ExitError
          # Expected to raise
        end

        expect(instance).to have_received(:debug_error)
      end
    end

    context "when command times out" do
      it "logs timeout error" do
        begin
          # Use a much shorter sleep to trigger timeout faster (0.5s sleep with 0.1s timeout)
          instance.debug_execute_command("sleep", args: ["0.5"], timeout: 0.1)
        rescue TTY::Command::TimeoutExceeded
          # Expected to timeout
        end

        expect(instance).to have_received(:debug_error)
      end
    end
  end
end
