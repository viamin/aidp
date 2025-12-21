# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Setup::InMemoryConfigAdapter do
  let(:project_dir) { "/test/project" }

  let(:config) do
    {
      harness: {
        default_provider: "anthropic",
        fallback_providers: ["gemini"]
      },
      providers: {
        anthropic: {
          type: "usage_based",
          model_family: "claude",
          thinking_tiers: {
            mini: { models: ["claude-3-5-haiku"] },
            standard: { models: ["claude-3-5-sonnet"] },
            pro: { models: ["claude-3-opus"] }
          }
        },
        gemini: {
          type: "usage_based",
          model_family: "gemini"
        }
      },
      thinking: {
        default_tier: "mini",
        max_tier: "pro",
        allow_provider_switch: true,
        permissions_by_tier: {
          mini: "read_only",
          pro: "full"
        },
        overrides: {
          "skill.complex_refactor" => "pro"
        }
      }
    }
  end

  subject(:adapter) { described_class.new(config, project_dir) }

  describe "#initialize" do
    it "accepts config hash and project_dir" do
      expect(adapter.project_dir).to eq(project_dir)
    end

    it "handles nil config gracefully" do
      nil_adapter = described_class.new(nil, project_dir)
      expect(nil_adapter.configured_providers).to eq([])
    end
  end

  describe "#harness_config" do
    it "returns harness configuration" do
      expect(adapter.harness_config[:default_provider]).to eq("anthropic")
      expect(adapter.harness_config[:fallback_providers]).to eq(["gemini"])
    end

    it "returns empty hash when harness not configured" do
      empty_adapter = described_class.new({}, project_dir)
      expect(empty_adapter.harness_config).to eq({})
    end
  end

  describe "#provider_config" do
    it "returns provider configuration by symbol key" do
      expect(adapter.provider_config(:anthropic)[:type]).to eq("usage_based")
    end

    it "returns provider configuration by string key" do
      expect(adapter.provider_config("anthropic")[:type]).to eq("usage_based")
    end

    it "returns empty hash for unconfigured provider" do
      expect(adapter.provider_config(:unknown)).to eq({})
    end
  end

  describe "#configured_providers" do
    it "returns list of configured provider names as strings" do
      expect(adapter.configured_providers).to contain_exactly("anthropic", "gemini")
    end
  end

  describe "#default_provider" do
    it "returns the default provider" do
      expect(adapter.default_provider).to eq("anthropic")
    end
  end

  describe "#fallback_providers" do
    it "returns array of fallback providers" do
      expect(adapter.fallback_providers).to eq(["gemini"])
    end
  end

  describe "#provider_type" do
    it "returns the provider type" do
      expect(adapter.provider_type("anthropic")).to eq("usage_based")
    end

    it "returns 'unknown' for unconfigured provider" do
      expect(adapter.provider_type("unknown")).to eq("unknown")
    end
  end

  describe "#model_family" do
    it "returns the model family for a provider" do
      expect(adapter.model_family("anthropic")).to eq("claude")
    end

    it "returns 'auto' as default" do
      config_without_family = { providers: { test: { type: "subscription" } } }
      adapter_without = described_class.new(config_without_family, project_dir)
      expect(adapter_without.model_family("test")).to eq("auto")
    end
  end

  describe "#provider_thinking_tiers" do
    it "returns thinking tiers for a provider" do
      tiers = adapter.provider_thinking_tiers("anthropic")
      expect(tiers[:mini][:models]).to eq(["claude-3-5-haiku"])
    end

    it "returns empty hash for provider without tiers" do
      expect(adapter.provider_thinking_tiers("gemini")).to eq({})
    end
  end

  describe "#models_for_tier" do
    it "returns models for a specific tier and provider" do
      expect(adapter.models_for_tier(:mini, "anthropic")).to eq(["claude-3-5-haiku"])
    end

    it "returns empty array for nonexistent tier" do
      expect(adapter.models_for_tier(:unknown, "anthropic")).to eq([])
    end

    it "returns empty array when provider is nil" do
      expect(adapter.models_for_tier(:mini, nil)).to eq([])
    end
  end

  describe "#configured_tiers" do
    it "returns all configured tiers for a provider" do
      expect(adapter.configured_tiers("anthropic")).to contain_exactly("mini", "standard", "pro")
    end
  end

  describe "#allow_provider_switch_for_tier?" do
    it "returns true when allowed" do
      expect(adapter.allow_provider_switch_for_tier?).to be true
    end

    it "returns false when explicitly disabled" do
      config_no_switch = { thinking: { allow_provider_switch: false } }
      adapter_no_switch = described_class.new(config_no_switch, project_dir)
      expect(adapter_no_switch.allow_provider_switch_for_tier?).to be false
    end
  end

  describe "#default_tier" do
    it "returns configured default tier" do
      expect(adapter.default_tier).to eq("mini")
    end

    it "returns 'mini' as default when not configured" do
      empty_adapter = described_class.new({}, project_dir)
      expect(empty_adapter.default_tier).to eq("mini")
    end
  end

  describe "#max_tier" do
    it "returns configured max tier" do
      expect(adapter.max_tier).to eq("pro")
    end

    it "returns 'pro' as default when not configured" do
      empty_adapter = described_class.new({}, project_dir)
      expect(empty_adapter.max_tier).to eq("pro")
    end
  end

  describe "#tier_override_for" do
    it "returns tier override for a skill key" do
      expect(adapter.tier_override_for("skill.complex_refactor")).to eq("pro")
    end

    it "returns nil for unknown key" do
      expect(adapter.tier_override_for("unknown.key")).to be_nil
    end
  end

  describe "#permission_for_tier" do
    it "returns permission for a tier" do
      expect(adapter.permission_for_tier(:mini)).to eq("read_only")
      expect(adapter.permission_for_tier(:pro)).to eq("full")
    end

    it "returns 'tools' as default for unconfigured tier" do
      expect(adapter.permission_for_tier(:unknown)).to eq("tools")
    end
  end

  describe "#provider_configured?" do
    it "returns true for configured providers" do
      expect(adapter.provider_configured?("anthropic")).to be true
    end

    it "returns false for unconfigured providers" do
      expect(adapter.provider_configured?("unknown")).to be false
    end
  end

  describe "#raw_config" do
    it "returns a duplicate of the config hash" do
      raw = adapter.raw_config
      expect(raw).to eq(config)
      expect(raw).not_to be(config) # Should be a dup
    end
  end
end
