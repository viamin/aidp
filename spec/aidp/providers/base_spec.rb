# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Base do
  let(:provider) { described_class.new }

  before do
    # Mock the abstract methods
    allow(provider).to receive(:name).and_return("test_provider")
  end

  describe "initialization" do
    it "initializes with default values" do
      expect(provider.activity_state).to eq(:idle)
      expect(provider.last_activity_time).to be_a(Time)
      expect(provider.start_time).to be_nil
      expect(provider.step_name).to be_nil
      expect(provider.stuck_timeout).to eq(120)
    end

    it "initializes harness metrics" do
      metrics = provider.harness_metrics
      expect(metrics).to include(
        :total_requests,
        :successful_requests,
        :failed_requests,
        :rate_limited_requests,
        :total_tokens_used,
        :total_cost,
        :average_response_time,
        :last_request_time
      )
      expect(metrics[:total_requests]).to eq(0)
      expect(metrics[:successful_requests]).to eq(0)
      expect(metrics[:failed_requests]).to eq(0)
      expect(metrics[:rate_limited_requests]).to eq(0)
      expect(metrics[:total_tokens_used]).to eq(0)
      expect(metrics[:total_cost]).to eq(0.0)
      expect(metrics[:average_response_time]).to eq(0.0)
      expect(metrics[:last_request_time]).to be_nil
    end
  end

  describe "harness integration" do
    let(:mock_harness) { double("harness_runner") }

    it "sets harness context" do
      provider.set_harness_context(mock_harness)
      expect(provider.harness_mode?).to be true
    end

    it "detects harness mode" do
      expect(provider.harness_mode?).to be false
      provider.set_harness_context(mock_harness)
      expect(provider.harness_mode?).to be true
    end

    it "records harness request metrics" do
      allow(mock_harness).to receive(:record_provider_metrics)
      provider.set_harness_context(mock_harness)

      provider.record_harness_request(
        success: true,
        tokens_used: 100,
        cost: 0.01,
        response_time: 2.5,
        rate_limited: false
      )

      metrics = provider.harness_metrics
      expect(metrics[:total_requests]).to eq(1)
      expect(metrics[:successful_requests]).to eq(1)
      expect(metrics[:failed_requests]).to eq(0)
      expect(metrics[:rate_limited_requests]).to eq(0)
      expect(metrics[:total_tokens_used]).to eq(100)
      expect(metrics[:total_cost]).to eq(0.01)
      expect(metrics[:average_response_time]).to eq(2.5)
      expect(metrics[:last_request_time]).to be_a(Time)

      expect(mock_harness).to have_received(:record_provider_metrics).with("test_provider", metrics)
    end

    it "records failed harness request metrics" do
      allow(mock_harness).to receive(:record_provider_metrics)
      provider.set_harness_context(mock_harness)

      provider.record_harness_request(
        success: false,
        tokens_used: 0,
        cost: 0.0,
        response_time: 1.0,
        rate_limited: true
      )

      metrics = provider.harness_metrics
      expect(metrics[:total_requests]).to eq(1)
      expect(metrics[:successful_requests]).to eq(0)
      expect(metrics[:failed_requests]).to eq(1)
      expect(metrics[:rate_limited_requests]).to eq(1)
      expect(metrics[:total_tokens_used]).to eq(0)
      expect(metrics[:total_cost]).to eq(0.0)
      expect(metrics[:average_response_time]).to eq(1.0)
    end

    it "calculates success rate correctly" do
      provider.record_harness_request(success: true, response_time: 1.0)
      provider.record_harness_request(success: true, response_time: 2.0)
      provider.record_harness_request(success: false, response_time: 0.5)

      # Test through harness_health_status which calls the private method
      health_status = provider.harness_health_status
      expect(health_status[:success_rate]).to eq(2.0 / 3.0)
    end

    it "calculates rate limit ratio correctly" do
      provider.record_harness_request(success: true, rate_limited: false, response_time: 1.0)
      provider.record_harness_request(success: true, rate_limited: true, response_time: 2.0)
      provider.record_harness_request(success: false, rate_limited: true, response_time: 0.5)

      # Test through harness_health_status which calls the private method
      health_status = provider.harness_health_status
      expect(health_status[:rate_limit_ratio]).to eq(2.0 / 3.0)
    end

    it "calculates health score correctly" do
      provider.record_harness_request(success: true, response_time: 1.0)
      provider.record_harness_request(success: true, response_time: 2.0)
      provider.record_harness_request(success: false, response_time: 0.5)

      # Test through harness_health_status which calls the private method
      health_status = provider.harness_health_status
      expect(health_status[:health_score]).to be > 0
      expect(health_status[:health_score]).to be <= 100
    end
  end

  describe "harness health status" do
    it "provides health status" do
      status = provider.harness_health_status

      expect(status).to include(
        :provider,
        :activity_state,
        :stuck,
        :success_rate,
        :average_response_time,
        :total_requests,
        :rate_limit_ratio,
        :last_activity,
        :health_score
      )
      expect(status[:provider]).to eq("test_provider")
      expect(status[:activity_state]).to eq(:idle)
      expect(status[:stuck]).to be false
      expect(status[:success_rate]).to eq(1.0)
      expect(status[:total_requests]).to eq(0)
      expect(status[:rate_limit_ratio]).to eq(0.0)
      expect(status[:health_score]).to eq(100.0)
    end

    it "checks if provider is healthy" do
      expect(provider.harness_healthy?).to be true

      # Add some failed requests to make it unhealthy
      provider.record_harness_request(success: false, response_time: 1.0)
      provider.record_harness_request(success: false, response_time: 1.0)
      provider.record_harness_request(success: true, response_time: 1.0)

      expect(provider.harness_healthy?).to be false
    end

    it "considers provider unhealthy with high rate limit ratio" do
      # Add many rate limited requests
      5.times do
        provider.record_harness_request(success: true, rate_limited: true, response_time: 1.0)
      end
      provider.record_harness_request(success: true, rate_limited: false, response_time: 1.0)

      expect(provider.harness_healthy?).to be false
    end
  end

  describe "harness configuration" do
    it "provides harness configuration" do
      config = provider.harness_config

      expect(config).to include(
        :name,
        :supports_activity_monitoring,
        :default_timeout,
        :available,
        :health_status
      )
      expect(config[:name]).to eq("test_provider")
      expect(config[:supports_activity_monitoring]).to be true
      expect(config[:default_timeout]).to eq(120)
      expect(config[:available]).to be true
      expect(config[:health_status]).to be_a(Hash)
    end
  end

  describe "send_with_harness" do
    let(:mock_harness) { double("harness_runner") }

    before do
      allow(provider).to receive(:send).and_return("test result")
      allow(mock_harness).to receive(:record_provider_metrics)
      allow(mock_harness).to receive(:record_provider_error)
      provider.set_harness_context(mock_harness)
    end

    it "calls original send method and records metrics" do
      result = provider.send_with_harness(prompt: "test prompt")

      expect(result).to eq("test result")
      expect(provider).to have_received(:send).with(prompt: "test prompt", session: nil)

      metrics = provider.harness_metrics
      expect(metrics[:total_requests]).to eq(1)
      expect(metrics[:successful_requests]).to eq(1)
      expect(metrics[:failed_requests]).to eq(0)
    end

    it "handles errors and records them" do
      allow(provider).to receive(:send).and_raise(StandardError, "test error")

      expect {
        provider.send_with_harness(prompt: "test prompt")
      }.to raise_error(StandardError, "test error")

      metrics = provider.harness_metrics
      expect(metrics[:total_requests]).to eq(1)
      expect(metrics[:successful_requests]).to eq(0)
      expect(metrics[:failed_requests]).to eq(1)

      expect(mock_harness).to have_received(:record_provider_error).with("test_provider", "test error", false)
    end

    it "detects rate limiting errors" do
      allow(provider).to receive(:send).and_raise(StandardError, "rate limit exceeded")

      expect {
        provider.send_with_harness(prompt: "test prompt")
      }.to raise_error(StandardError, "rate limit exceeded")

      metrics = provider.harness_metrics
      expect(metrics[:rate_limited_requests]).to eq(1)

      expect(mock_harness).to have_received(:record_provider_error).with("test_provider", "rate limit exceeded", true)
    end

    it "extracts token usage from result" do
      token_result = {
        output: "test output",
        token_usage: { total: 150, cost: 0.02 },
        rate_limited: false
      }
      allow(provider).to receive(:send).and_return(token_result)

      result = provider.send_with_harness(prompt: "test prompt")

      expect(result).to eq(token_result)

      metrics = provider.harness_metrics
      expect(metrics[:total_tokens_used]).to eq(150)
      expect(metrics[:total_cost]).to eq(0.02)
    end

    it "detects rate limiting in result" do
      rate_limited_result = {
        output: "test output",
        rate_limited: true
      }
      allow(provider).to receive(:send).and_return(rate_limited_result)

      result = provider.send_with_harness(prompt: "test prompt")

      expect(result).to eq(rate_limited_result)

      metrics = provider.harness_metrics
      expect(metrics[:rate_limited_requests]).to eq(1)
    end
  end

  describe "activity monitoring" do
    it "supports activity monitoring by default" do
      expect(provider.supports_activity_monitoring?).to be true
    end

    it "sets up activity monitoring" do
      callback = double("callback")
      allow(callback).to receive(:call)

      provider.setup_activity_monitoring("test_step", callback, 60)

      expect(provider.step_name).to eq("test_step")
      expect(provider.stuck_timeout).to eq(60)
      expect(provider.start_time).to be_a(Time)
      expect(provider.activity_state).to eq(:working)
    end

    it "records activity" do
      provider.setup_activity_monitoring("test_step")
      provider.record_activity("test message")

      expect(provider.instance_variable_get(:@output_count)).to eq(1)
      expect(provider.instance_variable_get(:@last_output_time)).to be_a(Time)
      expect(provider.activity_state).to eq(:working)
    end

    it "marks as completed" do
      callback = double("callback")
      allow(callback).to receive(:call)
      provider.setup_activity_monitoring("test_step", callback)

      provider.mark_completed

      expect(provider.activity_state).to eq(:completed)
      expect(callback).to have_received(:call).with(:completed, nil, provider)
    end

    it "marks as failed" do
      callback = double("callback")
      allow(callback).to receive(:call)
      provider.setup_activity_monitoring("test_step", callback)

      provider.mark_failed("test error")

      expect(provider.activity_state).to eq(:failed)
      expect(callback).to have_received(:call).with(:failed, "test error", provider)
    end

    it "detects stuck state" do
      provider.setup_activity_monitoring("test_step")
      provider.record_activity("test message")

      # Move time forward past stuck timeout
      allow(Time).to receive(:now).and_return(Time.now + 130)

      expect(provider.stuck?).to be true
    end

    it "provides activity summary" do
      provider.setup_activity_monitoring("test_step")
      provider.record_activity("test message")
      provider.mark_completed

      summary = provider.activity_summary

      expect(summary).to include(
        :provider,
        :step_name,
        :start_time,
        :end_time,
        :duration,
        :final_state,
        :stuck_detected,
        :output_count
      )
      expect(summary[:provider]).to eq("test_provider")
      expect(summary[:step_name]).to eq("test_step")
      expect(summary[:final_state]).to eq(:completed)
      expect(summary[:stuck_detected]).to be false
      expect(summary[:output_count]).to eq(1)
    end
  end

  describe "job context integration" do
    let(:mock_job_manager) { double("job_manager") }
    let(:job_context) do
      {
        job_id: "test_job",
        execution_id: "test_execution",
        job_manager: mock_job_manager
      }
    end

    before do
      allow(mock_job_manager).to receive(:log_message)
      provider.set_job_context(**job_context)
    end

    it "logs activity state changes to job" do
      provider.setup_activity_monitoring("test_step")
      provider.mark_completed

      expect(mock_job_manager).to have_received(:log_message).with(
        "test_job",
        "test_execution",
        "Provider state changed to completed",
        "info",
        hash_including(:provider, :step_name, :activity_state)
      )
    end

    it "logs failed state changes to job" do
      provider.setup_activity_monitoring("test_step")
      provider.mark_failed("test error")

      expect(mock_job_manager).to have_received(:log_message).with(
        "test_job",
        "test_execution",
        "test error",
        "error",
        hash_including(:provider, :step_name, :activity_state)
      )
    end
  end
end
