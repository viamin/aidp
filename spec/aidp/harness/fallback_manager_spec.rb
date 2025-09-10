# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::FallbackManager do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:fallback_manager) { described_class.new(provider_manager, configuration, metrics_manager) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:configured_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:get_provider_models).and_return(["model1", "model2"])
    allow(provider_manager).to receive(:set_current_provider).and_return(true)
    allow(provider_manager).to receive(:set_current_model).and_return(true)

    # Mock configuration methods
    allow(configuration).to receive(:fallback_config).and_return({ strategies: {} })

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:record_fallback_attempt)
  end

  describe "initialization" do
    it "creates fallback manager successfully" do
      expect(fallback_manager).to be_a(described_class)
    end

    it "initializes fallback strategies" do
      strategies = fallback_manager.instance_variable_get(:@fallback_strategies)

      expect(strategies).to include(
        :rate_limit,
        :network_error,
        :server_error,
        :timeout,
        :authentication,
        :permission_denied,
        :default
      )
    end

    it "initializes helper components" do
      expect(fallback_manager.instance_variable_get(:@circuit_breaker_manager)).to be_a(described_class::CircuitBreakerManager)
      expect(fallback_manager.instance_variable_get(:@load_balancer)).to be_a(described_class::LoadBalancer)
      expect(fallback_manager.instance_variable_get(:@health_monitor)).to be_a(described_class::HealthMonitor)
    end
  end

  describe "retry exhaustion handling" do
    let(:context) { { retry_count: 3, error_message: "Max retries exceeded" } }

    it "handles retry exhaustion with provider switch" do
      result = fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, context)

      expect(result).to include(:success, :action, :new_provider, :reason, :fallback_info, :strategy)
      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to be_in(["gemini", "cursor"])
    end

    it "handles retry exhaustion with model switch for timeout errors" do
      result = fallback_manager.handle_retry_exhaustion("claude", "model1", :timeout, context)

      expect(result).to include(:success, :action, :provider, :new_model, :reason, :fallback_info, :strategy)
      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch)
      expect(result[:provider]).to eq("claude")
      expect(result[:new_model]).to eq("model2")
    end

    it "handles retry exhaustion with escalation for authentication errors" do
      result = fallback_manager.handle_retry_exhaustion("claude", "model1", :authentication, context)

      expect(result).to include(:success, :action, :error, :escalation_reason, :fallback_info, :strategy)
      expect(result[:success]).to be false
      expect(result[:action]).to eq(:escalated)
      expect(result[:requires_manual_intervention]).to be true
    end

    it "records fallback attempt in metrics manager" do
      expect(metrics_manager).to receive(:record_fallback_attempt).with(anything)

      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, context)
    end

    it "adds fallback to history" do
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, context)

      history = fallback_manager.get_fallback_history
      expect(history).not_to be_empty
      expect(history.last[:provider]).to eq("claude")
      expect(history.last[:model]).to eq("model1")
      expect(history.last[:error_type]).to eq(:network_error)
    end

    it "marks provider as exhausted" do
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, context)

      expect(fallback_manager.provider_exhausted?("claude", :network_error)).to be true
    end

    it "marks model as exhausted" do
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, context)

      expect(fallback_manager.model_exhausted?("claude", "model1", :network_error)).to be true
    end
  end

  describe "fallback strategies" do
    it "gets fallback strategy for error type" do
      strategy = fallback_manager.get_fallback_strategy(:rate_limit)

      expect(strategy[:name]).to eq("rate_limit")
      expect(strategy[:action]).to eq(:switch_provider)
      expect(strategy[:priority]).to eq(:high)
    end

    it "returns default strategy for unknown error type" do
      strategy = fallback_manager.get_fallback_strategy(:unknown_error)

      expect(strategy[:name]).to eq("default")
      expect(strategy[:action]).to eq(:switch_provider)
    end

    it "applies context modifications to strategy" do
      context = { priority: :critical, max_attempts: 5 }
      strategy = fallback_manager.get_fallback_strategy(:rate_limit, context)

      expect(strategy[:priority]).to eq(:critical)
      expect(strategy[:max_attempts]).to eq(5)
    end

    it "uses context-specific fallback strategy" do
      context = { fallback_strategy: :custom_strategy }
      allow(fallback_manager).to receive(:configure_fallback_strategies).with({
        custom_strategy: { name: "custom", action: :escalate }
      })

      fallback_manager.configure_fallback_strategies({
        custom_strategy: { name: "custom", action: :escalate }
      })

      strategy = fallback_manager.get_fallback_strategy(:rate_limit, context)
      expect(strategy[:name]).to eq("custom")
      expect(strategy[:action]).to eq(:escalate)
    end
  end

  describe "exhaustion status management" do
    before do
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})
    end

    it "checks if provider is exhausted for specific error type" do
      expect(fallback_manager.provider_exhausted?("claude", :network_error)).to be true
      expect(fallback_manager.provider_exhausted?("claude", :rate_limit)).to be false
    end

    it "checks if provider is exhausted for any error type" do
      expect(fallback_manager.provider_exhausted?("claude")).to be true
      expect(fallback_manager.provider_exhausted?("gemini")).to be false
    end

    it "checks if model is exhausted for specific error type" do
      expect(fallback_manager.model_exhausted?("claude", "model1", :network_error)).to be true
      expect(fallback_manager.model_exhausted?("claude", "model1", :rate_limit)).to be false
    end

    it "checks if model is exhausted for any error type" do
      expect(fallback_manager.model_exhausted?("claude", "model1")).to be true
      expect(fallback_manager.model_exhausted?("claude", "model2")).to be false
    end

    it "resets provider exhaustion for specific error type" do
      fallback_manager.reset_provider_exhaustion("claude", :network_error)

      expect(fallback_manager.provider_exhausted?("claude", :network_error)).to be false
    end

    it "resets provider exhaustion for all error types" do
      fallback_manager.reset_provider_exhaustion("claude")

      expect(fallback_manager.provider_exhausted?("claude")).to be false
    end

    it "resets model exhaustion for specific error type" do
      fallback_manager.reset_model_exhaustion("claude", "model1", :network_error)

      expect(fallback_manager.model_exhausted?("claude", "model1", :network_error)).to be false
    end

    it "resets model exhaustion for all error types" do
      fallback_manager.reset_model_exhaustion("claude", "model1")

      expect(fallback_manager.model_exhausted?("claude", "model1")).to be false
    end

    it "resets all exhaustion status" do
      fallback_manager.reset_all_exhaustion

      expect(fallback_manager.provider_exhausted?("claude")).to be false
      expect(fallback_manager.model_exhausted?("claude", "model1")).to be false
    end
  end

  describe "available providers and models" do
    before do
      # Exhaust some providers and models
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})
    end

    it "gets available providers excluding exhausted ones" do
      available = fallback_manager.get_available_providers(:network_error)

      expect(available).not_to include("claude")
      expect(available).to include("gemini", "cursor")
    end

    it "gets available providers for specific error type" do
      available = fallback_manager.get_available_providers(:rate_limit)

      expect(available).to include("claude", "gemini", "cursor")
    end

    it "gets available models excluding exhausted ones" do
      available = fallback_manager.get_available_models("claude", :network_error)

      expect(available).not_to include("model1")
      expect(available).to include("model2")
    end

    it "gets available models for specific error type" do
      available = fallback_manager.get_available_models("claude", :rate_limit)

      expect(available).to include("model1", "model2")
    end
  end

  describe "fallback execution strategies" do
    let(:fallback_info) do
      {
        provider: "claude",
        model: "model1",
        error_type: :network_error,
        context: {},
        timestamp: Time.now,
        retry_count: 3
      }
    end

    it "executes provider switch fallback" do
      strategy = { name: "test", action: :switch_provider, selection_strategy: :round_robin }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
      expect(result[:new_provider]).to be_in(["gemini", "cursor"])
    end

    it "executes model switch fallback" do
      strategy = { name: "test", action: :switch_model, selection_strategy: :performance_based }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch)
      expect(result[:provider]).to eq("claude")
      expect(result[:new_model]).to eq("model2")
    end

    it "executes provider-model switch fallback" do
      strategy = { name: "test", action: :switch_provider_model, selection_strategy: :health_based }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch).or eq(:provider_switch)
    end

    it "executes load balanced switch fallback" do
      strategy = { name: "test", action: :load_balance, selection_strategy: :load_balanced }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:load_balanced_switch)
      expect(result[:new_provider]).to be_in(["gemini", "cursor"])
    end

    it "executes circuit breaker fallback" do
      strategy = { name: "test", action: :circuit_breaker, selection_strategy: :circuit_breaker_aware }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:circuit_breaker_fallback)
      expect(result[:new_provider]).to be_in(["gemini", "cursor"])
    end

    it "executes escalation fallback" do
      strategy = { name: "test", action: :escalate, selection_strategy: :none }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:escalated)
      expect(result[:requires_manual_intervention]).to be true
    end

    it "executes abort fallback" do
      strategy = { name: "test", action: :abort, selection_strategy: :none }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:aborted)
    end

    it "executes default fallback for unknown action" do
      strategy = { name: "test", action: :unknown_action, selection_strategy: :round_robin }

      result = fallback_manager.execute_fallback(fallback_info, strategy)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
    end
  end

  describe "fallback selection strategies" do
    let(:fallback_info) do
      {
        provider: "claude",
        model: "model1",
        error_type: :network_error,
        context: {},
        timestamp: Time.now,
        retry_count: 3
      }
    end

    it "selects provider using health-based strategy" do
      strategy = { selection_strategy: :health_based }
      available_providers = ["gemini", "cursor"]

      selected = fallback_manager.send(:select_provider, available_providers, strategy, fallback_info)

      expect(selected).to be_in(available_providers)
    end

    it "selects provider using load-balanced strategy" do
      strategy = { selection_strategy: :load_balanced }
      available_providers = ["gemini", "cursor"]

      selected = fallback_manager.send(:select_provider, available_providers, strategy, fallback_info)

      expect(selected).to be_in(available_providers)
    end

    it "selects provider using circuit-breaker-aware strategy" do
      strategy = { selection_strategy: :circuit_breaker_aware }
      available_providers = ["gemini", "cursor"]

      selected = fallback_manager.send(:select_provider, available_providers, strategy, fallback_info)

      expect(selected).to be_in(available_providers)
    end

    it "selects provider using performance-based strategy" do
      strategy = { selection_strategy: :performance_based }
      available_providers = ["gemini", "cursor"]

      selected = fallback_manager.send(:select_provider, available_providers, strategy, fallback_info)

      expect(selected).to be_in(available_providers)
    end

    it "selects provider using round-robin strategy" do
      strategy = { selection_strategy: :round_robin }
      available_providers = ["gemini", "cursor"]

      # Test multiple selections to verify round-robin behavior
      selections = []
      4.times do
        selected = fallback_manager.send(:select_provider, available_providers, strategy, fallback_info)
        selections << selected
      end

      expect(selections).to all(be_in(available_providers))
      # Should cycle through providers
      expect(selections[0]).to eq(selections[2])
      expect(selections[1]).to eq(selections[3])
    end

    it "selects model using performance-based strategy" do
      strategy = { selection_strategy: :performance_based }
      available_models = ["model2"]

      selected = fallback_manager.send(:select_model, available_models, strategy, fallback_info)

      expect(selected).to eq("model2")
    end

    it "selects model using health-based strategy" do
      strategy = { selection_strategy: :health_based }
      available_models = ["model2"]

      selected = fallback_manager.send(:select_model, available_models, strategy, fallback_info)

      expect(selected).to eq("model2")
    end
  end

  describe "fallback status and history" do
    before do
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})
    end

    it "gets comprehensive fallback status" do
      status = fallback_manager.get_fallback_status

      expect(status).to include(
        :exhausted_providers,
        :exhausted_models,
        :fallback_attempts,
        :circuit_breaker_status,
        :health_status
      )

      expect(status[:exhausted_providers]).to include("claude")
      expect(status[:exhausted_models]).to include("claude")
    end

    it "gets fallback history within time range" do
      # Add some fallbacks
      fallback_manager.handle_retry_exhaustion("gemini", "model1", :rate_limit, {})

      time_range = (Time.now - 1)..Time.now
      history = fallback_manager.get_fallback_history(time_range)

      expect(history.size).to eq(2)
      expect(history.map { |h| h[:provider] }).to include("claude", "gemini")
    end

    it "clears fallback history" do
      fallback_manager.clear_fallback_history

      history = fallback_manager.get_fallback_history
      expect(history).to be_empty
    end
  end

  describe "fallback strategy configuration" do
    it "configures custom fallback strategies" do
      custom_strategies = {
        custom_error: {
          name: "custom_error",
          action: :escalate,
          priority: :critical
        }
      }

      fallback_manager.configure_fallback_strategies(custom_strategies)

      strategy = fallback_manager.get_fallback_strategy(:custom_error)
      expect(strategy[:name]).to eq("custom_error")
      expect(strategy[:action]).to eq(:escalate)
      expect(strategy[:priority]).to eq(:critical)
    end
  end

  describe "helper classes" do
    describe "CircuitBreakerManager" do
      let(:circuit_breaker_manager) { described_class::CircuitBreakerManager.new }

      it "manages circuit breaker state" do
        expect(circuit_breaker_manager.circuit_breaker_open?("claude")).to be false

        circuit_breaker_manager.open_circuit_breaker("claude", "model1", :network_error)

        expect(circuit_breaker_manager.circuit_breaker_open?("claude", "model1")).to be true
      end

      it "selects healthy providers" do
        providers = ["claude", "gemini", "cursor"]

        # Open circuit breaker for claude
        circuit_breaker_manager.open_circuit_breaker("claude", nil, :network_error)

        healthy = circuit_breaker_manager.select_healthy_provider(providers)

        expect(healthy).to be_in(["gemini", "cursor"])
      end

      it "gets circuit breaker status" do
        circuit_breaker_manager.open_circuit_breaker("claude", "model1", :network_error)

        status = circuit_breaker_manager.get_status

        expect(status).to have_key("claude:model1")
        expect(status["claude:model1"][:open]).to be true
        expect(status["claude:model1"][:error_type]).to eq(:network_error)
      end
    end

    describe "LoadBalancer" do
      let(:load_balancer) { described_class::LoadBalancer.new }

      it "selects providers using load balancing" do
        providers = ["claude", "gemini", "cursor"]
        strategy = { name: "test" }

        selected = load_balancer.select_provider(providers, strategy)

        expect(selected).to be_in(providers)
      end
    end

    describe "HealthMonitor" do
      let(:health_monitor) { described_class::HealthMonitor.new }

      it "selects healthiest provider" do
        providers = ["claude", "gemini", "cursor"]

        selected = health_monitor.select_healthiest_provider(providers)

        expect(selected).to eq("claude")
      end

      it "selects healthiest model" do
        models = ["model1", "model2"]

        selected = health_monitor.select_healthiest_model(models)

        expect(selected).to eq("model1")
      end

      it "gets health status" do
        status = health_monitor.get_status

        expect(status).to include(:providers, :models)
      end
    end
  end

  describe "error handling" do
    it "handles no available providers gracefully" do
      # Exhaust all providers
      fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})
      fallback_manager.handle_retry_exhaustion("gemini", "model1", :network_error, {})
      fallback_manager.handle_retry_exhaustion("cursor", "model1", :network_error, {})

      result = fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:no_providers_available)
    end

    it "handles no available models gracefully" do
      # Exhaust all models for a provider
      fallback_manager.handle_retry_exhaustion("claude", "model1", :timeout, {})
      fallback_manager.handle_retry_exhaustion("claude", "model2", :timeout, {})

      result = fallback_manager.handle_retry_exhaustion("claude", "model1", :timeout, {})

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
    end

    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:set_current_provider).and_raise(NoMethodError)

      expect {
        fallback_manager.handle_retry_exhaustion("claude", "model1", :network_error, {})
      }.to raise_error(NoMethodError)
    end

    it "handles missing configuration methods gracefully" do
      allow(configuration).to receive(:fallback_config).and_raise(NoMethodError)

      expect {
        described_class.new(provider_manager, configuration)
      }.to raise_error(NoMethodError)
    end
  end
end
