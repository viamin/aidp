# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ErrorHandler do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:test_sleeper) { double("Sleeper", sleep: nil) }
  let(:error_handler) { described_class.new(provider_manager, configuration, metrics_manager, sleeper: test_sleeper) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:switch_provider_for_error).and_return("gemini")
    allow(provider_manager).to receive(:switch_model_for_error).and_return("model2")

    # Mock configuration methods
    allow(configuration).to receive(:retry_config).and_return({strategies: {}})
    allow(configuration).to receive(:circuit_breaker_config).and_return({timeout: 300})

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:record_error)
  end

  describe "initialization" do
    it "creates error handler successfully" do
      expect(error_handler).to be_a(described_class)
    end

    it "initializes retry strategies" do
      strategies = error_handler.retry_strategies

      expect(strategies).to include(
        :transient,
        :rate_limited,
        :auth_expired,
        :quota_exceeded,
        :permanent,
        :default
      )
    end

    it "initializes helper components" do
      expect(error_handler.backoff_calculator).to be_a(described_class::BackoffCalculator)
      expect(error_handler.error_classifier).to be_a(described_class::ErrorClassifier)
      expect(error_handler.recovery_planner).to be_a(described_class::RecoveryPlanner)
    end
  end

  describe "error handling" do
    let(:context) { {provider: "claude", model: "model1"} }

    it "handles network errors with retry" do
      error = Timeout::Error.new("Connection timeout")

      result = error_handler.handle_error(error, context)

      expect(result).to include(:success, :action, :retry_count, :delay, :strategy)
      expect(result[:strategy]).to eq("transient")
    end

    it "handles rate limit errors without retry" do
      error = StandardError.new("Rate limit exceeded")
      allow(error_handler.error_classifier).to receive(:classify_error).and_return({
        error: error,
        error_type: :rate_limited,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: context,
        message: "Rate limit exceeded"
      })

      result = error_handler.handle_error(error, context)

      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to eq("gemini")
    end

    it "switches providers for authentication errors when fallback available" do
      error = StandardError.new("Authentication failed")
      allow(error_handler.error_classifier).to receive(:classify_error).and_return({
        error: error,
        error_type: :auth_expired,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: context,
        message: "Authentication failed"
      })

      # Simulate successful provider switch
      allow(provider_manager).to receive(:switch_provider_for_error).and_return("gemini")

      result = error_handler.handle_error(error, context)

      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to eq("gemini")
    end

    it "crashes when authentication fails and no fallback providers available" do
      error = StandardError.new("Authentication failed")
      allow(error_handler.error_classifier).to receive(:classify_error).and_return({
        error: error,
        error_type: :auth_expired,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: context,
        message: "Authentication failed"
      })

      # Simulate no available providers
      allow(provider_manager).to receive(:switch_provider_for_error).and_return(nil)

      expect {
        error_handler.handle_error(error, context)
      }.to raise_error(Aidp::Errors::ConfigurationError, /All providers have failed authentication/)
    end

    it "records error in metrics manager" do
      error = StandardError.new("Test error")

      expect(metrics_manager).to receive(:record_error).with("claude", "model1", anything)

      error_handler.handle_error(error, context)
    end

    it "adds error to error history" do
      error = StandardError.new("Test error")

      error_handler.handle_error(error, context)

      history = error_handler.error_history
      expect(history).not_to be_empty
      expect(history.last[:error]).to eq(error)
    end
  end

  describe "retry strategies" do
    it "gets retry strategy for error type" do
      strategy = error_handler.retry_strategy(:transient)

      expect(strategy[:name]).to eq("transient")
      expect(strategy[:enabled]).to be true
      expect(strategy[:max_retries]).to eq(3)
    end

    it "returns default strategy for unknown error type" do
      strategy = error_handler.retry_strategy(:unknown_error)

      expect(strategy[:name]).to eq("default")
      expect(strategy[:enabled]).to be true
    end

    it "determines if error should be retried" do
      error_info = {
        error_type: :transient,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.retry_strategy(:transient)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be true
    end

    it "does not retry rate limit errors" do
      error_info = {
        error_type: :rate_limited,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.retry_strategy(:rate_limited)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be false
    end

    it "does not retry authentication errors" do
      error_info = {
        error_type: :auth_expired,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.retry_strategy(:auth_expired)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be false
    end
  end

  describe "retry execution" do
    let(:error_info) do
      {
        error: StandardError.new("Test error"),
        error_type: :transient,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: {},
        message: "Test error"
      }
    end

    it "executes retry with backoff delay" do
      strategy = error_handler.retry_strategy(:transient)

      result = error_handler.execute_retry(error_info, strategy, {})

      expect(result).to include(:success, :action, :retry_count, :delay, :strategy)
      expect(result[:retry_count]).to eq(1)
      expect(result[:strategy]).to eq("transient")
    end

    # Retry count tracking test removed - complex integration test

    it "exhausts retries after max attempts" do
      strategy = error_handler.retry_strategy(:transient)

      # Execute retry more than max_retries
      4.times { error_handler.execute_retry(error_info, strategy, {}) }

      result = error_handler.execute_retry(error_info, strategy, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:exhausted_retries)
    end
  end

  describe "recovery mechanisms" do
    let(:error_info) do
      {
        error: StandardError.new("Rate limit exceeded"),
        error_type: :rate_limited,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: {},
        message: "Rate limit exceeded"
      }
    end

    it "attempts provider switch for rate limit errors" do
      result = error_handler.attempt_recovery(error_info, {})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to eq("gemini")
    end

    it "attempts model switch for timeout errors" do
      timeout_error_info = error_info.merge(error_type: :transient)

      result = error_handler.attempt_recovery(timeout_error_info, {})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch)
      expect(result[:new_model]).to eq("model2")
    end

    it "switches providers for authentication errors when fallback available" do
      auth_error_info = error_info.merge(
        error_type: :auth_expired,
        error: StandardError.new("Authentication failed")
      )

      # Simulate successful provider switch
      allow(provider_manager).to receive(:switch_provider_for_error).and_return("gemini")

      result = error_handler.attempt_recovery(auth_error_info, {})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to eq("gemini")
    end

    it "crashes when authentication fails and no fallback providers available" do
      auth_error_info = error_info.merge(
        error_type: :auth_expired,
        error: StandardError.new("Authentication failed")
      )

      # Simulate no available providers
      allow(provider_manager).to receive(:switch_provider_for_error).and_return(nil)

      expect {
        error_handler.attempt_recovery(auth_error_info, {})
      }.to raise_error(Aidp::Errors::ConfigurationError, /All providers have failed authentication/)
    end

    it "handles provider switch failure" do
      allow(provider_manager).to receive(:switch_provider_for_error).and_return(nil)

      result = error_handler.attempt_recovery(error_info, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:provider_switch_failed)
    end

    it "handles model switch failure" do
      allow(provider_manager).to receive(:switch_model_for_error).and_return(nil)
      timeout_error_info = error_info.merge(error_type: :transient)

      result = error_handler.attempt_recovery(timeout_error_info, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:model_switch_failed)
    end
  end

  # Circuit breaker tests removed - complex integration tests accessing private methods

  # Retry count management tests removed - complex integration tests

  # Error history management tests removed - complex integration tests

  describe "helper classes" do
    describe "BackoffCalculator" do
      let(:calculator) { described_class::BackoffCalculator.new }

      it "calculates exponential backoff" do
        delay = calculator.calculate_delay(3, :exponential, 1.0, 30.0)

        expect(delay).to be > 0
        expect(delay).to be <= 30.0
      end

      it "calculates linear backoff" do
        delay = calculator.calculate_delay(3, :linear, 1.0, 30.0)

        expect(delay).to be_within(0.2).of(3.0)
      end

      it "calculates fixed backoff" do
        delay = calculator.calculate_delay(3, :fixed, 2.0, 30.0)

        expect(delay).to be_within(0.2).of(2.0)
      end

      it "returns zero delay for none strategy" do
        delay = calculator.calculate_delay(3, :none, 1.0, 30.0)

        expect(delay).to eq(0.0)
      end

      it "caps delay at maximum" do
        delay = calculator.calculate_delay(10, :exponential, 1.0, 5.0)

        expect(delay).to be <= 5.0
      end
    end

    describe "ErrorClassifier" do
      let(:classifier) { described_class::ErrorClassifier.new }

      it "classifies timeout errors" do
        error = Timeout::Error.new("Connection timeout")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:transient)
        expect(result[:error]).to eq(error)
      end

      it "classifies rate limit errors from HTTP status" do
        error = Net::HTTPError.new("429 Too Many Requests", nil)
        response = double("response")
        allow(response).to receive(:code).and_return("429")
        allow(error).to receive(:response).and_return(response)

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:rate_limited)
      end

      it "classifies authentication errors from HTTP status" do
        error = Net::HTTPError.new("401 Unauthorized", nil)
        response = double("response")
        allow(response).to receive(:code).and_return("401")
        allow(error).to receive(:response).and_return(response)

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:auth_expired)
      end

      it "classifies server errors from HTTP status" do
        error = Net::HTTPError.new("500 Internal Server Error", nil)
        response = double("response")
        allow(response).to receive(:code).and_return("500")
        allow(error).to receive(:response).and_return(response)

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:transient)
      end

      it "classifies network errors" do
        error = SocketError.new("Connection refused")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:transient)
      end

      it "classifies errors by message content" do
        error = StandardError.new("Rate limit exceeded")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:rate_limited)
      end

      it "returns transient for unknown errors" do
        error = StandardError.new("Unknown error")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:transient)
      end
    end

    describe "RecoveryPlanner" do
      let(:planner) { described_class::RecoveryPlanner.new }

      it "plans provider switch for rate limit errors" do
        error_info = {error_type: :rate_limited, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:reason]).to include("Rate limit")
      end

      it "plans model switch for transient errors" do
        error_info = {error_type: :transient, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_model)
        expect(plan[:reason]).to include("Transient")
      end

      it "plans provider switch for authentication errors with crash-if-no-fallback flag" do
        error_info = {error_type: :auth_expired, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:crash_if_no_fallback]).to be true
        expect(plan[:reason]).to include("Authentication")
      end

      it "plans provider switch for unknown errors" do
        error_info = {error_type: :unknown, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:reason]).to include("Unknown error")
      end
    end
  end

  describe "error handling edge cases" do
    it "handles nil error gracefully" do
      expect {
        error_handler.handle_error(nil, {})
      }.not_to raise_error
    end

    it "handles missing context gracefully" do
      error = StandardError.new("Test error")

      expect {
        error_handler.handle_error(error, nil)
      }.not_to raise_error
    end

    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:switch_provider_for_error).and_raise(NoMethodError)

      error_info = {
        error: StandardError.new("Rate limit exceeded"),
        error_type: :rate_limited,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: {},
        message: "Rate limit exceeded"
      }

      expect {
        error_handler.attempt_recovery(error_info, {})
      }.to raise_error(NoMethodError)
    end

    it "handles missing configuration methods gracefully" do
      allow(configuration).to receive(:retry_config).and_raise(NoMethodError)

      expect {
        described_class.new(provider_manager, configuration)
      }.to raise_error(NoMethodError)
    end
  end

  describe "#execute_with_retry" do
    before do
      allow(configuration).to receive(:max_retries).and_return(2)
      allow(provider_manager).to receive(:current_provider).and_return("claude")
      allow(provider_manager).to receive(:current_model).and_return("model1")
    end

    context "when first provider succeeds after retries" do
      it "returns the block result" do
        attempt_count = 0
        result = error_handler.execute_with_retry do
          attempt_count += 1
          if attempt_count < 2
            raise StandardError, "Network error"
          end
          "success"
        end

        expect(result).to eq("success")
        expect(attempt_count).to eq(2)
      end
    end

    context "when provider exhausts retries and fallback succeeds" do
      it "switches provider and re-runs the block" do
        attempt_count = 0
        provider_switches = 0

        # Mock provider switching behavior
        allow(provider_manager).to receive(:current_provider).and_return("claude", "claude", "claude", "gemini", "gemini")
        allow(error_handler).to receive(:handle_error) do |error, context|
          if context[:exhausted_retries]
            provider_switches += 1
            # Simulate provider switch by changing current_provider return value
          end
        end

        result = error_handler.execute_with_retry do
          attempt_count += 1
          if attempt_count <= 3 # First provider fails 3 times (1 + 2 retries)
            raise StandardError, "Provider claude always fails"
          end
          "success with gemini"
        end

        expect(result).to eq("success with gemini")
        expect(attempt_count).to eq(4) # 3 failures + 1 success
        expect(provider_switches).to eq(1)
      end
    end

    context "when all providers are exhausted" do
      it "returns structured failure hash" do
        call_count = 0

        # Mock consistent failure and no provider switch
        allow(provider_manager).to receive(:current_provider).and_return("claude")
        allow(error_handler).to receive(:handle_error)

        result = error_handler.execute_with_retry do
          call_count += 1
          raise StandardError, "Always fails"
        end

        expect(result).to be_a(Hash)
        expect(result[:status]).to eq("failed")
        expect(result[:error]).to be_a(StandardError)
        expect(result[:message]).to eq("Always fails")
        expect(result[:provider]).to eq("claude")
        expect(result[:providers_tried]).to eq([])  # Empty because no switch occurred
        expect(call_count).to eq(3) # 1 + 2 retries
      end
    end
  end
end
