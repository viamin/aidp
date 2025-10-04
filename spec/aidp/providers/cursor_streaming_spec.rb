# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Cursor do
  let(:provider) { described_class.new }

  before do
    # Mock availability check
    allow(described_class).to receive(:available?).and_return(true)
    allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return("/usr/local/bin/cursor-agent")
  end

  describe "#send" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Test response", err: "") }

    before do
      allow(provider).to receive(:debug_execute_command).and_return(successful_result)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:display_message)
      allow(provider).to receive(:calculate_timeout).and_return(300)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      allow(provider).to receive(:mark_completed)

      # Mock spinner
      spinner = double("spinner", auto_spin: nil, success: nil, error: nil, update: nil, stop: nil)
      allow(TTY::Spinner).to receive(:new).and_return(spinner)

      # Mock thread to avoid infinite loops - return a mock thread that doesn't execute the block
      mock_thread = double("thread", alive?: false, kill: nil, join: nil)
      allow(Thread).to receive(:new).and_return(mock_thread)
    end

    context "when streaming is disabled" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
      end

      it "does not show streaming message" do
        provider.send(prompt: prompt)

        expect(provider).not_to have_received(:display_message).with(
          anything,
          type: :info
        )
      end

      it "uses non-streaming debug_execute_command" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "cursor-agent",
          args: ["agent"],
          input: prompt,
          timeout: 300,
          streaming: false
        )
      end
    end

    context "when streaming is enabled via AIDP_STREAMING" do
      before do
        ENV["AIDP_STREAMING"] = "1"
        ENV.delete("DEBUG")
      end

      after do
        ENV.delete("AIDP_STREAMING")
      end

      it "shows display streaming message" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:display_message).with(
          "📺 Display streaming enabled - output buffering reduced (cursor-agent does not support true streaming)",
          type: :info
        )
      end

      it "uses streaming debug_execute_command" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "cursor-agent",
          args: ["agent"],
          input: prompt,
          timeout: 300,
          streaming: true
        )
      end
    end

    context "when streaming is enabled via DEBUG" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV["DEBUG"] = "1"
      end

      after do
        ENV.delete("DEBUG")
      end

      it "shows display streaming message" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:display_message).with(
          "📺 Display streaming enabled - output buffering reduced (cursor-agent does not support true streaming)",
          type: :info
        )
      end

      it "uses streaming debug_execute_command" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "cursor-agent",
          args: ["agent"],
          input: prompt,
          timeout: 300,
          streaming: true
        )
      end
    end

    context "when agent command fails and falls back to -p mode" do
      let(:failed_result) { double("result", exit_status: 1, out: "", err: "Agent failed") }

      before do
        ENV["AIDP_STREAMING"] = "1"
        allow(provider).to receive(:debug_execute_command)
          .with("cursor-agent", args: ["agent"], input: prompt, timeout: 300, streaming: true)
          .and_raise(StandardError.new("Agent command failed"))
        allow(provider).to receive(:debug_execute_command)
          .with("cursor-agent", args: ["-p"], input: prompt, timeout: 300, streaming: true)
          .and_return(successful_result)
      end

      after do
        ENV.delete("AIDP_STREAMING")
      end

      it "falls back to -p mode with streaming enabled" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "cursor-agent",
          args: ["-p"],
          input: prompt,
          timeout: 300,
          streaming: true
        )
      end
    end
  end
end
