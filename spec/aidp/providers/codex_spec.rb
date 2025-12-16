# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"
require_relative "../../../lib/aidp/providers/codex"

RSpec.describe Aidp::Providers::Codex do
  let(:test_prompt) { TestPrompt.new }
  let(:provider) { described_class.new(prompt: test_prompt) }

  describe ".available?" do
    context "when codex is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("codex").and_return("/usr/local/bin/codex")
      end

      it "returns true" do
        expect(described_class.available?).to be true
      end
    end

    context "when codex is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("codex").and_return(nil)
      end

      it "returns false" do
        expect(described_class.available?).to be false
      end
    end
  end

  describe "#name" do
    it "returns the correct provider name" do
      expect(provider.name).to eq("codex")
    end
  end

  describe "#available?" do
    context "when codex is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("codex").and_return("/usr/local/bin/codex")
        successful_result = double("result", exit_status: 0)
        allow(Aidp::Util).to receive(:execute_command)
          .with("codex", ["--version"], timeout: 10)
          .and_return(successful_result)
      end

      it "returns true" do
        expect(provider.available?).to be true
      end
    end

    context "when codex is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("codex").and_return(nil)
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
      allow(Aidp::Util).to receive(:which).with("codex").and_return("/usr/local/bin/codex")
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

    context "when codex is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("codex").and_return(nil)
      end

      it "raises an error" do
        expect { provider.send_message(prompt: prompt) }.to raise_error("codex CLI not available")
      end
    end

    context "when codex is available" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
        allow(provider).to receive(:debug_execute_command).and_return(successful_result)
        allow(provider).to receive(:display_message)
        # Mock the thread to avoid actual threading
        thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
        allow(Thread).to receive(:new).and_return(thread_mock)
      end

      it "executes codex with exec mode" do
        provider.send_message(prompt: prompt)
        expect(provider).to have_received(:debug_execute_command)
          .with("codex", args: ["exec", prompt], timeout: 300)
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
            .to raise_error("codex failed with exit code 1: Error output")
        end

        it "marks as failed" do
          begin
            provider.send_message(prompt: prompt)
          rescue
            # Expected to raise
          end
          expect(provider).to have_received(:mark_failed)
            .with("codex failed with exit code 1")
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
            .with("codex", args: ["exec", prompt, "--session", "test-session"], timeout: 300)
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

    it "includes model when specified" do
      options = {
        model: "gpt-4",
        session: "test-session"
      }

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("codex", args: ["exec", prompt, "--session", "test-session", "--model", "gpt-4"], timeout: 300)
    end

    it "includes ask_for_approval flag when specified" do
      options = {ask_for_approval: true}

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("codex", args: ["exec", prompt, "--ask-for-approval"], timeout: 300)
    end

    it "combines multiple options" do
      options = {
        model: "gpt-4",
        session: "test-session",
        ask_for_approval: true
      }

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("codex", args: ["exec", prompt, "--session", "test-session", "--model", "gpt-4", "--ask-for-approval"], timeout: 300)
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

    context "when AIDP_CODEX_TIMEOUT is set" do
      around do |example|
        ENV["AIDP_CODEX_TIMEOUT"] = "600"
        example.run
        ENV.delete("AIDP_CODEX_TIMEOUT")
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
        # adaptive_timeout no longer caches, so no need to clear state
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
            .with("codex", ["--help"], timeout: 5)
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
          allow(Aidp::Util).to receive(:which).with("codex").and_return(nil)
        end

        it "returns false" do
          expect(provider.available?).to be false
        end
      end

      context "when version check fails" do
        before do
          allow(Aidp::Util).to receive(:which).with("codex").and_return("/usr/local/bin/codex")
          allow(Aidp::Util).to receive(:execute_command).and_raise(StandardError.new("Command failed"))
        end

        it "returns false" do
          expect(provider.available?).to be false
        end
      end

      context "when all checks pass" do
        before do
          allow(Aidp::Util).to receive(:which).with("codex").and_return("/usr/local/bin/codex")
          successful_result = double("result", exit_status: 0)
          allow(Aidp::Util).to receive(:execute_command)
            .with("codex", ["--version"], timeout: 10)
            .and_return(successful_result)
        end

        it "returns true" do
          expect(provider.available?).to be true
        end
      end
    end
  end
end
