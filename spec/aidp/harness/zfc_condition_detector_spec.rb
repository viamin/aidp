# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/zfc_condition_detector"
require "aidp/harness/provider_factory"

RSpec.describe Aidp::Harness::ZfcConditionDetector do
  let(:config) do
    instance_double(Aidp::Harness::Configuration,
      # ZFC config
      zfc_decision_enabled?: false,
      zfc_decision_tier: "mini",
      zfc_decision_cache_ttl: nil,
      zfc_decision_confidence_threshold: 0.7,
      zfc_ab_testing_enabled?: false,
      zfc_ab_testing_config: {enabled: false, sample_rate: 0.1, log_comparisons: true},
      default_provider: "anthropic")
  end

  let(:provider_factory) { instance_double(Aidp::Harness::ProviderFactory) }
  let(:provider) { instance_double(AgentHarness::Providers::Base) }

  subject(:detector) { described_class.new(config, provider_factory: provider_factory) }

  before do
    allow(Aidp::Harness::ThinkingDepthManager).to receive(:new).and_return(
      instance_double(Aidp::Harness::ThinkingDepthManager,
        select_model_for_tier: ["anthropic", "claude-3-haiku-20240307", {}])
    )

    allow(provider_factory).to receive(:create_provider).and_return(provider)

    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_error)
  end

  describe "#initialize" do
    it "initializes with config and provider factory" do
      expect(detector.config).to eq(config)
      expect(detector.legacy_detector).to be_a(Aidp::Harness::ConditionDetector)
      expect(detector.ai_engine).to be_a(Aidp::Harness::AIDecisionEngine)
      expect(detector.stats).to eq({
        zfc_calls: 0,
        legacy_calls: 0,
        zfc_fallbacks: 0,
        agreements: 0,
        disagreements: 0,
        zfc_total_cost: 0.0
      })
    end
  end

  describe "#is_rate_limited?" do
    let(:result) { {error: "Rate limit exceeded. Please retry after 60 seconds.", message: "Rate limit exceeded"} }

    context "when ZFC is disabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(false)
      end

      it "uses legacy detector" do
        expect(detector.legacy_detector).to receive(:is_rate_limited?).with(result, "anthropic")

        detector.is_rate_limited?(result, "anthropic")
      end

      it "increments legacy call counter" do
        allow(detector.legacy_detector).to receive(:is_rate_limited?).and_return(true)

        detector.is_rate_limited?(result, "anthropic")

        expect(detector.stats[:legacy_calls]).to eq(1)
      end
    end

    context "when ZFC is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      end

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

      it "uses AI decision engine" do
        expect(detector.ai_engine).to receive(:decide).with(
          :condition_detection,
          hash_including(context: hash_including(:response))
        ).and_call_original

        detector.is_rate_limited?(result, "anthropic")
      end

      it "returns true when AI detects rate limit with high confidence" do
        decision = detector.is_rate_limited?(result, "anthropic")

        expect(decision).to be true
      end

      it "returns false when AI detects other condition" do
        allow(provider).to receive(:send_message).and_return(
          {condition: "success", confidence: 0.95}.to_json
        )

        decision = detector.is_rate_limited?(result, "anthropic")

        expect(decision).to be false
      end

      it "returns false when confidence is below threshold" do
        allow(provider).to receive(:send_message).and_return(
          {condition: "rate_limit", confidence: 0.5}.to_json
        )

        decision = detector.is_rate_limited?(result, "anthropic")

        expect(decision).to be false
      end

      it "increments ZFC call counter" do
        detector.is_rate_limited?(result, "anthropic")

        expect(detector.stats[:zfc_calls]).to eq(1)
        expect(detector.stats[:zfc_total_cost]).to be > 0
      end

      it "falls back to legacy on AI error" do
        allow(provider).to receive(:send_message).and_raise(StandardError, "AI unavailable")
        allow(detector.legacy_detector).to receive(:is_rate_limited?).and_return(true)

        expect(Aidp).to receive(:log_error).with(
          "zfc_condition_detector",
          /falling back to legacy/,
          hash_including(:error)
        )

        decision = detector.is_rate_limited?(result, "anthropic")

        expect(decision).to be true
        expect(detector.stats[:zfc_fallbacks]).to eq(1)
      end
    end

    context "when A/B testing is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
        allow(config).to receive(:zfc_ab_testing_enabled?).and_return(true)
      end

      let(:ai_response) do
        {condition: "rate_limit", confidence: 0.95}.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "compares ZFC vs legacy results" do
        allow(detector.legacy_detector).to receive(:is_rate_limited?).and_return(true)

        detector.is_rate_limited?(result, "anthropic")

        expect(detector.stats[:agreements]).to eq(1)
        expect(detector.stats[:disagreements]).to eq(0)
      end

      it "records disagreement when results differ" do
        allow(detector.legacy_detector).to receive(:is_rate_limited?).and_return(false)

        expect(Aidp).to receive(:log_debug).with(
          "zfc_ab_testing",
          "ZFC vs Legacy disagreement",
          hash_including(:method, :zfc_result, :legacy_result)
        )

        detector.is_rate_limited?(result, "anthropic")

        expect(detector.stats[:agreements]).to eq(0)
        expect(detector.stats[:disagreements]).to eq(1)
      end
    end
  end

  describe "#needs_user_feedback?" do
    let(:result) { {output: "What would you like me to do next? Please provide your preference.", message: "What would you like me to do next?"} }

    context "when ZFC is disabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(false)
      end

      it "uses legacy detector" do
        expect(detector.legacy_detector).to receive(:needs_user_feedback?).with(result)

        detector.needs_user_feedback?(result)
      end
    end

    context "when ZFC is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      end

      let(:ai_response) do
        {
          condition: "user_feedback_needed",
          confidence: 0.90,
          reasoning: "AI is asking for user preference"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "returns true when AI detects user feedback needed" do
        decision = detector.needs_user_feedback?(result)

        expect(decision).to be true
      end

      it "returns false when AI detects other condition" do
        allow(provider).to receive(:send_message).and_return(
          {condition: "success", confidence: 0.95}.to_json
        )

        decision = detector.needs_user_feedback?(result)

        expect(decision).to be false
      end
    end
  end

  describe "#is_work_complete?" do
    let(:result) do
      {
        output: "Here's the implementation:\n\ndef prime?(n)\n  return false if n < 2\n  (2..Math.sqrt(n)).none? { |i| n % i == 0 }\nend\n\nDone!",
        message: "Done!"
      }
    end
    let(:progress) { {task: "Write a function to check if number is prime"} }

    context "when ZFC is disabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:completion_detection).and_return(false)
      end

      it "uses legacy detector" do
        expect(detector.legacy_detector).to receive(:is_work_complete?).with(result, progress)

        detector.is_work_complete?(result, progress)
      end
    end

    context "when ZFC is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:completion_detection).and_return(true)
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

      it "uses AI decision engine" do
        expect(detector.ai_engine).to receive(:decide).with(
          :completion_detection,
          hash_including(
            context: hash_including(:response, :task_description)
          )
        ).and_call_original

        detector.is_work_complete?(result, progress)
      end

      it "returns true when AI detects completion with high confidence" do
        decision = detector.is_work_complete?(result, progress)

        expect(decision).to be true
      end

      it "returns false when AI detects incomplete work" do
        allow(provider).to receive(:send_message).and_return(
          {complete: false, confidence: 0.95}.to_json
        )

        decision = detector.is_work_complete?(result, progress)

        expect(decision).to be false
      end

      it "returns false when confidence is below threshold" do
        allow(provider).to receive(:send_message).and_return(
          {complete: true, confidence: 0.5}.to_json
        )

        decision = detector.is_work_complete?(result, progress)

        expect(decision).to be false
      end

      it "falls back to legacy on AI error" do
        allow(provider).to receive(:send_message).and_raise(StandardError, "AI unavailable")
        allow(detector.legacy_detector).to receive(:is_work_complete?).and_return(true)

        expect(Aidp).to receive(:log_error).with(
          "zfc_condition_detector",
          /falling back to legacy/,
          hash_including(:error)
        )

        decision = detector.is_work_complete?(result, progress)

        expect(decision).to be true
        expect(detector.stats[:zfc_fallbacks]).to eq(1)
      end
    end
  end

  describe "#extract_questions" do
    it "delegates to legacy detector" do
      result = {content: "What is your name? How can I help?"}

      expect(detector.legacy_detector).to receive(:extract_questions).with(result)

      detector.extract_questions(result)
    end
  end

  describe "#extract_rate_limit_info" do
    it "delegates to legacy detector" do
      result = {error: "Rate limit exceeded"}

      expect(detector.legacy_detector).to receive(:extract_rate_limit_info).with(result, "anthropic")

      detector.extract_rate_limit_info(result, "anthropic")
    end
  end

  describe "#statistics" do
    it "returns statistics with zero calls" do
      stats = detector.statistics

      expect(stats[:total_calls]).to eq(0)
      expect(stats[:accuracy]).to be_nil
    end

    it "calculates statistics after calls" do
      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      allow(provider).to receive(:send_message).and_return(
        {condition: "rate_limit", confidence: 0.95}.to_json
      )

      result = {error: "Rate limit"}

      # Make 3 ZFC calls and 2 legacy calls
      3.times { detector.is_rate_limited?(result) }

      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(false)
      2.times { detector.is_rate_limited?(result) }

      stats = detector.statistics

      expect(stats[:total_calls]).to eq(5)
      expect(stats[:zfc_calls]).to eq(3)
      expect(stats[:legacy_calls]).to eq(2)
      expect(stats[:zfc_percentage]).to eq(60.0)
      expect(stats[:zfc_total_cost]).to be > 0
    end

    it "calculates accuracy from A/B testing" do
      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      allow(config).to receive(:zfc_ab_testing_enabled?).and_return(true)
      allow(provider).to receive(:send_message).and_return(
        {condition: "rate_limit", confidence: 0.95}.to_json
      )
      allow(detector.legacy_detector).to receive(:is_rate_limited?).and_return(true, true, false)

      result = {error: "Rate limit"}

      3.times { detector.is_rate_limited?(result) }

      stats = detector.statistics

      expect(stats[:agreements]).to eq(2)
      expect(stats[:disagreements]).to eq(1)
      expect(stats[:accuracy]).to eq(66.67)
    end
  end

  describe "result text conversion" do
    it "handles string results" do
      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      allow(provider).to receive(:send_message).and_return(
        {condition: "success", confidence: 0.95}.to_json
      )

      detector.is_rate_limited?("Rate limit exceeded")

      # Should not raise error
      expect(detector.stats[:zfc_calls]).to eq(1)
    end

    it "handles hash results with :content" do
      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      allow(provider).to receive(:send_message).and_return(
        {condition: "success", confidence: 0.95}.to_json
      )

      detector.is_rate_limited?({content: "Success"})

      expect(detector.stats[:zfc_calls]).to eq(1)
    end

    it "handles hash results with :error" do
      allow(config).to receive(:zfc_decision_enabled?).with(:condition_detection).and_return(true)
      allow(provider).to receive(:send_message).and_return(
        {condition: "rate_limit", confidence: 0.95}.to_json
      )

      detector.is_rate_limited?({error: "Rate limit"})

      expect(detector.stats[:zfc_calls]).to eq(1)
    end
  end

  describe "#classify_error" do
    let(:test_error) { StandardError.new("Rate limit exceeded") }

    context "when ZFC is disabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:error_classification).and_return(false)
      end

      it "uses legacy detector" do
        expect(detector.legacy_detector).to receive(:classify_error).with(test_error)

        detector.classify_error(test_error)
      end
    end

    context "when ZFC is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:error_classification).and_return(true)
      end

      let(:ai_response) do
        {
          error_type: "rate_limit",
          retryable: true,
          recommended_action: "retry",
          confidence: 0.95,
          reasoning: "Error message explicitly mentions rate limit"
        }.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "uses AI decision engine" do
        expect(detector.ai_engine).to receive(:decide).with(
          :error_classification,
          hash_including(context: hash_including(:error_message))
        ).and_call_original

        detector.classify_error(test_error)
      end

      it "returns classification with AI results" do
        result = detector.classify_error(test_error)

        expect(result[:error_type]).to eq(:rate_limit)
        expect(result[:retryable]).to be true
        expect(result[:recommended_action]).to eq(:retry)
        expect(result[:confidence]).to eq(0.95)
        expect(result[:reasoning]).to eq("Error message explicitly mentions rate limit")
      end

      it "falls back to legacy when confidence is low" do
        allow(provider).to receive(:send_message).and_return(
          {error_type: "other", retryable: false, recommended_action: "fail", confidence: 0.3}.to_json
        )
        allow(detector.legacy_detector).to receive(:classify_error).and_return({error_type: :timeout})

        result = detector.classify_error(test_error)

        expect(result[:error_type]).to eq(:timeout)
      end

      it "increments ZFC call counter" do
        detector.classify_error(test_error)

        expect(detector.stats[:zfc_calls]).to eq(1)
      end

      it "falls back to legacy on AI error" do
        allow(provider).to receive(:send_message).and_raise(StandardError, "AI unavailable")
        allow(detector.legacy_detector).to receive(:classify_error).and_return({error_type: :rate_limit})

        expect(Aidp).to receive(:log_error).with(
          "zfc_condition_detector",
          /falling back to legacy/,
          hash_including(:error, :original_error)
        )

        result = detector.classify_error(test_error)

        expect(result[:error_type]).to eq(:rate_limit)
        expect(detector.stats[:zfc_fallbacks]).to eq(1)
      end
    end

    context "when A/B testing is enabled" do
      before do
        allow(config).to receive(:zfc_decision_enabled?).with(:error_classification).and_return(true)
        allow(config).to receive(:zfc_ab_testing_enabled?).and_return(true)
      end

      let(:ai_response) do
        {error_type: "rate_limit", retryable: true, recommended_action: "retry", confidence: 0.95}.to_json
      end

      before do
        allow(provider).to receive(:send_message).and_return(ai_response)
      end

      it "compares ZFC vs legacy results" do
        allow(detector.legacy_detector).to receive(:classify_error).and_return({error_type: :rate_limit})

        detector.classify_error(test_error)

        expect(detector.stats[:agreements]).to eq(1)
        expect(detector.stats[:disagreements]).to eq(0)
      end

      it "records disagreement when results differ" do
        allow(detector.legacy_detector).to receive(:classify_error).and_return({error_type: :timeout})

        expect(Aidp).to receive(:log_debug).with(
          "zfc_ab_testing",
          "Error classification disagreement",
          hash_including(:ai_error_type, :legacy_error_type)
        )

        detector.classify_error(test_error)

        expect(detector.stats[:agreements]).to eq(0)
        expect(detector.stats[:disagreements]).to eq(1)
      end
    end
  end
end
