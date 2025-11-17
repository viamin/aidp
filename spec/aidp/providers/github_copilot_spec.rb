# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"
require_relative "../../../lib/aidp/providers/github_copilot"

RSpec.describe Aidp::Providers::GithubCopilot do
  let(:test_prompt) { TestPrompt.new }
  let(:provider) { described_class.new(prompt: test_prompt) }

  describe ".available?" do
    context "when copilot is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("copilot").and_return("/usr/local/bin/copilot")
      end

      it "returns true" do
        expect(described_class.available?).to be true
      end
    end

    context "when copilot is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("copilot").and_return(nil)
      end

      it "returns false" do
        expect(described_class.available?).to be false
      end
    end
  end

  describe "#name" do
    it "returns the correct provider name" do
      expect(provider.name).to eq("github_copilot")
    end
  end

  describe "#available?" do
    context "when copilot is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("copilot").and_return("/usr/local/bin/copilot")
        successful_result = double("result", exit_status: 0)
        allow(Aidp::Util).to receive(:execute_command)
          .with("copilot", ["--version"], timeout: 10)
          .and_return(successful_result)
      end

      it "returns true" do
        expect(provider.available?).to be true
      end
    end

    context "when copilot is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("copilot").and_return(nil)
      end

      it "returns false" do
        expect(provider.available?).to be false
      end
    end
  end

  describe "#send" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Success output", err: "") }
    let(:failed_result) { double("result", exit_status: 1, out: "", err: "Error output") }

    before do
      # Mock external CLI availability check - default to available
      allow(Aidp::Util).to receive(:which).with("copilot").and_return("/usr/local/bin/copilot")
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_error)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      allow(provider).to receive(:mark_completed)
      allow(provider).to receive(:mark_failed)
      allow(provider).to receive(:print_activity_status)
      allow(provider).to receive(:clear_activity_status)
      # Stub timeout calculation to avoid environment dependencies
      allow(provider).to receive(:calculate_timeout).and_return(300)
    end

    context "when copilot is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("copilot").and_return(nil)
      end

      it "raises an error" do
        expect { provider.send_message(prompt: prompt) }.to raise_error("copilot CLI not available")
      end
    end

    context "when copilot is available" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
        allow(provider).to receive(:debug_execute_command).and_return(successful_result)
        allow(provider).to receive(:display_message)
        # Mock the thread to avoid actual threading
        thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
        allow(Thread).to receive(:new).and_return(thread_mock)
      end

      it "executes copilot with prompt mode" do
        provider.send_message(prompt: prompt)
        expect(provider).to have_received(:debug_execute_command)
          .with("copilot", args: ["-p", prompt, "--allow-all-tools"], timeout: 300)
      end

      it "returns the output when successful" do
        result = provider.send_message(prompt: prompt)
        expect(result).to eq("Success output")
      end

      it "marks as completed when successful" do
        provider.send_message(prompt: prompt)
        expect(provider).to have_received(:mark_completed)
      end

      context "when execution fails" do
        before do
          allow(provider).to receive(:debug_execute_command).and_return(failed_result)
          # Mock the thread to avoid actual threading
          thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
          allow(Thread).to receive(:new).and_return(thread_mock)
        end

        it "raises an error with exit code and stderr" do
          expect { provider.send_message(prompt: prompt) }
            .to raise_error("copilot failed with exit code 1: Error output")
        end

        it "marks as failed" do
          begin
            provider.send_message(prompt: prompt)
          rescue
            # Expected to raise
          end
          expect(provider).to have_received(:mark_failed)
            .with("copilot failed with exit code 1")
        end
      end

      context "with session parameter" do
        let(:session) { "test-session" }

        before do
          ENV.delete("AIDP_STREAMING")
          ENV.delete("DEBUG")
          allow(provider).to receive(:display_message)
          # Mock the thread to avoid actual threading
          thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
          allow(Thread).to receive(:new).and_return(thread_mock)
        end

        it "includes session parameter in command" do
          provider.send_message(prompt: prompt, session: "test-session")
          expect(provider).to have_received(:debug_execute_command)
            .with("copilot", args: ["-p", prompt, "--allow-all-tools", "--resume", "test-session"], timeout: 300)
        end
      end
    end
  end

  describe "#send_with_options" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Success output", err: "") }

    before do
      ENV.delete("AIDP_STREAMING")
      ENV.delete("DEBUG")
      allow(provider).to receive(:calculate_timeout).and_return(300)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_execute_command).and_return(successful_result)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      allow(provider).to receive(:mark_completed)
      allow(provider).to receive(:display_message)
    end

    it "includes tools when specified" do
      options = {
        tools: ["read", "write"],
        session: "test-session"
      }

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("copilot", args: ["-p", prompt, "--resume", "test-session", "--allow-tool", "read", "--allow-tool", "write"], timeout: 300)
    end

    it "includes log level when specified" do
      options = {log_level: "debug"}

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("copilot", args: ["-p", prompt, "--allow-all-tools", "--log-level", "debug"], timeout: 300)
    end

    it "includes directories when specified" do
      directories = ["/tmp/project", "/tmp/workspace"]
      options = {directories: directories}

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("copilot", args: ["-p", prompt, "--allow-all-tools", "--add-dir", "/tmp/project", "--add-dir", "/tmp/workspace"], timeout: 300)
    end
  end

  describe "timeout calculation" do
    before do
      allow(provider).to receive(:puts) # Suppress output
    end

    context "when AIDP_QUICK_MODE is set" do
      around do |example|
        ENV["AIDP_QUICK_MODE"] = "true"
        example.run
        ENV.delete("AIDP_QUICK_MODE")
      end

      it "returns 120 seconds" do
        expect(provider.__send__(:calculate_timeout)).to eq(120)
      end
    end

    context "when AIDP_GITHUB_COPILOT_TIMEOUT is set" do
      around do |example|
        ENV["AIDP_GITHUB_COPILOT_TIMEOUT"] = "600"
        example.run
        ENV.delete("AIDP_GITHUB_COPILOT_TIMEOUT")
      end

      it "returns the configured timeout" do
        expect(provider.__send__(:calculate_timeout)).to eq(600)
      end
    end

    context "with adaptive timeout" do
      before do
        allow(provider).to receive(:adaptive_timeout).and_return(450)
      end

      it "returns the adaptive timeout" do
        expect(provider.__send__(:calculate_timeout)).to eq(450)
      end
    end

    context "with default timeout" do
      it "returns 300 seconds" do
        expect(provider.__send__(:calculate_timeout)).to eq(300)
      end
    end
  end

  describe "adaptive timeout calculation" do
    it "returns appropriate timeouts for different step types" do
      test_cases = {
        "REPOSITORY_ANALYSIS" => 180,
        "ARCHITECTURE_ANALYSIS" => 600,
        "TEST_ANALYSIS" => 300,
        "FUNCTIONALITY_ANALYSIS" => 600,
        "DOCUMENTATION_ANALYSIS" => 300,
        "STATIC_ANALYSIS" => 450,
        "REFACTORING_RECOMMENDATIONS" => 600,
        "UNKNOWN_STEP" => nil
      }

      test_cases.each do |step_name, expected_timeout|
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("AIDP_CURRENT_STEP").and_return(step_name)

        # Clear the cached timeout to ensure fresh calculation for each step
        provider.instance_variable_set(:@adaptive_timeout, nil)
        actual_timeout = provider.__send__(:adaptive_timeout)
        expect(actual_timeout).to eq(expected_timeout), "Expected #{expected_timeout} for #{step_name}, got #{actual_timeout}"
      end
    end
  end

  describe "health checks" do
    describe "#harness_healthy?" do
      before do
        allow(provider).to receive(:stuck?).and_return(false)
        allow(provider).to receive(:calculate_success_rate).and_return(0.8)
        allow(provider).to receive(:calculate_rate_limit_ratio).and_return(0.1)
      end

      context "when base health check fails" do
        before do
          allow(provider).to receive(:stuck?).and_return(true)
        end

        it "returns false" do
          expect(provider.harness_healthy?).to be false
        end
      end

      context "when CLI help command fails" do
        before do
          allow(Aidp::Util).to receive(:execute_command).and_raise(StandardError.new("Command failed"))
        end

        it "returns false" do
          expect(provider.harness_healthy?).to be false
        end
      end

      context "when all checks pass" do
        before do
          successful_result = double("result", exit_status: 0)
          allow(Aidp::Util).to receive(:execute_command)
            .with("copilot", ["--help"], timeout: 5)
            .and_return(successful_result)
        end

        it "returns true" do
          expect(provider.harness_healthy?).to be true
        end
      end
    end

    describe "#available?" do
      context "when class method returns false" do
        before do
          allow(Aidp::Util).to receive(:which).with("copilot").and_return(nil)
        end

        it "returns false" do
          expect(provider.available?).to be false
        end
      end

      context "when version check fails" do
        before do
          allow(Aidp::Util).to receive(:which).with("copilot").and_return("/usr/local/bin/copilot")
          allow(Aidp::Util).to receive(:execute_command).and_raise(StandardError.new("Command failed"))
        end

        it "returns false" do
          expect(provider.available?).to be false
        end
      end

      context "when all checks pass" do
        before do
          allow(Aidp::Util).to receive(:which).with("copilot").and_return("/usr/local/bin/copilot")
          successful_result = double("result", exit_status: 0)
          allow(Aidp::Util).to receive(:execute_command)
            .with("copilot", ["--version"], timeout: 10)
            .and_return(successful_result)
        end

        it "returns true" do
          expect(provider.available?).to be true
        end
      end
    end
  end
end
