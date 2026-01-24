# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Interfaces::CommandExecutorInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::CommandExecutorInterface
      end
    end

    it "requires #execute to be implemented" do
      instance = bare_class.new
      expect { instance.execute("ls") }
        .to raise_error(NotImplementedError, /must implement #execute/)
    end

    it "accepts all expected parameters" do
      instance = bare_class.new
      expect { instance.execute("ls", args: ["-la"], input: "data", timeout: 30, env: {}) }
        .to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Aidp::Interfaces::CommandResult do
  describe "#initialize" do
    it "stores stdout, stderr, and exit_status" do
      result = described_class.new(stdout: "output", stderr: "error", exit_status: 0)

      expect(result.stdout).to eq("output")
      expect(result.stderr).to eq("error")
      expect(result.exit_status).to eq(0)
    end

    it "converts values to expected types" do
      result = described_class.new(stdout: nil, stderr: nil, exit_status: "1")

      expect(result.stdout).to eq("")
      expect(result.stderr).to eq("")
      expect(result.exit_status).to eq(1)
    end

    it "freezes the result object" do
      result = described_class.new(stdout: "out", stderr: "err", exit_status: 0)

      expect(result).to be_frozen
    end
  end

  describe "#success?" do
    it "returns true when exit_status is 0" do
      result = described_class.new(stdout: "", stderr: "", exit_status: 0)
      expect(result.success?).to be true
    end

    it "returns false when exit_status is non-zero" do
      result = described_class.new(stdout: "", stderr: "", exit_status: 1)
      expect(result.success?).to be false
    end
  end

  describe "#out" do
    it "is an alias for stdout" do
      result = described_class.new(stdout: "hello", stderr: "", exit_status: 0)
      expect(result.out).to eq(result.stdout)
    end
  end

  describe "#err" do
    it "is an alias for stderr" do
      result = described_class.new(stdout: "", stderr: "error", exit_status: 0)
      expect(result.err).to eq(result.stderr)
    end
  end
end

RSpec.describe Aidp::Interfaces::CommandTimeoutError do
  it "stores command and timeout" do
    error = described_class.new(command: "claude", timeout: 30)

    expect(error.command).to eq("claude")
    expect(error.timeout).to eq(30)
    expect(error.message).to include("claude")
    expect(error.message).to include("30")
  end
end

RSpec.describe Aidp::Interfaces::CommandExecutionError do
  it "stores command and original error" do
    original = StandardError.new("connection refused")
    error = described_class.new(command: "claude", original_error: original)

    expect(error.command).to eq("claude")
    expect(error.original_error).to eq(original)
    expect(error.message).to include("claude")
    expect(error.message).to include("connection refused")
  end
end

RSpec.describe Aidp::Interfaces::NullExecutor do
  subject(:executor) { described_class.new }

  describe "interface compliance" do
    it "includes CommandExecutorInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::CommandExecutorInterface)
    end
  end

  describe "#execute" do
    it "returns a successful empty result" do
      result = executor.execute("ls", args: ["-la"])

      expect(result).to be_a(Aidp::Interfaces::CommandResult)
      expect(result.success?).to be true
      expect(result.stdout).to eq("")
      expect(result.stderr).to eq("")
    end

    it "accepts all parameters without error" do
      expect {
        executor.execute("cmd", args: ["-a"], input: "data", timeout: 30, env: {"FOO" => "bar"})
      }.not_to raise_error
    end
  end
end

RSpec.describe Aidp::Interfaces::TtyCommandExecutor do
  subject(:executor) { described_class.new(logger: logger, component_name: "test_executor") }
  let(:logger) { nil } # Use nil logger; the executor handles this gracefully

  # Use a spy logger for tests that need to verify logging
  let(:spy_logger) do
    Class.new do
      include Aidp::Interfaces::LoggerInterface

      attr_reader :calls

      def initialize
        @calls = []
      end

      def log_debug(component, message, **metadata)
        @calls << {level: :debug, component: component, message: message, metadata: metadata}
      end

      def log_info(component, message, **metadata)
        @calls << {level: :info, component: component, message: message, metadata: metadata}
      end

      def log_warn(component, message, **metadata)
        @calls << {level: :warn, component: component, message: message, metadata: metadata}
      end

      def log_error(component, message, **metadata)
        @calls << {level: :error, component: component, message: message, metadata: metadata}
      end
    end.new
  end

  describe "interface compliance" do
    it "includes CommandExecutorInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::CommandExecutorInterface)
    end
  end

  describe "#execute" do
    context "when command succeeds" do
      it "returns a CommandResult with output" do
        result = executor.execute("echo", args: ["hello"])

        expect(result).to be_a(Aidp::Interfaces::CommandResult)
        expect(result.success?).to be true
        expect(result.stdout.strip).to eq("hello")
        expect(result.stderr).to eq("")
      end

      it "logs the execution" do
        executor_with_spy = described_class.new(logger: spy_logger, component_name: "test_executor")
        executor_with_spy.execute("echo", args: ["test"])

        executing_call = spy_logger.calls.find { |c| c[:message] == "executing_command" }
        completed_call = spy_logger.calls.find { |c| c[:message] == "command_completed" }

        expect(executing_call).not_to be_nil
        expect(executing_call[:component]).to eq("test_executor")
        expect(executing_call[:metadata][:command]).to eq("echo")

        expect(completed_call).not_to be_nil
        expect(completed_call[:component]).to eq("test_executor")
        expect(completed_call[:metadata][:command]).to eq("echo")
        expect(completed_call[:metadata][:exit_status]).to eq(0)
      end
    end

    context "when command fails" do
      it "returns a CommandResult with non-zero exit status" do
        result = executor.execute("sh", args: ["-c", "exit 42"])

        expect(result.success?).to be false
        expect(result.exit_status).to eq(42)
      end
    end

    context "with stdin input" do
      it "passes input to the command" do
        result = executor.execute("cat", input: "hello stdin")

        expect(result.success?).to be true
        expect(result.stdout).to eq("hello stdin")
      end
    end

    context "when command times out" do
      it "raises CommandTimeoutError" do
        expect {
          executor.execute("sleep", args: ["10"], timeout: 0.1)
        }.to raise_error(Aidp::Interfaces::CommandTimeoutError) do |error|
          expect(error.command).to eq("sleep")
          expect(error.timeout).to eq(0.1)
        end
      end
    end

    context "when command does not exist" do
      it "raises CommandExecutionError" do
        expect {
          executor.execute("nonexistent_command_xyz")
        }.to raise_error(Aidp::Interfaces::CommandExecutionError) do |error|
          expect(error.command).to eq("nonexistent_command_xyz")
        end
      end
    end

    context "without a logger" do
      let(:executor) { described_class.new }

      it "executes without error" do
        result = executor.execute("echo", args: ["no logger"])
        expect(result.success?).to be true
      end
    end
  end
end
