# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/usage_limit"
require_relative "../../../lib/aidp/harness/usage_limit_tracker"
require_relative "../../../lib/aidp/harness/usage_limit_enforcer"

RSpec.describe Aidp::Harness::UsageLimitEnforcer do
  let(:project_dir) { "/tmp/enforcer_test_#{Process.pid}" }
  let(:provider_name) { "test_provider" }
  let(:usage_limit) do
    Aidp::Harness::UsageLimit.from_config({
      enabled: true,
      period: "monthly",
      max_tokens: 100_000,
      max_cost: 10.0,
      tier_limits: {
        mini: {max_tokens: 200_000, max_cost: 5.0},
        advanced: {max_tokens: 50_000, max_cost: 20.0}
      }
    })
  end
  let(:tracker) { Aidp::Harness::UsageLimitTracker.new(provider_name: provider_name, project_dir: project_dir) }
  let(:enforcer) { described_class.new(provider_name: provider_name, usage_limit: usage_limit, tracker: tracker) }

  before do
    FileUtils.mkdir_p(project_dir)
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "#check_before_request" do
    it "does not raise when within limits" do
      expect { enforcer.check_before_request(tier: "standard") }.not_to raise_error
    end

    it "raises UsageLimitExceededError when tokens exceed limit" do
      # Record usage that exceeds limits
      tracker.record_usage(tokens: 100_000, cost: 0.0, tier: "standard")

      expect { enforcer.check_before_request(tier: "standard") }
        .to raise_error(Aidp::Harness::UsageLimitExceededError)
    end

    it "raises UsageLimitExceededError when cost exceeds limit" do
      tracker.record_usage(tokens: 0, cost: 10.0, tier: "standard")

      expect { enforcer.check_before_request(tier: "standard") }
        .to raise_error(Aidp::Harness::UsageLimitExceededError)
    end

    it "uses tier-specific limits" do
      # Mini has higher token limit (200k) but lower cost limit (5.0)
      tracker.record_usage(tokens: 150_000, cost: 0.0, tier: "mini")

      expect { enforcer.check_before_request(tier: "mini") }.not_to raise_error
    end

    it "raises error with descriptive message" do
      tracker.record_usage(tokens: 100_000, cost: 5.0, tier: "standard")

      expect { enforcer.check_before_request(tier: "standard") }
        .to raise_error(Aidp::Harness::UsageLimitExceededError, /Tokens: 100000\/100000/)
    end
  end

  describe "#record_after_request" do
    it "records usage to tracker" do
      enforcer.record_after_request(tokens: 5000, cost: 0.50, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:total_tokens]).to eq(5000)
      expect(usage[:total_cost]).to eq(0.50)
    end
  end

  describe "#check_headroom" do
    it "returns would_exceed: false when within limits" do
      result = enforcer.check_headroom(additional_tokens: 10_000, additional_cost: 1.0)
      expect(result[:would_exceed]).to be false
    end

    it "returns would_exceed: true when would exceed token limit" do
      tracker.record_usage(tokens: 95_000, cost: 0.0, tier: "standard")

      result = enforcer.check_headroom(additional_tokens: 10_000)
      expect(result[:would_exceed]).to be true
    end

    it "returns headroom information" do
      result = enforcer.check_headroom
      expect(result[:headroom][:tokens]).to eq(100_000)
      expect(result[:headroom][:cost]).to eq(10.0)
    end

    it "returns current usage" do
      tracker.record_usage(tokens: 50_000, cost: 5.0, tier: "standard")

      result = enforcer.check_headroom
      expect(result[:current][:tokens]).to eq(50_000)
      expect(result[:current][:cost]).to eq(5.0)
    end
  end

  describe "#usage_summary" do
    it "returns enabled: true when limits configured" do
      summary = enforcer.usage_summary
      expect(summary[:enabled]).to be true
    end

    it "returns provider name" do
      summary = enforcer.usage_summary
      expect(summary[:provider]).to eq(provider_name)
    end

    it "returns period information" do
      summary = enforcer.usage_summary
      expect(summary[:period]).to eq("monthly")
      expect(summary[:period_description]).to be_a(String)
    end

    it "returns tier summaries" do
      tracker.record_usage(tokens: 1000, cost: 0.10, tier: "mini")

      summary = enforcer.usage_summary
      expect(summary[:tiers]).to be_an(Array)

      mini_tier = summary[:tiers].find { |t| t[:tier] == "mini" }
      expect(mini_tier[:tokens]).to eq(1000)
    end

    it "calculates percentage used" do
      tracker.record_usage(tokens: 50_000, cost: 2.5, tier: "mini")

      summary = enforcer.usage_summary
      mini_tier = summary[:tiers].find { |t| t[:tier] == "mini" }

      # mini has 200k token limit, so 50k should be 25%
      expect(mini_tier[:token_percent]).to eq(25.0)
    end
  end

  describe "with disabled limits" do
    let(:disabled_limit) { Aidp::Harness::UsageLimit.from_config({enabled: false}) }
    let(:disabled_enforcer) { described_class.new(provider_name: provider_name, usage_limit: disabled_limit, tracker: tracker) }

    it "check_before_request does not raise" do
      tracker.record_usage(tokens: 1_000_000, cost: 1000.0, tier: "standard")
      expect { disabled_enforcer.check_before_request }.not_to raise_error
    end

    it "record_after_request does nothing" do
      disabled_enforcer.record_after_request(tokens: 5000, cost: 0.50)
      usage = tracker.current_usage
      # Disabled enforcer should not record usage, so tokens remain 0
      expect(usage[:total_tokens]).to eq(0)
    end

    it "usage_summary returns enabled: false" do
      summary = disabled_enforcer.usage_summary
      expect(summary[:enabled]).to be false
    end
  end
end

RSpec.describe Aidp::Harness::UsageLimitExceededError do
  it "includes provider name" do
    error = described_class.new(
      provider_name: "test",
      tier: "standard",
      current_tokens: 100_000,
      current_cost: 5.0,
      max_tokens: 100_000,
      max_cost: 10.0,
      period_description: "January 2024"
    )

    expect(error.provider_name).to eq("test")
    expect(error.message).to include("test")
  end

  it "converts to hash" do
    error = described_class.new(
      provider_name: "test",
      tier: "standard",
      current_tokens: 100_000,
      current_cost: 5.0,
      max_tokens: 100_000,
      max_cost: 10.0,
      period_description: "January 2024"
    )

    hash = error.to_h
    expect(hash[:type]).to eq("usage_limit_exceeded")
    expect(hash[:provider]).to eq("test")
    expect(hash[:current_tokens]).to eq(100_000)
  end
end
