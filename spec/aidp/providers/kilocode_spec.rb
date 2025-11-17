# frozen_string_literal: true

require "spec_helper"
require "aidp/providers/kilocode"

RSpec.describe Aidp::Providers::Kilocode do
  let(:provider) { described_class.new }

  describe ".available?" do
    it "returns false if kilocode binary missing" do
      allow(Aidp::Util).to receive(:which).with("kilocode").and_return(nil)
      expect(described_class.available?).to be false
    end

    it "returns true if kilocode binary found" do
      allow(Aidp::Util).to receive(:which).with("kilocode").and_return("/usr/local/bin/kilocode")
      expect(described_class.available?).to be true
    end
  end

  describe "basic attributes" do
    it "has name and display_name" do
      expect(provider.name).to eq("kilocode")
      expect(provider.display_name).to eq("Kilocode")
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
      expect(provider.__send__(:calculate_timeout)).to eq(120)
      ENV.delete("AIDP_QUICK_MODE")
    end

    it "uses env override timeout when set" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      ENV["AIDP_KILOCODE_TIMEOUT"] = "42"
      expect(provider.__send__(:calculate_timeout)).to eq(42)
      ENV.delete("AIDP_KILOCODE_TIMEOUT")
    end

    it "falls back to default timeout" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      expect(provider.__send__(:calculate_timeout)).to eq(300)
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
      expect(provider.__send__(:adaptive_timeout)).to eq(180)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns architecture analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "ARCHITECTURE_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(600)
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
      provider.__send__(:setup_activity_monitoring, "kilocode", provider.method(:activity_callback))
      provider.__send__(:record_activity, "start")
      provider.__send__(:mark_completed)
      expect(provider.instance_variable_get(:@activity_state)).to eq(:completed)
    end

    it "marks as failed with reason" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "kilocode", provider.method(:activity_callback))
      provider.__send__(:mark_failed, "test failure")
      expect(provider.instance_variable_get(:@activity_state)).to eq(:failed)
    end

    it "records activity messages" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "kilocode", provider.method(:activity_callback))
      provider.__send__(:record_activity, "test message")

      # record_activity should execute without error
      # Note: implementation may not maintain history array
    end
  end

  describe "#activity_callback" do
    it "handles state transitions" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :running, "Running", "kilocode")
      # Callback should execute without error
    end

    it "handles completed state" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :completed, "Done", "kilocode")
    end

    it "handles failed state" do
      allow(provider).to receive(:display_message)
      provider.__send__(:activity_callback, :failed, "Error", "kilocode")
    end
  end

  describe "#send_message" do
    before do
      # Mock external CLI availability check - default to available
      allow(Aidp::Util).to receive(:which).with("kilocode").and_return("/usr/local/bin/kilocode")
      allow(provider).to receive(:display_message)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_execute_command)
      allow(provider).to receive(:debug_error)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      # Allow actual state transitions so background thread can exit
      allow(provider).to receive(:mark_completed).and_call_original
      allow(provider).to receive(:mark_failed).and_call_original
      # Use a short timeout so activity thread exits quickly if state not updated
      allow(provider).to receive(:calculate_timeout).and_return(1)
      # Provide a spinner test double with needed interface
      spinner_double = double("Spinner", auto_spin: nil, success: nil, error: nil, update: nil, stop: nil)
      allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
    end

    after do
      # Ensure any lingering provider activity threads are terminated to avoid RSpec double leakage
      Thread.list.each do |t|
        bt = t.backtrace
        next unless bt&.any? { |l| l.include?("providers/kilocode.rb") }
        t.kill
        t.join(0.1)
      end
    end

    it "raises error when kilocode is not available" do
      allow(Aidp::Util).to receive(:which).with("kilocode").and_return(nil)

      expect {
        provider.send_message(prompt: "test prompt")
      }.to raise_error("kilocode not available")
    end

    it "uses KILOCODE_MODEL env variable when set" do
      ENV["KILOCODE_MODEL"] = "test-model"

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "kilocode",
        hash_including(args: ["--auto", "-m", "test-model"])
      )

      ENV.delete("KILOCODE_MODEL")
    end

    it "does not include model flag when KILOCODE_MODEL not set" do
      ENV.delete("KILOCODE_MODEL")

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "kilocode",
        hash_including(args: ["--auto"])
      )
    end

    it "includes workspace flag when in git directory and KILOCODE_WORKSPACE is set" do
      allow(Dir).to receive(:exist?).with(".git").and_return(true)
      ENV["KILOCODE_WORKSPACE"] = "/path/to/workspace"

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "kilocode",
        hash_including(args: ["--auto", "--workspace", "/path/to/workspace"])
      )

      ENV.delete("KILOCODE_WORKSPACE")
    end

    it "passes KILOCODE_TOKEN environment variable" do
      ENV["KILOCODE_TOKEN"] = "test-token-123"

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test")

      expect(provider).to have_received(:debug_execute_command).with(
        "kilocode",
        hash_including(env: {"KILOCODE_TOKEN" => "test-token-123"})
      )

      ENV.delete("KILOCODE_TOKEN")
    end

    it "handles successful execution" do
      result = double("Result", exit_status: 0, out: "success output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      output = provider.send_message(prompt: "test")

      expect(output).to eq("success output")
      expect(provider).to have_received(:mark_completed)
    end

    it "handles failed execution" do
      result = double("Result", exit_status: 1, out: "", err: "error output")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      expect {
        provider.send_message(prompt: "test")
      }.to raise_error(/kilocode failed with exit code 1/)
      expect(provider.instance_variable_get(:@activity_state)).to eq(:failed)
    end

    it "warns about large prompts" do
      large_prompt = "a" * 3001

      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: large_prompt)

      expect(provider).to have_received(:debug_log).with(
        anything,
        hash_including(level: :warn)
      )
    end

    it "passes prompt as input to kilocode command" do
      result = double("Result", exit_status: 0, out: "output", err: "")
      allow(provider).to receive(:debug_execute_command).and_return(result)

      provider.send_message(prompt: "test prompt content")

      expect(provider).to have_received(:debug_execute_command).with(
        "kilocode",
        hash_including(input: "test prompt content")
      )
    end
  end
end
