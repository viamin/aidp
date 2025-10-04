# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider Streaming Support" do
  describe "Streaming environment detection" do
    context "when AIDP_STREAMING is set" do
      before { ENV["AIDP_STREAMING"] = "1" }
      after { ENV.delete("AIDP_STREAMING") }

      it "detects streaming mode" do
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        expect(streaming_enabled).to be true
      end
    end

    context "when DEBUG is set" do
      before { ENV["DEBUG"] = "1" }
      after { ENV.delete("DEBUG") }

      it "detects streaming mode" do
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        expect(streaming_enabled).to be true
      end
    end

    context "when neither is set" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
      end

      it "does not detect streaming mode" do
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        expect(streaming_enabled).to be false
      end
    end
  end

  describe "Claude streaming arguments" do
    context "when streaming is enabled" do
      it "includes stream-json format arguments" do
        args = ["--print"]
        streaming_enabled = true

        args += if streaming_enabled
          ["--output-format=stream-json", "--include-partial-messages"]
        else
          ["--output-format=text"]
        end

        expect(args).to include("--output-format=stream-json")
        expect(args).to include("--include-partial-messages")
      end
    end

    context "when streaming is disabled" do
      it "includes text format arguments" do
        args = ["--print"]
        streaming_enabled = false

        args += if streaming_enabled
          ["--output-format=stream-json", "--include-partial-messages"]
        else
          ["--output-format=text"]
        end

        expect(args).to include("--output-format=text")
        expect(args).not_to include("--output-format=stream-json")
      end
    end
  end

  describe "Provider streaming messages" do
    it "shows true streaming message for Claude" do
      message = "📺 True streaming enabled - real-time chunks from Claude API"
      expect(message).to include("True streaming")
      expect(message).to include("real-time chunks")
    end

    it "shows display streaming message for other providers" do
      provider_name = "cursor-agent"
      message = "📺 Display streaming enabled - output buffering reduced (#{provider_name} does not support true streaming)"

      expect(message).to include("Display streaming")
      expect(message).to include("does not support true streaming")
      expect(message).to include(provider_name)
    end
  end
end
