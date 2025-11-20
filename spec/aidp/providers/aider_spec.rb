# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"
require_relative "../../../lib/aidp/providers/aider"

RSpec.describe Aidp::Providers::Aider do
  let(:test_prompt) { TestPrompt.new }
  let(:provider) { described_class.new(prompt: test_prompt) }

  describe ".available?" do
    context "when aider is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("aider").and_return("/usr/local/bin/aider")
      end

      it "returns true" do
        expect(described_class.available?).to be true
      end
    end

    context "when aider is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("aider").and_return(nil)
      end

      it "returns false" do
        expect(described_class.available?).to be false
      end
    end
  end

  describe ".supports_model_family?" do
    it "supports gpt models" do
      expect(described_class.supports_model_family?("gpt-4")).to be true
      expect(described_class.supports_model_family?("gpt-3.5-turbo")).to be true
    end

    it "supports claude models" do
      expect(described_class.supports_model_family?("claude-3-5-sonnet")).to be true
      expect(described_class.supports_model_family?("claude-3-opus")).to be true
    end

    it "supports gemini models" do
      expect(described_class.supports_model_family?("gemini-pro")).to be true
    end

    it "supports deepseek models" do
      expect(described_class.supports_model_family?("deepseek-coder")).to be true
    end

    it "supports qwen models" do
      expect(described_class.supports_model_family?("qwen-coder")).to be true
    end

    it "supports o1 models" do
      expect(described_class.supports_model_family?("o1-preview")).to be true
    end

    it "does not support unknown models" do
      expect(described_class.supports_model_family?("unknown-model")).to be false
    end
  end

  describe ".firewall_requirements" do
    it "returns required domains for aider" do
      requirements = described_class.firewall_requirements
      expect(requirements[:domains]).to include("aider.chat")
      expect(requirements[:domains]).to include("openrouter.ai")
      expect(requirements[:domains]).to include("api.openrouter.ai")
    end

    it "returns empty IP ranges" do
      requirements = described_class.firewall_requirements
      expect(requirements[:ip_ranges]).to eq([])
    end
  end

  describe "#name" do
    it "returns the correct provider name" do
      expect(provider.name).to eq("aider")
    end
  end

  describe "#display_name" do
    it "returns the correct display name" do
      expect(provider.display_name).to eq("Aider")
    end
  end

  describe "#available?" do
    context "when aider is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("aider").and_return("/usr/local/bin/aider")
        successful_result = double("result", exit_status: 0)
        allow(Aidp::Util).to receive(:execute_command)
          .with("aider", ["--version"], timeout: 10)
          .and_return(successful_result)
      end

      it "returns true" do
        expect(provider.available?).to be true
      end
    end

    context "when aider is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("aider").and_return(nil)
      end

      it "returns false" do
        expect(provider.available?).to be false
      end
    end
  end

  describe "#send_message" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Success output", err: "") }
    let(:failed_result) { double("result", exit_status: 1, out: "", err: "Error output") }

    before do
      # Mock external CLI availability check - default to available
      allow(Aidp::Util).to receive(:which).with("aider").and_return("/usr/local/bin/aider")
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

    context "when aider is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("aider").and_return(nil)
      end

      it "raises an error" do
        expect { provider.send_message(prompt: prompt) }.to raise_error("aider CLI not available")
      end
    end

    context "when aider is available" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
        allow(provider).to receive(:debug_execute_command).and_return(successful_result)
        allow(provider).to receive(:display_message)
        # Mock the thread to avoid actual threading
        thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
        allow(Thread).to receive(:new).and_return(thread_mock)
      end

      it "executes aider with --yes and --message flags" do
        provider.send_message(prompt: prompt)
        expect(provider).to have_received(:debug_execute_command)
          .with("aider", args: ["--yes", "--message", prompt, "--no-auto-commits"], timeout: 300)
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
            .to raise_error("aider failed with exit code 1: Error output")
        end

        it "marks as failed" do
          begin
            provider.send_message(prompt: prompt)
          rescue
            # Expected to raise
          end
          expect(provider).to have_received(:mark_failed)
            .with("aider failed with exit code 1")
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

        it "includes restore-chat-history flag in command" do
          provider.send_message(prompt: prompt, session: "test-session")
          expect(provider).to have_received(:debug_execute_command)
            .with("aider", args: ["--yes", "--message", prompt, "--no-auto-commits", "--restore-chat-history"], timeout: 300)
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
        .with("aider", args: ["--yes", "--message", prompt, "--no-auto-commits", "--restore-chat-history", "--model", "gpt-4"], timeout: 300)
    end

    it "includes auto-commits flag when specified" do
      options = {auto_commits: true}

      provider.send_with_options(prompt: prompt, **options)

      expect(provider).to have_received(:debug_execute_command)
        .with("aider", args: ["--yes", "--message", prompt, "--auto-commits"], timeout: 300)
    end

    it "disables auto-commits by default" do
      provider.send_with_options(prompt: prompt)

      expect(provider).to have_received(:debug_execute_command)
        .with("aider", args: ["--yes", "--message", prompt, "--no-auto-commits"], timeout: 300)
    end
  end

  describe "#harness_healthy?" do
    before do
      allow(Aidp::Util).to receive(:which).with("aider").and_return("/usr/local/bin/aider")
      allow(provider).to receive(:stuck?).and_return(false)
    end

    context "when help command succeeds" do
      before do
        successful_result = double("result", exit_status: 0)
        allow(Aidp::Util).to receive(:execute_command)
          .with("aider", ["--help"], timeout: 5)
          .and_return(successful_result)
      end

      it "returns true" do
        expect(provider.harness_healthy?).to be true
      end
    end

    context "when help command fails" do
      before do
        allow(Aidp::Util).to receive(:execute_command)
          .with("aider", ["--help"], timeout: 5)
          .and_raise(StandardError.new("Command failed"))
      end

      it "returns false" do
        expect(provider.harness_healthy?).to be false
      end
    end
  end

  describe "timeout calculation" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Success", err: "") }

    before do
      allow(Aidp::Util).to receive(:which).with("aider").and_return("/usr/local/bin/aider")
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_execute_command).and_return(successful_result)
      allow(provider).to receive(:setup_activity_monitoring)
      allow(provider).to receive(:record_activity)
      allow(provider).to receive(:mark_completed)
      allow(provider).to receive(:display_message)
      # Mock the thread to avoid actual threading
      thread_mock = double("Thread", alive?: true, kill: nil, join: nil)
      allow(Thread).to receive(:new).and_return(thread_mock)
    end

    context "with environment override" do
      before do
        ENV["AIDP_AIDER_TIMEOUT"] = "600"
        allow(provider).to receive(:calculate_timeout).and_call_original
      end

      after do
        ENV.delete("AIDP_AIDER_TIMEOUT")
      end

      it "uses the environment timeout value" do
        provider.send_message(prompt: prompt)
        expect(provider).to have_received(:debug_execute_command)
          .with("aider", args: ["--yes", "--message", prompt, "--no-auto-commits"], timeout: 600)
      end
    end
  end
end
