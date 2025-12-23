# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Setup::InMemoryConfigManager do
  let(:project_dir) { "/test/project" }

  let(:config) do
    {
      harness: {
        default_provider: "anthropic",
        fallback_providers: ["gemini"],
        retry: {
          enabled: true,
          max_attempts: 5
        },
        circuit_breaker: {
          enabled: true,
          failure_threshold: 3
        },
        rate_limit: {
          enabled: true,
          burst_limit: 20
        }
      },
      providers: {
        anthropic: {
          type: "usage_based",
          model_family: "claude",
          models: ["claude-3-5-sonnet"],
          max_tokens: 8192,
          default_flags: ["--verbose"],
          priority: 1,
          features: {
            vision: true,
            code_generation: true
          },
          auth: {
            api_key_env: "ANTHROPIC_API_KEY"
          },
          endpoints: {
            default: "https://api.anthropic.com"
          },
          model_weights: {
            "claude-3-5-sonnet" => 10
          },
          monitoring: {
            enabled: true,
            metrics_interval: 30
          }
        },
        gemini: {
          type: "usage_based",
          model_family: "gemini",
          priority: 2
        }
      }
    }
  end

  subject(:manager) { described_class.new(config, project_dir) }

  describe "#initialize" do
    it "accepts config hash and project_dir" do
      expect(manager.project_dir).to eq(project_dir)
    end

    it "handles nil config gracefully" do
      nil_manager = described_class.new(nil, project_dir)
      expect(nil_manager.provider_names).to eq([])
    end
  end

  describe "#config" do
    it "returns the full config" do
      expect(manager.config).to eq(config)
    end

    it "returns a copy to prevent mutation" do
      returned_config = manager.config
      expect(returned_config).not_to be(config)
      # Verify mutation doesn't affect internal state
      returned_config[:harness][:default_provider] = "modified"
      expect(manager.default_provider).to eq("anthropic")
    end

    it "ignores options parameter (for compatibility)" do
      expect(manager.config(force_reload: true)).to eq(config)
    end
  end

  describe "#harness_config" do
    it "returns harness configuration" do
      expect(manager.harness_config[:default_provider]).to eq("anthropic")
    end

    it "returns empty hash when not configured" do
      empty_manager = described_class.new({}, project_dir)
      expect(empty_manager.harness_config).to eq({})
    end
  end

  describe "#provider_config" do
    it "returns provider configuration by symbol" do
      expect(manager.provider_config(:anthropic)[:type]).to eq("usage_based")
    end

    it "returns provider configuration by string" do
      expect(manager.provider_config("anthropic")[:type]).to eq("usage_based")
    end

    it "returns nil for unconfigured provider" do
      expect(manager.provider_config(:unknown)).to be_nil
    end
  end

  describe "#all_providers" do
    it "returns all provider configurations" do
      providers = manager.all_providers
      expect(providers.keys).to contain_exactly(:anthropic, :gemini)
    end
  end

  describe "#provider_names" do
    it "returns provider names as strings" do
      expect(manager.provider_names).to contain_exactly("anthropic", "gemini")
    end
  end

  describe "#default_provider" do
    it "returns the default provider" do
      expect(manager.default_provider).to eq("anthropic")
    end
  end

  describe "#fallback_providers" do
    it "returns configured fallback providers" do
      expect(manager.fallback_providers).to eq(["gemini"])
    end

    it "filters to only configured providers" do
      config_with_bad_fallback = {
        harness: {fallback_providers: ["unknown", "gemini"]},
        providers: {gemini: {type: "usage_based"}}
      }
      mgr = described_class.new(config_with_bad_fallback, project_dir)
      expect(mgr.fallback_providers).to eq(["gemini"])
    end
  end

  describe "#config_valid?" do
    it "returns true when valid config" do
      expect(manager.config_valid?).to be true
    end

    it "returns false when no default provider" do
      invalid_manager = described_class.new({}, project_dir)
      expect(invalid_manager.config_valid?).to be_falsy
    end
  end

  describe "#validation_errors" do
    it "returns empty array" do
      expect(manager.validation_errors).to eq([])
    end
  end

  describe "#validation_warnings" do
    it "returns empty array" do
      expect(manager.validation_warnings).to eq([])
    end
  end

  describe "#reload_config" do
    it "is a no-op for in-memory config" do
      expect { manager.reload_config }.not_to raise_error
    end
  end

  describe "#config_summary" do
    it "returns summary hash" do
      summary = manager.config_summary
      expect(summary[:providers]).to eq(2)
      expect(summary[:default_provider]).to eq("anthropic")
      expect(summary[:fallback_providers]).to eq(1)
    end
  end

  describe "#provider_type" do
    it "returns provider type" do
      expect(manager.provider_type("anthropic")).to eq("usage_based")
    end

    it "returns nil for unknown provider" do
      expect(manager.provider_type("unknown")).to be_nil
    end
  end

  describe "#provider_models" do
    it "returns models for a provider" do
      expect(manager.provider_models("anthropic")).to eq(["claude-3-5-sonnet"])
    end

    it "returns empty array for provider without models" do
      expect(manager.provider_models("gemini")).to eq([])
    end
  end

  describe "#provider_features" do
    it "returns feature configuration" do
      features = manager.provider_features("anthropic")
      expect(features[:vision]).to be true
      expect(features[:code_generation]).to be true
    end

    it "returns defaults for provider without features" do
      features = manager.provider_features("gemini")
      expect(features[:code_generation]).to be true
      expect(features[:vision]).to be false
    end
  end

  describe "#provider_supports_feature?" do
    it "returns true for supported features" do
      expect(manager.provider_supports_feature?("anthropic", :vision)).to be true
    end

    it "returns false for unsupported features" do
      expect(manager.provider_supports_feature?("gemini", :vision)).to be false
    end
  end

  describe "#provider_priority" do
    it "returns configured priority" do
      expect(manager.provider_priority("anthropic")).to eq(1)
    end

    it "returns 1 as default" do
      config_no_priority = {providers: {test: {type: "sub"}}}
      mgr = described_class.new(config_no_priority, project_dir)
      expect(mgr.provider_priority("test")).to eq(1)
    end
  end

  describe "#retry_config" do
    it "returns retry configuration" do
      retry_cfg = manager.retry_config
      expect(retry_cfg[:enabled]).to be true
      expect(retry_cfg[:max_attempts]).to eq(5)
    end

    it "returns defaults when not configured" do
      empty_manager = described_class.new({}, project_dir)
      retry_cfg = empty_manager.retry_config
      expect(retry_cfg[:max_attempts]).to eq(3)
    end
  end

  describe "#circuit_breaker_config" do
    it "returns circuit breaker configuration" do
      cb_cfg = manager.circuit_breaker_config
      expect(cb_cfg[:enabled]).to be true
      expect(cb_cfg[:failure_threshold]).to eq(3)
    end
  end

  describe "#rate_limit_config" do
    it "returns rate limit configuration" do
      rl_cfg = manager.rate_limit_config
      expect(rl_cfg[:enabled]).to be true
      expect(rl_cfg[:burst_limit]).to eq(20)
    end
  end

  describe "#provider_monitoring_config" do
    it "returns monitoring configuration" do
      mon_cfg = manager.provider_monitoring_config("anthropic")
      expect(mon_cfg[:enabled]).to be true
      expect(mon_cfg[:metrics_interval]).to eq(30)
    end
  end

  describe "#provider_model_weights" do
    it "returns model weights" do
      weights = manager.provider_model_weights("anthropic")
      expect(weights["claude-3-5-sonnet"]).to eq(10)
    end
  end

  describe "#provider_max_tokens" do
    it "returns max tokens" do
      expect(manager.provider_max_tokens("anthropic")).to eq(8192)
    end
  end

  describe "#provider_default_flags" do
    it "returns default flags as strings" do
      expect(manager.provider_default_flags("anthropic")).to eq(["--verbose"])
    end
  end

  describe "#provider_auth_config" do
    it "returns auth configuration" do
      auth = manager.provider_auth_config("anthropic")
      expect(auth[:api_key_env]).to eq("ANTHROPIC_API_KEY")
    end
  end

  describe "#provider_endpoints" do
    it "returns endpoints configuration" do
      endpoints = manager.provider_endpoints("anthropic")
      expect(endpoints[:default]).to eq("https://api.anthropic.com")
    end
  end
end
