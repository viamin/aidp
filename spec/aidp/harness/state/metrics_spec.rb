# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/metrics"

RSpec.describe Aidp::Harness::State::Metrics do
  let(:persistence) { instance_double("Persistence") }
  let(:workflow_state) { instance_double("WorkflowState") }
  let(:metrics) { described_class.new(persistence, workflow_state) }
  let(:empty_state) { {} }

  before do
    allow(persistence).to receive(:load_state).and_return(empty_state)
    allow(persistence).to receive(:save_state)
    allow(workflow_state).to receive(:completed_steps).and_return([])
    allow(workflow_state).to receive(:session_duration).and_return(0)
  end

  describe "#initialize" do
    it "initializes with persistence and workflow_state" do
      expect(metrics).to be_a(described_class)
    end
  end

  describe "#record_provider_switch" do
    it "increments provider switch count" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:provider_switches]).to eq(1)
        expect(state[:last_provider_switch][:from]).to eq("anthropic")
        expect(state[:last_provider_switch][:to]).to eq("cursor")
        expect(state[:last_provider_switch][:timestamp]).to be_a(Time)
        expect(state[:last_updated]).to be_a(Time)
      end

      metrics.record_provider_switch("anthropic", "cursor")
    end

    it "accumulates multiple switches" do
      allow(persistence).to receive(:load_state).and_return(provider_switches: 2)

      expect(persistence).to receive(:save_state) do |state|
        expect(state[:provider_switches]).to eq(3)
      end

      metrics.record_provider_switch("cursor", "gemini")
    end
  end

  describe "#record_rate_limit_event" do
    let(:reset_time) { Time.now + 3600 }

    it "increments rate limit event count" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:rate_limit_events]).to eq(1)
        expect(state[:last_rate_limit][:provider]).to eq("anthropic")
        expect(state[:last_rate_limit][:reset_time]).to eq(reset_time)
        expect(state[:last_rate_limit][:timestamp]).to be_a(Time)
      end

      metrics.record_rate_limit_event("anthropic", reset_time)
    end
  end

  describe "#record_user_feedback_request" do
    it "increments user feedback request count" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:user_feedback_requests]).to eq(1)
        expect(state[:last_user_feedback][:step]).to eq("review_plan")
        expect(state[:last_user_feedback][:questions_count]).to eq(3)
        expect(state[:last_user_feedback][:timestamp]).to be_a(Time)
      end

      metrics.record_user_feedback_request("review_plan", 3)
    end
  end

  describe "#record_error_event" do
    it "increments error event count" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:error_events]).to eq(1)
        expect(state[:last_error][:step]).to eq("execute_plan")
        expect(state[:last_error][:error_type]).to eq("rate_limit")
        expect(state[:last_error][:provider]).to eq("anthropic")
        expect(state[:last_error][:timestamp]).to be_a(Time)
      end

      metrics.record_error_event("execute_plan", "rate_limit", "anthropic")
    end

    it "allows nil provider" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:last_error][:provider]).to be_nil
      end

      metrics.record_error_event("execute_plan", "unknown_error", nil)
    end
  end

  describe "#record_retry_attempt" do
    it "increments retry attempt count" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:retry_attempts]).to eq(1)
        expect(state[:last_retry][:step]).to eq("execute_plan")
        expect(state[:last_retry][:provider]).to eq("anthropic")
        expect(state[:last_retry][:attempt]).to eq(2)
        expect(state[:last_retry][:timestamp]).to be_a(Time)
      end

      metrics.record_retry_attempt("execute_plan", "anthropic", 2)
    end
  end

  describe "#harness_metrics" do
    context "when no metrics exist" do
      it "returns metrics with zeros" do
        result = metrics.harness_metrics

        expect(result[:provider_switches]).to eq(0)
        expect(result[:rate_limit_events]).to eq(0)
        expect(result[:user_feedback_requests]).to eq(0)
        expect(result[:error_events]).to eq(0)
        expect(result[:retry_attempts]).to eq(0)
      end
    end

    context "when metrics exist" do
      before do
        allow(persistence).to receive(:load_state).and_return(
          provider_switches: 5,
          rate_limit_events: 2,
          user_feedback_requests: 3,
          error_events: 1,
          retry_attempts: 4,
          current_provider: "anthropic",
          state: "running",
          last_updated: Time.now
        )
      end

      it "returns all harness metrics" do
        result = metrics.harness_metrics

        expect(result[:provider_switches]).to eq(5)
        expect(result[:rate_limit_events]).to eq(2)
        expect(result[:user_feedback_requests]).to eq(3)
        expect(result[:error_events]).to eq(1)
        expect(result[:retry_attempts]).to eq(4)
        expect(result[:current_provider]).to eq("anthropic")
        expect(result[:harness_state]).to eq("running")
        expect(result[:last_activity]).to be_a(Time)
      end
    end
  end

  describe "#performance_metrics" do
    before do
      allow(workflow_state).to receive(:completed_steps).and_return(["step1", "step2", "step3"])
      allow(workflow_state).to receive(:session_duration).and_return(3600) # 1 hour
      allow(persistence).to receive(:load_state).and_return(
        provider_switches: 2,
        rate_limit_events: 1,
        user_feedback_requests: 1,
        error_events: 1,
        retry_attempts: 2
      )
    end

    it "returns performance metrics" do
      result = metrics.performance_metrics

      expect(result).to have_key(:efficiency)
      expect(result).to have_key(:reliability)
      expect(result).to have_key(:performance)
    end

    describe "efficiency metrics" do
      it "calculates switches per step" do
        result = metrics.performance_metrics
        # 2 switches / 3 steps = 0.67
        expect(result[:efficiency][:provider_switches_per_step]).to eq(0.67)
      end

      it "calculates retries per step" do
        result = metrics.performance_metrics
        # 2 retries / 3 steps = 0.67
        expect(result[:efficiency][:average_retries_per_step]).to eq(0.67)
      end

      it "calculates feedback ratio" do
        result = metrics.performance_metrics
        # 1 feedback / 3 steps = 0.33
        expect(result[:efficiency][:user_feedback_ratio]).to eq(0.33)
      end
    end

    describe "reliability metrics" do
      it "calculates error rate" do
        result = metrics.performance_metrics
        # 1 error / (1 error + 3 completed) * 100 = 25%
        expect(result[:reliability][:error_rate]).to eq(25.0)
      end

      it "calculates rate limit frequency" do
        result = metrics.performance_metrics
        # 1 rate limit / 1 hour = 1.0 per hour
        expect(result[:reliability][:rate_limit_frequency]).to eq(1.0)
      end

      it "calculates success rate" do
        result = metrics.performance_metrics
        # 3 completed / (3 completed + 1 error) * 100 = 75%
        expect(result[:reliability][:success_rate]).to eq(75.0)
      end
    end

    describe "performance metrics" do
      it "includes session duration" do
        result = metrics.performance_metrics
        expect(result[:performance][:session_duration]).to eq(3600)
      end

      it "calculates steps per hour" do
        result = metrics.performance_metrics
        # 3 steps / 1 hour = 3.0
        expect(result[:performance][:steps_per_hour]).to eq(3.0)
      end

      it "calculates average step duration" do
        result = metrics.performance_metrics
        # 3600 seconds / 3 steps = 1200 seconds
        expect(result[:performance][:average_step_duration]).to eq(1200.0)
      end
    end
  end

  describe "edge cases" do
    context "when no steps are completed" do
      before do
        allow(workflow_state).to receive(:completed_steps).and_return([])
        allow(workflow_state).to receive(:session_duration).and_return(0)
      end

      it "handles division by zero gracefully" do
        result = metrics.performance_metrics

        expect(result[:efficiency][:provider_switches_per_step]).to eq(0)
        expect(result[:efficiency][:average_retries_per_step]).to eq(0)
        expect(result[:efficiency][:user_feedback_ratio]).to eq(0)
        expect(result[:reliability][:error_rate]).to eq(0)
        expect(result[:reliability][:rate_limit_frequency]).to eq(0)
        expect(result[:reliability][:success_rate]).to eq(100) # Default to 100% when no attempts
        expect(result[:performance][:steps_per_hour]).to eq(0)
        expect(result[:performance][:average_step_duration]).to eq(0)
      end
    end
  end
end
