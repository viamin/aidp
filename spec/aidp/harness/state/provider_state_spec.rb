# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/provider_state"

RSpec.describe Aidp::Harness::State::ProviderState do
  let(:persistence) { instance_double("Persistence") }
  let(:provider_state) { described_class.new(persistence) }
  let(:empty_state) { {} }

  before do
    allow(persistence).to receive(:load_state).and_return(empty_state)
    allow(persistence).to receive(:save_state)
  end

  describe "#initialize" do
    it "initializes with persistence" do
      expect(provider_state).to be_a(described_class)
    end
  end

  describe "#provider_state" do
    context "when no provider state exists" do
      it "returns empty hash" do
        expect(provider_state.provider_state).to eq({})
      end
    end

    context "when provider state exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(
          provider_state: {anthropic: {status: "active"}}
        )
      end

      it "returns provider state" do
        expect(provider_state.provider_state).to eq({anthropic: {status: "active"}})
      end
    end
  end

  describe "#update_provider_state" do
    it "updates provider state and saves" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:provider_state]["anthropic"]).to eq({status: "active"})
        expect(state[:last_updated]).to be_a(Time)
      end

      provider_state.update_provider_state("anthropic", {status: "active"})
    end

    it "merges with existing provider state" do
      allow(persistence).to receive(:load_state).and_return(
        provider_state: {cursor: {status: "active"}}
      )

      expect(persistence).to receive(:save_state) do |state|
        expect(state[:provider_state]).to include(cursor: {status: "active"})
        expect(state[:provider_state]["anthropic"]).to eq({status: "rate_limited"})
      end

      provider_state.update_provider_state("anthropic", {status: "rate_limited"})
    end
  end

  describe "#rate_limit_info" do
    context "when no rate limit info exists" do
      it "returns empty hash" do
        expect(provider_state.rate_limit_info).to eq({})
      end
    end

    context "when rate limit info exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(
          rate_limit_info: {anthropic: {reset_time: "2025-10-15T12:00:00Z"}}
        )
      end

      it "returns rate limit info" do
        expect(provider_state.rate_limit_info).to eq(
          {anthropic: {reset_time: "2025-10-15T12:00:00Z"}}
        )
      end
    end
  end

  describe "#update_rate_limit_info" do
    let(:reset_time) { Time.now + 3600 }

    it "updates rate limit info with reset time" do
      expect(persistence).to receive(:save_state) do |state|
        info = state[:rate_limit_info]["anthropic"]
        expect(info[:reset_time]).to be_a(String)
        expect(info[:error_count]).to eq(3)
        expect(info[:last_updated]).to be_a(String)
      end

      provider_state.update_rate_limit_info("anthropic", reset_time, 3)
    end

    it "defaults error count to 0" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:rate_limit_info]["anthropic"][:error_count]).to eq(0)
      end

      provider_state.update_rate_limit_info("anthropic", reset_time)
    end
  end

  describe "#provider_rate_limited?" do
    context "when no rate limit info exists" do
      it "returns false" do
        expect(provider_state.provider_rate_limited?("anthropic")).to be false
      end
    end

    context "when reset time is in the future" do
      before do
        future_time = (Time.now + 3600).iso8601
        allow(persistence).to receive(:load_state).and_return(
          rate_limit_info: {"anthropic" => {reset_time: future_time}}
        )
      end

      it "returns true" do
        expect(provider_state.provider_rate_limited?("anthropic")).to be true
      end
    end

    context "when reset time is in the past" do
      before do
        past_time = (Time.now - 3600).iso8601
        allow(persistence).to receive(:load_state).and_return(
          rate_limit_info: {anthropic: {reset_time: past_time}}
        )
      end

      it "returns false" do
        expect(provider_state.provider_rate_limited?("anthropic")).to be false
      end
    end
  end

  describe "#next_provider_reset_time" do
    context "when no rate limits exist" do
      it "returns nil" do
        expect(provider_state.next_provider_reset_time).to be_nil
      end
    end

    context "when multiple providers have rate limits" do
      before do
        time1 = (Time.now + 1800).iso8601  # 30 minutes
        time2 = (Time.now + 3600).iso8601  # 60 minutes
        allow(persistence).to receive(:load_state).and_return(
          rate_limit_info: {
            anthropic: {reset_time: time2},
            cursor: {reset_time: time1}
          }
        )
      end

      it "returns the earliest reset time" do
        next_reset = provider_state.next_provider_reset_time
        expect(next_reset).to be_a(Time)
        # Should be cursor's reset time (earlier)
        expect(next_reset).to be < (Time.now + 1900)
      end
    end
  end

  describe "#token_usage" do
    context "when no token usage exists" do
      it "returns empty hash" do
        expect(provider_state.token_usage).to eq({})
      end
    end

    context "when token usage exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(
          token_usage: {"anthropic:claude-3" => {total_tokens: 1000}}
        )
      end

      it "returns token usage" do
        expect(provider_state.token_usage).to eq(
          {"anthropic:claude-3" => {total_tokens: 1000}}
        )
      end
    end
  end

  describe "#record_token_usage" do
    it "records new token usage" do
      expect(persistence).to receive(:save_state) do |state|
        usage = state[:token_usage]["anthropic:claude-3"]
        expect(usage[:input_tokens]).to eq(100)
        expect(usage[:output_tokens]).to eq(200)
        expect(usage[:total_tokens]).to eq(300)
        expect(usage[:cost]).to eq(0.01)
        expect(usage[:requests]).to eq(1)
      end

      provider_state.record_token_usage("anthropic", "claude-3", 100, 200, 0.01)
    end

    it "accumulates token usage for same provider:model" do
      allow(persistence).to receive(:load_state).and_return(
        token_usage: {
          "anthropic:claude-3" => {
            input_tokens: 50,
            output_tokens: 100,
            total_tokens: 150,
            cost: 0.005,
            requests: 1
          }
        }
      )

      expect(persistence).to receive(:save_state) do |state|
        usage = state[:token_usage]["anthropic:claude-3"]
        expect(usage[:input_tokens]).to eq(150)  # 50 + 100
        expect(usage[:output_tokens]).to eq(300) # 100 + 200
        expect(usage[:total_tokens]).to eq(450)  # 150 + 300
        expect(usage[:cost]).to eq(0.015)        # 0.005 + 0.01
        expect(usage[:requests]).to eq(2)         # 1 + 1
      end

      provider_state.record_token_usage("anthropic", "claude-3", 100, 200, 0.01)
    end
  end

  describe "#token_usage_summary" do
    context "when no token usage exists" do
      it "returns summary with zeros" do
        summary = provider_state.token_usage_summary
        expect(summary[:total_tokens]).to eq(0)
        expect(summary[:total_cost]).to eq(0)
        expect(summary[:total_requests]).to eq(0)
        expect(summary[:by_provider_model]).to eq({})
      end
    end

    context "when token usage exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(
          token_usage: {
            "anthropic:claude-3" => {
              input_tokens: 100,
              output_tokens: 200,
              total_tokens: 300,
              cost: 0.01,
              requests: 1
            },
            "cursor:gpt-4" => {
              input_tokens: 50,
              output_tokens: 100,
              total_tokens: 150,
              cost: 0.005,
              requests: 1
            }
          }
        )
      end

      it "returns aggregated summary" do
        summary = provider_state.token_usage_summary
        expect(summary[:total_tokens]).to eq(450)     # 300 + 150
        expect(summary[:total_cost]).to eq(0.015)     # 0.01 + 0.005
        expect(summary[:total_requests]).to eq(2)      # 1 + 1
        expect(summary[:by_provider_model].size).to eq(2)
      end
    end
  end
end
