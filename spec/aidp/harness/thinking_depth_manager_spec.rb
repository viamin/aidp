# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/harness/thinking_depth_manager"
require_relative "../../../lib/aidp/harness/capability_registry"
require_relative "../../../lib/aidp/harness/configuration"

RSpec.describe Aidp::Harness::ThinkingDepthManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:catalog_path) { File.join(temp_dir, ".aidp", "models_catalog.yml") }
  let(:config_path) { File.join(temp_dir, ".aidp", "aidp.yml") }

  let(:sample_catalog) do
    {
      "schema_version" => "1.0",
      "providers" => {
        "anthropic" => {
          "display_name" => "Anthropic",
          "models" => {
            "claude-3-haiku" => {"tier" => "mini", "cost_per_mtok_input" => 0.25},
            "claude-3-5-sonnet" => {"tier" => "standard", "cost_per_mtok_input" => 3.0},
            "claude-3-opus" => {"tier" => "pro", "cost_per_mtok_input" => 15.0}
          }
        },
        "openai" => {
          "display_name" => "OpenAI",
          "models" => {
            "gpt-4o-mini" => {"tier" => "mini", "cost_per_mtok_input" => 0.15},
            "o1-preview" => {"tier" => "thinking", "cost_per_mtok_input" => 15.0}
          }
        }
      },
      "tier_recommendations" => {
        "simple_edit" => {"recommended_tier" => "mini", "complexity_threshold" => 0.2},
        "standard_feature" => {"recommended_tier" => "standard", "complexity_threshold" => 0.5}
      }
    }
  end

  let(:sample_config) do
    {
      "harness" => {
        "default_provider" => "anthropic",
        "fallback_providers" => [],
        "work_loop" => {
          "enabled" => true
        }
      },
      "thinking" => {
        "default_tier" => "standard",
        "max_tier" => "pro",
        "allow_provider_switch" => true,
        "escalation" => {
          "on_fail_attempts" => 2,
          "on_complexity_threshold" => {
            "files_changed" => 5,
            "modules_touched" => 3
          }
        },
        "permissions_by_tier" => {
          "mini" => "safe",
          "standard" => "tools",
          "pro" => "dangerous"
        },
        "overrides" => {
          "skill.test" => "thinking"
        }
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "api_key" => "test-key",
          "models" => ["claude-3-5-sonnet"],
          "priority" => 1
        },
        "openai" => {
          "type" => "usage_based",
          "api_key" => "test-key",
          "models" => ["gpt-4o"],
          "priority" => 2
        }
      }
    }
  end

  before do
    FileUtils.mkdir_p(File.dirname(catalog_path))
    File.write(catalog_path, YAML.dump(sample_catalog))

    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, YAML.dump(sample_config))

    # Create and load registry
    @registry = Aidp::Harness::CapabilityRegistry.new(catalog_path: catalog_path)
    @registry.load_catalog

    @configuration = Aidp::Harness::Configuration.new(temp_dir)
    @manager = described_class.new(@configuration, registry: @registry)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  let(:registry) { @registry }
  let(:configuration) { @configuration }
  let(:manager) { @manager }

  describe "#initialize" do
    it "initializes with configuration and registry" do
      expect(manager.configuration).to eq(configuration)
      expect(manager.registry).to eq(registry)
    end

    it "creates registry automatically if not provided" do
      mgr = described_class.new(configuration, root_dir: temp_dir)
      expect(mgr.registry).to be_a(Aidp::Harness::CapabilityRegistry)
    end
  end

  describe "#current_tier" do
    it "defaults to config default_tier" do
      expect(manager.current_tier).to eq("standard")
    end

    it "returns set tier when changed" do
      manager.current_tier = "thinking"
      expect(manager.current_tier).to eq("thinking")
    end
  end

  describe "#current_tier=" do
    it "sets current tier" do
      manager.current_tier = "mini"
      expect(manager.current_tier).to eq("mini")
    end

    it "enforces max_tier cap" do
      manager.current_tier = "max"
      expect(manager.current_tier).to eq("pro") # Config max is pro
    end

    it "validates tier" do
      expect { manager.current_tier = "invalid" }.to raise_error(ArgumentError, /Invalid tier/)
    end

    it "logs tier changes" do
      manager.current_tier = "mini"
      expect(manager.tier_history.last[:to]).to eq("mini")
    end
  end

  describe "#max_tier" do
    it "returns config max_tier" do
      expect(manager.max_tier).to eq("pro")
    end

    it "returns session override when set" do
      manager.max_tier = "thinking"
      expect(manager.max_tier).to eq("thinking")
    end
  end

  describe "#max_tier=" do
    it "sets session max_tier" do
      manager.max_tier = "thinking"
      expect(manager.max_tier).to eq("thinking")
    end

    it "caps current tier if it exceeds new max" do
      manager.current_tier = "pro"
      manager.max_tier = "standard"
      expect(manager.current_tier).to eq("standard")
    end

    it "validates tier" do
      expect { manager.max_tier = "invalid" }.to raise_error(ArgumentError)
    end
  end

  describe "#default_tier" do
    it "returns config default_tier" do
      expect(manager.default_tier).to eq("standard")
    end
  end

  describe "#reset_to_default" do
    it "resets to default tier" do
      manager.current_tier = "pro"
      manager.max_tier = "thinking"

      manager.reset_to_default

      expect(manager.current_tier).to eq("standard")
      expect(manager.max_tier).to eq("pro") # Back to config max
    end

    it "resets escalation count" do
      manager.escalate_tier
      manager.escalate_tier
      expect(manager.escalation_count).to eq(2)

      manager.reset_to_default
      expect(manager.escalation_count).to eq(0)
    end
  end

  describe "#can_escalate?" do
    it "returns true when not at max" do
      manager.current_tier = "mini"
      expect(manager.can_escalate?).to be true
    end

    it "returns false when at max_tier" do
      manager.current_tier = "pro"
      expect(manager.can_escalate?).to be false
    end

    it "returns false when no next tier exists" do
      manager.max_tier = "max"
      manager.current_tier = "max"
      expect(manager.can_escalate?).to be false
    end
  end

  describe "#escalate_tier" do
    it "escalates to next tier" do
      manager.current_tier = "mini"
      result = manager.escalate_tier(reason: "test")
      expect(result).to eq("standard")
      expect(manager.current_tier).to eq("standard")
    end

    it "increments escalation count" do
      manager.escalate_tier
      expect(manager.escalation_count).to eq(1)

      manager.escalate_tier
      expect(manager.escalation_count).to eq(2)
    end

    it "logs escalation with reason" do
      manager.escalate_tier(reason: "high_complexity")
      expect(manager.tier_history.last[:reason]).to eq("high_complexity")
    end

    it "returns nil when cannot escalate" do
      manager.current_tier = "pro"
      result = manager.escalate_tier
      expect(result).to be_nil
    end

    it "respects max_tier" do
      manager.current_tier = "standard"
      manager.max_tier = "thinking"
      manager.escalate_tier
      expect(manager.current_tier).to eq("thinking")

      # Try to escalate beyond max
      result = manager.escalate_tier
      expect(result).to be_nil
      expect(manager.current_tier).to eq("thinking")
    end
  end

  describe "#de_escalate_tier" do
    it "de-escalates to previous tier" do
      manager.current_tier = "standard"
      result = manager.de_escalate_tier(reason: "success")
      expect(result).to eq("mini")
      expect(manager.current_tier).to eq("mini")
    end

    it "decrements escalation count" do
      manager.escalate_tier
      manager.escalate_tier
      expect(manager.escalation_count).to eq(2)

      manager.de_escalate_tier
      expect(manager.escalation_count).to eq(1)
    end

    it "does not go below zero escalation count" do
      manager.de_escalate_tier
      expect(manager.escalation_count).to eq(0)
    end

    it "logs de-escalation with reason" do
      manager.current_tier = "standard"
      manager.de_escalate_tier(reason: "cost_saving")
      expect(manager.tier_history.last[:reason]).to eq("cost_saving")
    end

    it "returns nil when at minimum tier" do
      manager.current_tier = "mini"
      result = manager.de_escalate_tier
      expect(result).to be_nil
    end
  end

  describe "#select_model_for_tier" do
    it "selects best model for tier and provider" do
      provider, model, data = manager.select_model_for_tier("mini", provider: "anthropic")
      expect(provider).to eq("anthropic")
      expect(model).to eq("claude-3-haiku")
      expect(data["tier"]).to eq("mini")
    end

    it "uses current tier when not specified" do
      manager.current_tier = "standard"
      _, model, _data = manager.select_model_for_tier
      expect(model).to eq("claude-3-5-sonnet")
    end

    it "switches provider when tier not available and switching allowed" do
      provider, model, _data = manager.select_model_for_tier("thinking", provider: "anthropic")
      expect(provider).to eq("openai") # Falls back to openai which has thinking
      expect(model).to eq("o1-preview")
    end

    it "returns nil when provider lacks tier and switching disabled" do
      config_data = sample_config.dup
      config_data["thinking"]["allow_provider_switch"] = false
      File.write(config_path, YAML.dump(config_data))

      configuration_no_switch = Aidp::Harness::Configuration.new(temp_dir)
      manager_no_switch = described_class.new(configuration_no_switch, registry: registry)

      result = manager_no_switch.select_model_for_tier("thinking", provider: "anthropic")
      expect(result).to be_nil
    end

    it "validates tier" do
      expect { manager.select_model_for_tier("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#tier_for_model" do
    it "returns tier for a specific model" do
      tier = manager.tier_for_model("anthropic", "claude-3-haiku")
      expect(tier).to eq("mini")
    end

    it "returns nil for unknown model" do
      tier = manager.tier_for_model("anthropic", "unknown")
      expect(tier).to be_nil
    end
  end

  describe "#tier_info" do
    it "returns comprehensive tier information" do
      info = manager.tier_info("standard")
      expect(info[:tier]).to eq("standard")
      expect(info[:next_tier]).to eq("thinking")
      expect(info[:previous_tier]).to eq("mini")
      expect(info[:at_max]).to be false
      expect(info[:at_min]).to be false
    end

    it "marks max tier correctly" do
      info = manager.tier_info("pro")
      expect(info[:at_max]).to be true
    end

    it "marks min tier correctly" do
      info = manager.tier_info("mini")
      expect(info[:at_min]).to be true
    end
  end

  describe "#recommend_tier_for_complexity" do
    it "recommends tier based on complexity score" do
      tier = manager.recommend_tier_for_complexity(0.1)
      expect(tier).to eq("mini")

      tier = manager.recommend_tier_for_complexity(0.4)
      expect(tier).to eq("standard")
    end

    it "caps recommendation at max_tier" do
      tier = manager.recommend_tier_for_complexity(0.99)
      expect(tier).to eq("pro") # Config max is pro, not max
    end
  end

  describe "#tier_override_for" do
    it "returns tier override for skill" do
      tier = manager.tier_override_for("skill.test")
      expect(tier).to eq("thinking")
    end

    it "returns nil for non-existent override" do
      tier = manager.tier_override_for("skill.nonexistent")
      expect(tier).to be_nil
    end

    it "caps override at max_tier" do
      config_data = sample_config.dup
      config_data["thinking"]["overrides"]["skill.extreme"] = "max"
      File.write(config_path, YAML.dump(config_data))

      config_with_override = Aidp::Harness::Configuration.new(temp_dir)
      manager_with_override = described_class.new(config_with_override, registry: registry)

      tier = manager_with_override.tier_override_for("skill.extreme")
      expect(tier).to eq("pro") # Capped at max_tier
    end
  end

  describe "#permission_for_current_tier" do
    it "returns permission level for current tier" do
      manager.current_tier = "mini"
      expect(manager.permission_for_current_tier).to eq("safe")

      manager.current_tier = "standard"
      expect(manager.permission_for_current_tier).to eq("tools")

      manager.current_tier = "pro"
      expect(manager.permission_for_current_tier).to eq("dangerous")
    end
  end

  describe "#escalation_count" do
    it "tracks number of escalations" do
      expect(manager.escalation_count).to eq(0)

      manager.escalate_tier
      expect(manager.escalation_count).to eq(1)

      manager.escalate_tier
      expect(manager.escalation_count).to eq(2)
    end
  end

  describe "#tier_history" do
    it "tracks tier changes" do
      manager.current_tier = "mini"
      manager.escalate_tier
      manager.escalate_tier

      history = manager.tier_history
      expect(history.size).to be >= 2
      expect(history.last[:to]).to eq("thinking")
    end

    it "returns a copy" do
      history1 = manager.tier_history
      manager.escalate_tier
      history2 = manager.tier_history

      expect(history1.size).not_to eq(history2.size)
    end
  end

  describe "#should_escalate_on_failures?" do
    it "returns true when failures meet threshold" do
      expect(manager.should_escalate_on_failures?(2)).to be true
      expect(manager.should_escalate_on_failures?(3)).to be true
    end

    it "returns false when below threshold" do
      expect(manager.should_escalate_on_failures?(1)).to be false
    end
  end

  describe "#should_escalate_on_complexity?" do
    it "returns true when files_changed exceeds threshold" do
      context = {files_changed: 6, modules_touched: 1}
      expect(manager.should_escalate_on_complexity?(context)).to be true
    end

    it "returns true when modules_touched exceeds threshold" do
      context = {files_changed: 1, modules_touched: 4}
      expect(manager.should_escalate_on_complexity?(context)).to be true
    end

    it "returns false when below all thresholds" do
      context = {files_changed: 2, modules_touched: 1}
      expect(manager.should_escalate_on_complexity?(context)).to be false
    end

    it "returns false when no thresholds configured" do
      config_data = sample_config.dup
      config_data["thinking"]["escalation"].delete("on_complexity_threshold")
      File.write(config_path, YAML.dump(config_data))

      config_no_thresholds = Aidp::Harness::Configuration.new(temp_dir)
      manager_no_thresholds = described_class.new(config_no_thresholds, registry: registry)

      context = {files_changed: 100, modules_touched: 100}
      expect(manager_no_thresholds.should_escalate_on_complexity?(context)).to be false
    end
  end

  describe "integration scenarios" do
    it "handles full escalation cycle" do
      manager.current_tier = "mini"

      # Escalate through tiers
      manager.escalate_tier(reason: "failure_1")
      expect(manager.current_tier).to eq("standard")

      manager.escalate_tier(reason: "failure_2")
      expect(manager.current_tier).to eq("thinking")

      manager.escalate_tier(reason: "failure_3")
      expect(manager.current_tier).to eq("pro")

      # Cannot escalate further (at max)
      result = manager.escalate_tier
      expect(result).to be_nil

      # De-escalate on success
      manager.de_escalate_tier(reason: "success")
      expect(manager.current_tier).to eq("thinking")

      # Check history
      history = manager.tier_history
      expect(history.size).to be >= 4
    end

    it "handles provider switching scenario" do
      # Start with anthropic at standard
      provider, model, _data = manager.select_model_for_tier("standard", provider: "anthropic")
      expect(provider).to eq("anthropic")
      expect(model).to eq("claude-3-5-sonnet")

      # Escalate to thinking - anthropic doesn't have it, switches to openai
      manager.escalate_tier
      provider, model, _data = manager.select_model_for_tier(manager.current_tier, provider: "anthropic")
      expect(provider).to eq("openai")
      expect(model).to eq("o1-preview")
    end
  end
end
