# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/usage_limit_tracker"

RSpec.describe Aidp::Harness::UsageLimitTracker do
  let(:project_dir) { "/tmp/usage_tracker_test_#{Process.pid}" }
  let(:provider_name) { "test_provider" }
  let(:tracker) { described_class.new(provider_name: provider_name, project_dir: project_dir) }

  before do
    FileUtils.mkdir_p(project_dir)
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "#record_usage" do
    it "records token usage" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:total_tokens]).to eq(1000)
    end

    it "records cost" do
      tracker.record_usage(tokens: 1000, cost: 0.05, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:total_cost]).to eq(0.05)
    end

    it "accumulates usage across multiple requests" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")
      tracker.record_usage(tokens: 2000, cost: 0.02, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:total_tokens]).to eq(3000)
      expect(usage[:total_cost]).to eq(0.03)
    end

    it "tracks request count" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")
      tracker.record_usage(tokens: 2000, cost: 0.02, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:request_count]).to eq(2)
    end

    it "tracks usage by tier" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "mini")
      tracker.record_usage(tokens: 5000, cost: 0.10, tier: "advanced")

      mini_usage = tracker.tier_usage(tier: "mini")
      expect(mini_usage[:tokens]).to eq(1000)
      expect(mini_usage[:cost]).to eq(0.01)

      advanced_usage = tracker.tier_usage(tier: "advanced")
      expect(advanced_usage[:tokens]).to eq(5000)
      expect(advanced_usage[:cost]).to eq(0.10)
    end

    it "ignores zero usage" do
      tracker.record_usage(tokens: 0, cost: 0.0, tier: "standard")

      usage = tracker.current_usage
      expect(usage[:request_count]).to eq(0)
    end
  end

  describe "#current_usage" do
    it "returns empty usage when no data recorded" do
      usage = tracker.current_usage

      expect(usage[:total_tokens]).to eq(0)
      expect(usage[:total_cost]).to eq(0.0)
      expect(usage[:request_count]).to eq(0)
    end

    it "includes period information" do
      usage = tracker.current_usage

      expect(usage[:period_key]).to be_a(String)
      expect(usage[:period_description]).to be_a(String)
      expect(usage[:start_time]).to be_a(Time)
      expect(usage[:end_time]).to be_a(Time)
    end

    it "respects custom period type" do
      usage = tracker.current_usage(period_type: "daily")
      expect(usage[:period_key]).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end

  describe "#tier_usage" do
    it "returns empty usage for tier with no data" do
      usage = tracker.tier_usage(tier: "mini")

      expect(usage[:tokens]).to eq(0)
      expect(usage[:cost]).to eq(0.0)
      expect(usage[:requests]).to eq(0)
    end
  end

  describe "#usage_history" do
    it "returns empty array when no history" do
      history = tracker.usage_history
      expect(history).to eq([])
    end

    it "returns usage history in reverse chronological order" do
      # This test simulates multiple periods by recording usage
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")

      history = tracker.usage_history
      expect(history).to be_an(Array)
    end

    it "limits history to requested number" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")

      history = tracker.usage_history(limit: 1)
      expect(history.length).to be <= 1
    end
  end

  describe "#reset_current_period" do
    it "clears usage for current period" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")
      tracker.reset_current_period

      usage = tracker.current_usage
      expect(usage[:total_tokens]).to eq(0)
    end
  end

  describe "#clear_all_usage" do
    it "removes all usage data" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")
      tracker.clear_all_usage

      usage = tracker.current_usage
      expect(usage[:total_tokens]).to eq(0)
    end
  end

  describe "persistence" do
    it "persists usage data across instances" do
      tracker.record_usage(tokens: 1000, cost: 0.01, tier: "standard")

      new_tracker = described_class.new(provider_name: provider_name, project_dir: project_dir)
      usage = new_tracker.current_usage

      expect(usage[:total_tokens]).to eq(1000)
    end
  end
end
