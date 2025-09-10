# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::RateLimitManager do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:rate_limit_manager) { described_class.new(provider_manager, configuration) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:configured_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:is_rate_limited?).and_return(false)
    allow(provider_manager).to receive(:is_model_rate_limited?).and_return(false)
    allow(provider_manager).to receive(:switch_provider).and_return("gemini")
    allow(provider_manager).to receive(:switch_model).and_return("model2")
    allow(provider_manager).to receive(:get_default_model).and_return("default-model")
    allow(provider_manager).to receive(:get_provider_models).and_return(["model1", "model2"])
    allow(provider_manager).to receive(:set_current_provider)
    allow(provider_manager).to receive(:set_current_model)
    allow(provider_manager).to receive(:mark_rate_limited)
    allow(provider_manager).to receive(:mark_model_rate_limited)
    allow(provider_manager).to receive(:clear_rate_limit)
    allow(provider_manager).to receive(:clear_model_rate_limit)
    allow(provider_manager).to receive(:get_metrics).and_return({
      successful_requests: 10,
      total_requests: 12,
      total_duration: 1000
    })
    allow(provider_manager).to receive(:get_model_metrics).and_return({
      successful_requests: 5,
      total_requests: 6,
      total_duration: 500
    })
    allow(provider_manager).to receive(:instance_variable_get).and_return({})

    # Mock configuration methods
    allow(configuration).to receive(:rate_limit_config).and_return({
      enabled: true,
      default_reset_time: 3600,
      rotation_strategy: "provider_first"
    })
  end

  describe "initialization" do
    it "creates rate limit manager successfully" do
      expect(rate_limit_manager).to be_a(described_class)
    end

    it "initializes retry strategies" do
      expect(rate_limit_manager.instance_variable_get(:@retry_strategies)).to include(
        rate_limit: hash_including(:max_retries, :base_delay, :exponential_base),
        network_error: hash_including(:max_retries, :base_delay, :exponential_base),
        server_error: hash_including(:max_retries, :base_delay, :exponential_base),
        timeout: hash_including(:max_retries, :base_delay, :exponential_base),
        authentication: hash_including(:max_retries, :base_delay, :exponential_base),
        default: hash_including(:max_retries, :base_delay, :exponential_base)
      )
    end

    it "initializes rotation strategies" do
      expect(rate_limit_manager.instance_variable_get(:@rotation_strategies)).to include(
        provider_first: hash_including(:description, :priority),
        model_first: hash_including(:description, :priority),
        cost_optimized: hash_including(:description, :priority),
        performance_optimized: hash_including(:description, :priority),
        quota_aware: hash_including(:description, :priority)
      )
    end
  end

  describe "rate limit handling" do
    let(:rate_limit_info) do
      {
        is_rate_limited: true,
        type: "rate_limit",
        reset_time: Time.now + 3600,
        retry_after: 60
      }
    end

    it "handles rate limit detection" do
      result = rate_limit_manager.handle_rate_limit("claude", "model1", "rate limit exceeded", nil)

      expect(result).to include(:success, :action, :provider, :model)
      expect(result[:success]).to be true
      expect(result[:action]).to eq("provider_switch")
    end

    it "records rate limit information" do
      expect(provider_manager).to receive(:mark_rate_limited).with("claude", rate_limit_info[:reset_time])

      rate_limit_manager.handle_rate_limit("claude", "model1", "rate limit exceeded", nil)
    end

    it "handles non-rate-limited responses" do
      result = rate_limit_manager.handle_rate_limit("claude", "model1", "success response", nil)

      expect(result[:success]).to be true
      expect(result[:action]).to eq("continue")
      expect(result[:provider]).to eq("claude")
      expect(result[:model]).to eq("model1")
    end
  end

  describe "provider rotation" do
    it "gets next available combination with provider-first strategy" do
      result = rate_limit_manager.get_next_available_combination("claude", "model1", { rotation_strategy: "provider_first" })

      expect(result[:success]).to be true
      expect(result[:action]).to eq("provider_switch")
      expect(result[:provider]).to eq("gemini")
    end

    it "gets next available combination with model-first strategy" do
      result = rate_limit_manager.get_next_available_combination("claude", "model1", { rotation_strategy: "model_first" })

      expect(result[:success]).to be true
      expect(result[:action]).to eq("model_switch")
      expect(result[:model]).to eq("model2")
    end

    it "gets next available combination with cost-optimized strategy" do
      result = rate_limit_manager.get_next_available_combination("claude", "model1", { rotation_strategy: "cost_optimized" })

      expect(result[:success]).to be true
      expect(result[:action]).to eq("cost_optimized_switch")
    end

    it "gets next available combination with performance-optimized strategy" do
      result = rate_limit_manager.get_next_available_combination("claude", "model1", { rotation_strategy: "performance_optimized" })

      expect(result[:success]).to be true
      expect(result[:action]).to eq("performance_optimized_switch")
    end

    it "gets next available combination with quota-aware strategy" do
      result = rate_limit_manager.get_next_available_combination("claude", "model1", { rotation_strategy: "quota_aware" })

      expect(result[:success]).to be true
      expect(result[:action]).to eq("quota_aware_switch")
    end
  end

  describe "rate limit status" do
    it "returns comprehensive rate limit status" do
      status = rate_limit_manager.get_rate_limit_status

      expect(status).to include(
        :providers,
        :models,
        :next_reset_times,
        :rotation_history,
        :quota_status,
        :cost_optimization
      )

      expect(status[:providers]).to include("claude", "gemini", "cursor")
      expect(status[:models]).to include("claude", "gemini", "cursor")
    end

    it "includes provider rate limit information" do
      status = rate_limit_manager.get_rate_limit_status

      status[:providers].each do |_provider, info|
        expect(info).to include(
          :rate_limited,
          :reset_time,
          :quota_used,
          :quota_limit
        )
      end
    end

    it "includes model rate limit information" do
      status = rate_limit_manager.get_rate_limit_status

      status[:models].each do |_provider, models|
        models.each do |_model, info|
          expect(info).to include(
            :rate_limited,
            :reset_time,
            :quota_used,
            :quota_limit
          )
        end
      end
    end
  end

  describe "retry strategies" do
    it "returns retry strategy for rate limit error" do
      strategy = rate_limit_manager.get_retry_strategy("rate_limit", { retry_count: 1 })

      expect(strategy).to include(
        :max_retries,
        :base_delay,
        :max_delay,
        :exponential_base,
        :jitter,
        :strategy,
        :backoff_delay
      )
      expect(strategy[:strategy]).to eq("exponential_backoff")
    end

    it "returns retry strategy for network error" do
      strategy = rate_limit_manager.get_retry_strategy("network_error", { retry_count: 1 })

      expect(strategy[:strategy]).to eq("linear_backoff")
      expect(strategy[:max_retries]).to eq(5)
    end

    it "returns retry strategy for server error" do
      strategy = rate_limit_manager.get_retry_strategy("server_error", { retry_count: 1 })

      expect(strategy[:strategy]).to eq("exponential_backoff")
      expect(strategy[:max_retries]).to eq(3)
    end

    it "returns retry strategy for timeout error" do
      strategy = rate_limit_manager.get_retry_strategy("timeout", { retry_count: 1 })

      expect(strategy[:strategy]).to eq("fixed_delay")
      expect(strategy[:max_retries]).to eq(2)
    end

    it "returns retry strategy for authentication error" do
      strategy = rate_limit_manager.get_retry_strategy("authentication", { retry_count: 1 })

      expect(strategy[:strategy]).to eq("immediate_fail")
      expect(strategy[:max_retries]).to eq(1)
    end

    it "returns default retry strategy for unknown error" do
      strategy = rate_limit_manager.get_retry_strategy("unknown_error", { retry_count: 1 })

      expect(strategy[:strategy]).to eq("exponential_backoff")
      expect(strategy[:max_retries]).to eq(3)
    end

    it "calculates backoff delay correctly" do
      strategy = rate_limit_manager.get_retry_strategy("rate_limit", { retry_count: 2 })

      # With base_delay=1.0, exponential_base=2.0, retry_count=2
      # Expected delay = 1.0 * (2.0 ** 2) = 4.0
      expect(strategy[:backoff_delay]).to eq(4.0)
    end

    it "applies jitter when enabled" do
      strategy = rate_limit_manager.get_retry_strategy("rate_limit", { retry_count: 1 })

      expect(strategy[:jitter]).to be true
      # The actual delay will be calculated with jitter in execute_retry
    end
  end

  describe "retry execution" do
    it "executes retry with strategy" do
      result = rate_limit_manager.execute_retry("claude", "model1", "rate_limit", { retry_count: 0 })

      expect(result).to include(:success, :action, :provider, :model)
      expect(result[:success]).to be true
    end

    it "does not retry when max retries exceeded" do
      result = rate_limit_manager.execute_retry("claude", "model1", "rate_limit", { retry_count: 5 })

      expect(result[:success]).to be false
      expect(result[:action]).to eq("no_retry")
      expect(result[:reason]).to eq("max_retries_exceeded")
    end

    it "records retry attempt" do
      rate_limit_manager.execute_retry("claude", "model1", "rate_limit", { retry_count: 0 })

      history = rate_limit_manager.instance_variable_get(:@rotation_history)
      expect(history).not_to be_empty
      expect(history.last[:type]).to eq("retry")
      expect(history.last[:error_type]).to eq("rate_limit")
    end
  end

  describe "rate limit clearing" do
    it "clears provider rate limit" do
      expect(provider_manager).to receive(:clear_rate_limit).with("claude")

      rate_limit_manager.clear_rate_limit("claude")
    end

    it "clears model rate limit" do
      expect(provider_manager).to receive(:clear_model_rate_limit).with("claude", "model1")

      rate_limit_manager.clear_rate_limit("claude", "model1")
    end
  end

  describe "rotation statistics" do
    it "returns rotation statistics" do
      # Add some rotation history
      rate_limit_manager.instance_variable_get(:@rotation_history) << {
        timestamp: Time.now,
        type: "rotation",
        from_provider: "claude",
        to_provider: "gemini",
        success: true,
        duration: 1.5,
        reason: "provider_switch"
      }

      stats = rate_limit_manager.get_rotation_statistics

      expect(stats).to include(
        :total_rotations,
        :rotations_by_reason,
        :rotations_by_provider,
        :average_rotation_time,
        :success_rate,
        :cost_impact,
        :quota_efficiency
      )

      expect(stats[:total_rotations]).to eq(1)
      expect(stats[:success_rate]).to eq(1.0)
    end

    it "calculates average rotation time" do
      # Add rotation history with durations
      history = rate_limit_manager.instance_variable_get(:@rotation_history)
      history << { duration: 1.0, success: true }
      history << { duration: 2.0, success: true }
      history << { success: true } # No duration

      stats = rate_limit_manager.get_rotation_statistics

      expect(stats[:average_rotation_time]).to eq(1.5) # (1.0 + 2.0) / 2
    end

    it "calculates success rate" do
      # Add rotation history
      history = rate_limit_manager.instance_variable_get(:@rotation_history)
      history << { success: true }
      history << { success: true }
      history << { success: false }

      stats = rate_limit_manager.get_rotation_statistics

      expect(stats[:success_rate]).to eq(2.0 / 3.0)
    end
  end

  describe "rate limit detection" do
    it "detects rate limit from error message" do
      rate_limit_info = rate_limit_manager.instance_variable_get(:@rate_limit_detector).detect_rate_limit(nil, StandardError.new("rate limit exceeded"))

      expect(rate_limit_info[:is_rate_limited]).to be true
      expect(rate_limit_info[:type]).to eq("rate_limit")
    end

    it "detects quota exceeded from response" do
      rate_limit_info = rate_limit_manager.instance_variable_get(:@rate_limit_detector).detect_rate_limit("quota exceeded", nil)

      expect(rate_limit_info[:is_rate_limited]).to be true
      expect(rate_limit_info[:type]).to eq("quota_exceeded")
    end

    it "does not detect rate limit from normal response" do
      rate_limit_info = rate_limit_manager.instance_variable_get(:@rate_limit_detector).detect_rate_limit("success response", nil)

      expect(rate_limit_info[:is_rate_limited]).to be false
    end
  end

  describe "quota tracking" do
    it "tracks quota usage" do
      quota_tracker = rate_limit_manager.instance_variable_get(:@quota_tracker)

      quota_tracker.record_rate_limit("claude", "model1", {})

      expect(quota_tracker.get_quota_used("claude", "model1")).to eq(1)
      expect(quota_tracker.get_quota_limit("claude", "model1")).to eq(1000)
    end

    it "clears quota usage" do
      quota_tracker = rate_limit_manager.instance_variable_get(:@quota_tracker)

      quota_tracker.record_rate_limit("claude", "model1", {})
      quota_tracker.clear_rate_limit("claude", "model1")

      expect(quota_tracker.get_quota_used("claude", "model1")).to eq(0)
    end
  end

  describe "cost optimization" do
    it "provides cost optimization status" do
      cost_optimizer = rate_limit_manager.instance_variable_get(:@cost_optimizer)

      status = cost_optimizer.get_status

      expect(status).to include(:cost_models, :cost_history)
    end

    it "calculates cost impact" do
      cost_optimizer = rate_limit_manager.instance_variable_get(:@cost_optimizer)

      impact = cost_optimizer.get_cost_impact

      expect(impact).to include(:total_cost_savings, :cost_optimization_rate)
    end
  end

  describe "backoff calculation" do
    it "calculates exponential backoff correctly" do
      backoff_calculator = rate_limit_manager.instance_variable_get(:@backoff_calculator)

      # Test exponential backoff: base_delay * (exponential_base ^ retry_count)
      delay1 = backoff_calculator.calculate_delay(1.0, 60.0, 2.0, 0) # 1.0 * (2^0) = 1.0
      delay2 = backoff_calculator.calculate_delay(1.0, 60.0, 2.0, 1) # 1.0 * (2^1) = 2.0
      delay3 = backoff_calculator.calculate_delay(1.0, 60.0, 2.0, 2) # 1.0 * (2^2) = 4.0

      expect(delay1).to eq(1.0)
      expect(delay2).to eq(2.0)
      expect(delay3).to eq(4.0)
    end

    it "respects maximum delay" do
      backoff_calculator = rate_limit_manager.instance_variable_get(:@backoff_calculator)

      delay = backoff_calculator.calculate_delay(1.0, 5.0, 2.0, 10) # Would be 1024.0, but max is 5.0

      expect(delay).to eq(5.0)
    end
  end

  describe "error handling" do
    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:configured_providers).and_raise(NoMethodError)

      expect {
        rate_limit_manager.get_rate_limit_status
      }.to raise_error(NoMethodError)
    end

    it "handles missing configuration methods gracefully" do
      allow(configuration).to receive(:rate_limit_config).and_raise(NoMethodError)

      expect {
        rate_limit_manager.get_retry_strategy("rate_limit", {})
      }.to raise_error(NoMethodError)
    end
  end
end
