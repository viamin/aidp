# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::DebugMixin do
  let(:test_class) do
    Class.new do
      include Aidp::DebugMixin
    end
  end

  let(:instance) { test_class.new }

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

    context "when streaming is disabled" do
      it "uses null printer" do
        expect(TTY::Command).to receive(:new).with(printer: :null).and_call_original

        instance.debug_execute_command(command, args: args, input: input, timeout: timeout, streaming: false)
      end

      it "does not show streaming message" do
        instance.debug_execute_command(command, args: args, input: input, timeout: timeout, streaming: false)

        expect(instance).not_to have_received(:debug_log).with(
          "📺 Streaming mode enabled - showing real-time output",
          level: :info
        )
      end
    end

    context "when streaming is enabled" do
      it "uses progress printer" do
        expect(TTY::Command).to receive(:new).with(printer: :progress).and_call_original

        instance.debug_execute_command(command, args: args, input: input, timeout: timeout, streaming: true)
      end

      it "shows streaming message" do
        instance.debug_execute_command(command, args: args, input: input, timeout: timeout, streaming: true)

        expect(instance).to have_received(:debug_log).with(
          "📺 Streaming mode enabled - showing real-time output",
          level: :info
        )
      end
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
