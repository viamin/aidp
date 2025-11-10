# frozen_string_literal: true

require "spec_helper"
require "aidp/providers/capability_registry"
require "aidp/providers/base"

RSpec.describe Aidp::Providers::CapabilityRegistry do
  let(:registry) { described_class.new }

  # Mock provider helper
  def create_mock_provider(name, caps = {}, mcp: false, dangerous: false)
    provider = instance_double(Aidp::Providers::Base)
    allow(provider).to receive(:name).and_return(name)
    allow(provider).to receive(:display_name).and_return(name.capitalize)
    allow(provider).to receive(:capabilities).and_return(caps)
    allow(provider).to receive(:supports_mcp?).and_return(mcp)
    allow(provider).to receive(:supports_dangerous_mode?).and_return(dangerous)
    allow(provider).to receive(:available?).and_return(true)
    allow(provider).to receive(:dangerous_mode_enabled?).and_return(false)
    allow(provider).to receive(:health_status).and_return("healthy")
    provider
  end

  describe "#initialize" do
    it "initializes with empty capabilities and providers" do
      expect(registry.registered_providers).to eq([])
    end
  end

  describe "#register" do
    let(:provider) do
      create_mock_provider(
        "anthropic",
        {
          reasoning_tiers: ["mini", "standard"],
          context_window: 200_000,
          supports_json_mode: true,
          supports_vision: true,
          streaming: true
        },
        mcp: true,
        dangerous: false
      )
    end

    it "registers a provider with its capabilities" do
      expect(Aidp).to receive(:log_debug).with(
        "CapabilityRegistry",
        "registered provider",
        hash_including(provider: "anthropic")
      )

      registry.register(provider)

      expect(registry.registered_providers).to include("anthropic")
    end

    it "includes supports_mcp from provider method" do
      registry.register(provider)

      caps = registry.capabilities_for("anthropic")
      expect(caps[:supports_mcp]).to be true
    end

    it "includes supports_dangerous_mode from provider method" do
      registry.register(provider)

      caps = registry.capabilities_for("anthropic")
      expect(caps[:supports_dangerous_mode]).to be false
    end

    it "registers multiple providers" do
      provider2 = create_mock_provider("openai", {streaming: true})

      registry.register(provider)
      registry.register(provider2)

      expect(registry.registered_providers).to match_array(["anthropic", "openai"])
    end
  end

  describe "#unregister" do
    let(:provider) { create_mock_provider("test_provider", {streaming: true}) }

    before do
      registry.register(provider)
    end

    it "removes provider from registry" do
      registry.unregister("test_provider")

      expect(registry.registered_providers).not_to include("test_provider")
      expect(registry.capabilities_for("test_provider")).to be_nil
    end
  end

  describe "#capabilities_for" do
    let(:provider) do
      create_mock_provider("test", {context_window: 100_000, streaming: true})
    end

    before do
      registry.register(provider)
    end

    it "returns capabilities hash for registered provider" do
      caps = registry.capabilities_for("test")

      expect(caps).to be_a(Hash)
      expect(caps[:context_window]).to eq(100_000)
      expect(caps[:streaming]).to be true
    end

    it "returns nil for unregistered provider" do
      expect(registry.capabilities_for("unknown")).to be_nil
    end
  end

  describe "#has_capability?" do
    let(:provider) do
      create_mock_provider(
        "test",
        {
          supports_vision: true,
          supports_tool_use: false,
          context_window: 128_000,
          reasoning_tiers: ["mini", "standard"]
        }
      )
    end

    before do
      registry.register(provider)
    end

    context "when checking boolean capabilities" do
      it "returns true for truthy capability without value check" do
        expect(registry.has_capability?("test", :supports_vision)).to be true
      end

      it "returns false for falsy capability without value check" do
        expect(registry.has_capability?("test", :supports_tool_use)).to be false
      end

      it "returns true when capability matches specific value" do
        expect(registry.has_capability?("test", :supports_vision, true)).to be true
      end

      it "returns false when capability doesn't match specific value" do
        expect(registry.has_capability?("test", :supports_vision, false)).to be false
      end
    end

    context "when checking numeric capabilities" do
      it "returns true when value matches" do
        expect(registry.has_capability?("test", :context_window, 128_000)).to be true
      end

      it "returns false when value doesn't match" do
        expect(registry.has_capability?("test", :context_window, 100_000)).to be false
      end
    end

    context "when checking array capabilities" do
      it "matches exact array value" do
        expect(registry.has_capability?("test", :reasoning_tiers, ["mini", "standard"])).to be true
      end
    end

    it "returns false for unregistered provider" do
      expect(registry.has_capability?("unknown", :streaming)).to be false
    end

    it "returns false for non-existent capability" do
      expect(registry.has_capability?("test", :non_existent)).to be false
    end
  end

  describe "#find_providers" do
    before do
      anthropic = create_mock_provider(
        "anthropic",
        {
          reasoning_tiers: ["mini", "standard", "thinking"],
          context_window: 200_000,
          supports_vision: true,
          streaming: true
        }
      )

      openai = create_mock_provider(
        "openai",
        {
          reasoning_tiers: ["mini", "standard"],
          context_window: 128_000,
          supports_vision: false,
          streaming: true
        }
      )

      gemini = create_mock_provider(
        "gemini",
        {
          reasoning_tiers: ["mini", "standard", "thinking"],
          context_window: 1_000_000,
          supports_vision: true,
          streaming: true
        }
      )

      registry.register(anthropic)
      registry.register(openai)
      registry.register(gemini)
    end

    it "finds providers with exact boolean match" do
      results = registry.find_providers(supports_vision: true)

      expect(results).to match_array(["anthropic", "gemini"])
    end

    it "finds providers with exact boolean false match" do
      results = registry.find_providers(supports_vision: false)

      expect(results).to include("openai")
    end

    it "finds providers by reasoning tier" do
      results = registry.find_providers(reasoning_tier: "thinking")

      expect(results).to match_array(["anthropic", "gemini"])
    end

    it "finds providers with minimum context window" do
      results = registry.find_providers(min_context_window: 150_000)

      expect(results).to match_array(["anthropic", "gemini"])
    end

    it "finds providers with maximum context window" do
      results = registry.find_providers(max_context_window: 150_000)

      expect(results).to include("openai")
    end

    it "finds providers matching multiple requirements" do
      results = registry.find_providers(
        supports_vision: true,
        min_context_window: 150_000,
        streaming: true
      )

      expect(results).to match_array(["anthropic", "gemini"])
    end

    it "returns empty array when no providers match" do
      results = registry.find_providers(
        supports_vision: true,
        reasoning_tier: "ultra_premium"
      )

      expect(results).to be_empty
    end

    it "returns all providers when no requirements given" do
      results = registry.find_providers

      expect(results).to match_array(["anthropic", "openai", "gemini"])
    end
  end

  describe "#registered_providers" do
    it "returns empty array when no providers registered" do
      expect(registry.registered_providers).to eq([])
    end

    it "returns array of provider names" do
      provider1 = create_mock_provider("provider1", {})
      provider2 = create_mock_provider("provider2", {})

      registry.register(provider1)
      registry.register(provider2)

      expect(registry.registered_providers).to match_array(["provider1", "provider2"])
    end
  end

  describe "#provider_info" do
    let(:provider) do
      provider = create_mock_provider(
        "test",
        {context_window: 100_000, streaming: true},
        mcp: true,
        dangerous: true
      )
      allow(provider).to receive(:dangerous_mode_enabled?).and_return(true)
      allow(provider).to receive(:available?).and_return(true)
      allow(provider).to receive(:health_status).and_return("healthy")
      provider
    end

    before do
      registry.register(provider)
    end

    it "returns detailed information for all providers" do
      info = registry.provider_info

      expect(info).to have_key("test")
      expect(info["test"][:display_name]).to eq("Test")
      expect(info["test"][:available]).to be true
      expect(info["test"][:dangerous_mode_enabled]).to be true
      expect(info["test"][:health_status]).to eq("healthy")
      expect(info["test"][:capabilities]).to include(context_window: 100_000)
    end

    it "returns empty hash when no providers registered" do
      empty_registry = described_class.new

      expect(empty_registry.provider_info).to eq({})
    end

    it "includes multiple providers" do
      provider2 = create_mock_provider("provider2", {streaming: false})
      registry.register(provider2)

      info = registry.provider_info

      expect(info.keys).to match_array(["test", "provider2"])
    end
  end

  describe "#compatibility_report" do
    let(:provider1) do
      create_mock_provider(
        "provider1",
        {
          streaming: true,
          supports_vision: true,
          context_window: 100_000
        }
      )
    end

    let(:provider2) do
      create_mock_provider(
        "provider2",
        {
          streaming: true,
          supports_vision: false,
          context_window: 200_000
        }
      )
    end

    before do
      registry.register(provider1)
      registry.register(provider2)
    end

    it "identifies common capabilities" do
      report = registry.compatibility_report("provider1", "provider2")

      expect(report[:common_capabilities]).to include(streaming: true)
    end

    it "identifies differences" do
      report = registry.compatibility_report("provider1", "provider2")

      expect(report[:differences]).to have_key(:supports_vision)
      expect(report[:differences][:supports_vision]).to eq(
        "provider1" => true,
        "provider2" => false
      )
    end

    it "calculates compatibility score" do
      report = registry.compatibility_report("provider1", "provider2")

      # 1 common (streaming) out of 5 total unique capabilities
      # supports_mcp and supports_dangerous_mode are added to both
      expect(report[:compatibility_score]).to be_a(Float)
      expect(report[:compatibility_score]).to be_between(0.0, 1.0)
    end

    it "returns error for non-existent provider" do
      report = registry.compatibility_report("provider1", "unknown")

      expect(report[:error]).to eq("Provider not found")
    end
  end

  describe "#capability_statistics" do
    before do
      provider1 = create_mock_provider(
        "provider1",
        {
          streaming: true,
          supports_vision: true,
          context_window: 100_000,
          reasoning_tiers: ["mini"]
        }
      )

      provider2 = create_mock_provider(
        "provider2",
        {
          streaming: true,
          supports_vision: false,
          context_window: 0,
          reasoning_tiers: []
        }
      )

      registry.register(provider1)
      registry.register(provider2)
    end

    it "counts total providers for each capability" do
      stats = registry.capability_statistics

      expect(stats[:streaming][:total_providers]).to eq(2)
    end

    it "counts supporting providers correctly for boolean true" do
      stats = registry.capability_statistics

      expect(stats[:streaming][:supporting_providers]).to eq(2)
      expect(stats[:supports_vision][:supporting_providers]).to eq(1)
    end

    it "counts supporting providers correctly for positive integers" do
      stats = registry.capability_statistics

      expect(stats[:context_window][:supporting_providers]).to eq(1)
    end

    it "counts supporting providers correctly for non-empty arrays" do
      stats = registry.capability_statistics

      expect(stats[:reasoning_tiers][:supporting_providers]).to eq(1)
    end

    it "lists providers supporting each capability" do
      stats = registry.capability_statistics

      expect(stats[:streaming][:providers]).to match_array(["provider1", "provider2"])
      expect(stats[:supports_vision][:providers]).to eq(["provider1"])
    end

    it "returns statistics for all capability keys" do
      stats = registry.capability_statistics

      described_class::CAPABILITY_KEYS.each do |key|
        expect(stats).to have_key(key)
      end
    end
  end

  describe "#clear" do
    let(:provider) { create_mock_provider("test", {streaming: true}) }

    before do
      registry.register(provider)
    end

    it "removes all providers" do
      registry.clear

      expect(registry.registered_providers).to be_empty
    end

    it "removes all capabilities" do
      registry.clear

      expect(registry.capabilities_for("test")).to be_nil
    end

    it "allows re-registration after clear" do
      registry.clear
      registry.register(provider)

      expect(registry.registered_providers).to include("test")
    end
  end

  describe "CAPABILITY_KEYS" do
    it "defines expected capability keys" do
      expected_keys = [
        :reasoning_tiers,
        :context_window,
        :supports_json_mode,
        :supports_tool_use,
        :supports_vision,
        :supports_file_upload,
        :streaming,
        :supports_mcp,
        :max_tokens,
        :supports_dangerous_mode
      ]

      expect(described_class::CAPABILITY_KEYS).to match_array(expected_keys)
    end

    it "is frozen" do
      expect(described_class::CAPABILITY_KEYS).to be_frozen
    end
  end
end
