# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Gemini do
  let(:gemini) { described_class.new }
  let(:sample_prompt) { "Write a simple hello world program" }

  describe ".available?" do
    it "returns true when gemini command is available" do
      allow(Aidp::Util).to receive(:which).with("gemini").and_return("/usr/local/bin/gemini")

      expect(described_class.available?).to be(true)
    end

    it "returns false when gemini command is not available" do
      allow(Aidp::Util).to receive(:which).with("gemini").and_return(nil)

      expect(described_class.available?).to be(false)
    end
  end

  describe "#name" do
    it "returns gemini" do
      expect(gemini.name).to eq("gemini")
    end
  end

  describe "#display_name" do
    it "returns Google Gemini" do
      expect(gemini.display_name).to eq("Google Gemini")
    end
  end

  describe "#send" do
    let(:mock_result) { double("result", out: "Hello, World!", err: "", exit_status: 0) }

    before do
      allow(described_class).to receive(:available?).and_return(true)
      allow(gemini).to receive(:debug_execute_command).and_return(mock_result)
      allow(gemini).to receive(:debug_provider)
      allow(gemini).to receive(:debug_log)
      allow(gemini).to receive(:debug_command)
      allow(gemini).to receive(:display_message)
      # Short timeout accelerates any internal loops
      allow(gemini).to receive(:calculate_timeout).and_return(1)
      spinner_double = double("Spinner", auto_spin: nil, success: nil, error: nil, update: nil, stop: nil)
      allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
    end

    include_context "provider_thread_cleanup", "providers/gemini.rb"

    context "when gemini is available" do
      it "executes gemini command with correct arguments" do
        expect(gemini).to receive(:debug_execute_command).with(
          "gemini",
          hash_including(
            args: ["--print"],
            input: sample_prompt,
            timeout: anything,
            streaming: false
          )
        ).and_return(mock_result)

        result = gemini.send_message(prompt: sample_prompt)
        expect(result).to eq("Hello, World!")
      end

      it "returns the command output on success" do
        result = gemini.send_message(prompt: sample_prompt)
        expect(result).to eq("Hello, World!")
      end

      it "logs debug information" do
        expect(gemini).to receive(:debug_provider).with("gemini", "Starting execution", hash_including(:timeout))
        expect(gemini).to receive(:debug_log).with("📝 Sending prompt to gemini...", level: :info)
        expect(gemini).to receive(:debug_command).with("gemini", hash_including(args: ["--print"]))

        gemini.send_message(prompt: sample_prompt)
      end

      context "when streaming is enabled via AIDP_STREAMING" do
        before { ENV["AIDP_STREAMING"] = "1" }
        after { ENV.delete("AIDP_STREAMING") }

        it "enables streaming mode" do
          expect(gemini).to receive(:debug_execute_command).with(
            "gemini",
            hash_including(streaming: true)
          ).and_return(mock_result)

          expect(gemini).to receive(:display_message).with(
            /Display streaming enabled.*gemini CLI does not support true streaming/,
            type: :info
          )

          gemini.send_message(prompt: sample_prompt)
        end
      end

      context "when streaming is enabled via DEBUG" do
        before { ENV["DEBUG"] = "1" }
        after { ENV.delete("DEBUG") }

        it "enables streaming mode" do
          expect(gemini).to receive(:debug_execute_command).with(
            "gemini",
            hash_including(streaming: true)
          ).and_return(mock_result)

          expect(gemini).to receive(:display_message).with(
            /Display streaming enabled.*gemini CLI does not support true streaming/,
            type: :info
          )

          gemini.send_message(prompt: sample_prompt)
        end
      end
    end

    context "when gemini command fails" do
      let(:failed_result) { double("result", out: "", err: "API key invalid", exit_status: 1) }

      before do
        allow(gemini).to receive(:debug_execute_command).and_return(failed_result)
        allow(gemini).to receive(:debug_error)
      end

      it "raises an error with exit code and stderr" do
        expect { gemini.send_message(prompt: sample_prompt) }.to raise_error(/gemini failed with exit code 1: API key invalid/)
      end

      it "logs debug error" do
        expect(gemini).to receive(:debug_error).with(
          kind_of(StandardError),
          hash_including(exit_code: 1, stderr: "API key invalid")
        )

        expect { gemini.send_message(prompt: sample_prompt) }.to raise_error
      end
    end

    context "when gemini is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises an error" do
        expect { gemini.send_message(prompt: sample_prompt) }.to raise_error("gemini CLI not available")
      end
    end

    context "when an exception occurs" do
      before do
        allow(gemini).to receive(:debug_execute_command).and_raise(StandardError, "Network error")
        allow(gemini).to receive(:debug_error)
      end

      it "logs debug error and re-raises" do
        expect(gemini).to receive(:debug_error).with(
          kind_of(StandardError),
          hash_including(provider: "gemini", prompt_length: sample_prompt.length)
        )

        expect { gemini.send_message(prompt: sample_prompt) }.to raise_error("Network error")
      end
    end
  end

  describe "#calculate_timeout (private)" do
    before do
      allow(gemini).to receive(:display_message)
    end

    it "returns quick mode timeout when AIDP_QUICK_MODE is set" do
      ENV["AIDP_QUICK_MODE"] = "1"

      expect(gemini).to receive(:display_message).with(
        /Quick mode enabled.*2 minute timeout/,
        type: :highlight
      )

      timeout = gemini.__send__(:calculate_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_QUICK_MODE)

      ENV.delete("AIDP_QUICK_MODE")
    end

    it "returns environment override when AIDP_GEMINI_TIMEOUT is set" do
      ENV["AIDP_GEMINI_TIMEOUT"] = "600"

      timeout = gemini.__send__(:calculate_timeout)
      expect(timeout).to eq(600)

      ENV.delete("AIDP_GEMINI_TIMEOUT")
    end

    it "returns adaptive timeout when available" do
      allow(gemini).to receive(:get_adaptive_timeout).and_return(180)

      expect(gemini).to receive(:display_message).with(
        /Using adaptive timeout: 180 seconds/,
        type: :info
      )

      timeout = gemini.__send__(:calculate_timeout)
      expect(timeout).to eq(180)
    end

    it "returns default timeout when no overrides" do
      allow(gemini).to receive(:get_adaptive_timeout).and_return(nil)

      expect(gemini).to receive(:display_message).with(
        /Using default timeout.*5 minutes/,
        type: :info
      )

      timeout = gemini.__send__(:calculate_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DEFAULT)
    end
  end

  describe "#get_adaptive_timeout (private)" do
    after do
      ENV.delete("AIDP_CURRENT_STEP") if ENV["AIDP_CURRENT_STEP"]
    end

    it "returns repository analysis timeout for REPOSITORY_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "REPOSITORY_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REPOSITORY_ANALYSIS)
    end

    it "returns architecture analysis timeout for ARCHITECTURE_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "ARCHITECTURE_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_ARCHITECTURE_ANALYSIS)
    end

    it "returns test analysis timeout for TEST_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_TEST_ANALYSIS)
    end

    it "returns functionality analysis timeout for FUNCTIONALITY_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "FUNCTIONALITY_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_FUNCTIONALITY_ANALYSIS)
    end

    it "returns documentation analysis timeout for DOCUMENTATION_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "DOCUMENTATION_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DOCUMENTATION_ANALYSIS)
    end

    it "returns static analysis timeout for STATIC_ANALYSIS step" do
      ENV["AIDP_CURRENT_STEP"] = "STATIC_ANALYSIS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_STATIC_ANALYSIS)
    end

    it "returns refactoring timeout for REFACTORING_RECOMMENDATIONS step" do
      ENV["AIDP_CURRENT_STEP"] = "REFACTORING_RECOMMENDATIONS"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REFACTORING_RECOMMENDATIONS)
    end

    it "returns nil for unknown step" do
      ENV["AIDP_CURRENT_STEP"] = "UNKNOWN_STEP"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to be_nil
    end

    it "returns nil when no step is set" do
      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to be_nil
    end

    it "handles partial matches in step names" do
      ENV["AIDP_CURRENT_STEP"] = "SOME_REPOSITORY_ANALYSIS_TASK"

      timeout = gemini.__send__(:get_adaptive_timeout)
      expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REPOSITORY_ANALYSIS)
    end
  end
end
