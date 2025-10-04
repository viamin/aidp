# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Anthropic do
  let(:provider) { described_class.new }

  before do
    # Mock availability check
    allow(described_class).to receive(:available?).and_return(true)
    allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")
  end

  describe "#available?" do
    it "returns true when claude CLI is available" do
      expect(provider.available?).to be true
    end

    it "returns false when claude CLI is not available" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(provider.available?).to be false
    end
  end

  describe "#name" do
    it "returns the correct name" do
      expect(provider.name).to eq("anthropic")
    end
  end

  describe "#display_name" do
    it "returns the correct display name" do
      expect(provider.display_name).to eq("Anthropic Claude CLI")
    end
  end

  describe "#send" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Test response", err: "") }
    let(:failed_result) { double("result", exit_status: 1, out: "", err: "Error message") }

    before do
      allow(provider).to receive(:debug_execute_command).and_return(successful_result)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_error)
      allow(provider).to receive(:display_message)
      allow(provider).to receive(:calculate_timeout).and_return(300)
    end

    context "when streaming is disabled" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
      end

      it "uses text output format" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--output-format=text"],
          input: prompt,
          timeout: 300,
          streaming: false
        )
      end

      it "returns the output directly" do
        result = provider.send(prompt: prompt)
        expect(result).to eq("Test response")
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

      it "uses stream-json output format" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--verbose", "--output-format=stream-json", "--include-partial-messages"],
          input: prompt,
          timeout: 300,
          streaming: true
        )
      end

      it "shows true streaming message" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:display_message).with(
          "📺 True streaming enabled - real-time chunks from Claude API",
          type: :info
        )
      end

      it "parses stream-json output" do
        allow(successful_result).to receive(:out).and_return('{"type":"content_block_delta","delta":{"text":"Hello"}}')
        allow(provider).to receive(:parse_stream_json_output).and_return("Hello")

        provider.send(prompt: prompt)

        expect(provider).to have_received(:parse_stream_json_output).with('{"type":"content_block_delta","delta":{"text":"Hello"}}')
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

      it "uses stream-json output format" do
        provider.send(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--verbose", "--output-format=stream-json", "--include-partial-messages"],
          input: prompt,
          timeout: 300,
          streaming: true
        )
      end
    end

    context "when command fails" do
      before do
        allow(provider).to receive(:debug_execute_command).and_return(failed_result)
      end

      it "raises an error" do
        expect {
          provider.send(prompt: prompt)
        }.to raise_error(RuntimeError, "claude failed with exit code 1: Error message")
      end

      it "logs the error" do
        expect {
          provider.send(prompt: prompt)
        }.to raise_error

        expect(provider).to have_received(:debug_error).at_least(:once)
      end
    end
  end

  describe "#parse_stream_json_output" do
    context "with valid stream-json output" do
      it "extracts content from content_block_delta" do
        output = '{"type":"content_block_delta","delta":{"text":"Hello"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" world"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from message structure" do
        output = '{"message":{"content":[{"text":"Hello world"}]}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from array content structure" do
        output = '{"content":[{"text":"Hello"},{"text":" world"}]}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "handles string content in message" do
        output = '{"message":{"content":"Hello world"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end
    end

    context "with invalid JSON" do
      it "treats invalid JSON lines as plain text" do
        output = "Invalid JSON line\n" + '{"type":"content_block_delta","delta":{"text":"Valid"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Invalid JSON lineValid")
      end

      it "handles completely invalid JSON gracefully" do
        output = "Not JSON at all"

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Not JSON at all")
      end
    end

    context "with empty or nil input" do
      it "handles nil input" do
        result = provider.__send__(:parse_stream_json_output, nil)
        expect(result).to be_nil
      end

      it "handles empty input" do
        result = provider.__send__(:parse_stream_json_output, "")
        expect(result).to eq("")
      end
    end

    context "with mixed content" do
      it "combines multiple content blocks" do
        output = '{"type":"content_block_delta","delta":{"text":"First"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" second"}}' + "\n" \
          '{"message":{"content":"Third"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("First secondThird")
      end
    end

    context "when parsing fails" do
      it "returns original output on parsing error" do
        output = "Some output"
        allow(provider).to receive(:debug_log)

        # Temporarily stub JSON.parse to raise an error for this test
        original_parse = JSON.method(:parse)
        allow(JSON).to receive(:parse) do |*args|
          if args.first.include?("Some output")
            raise StandardError.new("Parse error")
          else
            original_parse.call(*args)
          end
        end

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Some output")
      end
    end
  end
end
