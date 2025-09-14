# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::Harness::CircuitBreakerManager do
  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:error_logger) { instance_double("Aidp::Harness::ErrorLogger") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:circuit_breaker_manager) { described_class.new(configuration, error_logger, metrics_manager) }

  before do
    # Mock configuration methods
    allow(configuration).to receive(:circuit_breaker_config).and_return({
      failure_threshold: 5,
      success_threshold: 3,
      timeout: 60,
      half_open_max_requests: 1,
      failure_rate_threshold: 0.5,
      minimum_requests: 10
    })
    allow(configuration).to receive(:configured_providers).and_return(["claude", "gemini", "cursor"])

    # Mock error logger methods
    allow(error_logger).to receive(:log_circuit_breaker_event)

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:record_request)
    allow(metrics_manager).to receive(:get_provider_metrics)
    allow(metrics_manager).to receive(:record_circuit_breaker_success)
    allow(metrics_manager).to receive(:record_circuit_breaker_failure)
  end

  describe "initialization" do
    it "creates circuit breaker manager successfully" do
      expect(circuit_breaker_manager).to be_a(described_class)
    end

    it "initializes circuit breaker configuration" do
      config = circuit_breaker_manager.instance_variable_get(:@circuit_breaker_config)

      expect(config).to include(
        :failure_threshold,
        :success_threshold,
        :timeout,
        :half_open_max_requests,
        :failure_rate_threshold,
        :minimum_requests
      )
    end

    it "initializes circuit breakers for configured providers" do
      circuit_breakers = circuit_breaker_manager.instance_variable_get(:@circuit_breakers)

      expect(circuit_breakers).to have_key("claude")
      expect(circuit_breakers).to have_key("gemini")
      expect(circuit_breakers).to have_key("cursor")
    end

    it "initializes helper components" do
      expect(circuit_breaker_manager.instance_variable_get(:@health_checker)).to be_a(described_class::HealthChecker)
      expect(circuit_breaker_manager.instance_variable_get(:@recovery_tester)).to be_a(described_class::RecoveryTester)
      expect(circuit_breaker_manager.instance_variable_get(:@state_notifier)).to be_a(described_class::StateNotifier)
    end
  end

  describe "circuit breaker state management" do
    it "starts with closed state" do
      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
    end

    it "allows execution when circuit breaker is closed" do
      expect(circuit_breaker_manager.can_execute?("claude")).to be true
    end

    it "tracks failure counts" do
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))

      status = circuit_breaker_manager.get_status("claude")
      expect(status[:failure_count]).to eq(1)
    end

    it "tracks success counts" do
      circuit_breaker_manager.record_success("claude")

      status = circuit_breaker_manager.get_status("claude")
      expect(status[:success_count]).to eq(1)
    end

    it "resets failure count on success when closed" do
      # Use configuration without failure rate threshold for this test
      allow(configuration).to receive(:circuit_breaker_config).and_return({
        failure_threshold: 5,
        success_threshold: 3,
        timeout: 60,
        half_open_max_requests: 1,
        failure_rate_threshold: 0,  # Disable failure rate threshold
        minimum_requests: 10
      })

      # Create a new circuit breaker manager with the updated configuration
      test_circuit_breaker_manager = described_class.new(configuration, error_logger, metrics_manager)

      # Record some failures
      test_circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))
      test_circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))

      # Record success
      test_circuit_breaker_manager.record_success("claude")

      status = test_circuit_breaker_manager.get_status("claude")
      expect(status[:failure_count]).to eq(0)
    end
  end

  describe "circuit breaker opening" do
    before do
      # Configure circuit breaker with low threshold for testing
      circuit_breaker_manager.configure_circuit_breaker("claude", nil, {failure_threshold: 3})
    end

    it "opens circuit breaker when failure threshold is exceeded" do
      # Record failures up to threshold
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))

      expect(circuit_breaker_manager.get_state("claude")).to eq(:open)
    end

    it "prevents execution when circuit breaker is open" do
      # Open the circuit breaker
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")

      expect(circuit_breaker_manager.can_execute?("claude")).to be false
    end

    it "logs circuit breaker opening" do
      expect(error_logger).to receive(:log_circuit_breaker_event).with("claude", nil, :opened, "Test open", anything)

      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")
    end

    it "records state change in history" do
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")

      history = circuit_breaker_manager.get_history("claude")
      expect(history).not_to be_empty
      expect(history.last[:to_state]).to eq(:open)
      expect(history.last[:reason]).to eq("Test open")
    end
  end

  describe "circuit breaker recovery" do
    before do
      # Open circuit breaker
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")
    end

    it "allows execution after timeout when circuit breaker is open" do
      # Mock time to simulate timeout
      allow(Time).to receive(:now).and_return(Time.now + 61)

      expect(circuit_breaker_manager.can_execute?("claude")).to be true
    end

    it "transitions to half-open state after timeout" do
      # Mock time to simulate timeout
      allow(Time).to receive(:now).and_return(Time.now + 61)

      # Check if execution is allowed (this should trigger half-open transition)
      circuit_breaker_manager.can_execute?("claude")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:half_open)
    end

    it "closes circuit breaker after successful recovery" do
      # Transition to half-open
      circuit_breaker_manager.half_open_circuit_breaker("claude", nil, "Test half-open")

      # Record successes up to threshold
      circuit_breaker_manager.record_success("claude")
      circuit_breaker_manager.record_success("claude")
      circuit_breaker_manager.record_success("claude")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
    end

    it "reopens circuit breaker on failure during recovery" do
      # Transition to half-open
      circuit_breaker_manager.half_open_circuit_breaker("claude", nil, "Test half-open")

      # Record failure
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error"))

      expect(circuit_breaker_manager.get_state("claude")).to eq(:open)
    end
  end

  describe "manual circuit breaker control" do
    it "manually opens circuit breaker" do
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Manual open")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:open)
    end

    it "manually closes circuit breaker" do
      # Open first
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Manual open")

      # Then close
      circuit_breaker_manager.close_circuit_breaker("claude", nil, "Manual close")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
    end

    it "manually sets circuit breaker to half-open" do
      circuit_breaker_manager.half_open_circuit_breaker("claude", nil, "Manual half-open")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:half_open)
    end

    it "resets circuit breaker" do
      # Open circuit breaker
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")

      # Reset
      circuit_breaker_manager.reset_circuit_breaker("claude")

      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
    end

    it "resets all circuit breakers" do
      # Open some circuit breakers
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")
      circuit_breaker_manager.open_circuit_breaker("gemini", nil, "Test open")

      # Reset all
      circuit_breaker_manager.reset_all_circuit_breakers

      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
      expect(circuit_breaker_manager.get_state("gemini")).to eq(:closed)
    end
  end

  describe "circuit breaker status and statistics" do
    before do
      # Set up some test data
      circuit_breaker_manager.record_success("claude")
      circuit_breaker_manager.record_success("claude")
      circuit_breaker_manager.record_failure("gemini", nil, StandardError.new("Test error"))
      circuit_breaker_manager.open_circuit_breaker("cursor", nil, "Test open")
    end

    it "gets circuit breaker status" do
      status = circuit_breaker_manager.get_status("claude")

      expect(status).to include(
        :state,
        :failure_count,
        :success_count,
        :last_failure_time,
        :failure_threshold,
        :success_threshold,
        :timeout,
        :next_attempt_time,
        :health_score
      )
      expect(status[:state]).to eq(:closed)
      expect(status[:success_count]).to eq(2)
    end

    it "gets all circuit breaker states" do
      all_states = circuit_breaker_manager.get_all_states

      expect(all_states).to have_key("claude")
      expect(all_states).to have_key("gemini")
      expect(all_states).to have_key("cursor")
      expect(all_states["cursor"][:state]).to eq(:open)
    end

    it "gets circuit breaker statistics" do
      stats = circuit_breaker_manager.get_statistics

      expect(stats).to include(
        :total_circuit_breakers,
        :open_circuit_breakers,
        :half_open_circuit_breakers,
        :closed_circuit_breakers,
        :total_failures,
        :total_successes,
        :average_failure_rate,
        :most_failing_provider,
        :circuit_breaker_effectiveness
      )
      expect(stats[:total_circuit_breakers]).to eq(3)
      expect(stats[:open_circuit_breakers]).to eq(1)
      expect(stats[:closed_circuit_breakers]).to eq(2)
    end

    it "gets circuit breaker history" do
      history = circuit_breaker_manager.get_history("cursor")

      expect(history).not_to be_empty
      expect(history.last[:to_state]).to eq(:open)
    end
  end

  describe "circuit breaker configuration" do
    it "configures circuit breaker settings" do
      config = {
        failure_threshold: 10,
        success_threshold: 5,
        timeout: 120
      }

      circuit_breaker_manager.configure_circuit_breaker("claude", nil, config)

      status = circuit_breaker_manager.get_status("claude")
      expect(status[:failure_threshold]).to eq(10)
      expect(status[:success_threshold]).to eq(5)
      expect(status[:timeout]).to eq(120)
    end

    it "validates circuit breaker configuration" do
      invalid_config = {
        failure_threshold: -1,
        success_threshold: 0,
        timeout: -1
      }

      expect {
        circuit_breaker_manager.configure_circuit_breaker("claude", nil, invalid_config)
      }.to raise_error(ArgumentError)
    end

    it "logs configuration changes" do
      config = {failure_threshold: 10}

      expect(error_logger).to receive(:log_circuit_breaker_event).with("claude", nil, :configured, "Configuration updated", config)

      circuit_breaker_manager.configure_circuit_breaker("claude", nil, config)
    end
  end

  describe "health checking" do
    it "performs health check for circuit breaker" do
      health = circuit_breaker_manager.health_check("claude")

      expect(health).to include(:healthy, :reason)
      expect(health[:healthy]).to be true
    end

    it "reports unhealthy when circuit breaker is open and timeout not reached" do
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")

      health = circuit_breaker_manager.health_check("claude")

      expect(health[:healthy]).to be false
      expect(health[:reason]).to include("recovery timeout not reached")
    end

    it "reports healthy when circuit breaker is open and timeout reached" do
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")

      # Mock time to simulate timeout
      allow(Time).to receive(:now).and_return(Time.now + 61)

      health = circuit_breaker_manager.health_check("claude")

      expect(health[:healthy]).to be true
      expect(health[:reason]).to include("ready for recovery")
    end
  end

  describe "provider and model availability" do
    before do
      # Set up test scenario
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test open")
      circuit_breaker_manager.open_circuit_breaker("gemini", "model1", "Test open")
    end

    it "gets available providers excluding open circuit breakers" do
      providers = ["claude", "gemini", "cursor"]
      available = circuit_breaker_manager.get_available_providers(providers)

      expect(available).to include("cursor")
      expect(available).not_to include("claude")
    end

    it "gets available models excluding open circuit breakers" do
      models = ["model1", "model2", "model3"]
      available = circuit_breaker_manager.get_available_models("gemini", models)

      expect(available).to include("model2", "model3")
      expect(available).not_to include("model1")
    end
  end

  describe "model-specific circuit breakers" do
    it "creates separate circuit breakers for provider and model" do
      # Provider-level circuit breaker
      circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Provider error"))

      # Model-level circuit breaker
      circuit_breaker_manager.record_failure("claude", "model1", StandardError.new("Model error"))

      provider_status = circuit_breaker_manager.get_status("claude")
      model_status = circuit_breaker_manager.get_status("claude", "model1")

      expect(provider_status[:failure_count]).to eq(1)
      expect(model_status[:failure_count]).to eq(1)
    end

    it "allows execution when provider is open but model is closed" do
      # Open provider circuit breaker
      circuit_breaker_manager.open_circuit_breaker("claude", nil, "Provider open")

      # Model circuit breaker should still be closed
      expect(circuit_breaker_manager.can_execute?("claude", "model1")).to be true
    end

    it "prevents execution when model circuit breaker is open" do
      # Open model circuit breaker
      circuit_breaker_manager.open_circuit_breaker("claude", "model1", "Model open")

      expect(circuit_breaker_manager.can_execute?("claude", "model1")).to be false
    end
  end

  describe "failure rate threshold" do
    before do
      # Configure circuit breaker with failure rate threshold
      circuit_breaker_manager.configure_circuit_breaker("claude", nil, {
        failure_threshold: 100, # High threshold
        failure_rate_threshold: 0.5,
        minimum_requests: 10
      })
    end

    it "opens circuit breaker based on failure rate" do
      # Record 10 requests with 6 failures (60% failure rate)
      # First record some successes to meet minimum_requests threshold
      4.times { circuit_breaker_manager.record_success("claude") }

      # Then record 6 failures to exceed failure rate threshold
      6.times { circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error")) }

      # Check state after failures (should be open)
      expect(circuit_breaker_manager.get_state("claude")).to eq(:open)
    end

    it "does not open circuit breaker when failure rate is below threshold" do
      # Record 10 requests with 4 failures (40% failure rate)
      4.times { circuit_breaker_manager.record_failure("claude", nil, StandardError.new("Test error")) }
      6.times { circuit_breaker_manager.record_success("claude") }

      expect(circuit_breaker_manager.get_state("claude")).to eq(:closed)
    end
  end

  describe "metrics integration" do
    it "records success in metrics manager" do
      expect(metrics_manager).to receive(:record_circuit_breaker_success).with("claude", nil, :closed)

      circuit_breaker_manager.record_success("claude")
    end

    it "records failure in metrics manager" do
      error = StandardError.new("Test error")

      expect(metrics_manager).to receive(:record_circuit_breaker_failure).with("claude", nil, :closed, error)

      circuit_breaker_manager.record_failure("claude", nil, error)
    end
  end

  describe "helper classes" do
    describe "HealthChecker" do
      let(:health_checker) { described_class::HealthChecker.new }

      it "performs health checks" do
        health = health_checker.check_health("claude", "model1")

        expect(health).to include(:healthy, :response_time, :last_check)
        expect(health[:healthy]).to be true
      end

      it "calculates health scores" do
        score = health_checker.get_health_score("claude", "model1")

        expect(score).to be_a(Numeric)
        expect(score).to be_between(0, 1)
      end
    end

    describe "RecoveryTester" do
      let(:recovery_tester) { described_class::RecoveryTester.new }

      it "tests recovery" do
        result = recovery_tester.test_recovery("claude", "model1")

        expect(result).to include(:success, :response_time, :test_time)
        expect(result[:success]).to be true
      end

      it "determines if recovery should be attempted" do
        should_attempt = recovery_tester.should_attempt_recovery("claude", "model1")

        expect(should_attempt).to be true
      end
    end

    describe "StateNotifier" do
      let(:state_notifier) { described_class::StateNotifier.new }

      it "notifies state changes" do
        output = capture_stdout do
          state_notifier.notify_state_change("claude", "model1", :closed, :open, "Test")
        end
        expect(output).to match(/Circuit breaker state change/)
      end

      it "allows adding notifiers" do
        notifier = double("notifier")

        expect { state_notifier.add_notifier(notifier) }.not_to raise_error
      end
    end
  end

  describe "error handling" do
    it "handles missing configuration methods gracefully" do
      allow(configuration).to receive(:circuit_breaker_config).and_raise(NoMethodError)

      expect {
        described_class.new(configuration)
      }.to raise_error(NoMethodError)
    end

    it "handles missing error logger methods gracefully" do
      allow(error_logger).to receive(:log_circuit_breaker_event).and_raise(NoMethodError)

      expect {
        circuit_breaker_manager.open_circuit_breaker("claude", nil, "Test")
      }.to raise_error(NoMethodError)
    end

    it "handles missing metrics manager methods gracefully" do
      allow(metrics_manager).to receive(:record_circuit_breaker_success).and_raise(NoMethodError)

      expect {
        circuit_breaker_manager.record_success("claude")
      }.to raise_error(NoMethodError)
    end
  end
end
