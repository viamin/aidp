# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ErrorHandler do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:error_handler) { described_class.new(provider_manager, configuration, metrics_manager) }

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
      strategies = error_handler.instance_variable_get(:@retry_strategies)

      expect(strategies).to include(
        :network_error,
        :server_error,
        :timeout,
        :rate_limit,
        :authentication,
        :permission_denied,
        :default
      )
    end

    it "initializes helper components" do
      expect(error_handler.instance_variable_get(:@backoff_calculator)).to be_a(described_class::BackoffCalculator)
      expect(error_handler.instance_variable_get(:@error_classifier)).to be_a(described_class::ErrorClassifier)
      expect(error_handler.instance_variable_get(:@recovery_planner)).to be_a(described_class::RecoveryPlanner)
    end
  end

  describe "error handling" do
    let(:context) { {provider: "claude", model: "model1"} }

    it "handles network errors with retry" do
      error = Net::TimeoutError.new("Connection timeout")

      result = error_handler.handle_error(error, context)

      expect(result).to include(:success, :action, :retry_count, :delay, :strategy)
      expect(result[:strategy]).to eq("network_error")
    end

    it "handles rate limit errors without retry" do
      error = StandardError.new("Rate limit exceeded")
      allow(error_handler.instance_variable_get(:@error_classifier)).to receive(:classify_error).and_return({
        error: error,
        error_type: :rate_limit,
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

    it "handles authentication errors with escalation" do
      error = StandardError.new("Authentication failed")
      allow(error_handler.instance_variable_get(:@error_classifier)).to receive(:classify_error).and_return({
        error: error,
        error_type: :authentication,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: context,
        message: "Authentication failed"
      })

      result = error_handler.handle_error(error, context)

      expect(result[:action]).to eq(:escalated)
      expect(result[:requires_manual_intervention]).to be true
    end

    it "records error in metrics manager" do
      error = StandardError.new("Test error")

      expect(metrics_manager).to receive(:record_error).with("claude", "model1", anything)

      error_handler.handle_error(error, context)
    end

    it "adds error to error history" do
      error = StandardError.new("Test error")

      error_handler.handle_error(error, context)

      history = error_handler.get_error_history
      expect(history).not_to be_empty
      expect(history.last[:error]).to eq(error)
    end
  end

  describe "retry strategies" do
    it "gets retry strategy for error type" do
      strategy = error_handler.get_retry_strategy(:network_error)

      expect(strategy[:name]).to eq("network_error")
      expect(strategy[:enabled]).to be true
      expect(strategy[:max_retries]).to eq(3)
    end

    it "returns default strategy for unknown error type" do
      strategy = error_handler.get_retry_strategy(:unknown_error)

      expect(strategy[:name]).to eq("default")
      expect(strategy[:enabled]).to be true
    end

    it "determines if error should be retried" do
      error_info = {
        error_type: :network_error,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.get_retry_strategy(:network_error)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be true
    end

    it "does not retry rate limit errors" do
      error_info = {
        error_type: :rate_limit,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.get_retry_strategy(:rate_limit)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be false
    end

    it "does not retry authentication errors" do
      error_info = {
        error_type: :authentication,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.get_retry_strategy(:authentication)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be false
    end
  end

  describe "retry execution" do
    let(:error_info) do
      {
        error: StandardError.new("Test error"),
        error_type: :network_error,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: {},
        message: "Test error"
      }
    end

    it "executes retry with backoff delay" do
      strategy = error_handler.get_retry_strategy(:network_error)

      result = error_handler.execute_retry(error_info, strategy, {})

      expect(result).to include(:success, :action, :retry_count, :delay, :strategy)
      expect(result[:retry_count]).to eq(1)
      expect(result[:strategy]).to eq("network_error")
    end

    it "tracks retry counts per provider/model/error_type" do
      strategy = error_handler.get_retry_strategy(:network_error)

      # Execute retry twice
      error_handler.execute_retry(error_info, strategy, {})
      error_handler.execute_retry(error_info, strategy, {})

      status = error_handler.get_retry_status("claude", "model1")
      expect(status[:network_error][:retry_count]).to eq(2)
    end

    it "exhausts retries after max attempts" do
      strategy = error_handler.get_retry_strategy(:network_error)

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
        error_type: :rate_limit,
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
      timeout_error_info = error_info.merge(error_type: :timeout)

      result = error_handler.attempt_recovery(timeout_error_info, {})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch)
      expect(result[:new_model]).to eq("model2")
    end

    it "escalates authentication errors" do
      auth_error_info = error_info.merge(error_type: :authentication)

      result = error_handler.attempt_recovery(auth_error_info, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:escalated)
      expect(result[:requires_manual_intervention]).to be true
    end

    it "handles provider switch failure" do
      allow(provider_manager).to receive(:switch_provider_for_error).and_return(nil)

      result = error_handler.attempt_recovery(error_info, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:provider_switch_failed)
    end

    it "handles model switch failure" do
      allow(provider_manager).to receive(:switch_model_for_error).and_return(nil)
      timeout_error_info = error_info.merge(error_type: :timeout)

      result = error_handler.attempt_recovery(timeout_error_info, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:model_switch_failed)
    end
  end

  describe "circuit breaker" do
    it "opens circuit breaker for repeated failures" do
      error_info = {
        error: StandardError.new("Repeated failure"),
        error_type: :server_error,
        provider: "claude",
        model: "model1",
        timestamp: Time.now,
        context: {},
        message: "Repeated failure"
      }

      result = error_handler.open_circuit_breaker(error_info, {failure_count: 5, threshold: 5})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:circuit_breaker_opened)

      status = error_handler.get_circuit_breaker_status
      expect(status["claude:model1"][:open]).to be true
    end

    it "prevents retries when circuit breaker is open" do
      # Open circuit breaker
      error_info = {
        error_type: :server_error,
        provider: "claude",
        model: "model1"
      }

      error_handler.open_circuit_breaker(error_info, {failure_count: 5, threshold: 5})

      # Check if retry should be prevented
      strategy = error_handler.get_retry_strategy(:server_error)
      should_retry = error_handler.send(:should_retry?, error_info, strategy)

      expect(should_retry).to be false
    end

    it "resets circuit breaker after timeout" do
      # Open circuit breaker
      error_info = {
        error_type: :server_error,
        provider: "claude",
        model: "model1"
      }

      error_handler.open_circuit_breaker(error_info, {failure_count: 5, threshold: 5})

      # Simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 400)

      # Check if circuit breaker is now closed
      circuit_breaker_open = error_handler.send(:circuit_breaker_open?, "claude:model1")
      expect(circuit_breaker_open).to be false
    end

    it "resets specific circuit breaker" do
      # Open circuit breaker
      error_info = {
        error_type: :server_error,
        provider: "claude",
        model: "model1"
      }

      error_handler.open_circuit_breaker(error_info, {failure_count: 5, threshold: 5})

      # Reset circuit breaker
      error_handler.reset_circuit_breaker("claude", "model1")

      status = error_handler.get_circuit_breaker_status
      expect(status).not_to have_key("claude:model1")
    end

    it "resets all circuit breakers" do
      # Open multiple circuit breakers
      error_info1 = {error_type: :server_error, provider: "claude", model: "model1"}
      error_info2 = {error_type: :server_error, provider: "gemini", model: "model1"}

      error_handler.open_circuit_breaker(error_info1, {failure_count: 5, threshold: 5})
      error_handler.open_circuit_breaker(error_info2, {failure_count: 5, threshold: 5})

      # Reset all circuit breakers
      error_handler.reset_all_circuit_breakers

      status = error_handler.get_circuit_breaker_status
      expect(status).to be_empty
    end
  end

  describe "retry count management" do
    it "resets retry counts for specific provider/model" do
      # Generate some retry counts
      error_info = {
        error_type: :network_error,
        provider: "claude",
        model: "model1"
      }

      strategy = error_handler.get_retry_strategy(:network_error)
      error_handler.execute_retry(error_info, strategy, {})

      # Reset retry counts
      error_handler.reset_retry_counts("claude", "model1")

      status = error_handler.get_retry_status("claude", "model1")
      expect(status).to be_empty
    end

    it "resets retry counts for all models of a provider" do
      # Generate retry counts for multiple models
      error_info1 = {error_type: :network_error, provider: "claude", model: "model1"}
      error_info2 = {error_type: :network_error, provider: "claude", model: "model2"}

      strategy = error_handler.get_retry_strategy(:network_error)
      error_handler.execute_retry(error_info1, strategy, {})
      error_handler.execute_retry(error_info2, strategy, {})

      # Reset all retry counts for provider
      error_handler.reset_retry_counts("claude")

      status = error_handler.get_retry_status("claude")
      expect(status).to be_empty
    end
  end

  describe "error history management" do
    it "gets error history within time range" do
      # Add some errors
      error1 = StandardError.new("Error 1")
      error2 = StandardError.new("Error 2")

      error_handler.handle_error(error1, {provider: "claude", model: "model1"})
      sleep(0.01) # Ensure different timestamps
      error_handler.handle_error(error2, {provider: "claude", model: "model1"})

      # Get history within time range
      time_range = (Time.now - 1)..Time.now
      history = error_handler.get_error_history(time_range)

      expect(history.size).to eq(2)
    end

    it "clears error history" do
      # Add some errors
      error = StandardError.new("Test error")
      error_handler.handle_error(error, {provider: "claude", model: "model1"})

      # Clear history
      error_handler.clear_error_history

      history = error_handler.get_error_history
      expect(history).to be_empty
    end
  end

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

        expect(delay).to eq(3.0)
      end

      it "calculates fixed backoff" do
        delay = calculator.calculate_delay(3, :fixed, 2.0, 30.0)

        expect(delay).to eq(2.0)
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
        error = Net::TimeoutError.new("Connection timeout")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:timeout)
        expect(result[:error]).to eq(error)
      end

      it "classifies rate limit errors from HTTP status" do
        error = Net::HTTPError.new("429 Too Many Requests", nil)
        allow(error.response).to receive(:code).and_return("429")

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:rate_limit)
      end

      it "classifies authentication errors from HTTP status" do
        error = Net::HTTPError.new("401 Unauthorized", nil)
        allow(error.response).to receive(:code).and_return("401")

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:authentication)
      end

      it "classifies server errors from HTTP status" do
        error = Net::HTTPError.new("500 Internal Server Error", nil)
        allow(error.response).to receive(:code).and_return("500")

        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:server_error)
      end

      it "classifies network errors" do
        error = SocketError.new("Connection refused")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:network_error)
      end

      it "classifies errors by message content" do
        error = StandardError.new("Rate limit exceeded")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:rate_limit)
      end

      it "returns default for unknown errors" do
        error = StandardError.new("Unknown error")
        result = classifier.classify_error(error, {})

        expect(result[:error_type]).to eq(:default)
      end
    end

    describe "RecoveryPlanner" do
      let(:planner) { described_class::RecoveryPlanner.new }

      it "plans provider switch for rate limit errors" do
        error_info = {error_type: :rate_limit, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:reason]).to include("Rate limit")
      end

      it "plans model switch for timeout errors" do
        error_info = {error_type: :timeout, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_model)
        expect(plan[:reason]).to include("Timeout")
      end

      it "plans escalation for authentication errors" do
        error_info = {error_type: :authentication, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:escalate)
        expect(plan[:reason]).to include("Authentication")
      end

      it "plans provider switch for network errors" do
        error_info = {error_type: :network_error, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:reason]).to include("Network error")
      end

      it "plans provider switch for server errors" do
        error_info = {error_type: :server_error, provider: "claude", model: "model1"}

        plan = planner.create_recovery_plan(error_info, {})

        expect(plan[:action]).to eq(:switch_provider)
        expect(plan[:reason]).to include("Server error")
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
        error_type: :rate_limit,
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
end
