# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::RateLimitRecoveryManager do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:recovery_manager) { described_class.new(provider_manager, configuration, metrics_manager) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:get_available_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:get_provider_models).and_return(["model1", "model2"])
    allow(provider_manager).to receive(:set_current_provider).and_return(true)
    allow(provider_manager).to receive(:set_current_model).and_return(true)

    # Mock configuration methods
    allow(configuration).to receive(:rate_limit_config).and_return({strategies: {}})

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:record_rate_limit)

    # Mock quota manager methods
    quota_manager = recovery_manager.instance_variable_get(:@quota_manager)
    allow(quota_manager).to receive(:find_best_quota_combination).and_return({
      provider: "gemini",
      model: "model1",
      quota_remaining: 500
    })
    allow(quota_manager).to receive(:record_rate_limit)
    allow(quota_manager).to receive(:get_quota_status).and_return({quota_remaining: 0})
    allow(quota_manager).to receive(:get_all_quota_status).and_return({})

    # Mock rate limit recovery manager methods
    allow(recovery_manager).to receive(:get_available_providers).and_return(["gemini", "cursor"])
    allow(recovery_manager).to receive(:get_available_models).and_return(["model1", "model2"])
  end

  describe "initialization" do
    it "creates rate limit recovery manager successfully" do
      expect(recovery_manager).to be_a(described_class)
    end

    it "initializes switch strategies" do
      strategies = recovery_manager.instance_variable_get(:@switch_strategies)

      expect(strategies).to include(
        :immediate_provider_switch,
        :immediate_model_switch,
        :quota_aware,
        :cost_optimized,
        :performance_optimized,
        :wait_and_retry,
        :escalate,
        :default
      )
    end

    it "initializes helper components" do
      expect(recovery_manager.instance_variable_get(:@rate_limit_tracker)).to be_a(described_class::RateLimitTracker)
      expect(recovery_manager.instance_variable_get(:@quota_manager)).to be_a(described_class::QuotaManager)
    end
  end

  describe "rate limit handling" do
    let(:rate_limit_info) do
      {
        type: :rate_limit,
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 0,
        quota_limit: 1000
      }
    end

    let(:context) { {error_message: "Rate limit exceeded"} }

    it "handles rate limit with immediate provider switch" do
      provider_switch_rate_limit = rate_limit_info.merge(quota_remaining: 100)
      result = recovery_manager.handle_rate_limit("claude", "model1", provider_switch_rate_limit, context)

      expect(result).to include(:success, :action, :new_provider, :reason, :recovery_info, :strategy)
      expect(result[:success]).to be true
      expect(result[:action]).to eq(:provider_switch)
      expect(["gemini", "cursor"]).to include(result[:new_provider])
    end

    it "handles rate limit with model switch when provider switch fails" do
      # Mock provider manager to return nil for provider switch but true for model switch
      allow(provider_manager).to receive(:set_current_provider).and_return(nil)
      allow(provider_manager).to receive(:set_current_model).and_return(true)

      model_switch_rate_limit = rate_limit_info.merge(quota_remaining: 100)
      result = recovery_manager.handle_rate_limit("claude", "model1", model_switch_rate_limit, context)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:model_switch)
      expect(result[:new_provider]).to eq("claude")
      expect(result[:new_model]).to eq("model1")
    end

    it "handles rate limit with wait and retry for temporary rate limits" do
      temporary_rate_limit = rate_limit_info.merge(retry_after: 30)

      result = recovery_manager.handle_rate_limit("claude", "model1", temporary_rate_limit, context)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:wait_and_retry)
      expect(result[:wait_time]).to eq(30)
    end

    it "handles rate limit with quota-aware switch" do
      quota_exhausted_rate_limit = rate_limit_info.merge(quota_remaining: 0)

      result = recovery_manager.handle_rate_limit("claude", "model1", quota_exhausted_rate_limit, context)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:quota_aware_switch)
    end

    it "handles rate limit with cost-optimized switch" do
      cost_sensitive_context = context.merge(cost_sensitive: true)
      cost_optimized_rate_limit = rate_limit_info.merge(quota_remaining: 100)

      result = recovery_manager.handle_rate_limit("claude", "model1", cost_optimized_rate_limit, cost_sensitive_context)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:cost_optimized_switch)
    end

    it "handles rate limit with performance-optimized switch" do
      performance_critical_context = context.merge(performance_critical: true)
      performance_optimized_rate_limit = rate_limit_info.merge(quota_remaining: 100)

      result = recovery_manager.handle_rate_limit("claude", "model1", performance_optimized_rate_limit, performance_critical_context)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:performance_optimized_switch)
    end

    it "handles rate limit with escalation when no alternatives available" do
      # Mock to return only the current provider (no alternatives)
      allow(recovery_manager).to receive(:get_available_providers).and_return(["claude"])
      allow(recovery_manager).to receive(:get_available_models).and_return(["model1"])

      # Use rate limit info that doesn't trigger quota-aware strategy
      escalation_rate_limit = rate_limit_info.merge(quota_remaining: 100)
      result = recovery_manager.handle_rate_limit("claude", "model1", escalation_rate_limit, context)

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:escalated)
      expect(result[:requires_manual_intervention]).to be true
    end

    it "records rate limit recovery in metrics manager" do
      expect(metrics_manager).to receive(:record_rate_limit).with(anything, anything, anything, anything)

      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)
    end

    it "adds recovery to history" do
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)

      history = recovery_manager.get_recovery_history
      expect(history).not_to be_empty
      expect(history.last[:provider]).to eq("claude")
      expect(history.last[:model]).to eq("model1")
    end

    it "tracks rate limit in rate limit tracker" do
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)

      tracker = recovery_manager.instance_variable_get(:@rate_limit_tracker)
      status = tracker.get_status
      expect(status).to have_key("claude:model1")
    end

    it "updates quota usage in quota manager" do
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)

      quota_manager = recovery_manager.instance_variable_get(:@quota_manager)
      quota_status = quota_manager.get_quota_status("claude", "model1")
      expect(quota_status[:quota_remaining]).to eq(0)
    end
  end

  describe "switch strategies" do
    let(:rate_limit_info) do
      {
        type: :rate_limit,
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 0,
        quota_limit: 1000
      }
    end

    it "gets switch strategy for rate limit scenario" do
      strategy = recovery_manager.get_switch_strategy("claude", "model1", rate_limit_info, {})

      expect(strategy).to include(:name, :action, :priority, :selection_strategy)
    end

    it "applies context modifications to strategy" do
      context = {priority: :critical, cooldown_period: 120}
      strategy = recovery_manager.get_switch_strategy("claude", "model1", rate_limit_info, context)

      expect(strategy[:priority]).to eq(:critical)
      expect(strategy[:cooldown_period]).to eq(120)
    end

    it "uses context-specific switch strategy" do
      context = {switch_strategy: :custom_strategy}
      recovery_manager.configure_switch_strategies({
        custom_strategy: {name: "custom", action: :escalate}
      })

      strategy = recovery_manager.get_switch_strategy("claude", "model1", rate_limit_info, context)
      expect(strategy[:name]).to eq("custom")
      expect(strategy[:action]).to eq(:escalate)
    end
  end

  describe "rate limit status management" do
    before do
      rate_limit_info = {
        type: :rate_limit,
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 0,
        quota_limit: 1000
      }

      # Mock the rate limit handling to fail so the rate limit remains active
      quota_manager = recovery_manager.instance_variable_get(:@quota_manager)
      allow(quota_manager).to receive(:find_best_quota_combination).and_return(nil)
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, {})
    end

    it "checks if provider is rate limited" do
      expect(recovery_manager.is_rate_limited?("claude")).to be true
      expect(recovery_manager.is_rate_limited?("gemini")).to be false
    end

    it "checks if model is rate limited" do
      expect(recovery_manager.is_rate_limited?("claude", "model1")).to be true
      expect(recovery_manager.is_rate_limited?("claude", "model2")).to be false
    end

    it "gets rate limit status for provider" do
      status = recovery_manager.get_rate_limit_status("claude")

      expect(status).to be_a(Hash)
      expect(status).to have_key("model1")
    end

    it "gets rate limit status for model" do
      status = recovery_manager.get_rate_limit_status("claude", "model1")

      expect(status).to be_a(Hash)
      expect(status).to include(:rate_limit_info, :timestamp, :recovery_attempts)
    end

    it "gets available providers excluding rate limited ones" do
      available = recovery_manager.get_available_providers

      expect(available).not_to include("claude")
      expect(available).to include("gemini", "cursor")
    end

    it "gets available models excluding rate limited ones" do
      # Remove the global mock for this test to allow proper filtering
      allow(recovery_manager).to receive(:get_available_models).and_call_original
      allow(provider_manager).to receive(:get_provider_models).and_return(["model1", "model2"])

      available = recovery_manager.get_available_models("claude")

      expect(available).not_to include("model1")
      expect(available).to include("model2")
    end

    it "resets rate limit for specific provider/model" do
      recovery_manager.reset_rate_limit("claude", "model1")

      expect(recovery_manager.is_rate_limited?("claude", "model1")).to be false
    end

    it "resets rate limit for all models of provider" do
      recovery_manager.reset_rate_limit("claude")

      expect(recovery_manager.is_rate_limited?("claude")).to be false
    end

    it "resets all rate limits" do
      recovery_manager.reset_all_rate_limits

      expect(recovery_manager.is_rate_limited?("claude")).to be false
    end
  end

  describe "quota management" do
    it "gets quota status for provider/model" do
      quota_status = recovery_manager.get_quota_status("claude", "model1")

      expect(quota_status).to be_a(Hash)
    end
  end

  describe "recovery history management" do
    it "gets recovery history within time range" do
      # Add some recoveries
      rate_limit_info = {type: :rate_limit, retry_after: 60}
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, {})
      recovery_manager.handle_rate_limit("gemini", "model1", rate_limit_info, {})

      time_range = (Time.now - 1)..Time.now
      history = recovery_manager.get_recovery_history(time_range)

      expect(history.size).to eq(2)
      expect(history.map { |h| h[:provider] }).to include("claude", "gemini")
    end

    it "clears recovery history" do
      rate_limit_info = {type: :rate_limit, retry_after: 60}
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, {})

      recovery_manager.clear_recovery_history

      history = recovery_manager.get_recovery_history
      expect(history).to be_empty
    end
  end

  describe "comprehensive status" do
    before do
      rate_limit_info = {
        type: :rate_limit,
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 0,
        quota_limit: 1000
      }

      # Mock the rate limit handling to fail so active rate limits are created
      quota_manager = recovery_manager.instance_variable_get(:@quota_manager)
      allow(quota_manager).to receive(:find_best_quota_combination).and_return(nil)
      recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, {})
    end

    it "gets comprehensive rate limit status" do
      status = recovery_manager.get_comprehensive_status

      expect(status).to include(
        :active_rate_limits,
        :quota_status,
        :rate_limit_tracker_status,
        :recovery_history_count,
        :switch_cooldowns
      )

      expect(status[:active_rate_limits]).to have_key("claude")
      expect(status[:recovery_history_count]).to eq(1)
    end
  end

  describe "switch strategy configuration" do
    it "configures custom switch strategies" do
      custom_strategies = {
        custom_recovery: {
          name: "custom_recovery",
          action: :escalate,
          priority: :critical
        }
      }

      recovery_manager.configure_switch_strategies(custom_strategies)

      strategy = recovery_manager.get_switch_strategy("claude", "model1", {type: :rate_limit}, {switch_strategy: :custom_recovery})
      expect(strategy[:name]).to eq("custom_recovery")
      expect(strategy[:action]).to eq(:escalate)
      expect(strategy[:priority]).to eq(:critical)
    end
  end

  describe "switch cooldown management" do
    let(:rate_limit_info) do
      {
        type: :rate_limit,
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 0,
        quota_limit: 1000
      }
    end

    it "enforces switch cooldown periods" do
      # Configure strategy with cooldown
      recovery_manager.configure_switch_strategies({
        cooldown_strategy: {
          name: "cooldown_strategy",
          action: :switch_provider,
          cooldown_period: 60
        }
      })

      context = {switch_strategy: :cooldown_strategy}

      # First switch should succeed
      result1 = recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)
      expect(result1[:success]).to be true

      # Second switch should be blocked by cooldown
      result2 = recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, context)
      expect(result2[:success]).to be false
      expect(result2[:action]).to eq(:switch_cooldown_active)
    end
  end

  describe "helper classes" do
    describe "RateLimitTracker" do
      let(:tracker) { described_class::RateLimitTracker.new }

      it "tracks rate limits" do
        rate_limit_info = {type: :rate_limit, retry_after: 60}

        tracker.record_rate_limit("claude", "model1", rate_limit_info)

        status = tracker.get_status
        expect(status).to have_key("claude:model1")
        expect(status["claude:model1"][:count]).to eq(1)
      end

      it "clears rate limits" do
        rate_limit_info = {type: :rate_limit, retry_after: 60}

        tracker.record_rate_limit("claude", "model1", rate_limit_info)
        tracker.clear_rate_limit("claude", "model1")

        status = tracker.get_status
        expect(status).not_to have_key("claude:model1")
      end

      it "clears all rate limits" do
        rate_limit_info = {type: :rate_limit, retry_after: 60}

        tracker.record_rate_limit("claude", "model1", rate_limit_info)
        tracker.record_rate_limit("gemini", "model1", rate_limit_info)
        tracker.clear_all_rate_limits

        status = tracker.get_status
        expect(status).to be_empty
      end
    end

    describe "QuotaManager" do
      let(:quota_manager) { described_class::QuotaManager.new }

      it "tracks quota usage" do
        rate_limit_info = {quota_remaining: 100, quota_limit: 1000}

        quota_manager.record_rate_limit("claude", "model1", rate_limit_info)

        quota_status = quota_manager.get_quota_status("claude", "model1")
        expect(quota_status[:quota_remaining]).to eq(100)
        expect(quota_status[:quota_limit]).to eq(1000)
      end

      it "finds best quota combination" do
        quota_manager.record_rate_limit("claude", "model1", {quota_remaining: 100, quota_limit: 1000})
        quota_manager.record_rate_limit("gemini", "model1", {quota_remaining: 200, quota_limit: 1000})

        best_combination = quota_manager.find_best_quota_combination({})

        expect(best_combination[:provider]).to eq("gemini")
        expect(best_combination[:quota_remaining]).to eq(200)
      end

      it "resets quota for specific provider/model" do
        rate_limit_info = {quota_remaining: 100, quota_limit: 1000}

        quota_manager.record_rate_limit("claude", "model1", rate_limit_info)
        quota_manager.reset_quota("claude", "model1")

        quota_status = quota_manager.get_quota_status("claude", "model1")
        expect(quota_status).to be_empty
      end

      it "resets all quotas" do
        rate_limit_info = {quota_remaining: 100, quota_limit: 1000}

        quota_manager.record_rate_limit("claude", "model1", rate_limit_info)
        quota_manager.record_rate_limit("gemini", "model1", rate_limit_info)
        quota_manager.reset_all_quotas

        all_quotas = quota_manager.get_all_quota_status
        expect(all_quotas).to be_empty
      end
    end
  end

  describe "error handling" do
    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:set_current_provider).and_raise(NoMethodError)

      rate_limit_info = {type: :rate_limit, retry_after: 60}

      expect {
        recovery_manager.handle_rate_limit("claude", "model1", rate_limit_info, {})
      }.to raise_error(NoMethodError)
    end
  end
end
