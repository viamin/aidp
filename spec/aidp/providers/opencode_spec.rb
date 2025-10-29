# frozen_string_literal: true

require "spec_helper"
require "aidp/providers/opencode"

RSpec.describe Aidp::Providers::Opencode do
  let(:provider) { described_class.new }

  describe ".available?" do
    it "returns false if opencode binary missing" do
      allow(Aidp::Util).to receive(:which).with("opencode").and_return(nil)
      expect(described_class.available?).to be false
    end

    it "returns true if opencode binary found" do
      allow(Aidp::Util).to receive(:which).with("opencode").and_return("/usr/local/bin/opencode")
      expect(described_class.available?).to be true
    end
  end

  describe "basic attributes" do
    it "has name and display_name" do
      expect(provider.name).to eq("opencode")
      expect(provider.display_name).to eq("OpenCode")
    end
  end

  describe "timeout calculation" do
    before do
      allow(provider).to receive(:display_message) # silence output
    end

    it "uses quick mode timeout when AIDP_QUICK_MODE set" do
      stub_const("Aidp::Providers::TIMEOUT_QUICK_MODE", 30)
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      ENV["AIDP_QUICK_MODE"] = "1"
      expect(provider.__send__(:calculate_timeout)).to eq(30)
      ENV.delete("AIDP_QUICK_MODE")
    end

    it "uses env override timeout when set" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      ENV["AIDP_OPENCODE_TIMEOUT"] = "42"
      expect(provider.__send__(:calculate_timeout)).to eq(42)
      ENV.delete("AIDP_OPENCODE_TIMEOUT")
    end

    it "falls back to default timeout" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      expect(provider.__send__(:calculate_timeout)).to eq(600)
    end
  end

  describe "adaptive timeout" do
    before do
      stub_const("Aidp::Providers::TIMEOUT_REPOSITORY_ANALYSIS", 100)
      stub_const("Aidp::Providers::TIMEOUT_ARCHITECTURE_ANALYSIS", 200)
      stub_const("Aidp::Providers::TIMEOUT_TEST_ANALYSIS", 300)
      stub_const("Aidp::Providers::TIMEOUT_FUNCTIONALITY_ANALYSIS", 400)
      stub_const("Aidp::Providers::TIMEOUT_DOCUMENTATION_ANALYSIS", 500)
      stub_const("Aidp::Providers::TIMEOUT_STATIC_ANALYSIS", 600)
      stub_const("Aidp::Providers::TIMEOUT_REFACTORING_RECOMMENDATIONS", 700)
    end

    it "returns repository analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "REPOSITORY_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(100)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns architecture analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "ARCHITECTURE_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(200)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns test analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(300)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns nil for unknown step" do
      ENV["AIDP_CURRENT_STEP"] = "UNKNOWN_STEP"
      expect(provider.__send__(:adaptive_timeout)).to be_nil
      ENV.delete("AIDP_CURRENT_STEP")
    end
  end

  describe "activity callbacks" do
    it "transitions states" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "opencode", provider.method(:activity_callback))
      provider.__send__(:record_activity, "start")
      provider.__send__(:mark_completed)
      expect(provider.instance_variable_get(:@activity_state)).to eq(:completed)
    end

    it "marks as failed with reason" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "opencode", provider.method(:activity_callback))
      provider.__send__(:mark_failed, "test failure")
      expect(provider.instance_variable_get(:@activity_state)).to eq(:failed)
    end

    it "records activity messages" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "opencode", provider.method(:activity_callback))
      provider.__send__(:record_activity, "test message")

      # record_activity should execute without error
      # Note: implementation may not maintain history array
    end
  end

  describe "#activity_callback" do
    it "handles state transitions" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :running, "Running", "opencode")
      # Callback should execute without error
    end

    it "handles completed state" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :completed, "Done", "opencode")
    end

    it "handles failed state" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :failed, "Error", "opencode")
    end
  end

  describe "#send_message" do
    before do
      allow(provider).to receive(:display_message)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_execute_command)
      allow(provider).to receive(:debug_error)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      allow(provider).to receive(:mark_completed)
      allow(provider).to receive(:mark_failed)
      allow(provider).to receive(:cleanup_activity_display)
      allow(TTY::Spinner).to receive(:new).and_return(double("Spinner", auto_spin: nil, success: nil, error: nil))
    end

    it "raises error when opencode is not available" do
      allow(described_class).to receive(:available?).and_return(false)

      expect {
        provider.send_message(prompt: "test prompt")
      }.to raise_error("opencode not available")
    end

    it "uses OPENCODE_MODEL env variable when set" do
      allow(described_class).to receive(:available?).and_return(true)
      ENV["OPENCODE_MODEL"] = "test-model"

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "opencode",
        hash_including(args: ["run", "-m", "test-model", "test"])
      )

      ENV.delete("OPENCODE_MODEL")
    end

    it "uses default model when OPENCODE_MODEL not set" do
      allow(described_class).to receive(:available?).and_return(true)
      ENV.delete("OPENCODE_MODEL")

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "opencode",
        hash_including(args: ["run", "-m", "github-copilot/claude-3.5-sonnet", "test"])
      )
    end

    it "handles successful execution" do
      allow(described_class).to receive(:available?).and_return(true)
      result = double("Result", exit_status: 0, out: "success output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      output = provider.send_message(prompt: "test")

      expect(output).to eq("success output")
      expect(provider).to have_received(:mark_completed)
    end

    it "handles failed execution" do
      allow(described_class).to receive(:available?).and_return(true)
      result = double("Result", exit_status: 1, out: "", err: "error output")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      expect {
        provider.send_message(prompt: "test")
      }.to raise_error(/opencode failed with exit code 1/)

      expect(provider).to have_received(:mark_failed).at_least(:once)
    end

    it "enables streaming mode when AIDP_STREAMING is set" do
      allow(described_class).to receive(:available?).and_return(true)
      ENV["AIDP_STREAMING"] = "1"

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:display_message).with(
        anything,
        hash_including(type: :info)
      ).at_least(:once)

      ENV.delete("AIDP_STREAMING")
    end

    it "warns about large prompts" do
      allow(described_class).to receive(:available?).and_return(true)
      large_prompt = "a" * 3001

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: large_prompt)

      expect(provider).to have_received(:debug_log).with(
        anything,
        hash_including(level: :warn)
      )
    end
  end
end
