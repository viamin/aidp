# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ai_decision_engine"
require "aidp/harness/thinking_depth_manager"
require "aidp/harness/provider_factory"

RSpec.describe Aidp::Harness::AIDecisionEngine do
  let(:config) do
    instance_double(Aidp::Harness::Configuration,
      default_tier: "mini",
      max_tier: "max",
      default_provider: "anthropic")
  end

  let(:provider_factory) { instance_double(Aidp::Harness::ProviderFactory) }
  let(:provider) { instance_double(Aidp::Providers::Base) }
  let(:thinking_manager) { instance_double(Aidp::Harness::ThinkingDepthManager) }

  subject(:engine) { described_class.new(config, provider_factory: provider_factory) }

  before do
    allow(Aidp::Harness::ThinkingDepthManager).to receive(:new)
      .and_return(thinking_manager)

    allow(thinking_manager).to receive(:select_model_for_tier)
      .and_return(["anthropic", "claude-3-haiku-20240307", {}])

    allow(provider_factory).to receive(:create_provider)
      .and_return(provider)

    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_error)
  end

  describe "#initialize" do
    it "initializes with config and provider factory" do
      expect(engine.config).to eq(config)
      expect(engine.provider_factory).to eq(provider_factory)
      expect(engine.cache).to eq({})
    end
  end

  describe "#decide" do
    context "with condition_detection decision type" do
      let(:context) { {response: "Error: Rate limit exceeded. Please retry later."} }

      let(:ai_response) do
        {
          condition: "rate_limit",
          confidence: 0.95,
          reasoning: "Message explicitly mentions rate limit"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "makes AI decision and returns structured result" do
        result = engine.decide(:condition_detection, context: context)

        expect(result).to be_a(Hash)
        expect(result[:condition]).to eq("rate_limit")
        expect(result[:confidence]).to eq(0.95)
        expect(result[:reasoning]).to be_a(String)
      end

      it "uses mini tier by default" do
        expect(thinking_manager).to receive(:select_model_for_tier).with("mini", provider: "anthropic")

        engine.decide(:condition_detection, context: context)
      end

      it "allows tier override" do
        expect(thinking_manager).to receive(:select_model_for_tier).with("thinking", provider: "anthropic")

        engine.decide(:condition_detection, context: context, tier: "thinking")
      end

      it "creates provider with correct parameters" do
        expect(provider_factory).to receive(:create_provider).with(
          "anthropic",
          hash_including(
            model: "claude-3-haiku-20240307"
          )
        )

        engine.decide(:condition_detection, context: context)
      end

      it "calls provider send_message" do
        expect(provider).to receive(:send_message).with(
          hash_including(
            prompt: String,
            session: nil
          )
        )

        engine.decide(:condition_detection, context: context)
      end

      it "logs decision making" do
        expect(Aidp).to receive(:log_debug).with(
          "ai_decision_engine",
          "making_decision",
          hash_including(
            decision_type: :condition_detection,
            tier: "mini",
            provider: "anthropic"
          )
        )

        engine.decide(:condition_detection, context: context)
      end
    end

    context "with error_classification decision type" do
      let(:context) do
        {
          error_message: "Connection timeout after 30 seconds",
          context: "Calling OpenAI API"
        }
      end

      let(:ai_response) do
        {
          error_type: "timeout",
          retryable: true,
          recommended_action: "retry",
          confidence: 0.90,
          reasoning: "Timeout errors are typically transient"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "classifies error correctly" do
        result = engine.decide(:error_classification, context: context)

        expect(result[:error_type]).to eq("timeout")
        expect(result[:retryable]).to be true
        expect(result[:recommended_action]).to eq("retry")
        expect(result[:confidence]).to eq(0.90)
      end
    end

    context "with completion_detection decision type" do
      let(:context) do
        {
          task_description: "Write a function to check if number is prime",
          response: "Here's the function:\n\ndef prime?(n)\n  return false if n < 2\n  (2..Math.sqrt(n)).none? { |i| n % i == 0 }\nend\n\nDone!"
        }
      end

      let(:ai_response) do
        {
          complete: true,
          confidence: 0.95,
          reasoning: "Function provided with implementation and completion marker"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "detects completion correctly" do
        result = engine.decide(:completion_detection, context: context)

        expect(result[:complete]).to be true
        expect(result[:confidence]).to eq(0.95)
      end
    end

    context "with unknown decision type" do
      it "raises ArgumentError" do
        expect {
          engine.decide(:unknown_type, context: {})
        }.to raise_error(ArgumentError, /Unknown decision type/)
      end
    end

    context "with caching" do
      let(:context) { {response: "Rate limit exceeded"} }

      let(:ai_response) do
        {
          condition: "rate_limit",
          confidence: 0.95,
          reasoning: "Rate limit detected"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "caches result when cache_ttl specified" do
        # First call - should hit AI
        expect(provider).to receive(:send_message).once

        result1 = engine.decide(:condition_detection, context: context, cache_ttl: 60)
        result2 = engine.decide(:condition_detection, context: context, cache_ttl: 60)

        expect(result1).to eq(result2)
      end

      it "logs cache hit" do
        engine.decide(:condition_detection, context: context, cache_ttl: 60)

        expect(Aidp).to receive(:log_debug).with(
          "ai_decision_engine",
          "cache_hit",
          hash_including(:cache_key, :ttl)
        )

        engine.decide(:condition_detection, context: context, cache_ttl: 60)
      end

      it "expires cache after TTL" do
        # First call
        engine.decide(:condition_detection, context: context, cache_ttl: 1)

        # Wait for cache to expire
        sleep 1.1

        # Second call should hit AI again
        expect(provider).to receive(:send_message).once

        engine.decide(:condition_detection, context: context, cache_ttl: 1)
      end

      it "doesn't cache when cache_ttl not specified" do
        expect(provider).to receive(:send_message).twice

        engine.decide(:condition_detection, context: context)
        engine.decide(:condition_detection, context: context)
      end
    end

    context "with schema validation" do
      let(:context) { {response: "Rate limit"} }

      it "validates required fields" do
        allow(provider).to receive(:send_message).and_return(
          {confidence: 0.9}.to_json  # Missing 'condition' field
        )

        expect {
          engine.decide(:condition_detection, context: context)
        }.to raise_error(Aidp::Harness::ValidationError, /Missing required field: condition/)
      end

      it "validates field types" do
        allow(provider).to receive(:send_message).and_return(
          {
            condition: "rate_limit",
            confidence: "high"  # Should be number
          }.to_json
        )

        expect {
          engine.decide(:condition_detection, context: context)
        }.to raise_error(Aidp::Harness::ValidationError, /must be number/)
      end

      it "validates enum values" do
        allow(provider).to receive(:send_message).and_return(
          {
            condition: "invalid_condition",  # Not in enum
            confidence: 0.9
          }.to_json
        )

        expect {
          engine.decide(:condition_detection, context: context)
        }.to raise_error(Aidp::Harness::ValidationError, /must be one of/)
      end

      it "validates number ranges" do
        allow(provider).to receive(:send_message).and_return(
          {
            condition: "rate_limit",
            confidence: 1.5  # Outside 0.0-1.0 range
          }.to_json
        )

        expect {
          engine.decide(:condition_detection, context: context)
        }.to raise_error(Aidp::Harness::ValidationError, /must be <=/)
      end

      it "validates boolean types" do
        allow(provider).to receive(:send_message).and_return(
          {
            error_type: "timeout",
            retryable: "yes",  # Should be boolean
            recommended_action: "retry",
            confidence: 0.9
          }.to_json
        )

        expect {
          engine.decide(:error_classification, context: {error_message: "timeout", context: ""})
        }.to raise_error(Aidp::Harness::ValidationError, /must be boolean/)
      end
    end

    context "with invalid AI response" do
      let(:context) { {response: "Error"} }

      it "handles non-JSON response" do
        allow(provider).to receive(:send_message).and_return("This is not JSON")

        expect(Aidp).to receive(:log_error).with(
          "ai_decision_engine",
          "json_parse_failed",
          hash_including(:error)
        )

        expect {
          engine.decide(:condition_detection, context: context)
        }.to raise_error(Aidp::Harness::ValidationError, /not valid JSON/)
      end

      it "extracts JSON from wrapped response" do
        allow(provider).to receive(:send_message).and_return(
          "Here's the result: {\"condition\":\"rate_limit\",\"confidence\":0.95} - done!"
        )

        result = engine.decide(:condition_detection, context: context)

        expect(result[:condition]).to eq("rate_limit")
        expect(result[:confidence]).to eq(0.95)
      end
    end

    context "with custom schema" do
      let(:context) { {response: "Test"} }

      let(:custom_schema) do
        {
          type: "object",
          properties: {
            result: {type: "string"}
          },
          required: ["result"]
        }
      end

      let(:ai_response) { {result: "success"}.to_json }

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "uses custom schema when provided" do
        result = engine.decide(:condition_detection,
          context: context,
          schema: custom_schema)

        expect(result[:result]).to eq("success")
      end
    end
  end

  describe "TEMPLATE_PATHS" do
    it "has condition_detection template path" do
      expect(described_class::TEMPLATE_PATHS[:condition_detection]).to eq("decision_engine/condition_detection")
    end

    it "has error_classification template path" do
      expect(described_class::TEMPLATE_PATHS[:error_classification]).to eq("decision_engine/error_classification")
    end

    it "has completion_detection template path" do
      expect(described_class::TEMPLATE_PATHS[:completion_detection]).to eq("decision_engine/completion_detection")
    end
  end

  describe "#available_decision_types" do
    it "returns all available decision types" do
      types = engine.available_decision_types

      expect(types).to include(:condition_detection)
      expect(types).to include(:error_classification)
      expect(types).to include(:completion_detection)
    end
  end
end
