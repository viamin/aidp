# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/usage_limit"

RSpec.describe Aidp::Harness::UsageLimit do
  describe ".from_config" do
    it "creates a UsageLimit from valid configuration" do
      config = {
        enabled: true,
        period: "monthly",
        reset_day: 15,
        max_tokens: 1_000_000,
        max_cost: 50.0,
        tier_limits: {
          mini: {max_tokens: 2_000_000, max_cost: 20.0},
          advanced: {max_tokens: 500_000, max_cost: 100.0}
        }
      }

      limit = described_class.from_config(config)

      expect(limit.enabled?).to be true
      expect(limit.period).to eq("monthly")
      expect(limit.reset_day).to eq(15)
      expect(limit.max_tokens).to eq(1_000_000)
      expect(limit.max_cost).to eq(50.0)
    end

    it "creates disabled limit from nil config" do
      limit = described_class.from_config(nil)
      expect(limit.enabled?).to be false
    end

    it "creates disabled limit from empty hash" do
      limit = described_class.from_config({})
      expect(limit.enabled?).to be false # enabled requires explicit true
    end

    it "defaults period to monthly" do
      limit = described_class.from_config({enabled: true})
      expect(limit.period).to eq("monthly")
    end

    it "defaults reset_day to 1" do
      limit = described_class.from_config({enabled: true})
      expect(limit.reset_day).to eq(1)
    end
  end

  describe "#limits_for_tier" do
    let(:config) do
      {
        enabled: true,
        period: "monthly",
        max_tokens: 500_000,
        max_cost: 25.0,
        tier_limits: {
          mini: {max_tokens: 1_000_000, max_cost: 10.0},
          advanced: {max_tokens: 200_000, max_cost: 50.0}
        }
      }
    end

    let(:limit) { described_class.from_config(config) }

    it "returns tier-specific limits when available" do
      limits = limit.limits_for_tier(:mini)
      expect(limits[:max_tokens]).to eq(1_000_000)
      expect(limits[:max_cost]).to eq(10.0)
    end

    it "returns advanced tier limits for thinking tier" do
      limits = limit.limits_for_tier(:thinking)
      expect(limits[:max_tokens]).to eq(200_000)
      expect(limits[:max_cost]).to eq(50.0)
    end

    it "falls back to global limits for unknown tier" do
      limits = limit.limits_for_tier(:unknown)
      expect(limits[:max_tokens]).to eq(500_000)
      expect(limits[:max_cost]).to eq(25.0)
    end
  end

  describe "#exceeds_limit?" do
    let(:limit) do
      described_class.from_config({
        enabled: true,
        max_tokens: 100_000,
        max_cost: 10.0
      })
    end

    it "returns exceeded: false when within limits" do
      result = limit.exceeds_limit?(current_tokens: 50_000, current_cost: 5.0)
      expect(result[:exceeded]).to be false
    end

    it "returns exceeded: true when tokens exceed limit" do
      result = limit.exceeds_limit?(current_tokens: 100_000, current_cost: 5.0)
      expect(result[:exceeded]).to be true
      expect(result[:reason]).to include("Token limit exceeded")
    end

    it "returns exceeded: true when cost exceeds limit" do
      result = limit.exceeds_limit?(current_tokens: 50_000, current_cost: 10.0)
      expect(result[:exceeded]).to be true
      expect(result[:reason]).to include("Cost limit exceeded")
    end

    it "returns exceeded: false when limits disabled" do
      disabled_limit = described_class.from_config({enabled: false})
      result = disabled_limit.exceeds_limit?(current_tokens: 1_000_000, current_cost: 1000.0)
      expect(result[:exceeded]).to be false
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      limit = described_class.from_config({enabled: true})
      expect(limit).to be_frozen
    end
  end

  describe "value equality" do
    it "considers two limits with same values as equal" do
      config = {enabled: true, period: "monthly", max_tokens: 100_000}
      limit1 = described_class.from_config(config)
      limit2 = described_class.from_config(config)

      expect(limit1).to eq(limit2)
      expect(limit1.hash).to eq(limit2.hash)
    end

    it "considers limits with different values as not equal" do
      limit1 = described_class.from_config({enabled: true, max_tokens: 100_000})
      limit2 = described_class.from_config({enabled: true, max_tokens: 200_000})

      expect(limit1).not_to eq(limit2)
    end
  end

  describe "#to_h" do
    it "converts to a hash representation" do
      limit = described_class.from_config({
        enabled: true,
        period: "monthly",
        reset_day: 1,
        max_tokens: 100_000
      })

      hash = limit.to_h
      expect(hash[:enabled]).to be true
      expect(hash[:period]).to eq("monthly")
      expect(hash[:max_tokens]).to eq(100_000)
    end
  end
end
