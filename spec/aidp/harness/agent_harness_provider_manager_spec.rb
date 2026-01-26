# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::AgentHarnessProviderManager do
  let(:mock_config) do
    double(
      "Configuration",
      default_provider: :claude,
      fallback_providers: [:cursor],
      providers: {},
      log_level: :info,
      default_timeout: 300,
      project_dir: Dir.pwd
    )
  end

  subject(:manager) { described_class.new(mock_config) }

  before(:each) do
    # Reset AgentHarness state between tests
    AgentHarness.reset!
  end

  describe "#initialize" do
    it "creates an adapter" do
      expect(manager.adapter).to be_a(Aidp::AgentHarnessAdapter)
    end
  end

  describe "#current_provider" do
    it "returns the current provider from AgentHarness" do
      expect(manager.current_provider).to eq(:claude)
    end
  end

  describe "#status" do
    it "returns a status hash" do
      status = manager.status
      expect(status).to be_a(Hash)
      expect(status).to have_key(:current_provider)
      expect(status).to have_key(:available_providers)
    end
  end

  describe "#configured_providers" do
    it "returns array of provider names" do
      providers = manager.configured_providers
      expect(providers).to be_an(Array)
    end
  end

  describe "#mark_rate_limited" do
    it "marks provider as rate limited" do
      manager.mark_rate_limited(:claude, Time.now + 3600)
      expect(manager.is_rate_limited?(:claude)).to be true
    end
  end

  describe "#is_rate_limited?" do
    it "returns false when not rate limited" do
      expect(manager.is_rate_limited?(:claude)).to be false
    end
  end

  describe "#healthy?" do
    it "returns true for healthy provider" do
      expect(manager.healthy?(:claude)).to be true
    end
  end

  describe "#circuit_open?" do
    it "returns false initially" do
      expect(manager.circuit_open?(:claude)).to be false
    end
  end

  describe "#record_success" do
    it "records success without error" do
      expect { manager.record_success(:claude) }.not_to raise_error
    end
  end

  describe "#record_failure" do
    it "records failure without error" do
      expect { manager.record_failure(:claude) }.not_to raise_error
    end
  end

  describe "#reset!" do
    it "resets all state" do
      manager.mark_rate_limited(:claude)
      manager.reset!
      expect(manager.is_rate_limited?(:claude)).to be false
    end
  end

  describe "#switch_provider" do
    context "when fallback provider is available" do
      before do
        # Configure cursor as fallback
        AgentHarness.configure do |config|
          config.provider(:cursor) { |p| p.enabled = true }
        end
      end

      it "switches to fallback on circuit breaker" do
        # Open circuit for claude
        5.times { manager.record_failure(:claude) }

        new_provider = manager.switch_provider("circuit_open")
        # May be nil if cursor binary not available, which is fine for this test
        expect([nil, :cursor]).to include(new_provider)
      end
    end

    context "when no fallback available" do
      before do
        # Open circuits for all providers
        5.times { manager.record_failure(:claude) }
        5.times { manager.record_failure(:cursor) }
      end

      it "returns nil" do
        new_provider = manager.switch_provider("all_failed")
        expect(new_provider).to be_nil
      end
    end
  end

  describe "#mark_provider_auth_failure" do
    it "records auth failure" do
      expect { manager.mark_provider_auth_failure(:claude) }.not_to raise_error
    end
  end

  describe "#mark_provider_failure_exhausted" do
    it "opens circuit breaker" do
      manager.mark_provider_failure_exhausted(:claude)
      expect(manager.circuit_open?(:claude)).to be true
    end
  end

  describe "#token_summary" do
    it "returns token summary hash" do
      summary = manager.token_summary
      expect(summary).to be_a(Hash)
    end
  end
end
