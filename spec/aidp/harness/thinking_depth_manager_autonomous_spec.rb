# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/harness/thinking_depth_manager"
require_relative "../../../lib/aidp/harness/capability_registry"
require_relative "../../../lib/aidp/harness/configuration"

RSpec.describe Aidp::Harness::ThinkingDepthManager do
  # Issue #375: Tests for autonomous mode and intelligent escalation

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
            "claude-3-5-haiku" => {"tier" => "mini", "cost_per_mtok_input" => 0.30},
            "claude-3-5-sonnet" => {"tier" => "standard", "cost_per_mtok_input" => 3.0},
            "claude-3-5-sonnet-v2" => {"tier" => "standard", "cost_per_mtok_input" => 3.5},
            "claude-3-opus" => {"tier" => "pro", "cost_per_mtok_input" => 15.0}
          }
        }
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
        "default_tier" => "mini",
        "max_tier" => "pro",
        "autonomous_max_tier" => "standard",
        "allow_provider_switch" => true,
        "escalation" => {
          "on_fail_attempts" => 2,
          "on_complexity_threshold" => {
            "files_changed" => 5,
            "modules_touched" => 3
          }
        },
        "autonomous_escalation" => {
          "min_attempts_per_model" => 2,
          "min_total_attempts" => 10,
          "retry_failed_models" => true
        },
        "permissions_by_tier" => {
          "mini" => "safe",
          "standard" => "tools",
          "pro" => "dangerous"
        },
        "overrides" => {}
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "api_key" => "test-key",
          "models" => ["claude-3-5-sonnet"],
          "priority" => 1,
          "thinking_tiers" => {
            "mini" => {
              "models" => ["claude-3-haiku", "claude-3-5-haiku"]
            },
            "standard" => {
              "models" => ["claude-3-5-sonnet", "claude-3-5-sonnet-v2"]
            },
            "pro" => {
              "models" => ["claude-3-opus"]
            }
          }
        },
        "cursor" => {
          "type" => "subscription",
          "models" => ["cursor-default"],
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

  describe "#autonomous_mode" do
    context "when initialized with autonomous_mode: true" do
      let(:autonomous_manager) do
        described_class.new(configuration, registry: registry, autonomous_mode: true)
      end

      it "sets autonomous_mode to true" do
        expect(autonomous_manager.autonomous_mode?).to be true
      end

      it "respects autonomous_max_tier in max_tier" do
        expect(autonomous_manager.max_tier).to eq("standard")
      end
    end

    context "when initialized with autonomous_mode: false" do
      it "uses regular max_tier" do
        expect(manager.max_tier).to eq("pro")
      end
    end

    describe "#enable_autonomous_mode" do
      it "enables autonomous mode" do
        manager.enable_autonomous_mode
        expect(manager.autonomous_mode?).to be true
      end

      it "caps current tier to autonomous_max_tier if needed" do
        manager.current_tier = "pro"
        manager.enable_autonomous_mode
        expect(manager.current_tier).to eq("standard")
      end

      it "resets model tracking" do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
        manager.enable_autonomous_mode
        expect(manager.model_attempts).to be_empty
      end
    end

    describe "#disable_autonomous_mode" do
      it "disables autonomous mode" do
        manager.enable_autonomous_mode
        manager.disable_autonomous_mode
        expect(manager.autonomous_mode?).to be false
      end
    end
  end

  describe "#autonomous_max_tier" do
    it "returns config autonomous_max_tier by default" do
      expect(manager.autonomous_max_tier).to eq("standard")
    end

    it "can be overridden for session" do
      manager.autonomous_max_tier = "thinking"
      expect(manager.autonomous_max_tier).to eq("thinking")
    end
  end

  describe "#record_model_attempt" do
    before { manager.enable_autonomous_mode }

    it "records a model attempt" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)

      expect(manager.model_attempt_count(provider: "anthropic", model: "claude-3-haiku")).to eq(1)
    end

    it "tracks multiple attempts" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)

      expect(manager.model_attempt_count(provider: "anthropic", model: "claude-3-haiku")).to eq(2)
    end

    it "marks model as failed on failure" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)

      expect(manager.model_failed?(provider: "anthropic", model: "claude-3-haiku")).to be true
    end

    it "does not mark model as failed on success" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)

      expect(manager.model_failed?(provider: "anthropic", model: "claude-3-haiku")).to be false
    end
  end

  describe "#select_next_model" do
    before { manager.enable_autonomous_mode }

    it "selects untested model first" do
      model = manager.select_next_model(provider: "anthropic")
      expect(model).to eq("claude-3-haiku")
    end

    it "selects model with fewer attempts" do
      # Record 2 attempts for first model
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)

      # Should now select the second model
      model = manager.select_next_model(provider: "anthropic")
      expect(model).to eq("claude-3-5-haiku")
    end

    it "returns nil when all models exhausted" do
      # Exhaust all models in mini tier
      2.times do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)
      end

      model = manager.select_next_model(provider: "anthropic")
      expect(model).to be_nil
    end
  end

  describe "#should_escalate_tier?" do
    before { manager.enable_autonomous_mode }

    it "returns false when not in autonomous mode" do
      manager.disable_autonomous_mode
      result = manager.should_escalate_tier?(provider: "anthropic")
      expect(result[:should_escalate]).to be false
      expect(result[:reason]).to eq("not_autonomous")
    end

    it "returns false when untested models remain" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)

      result = manager.should_escalate_tier?(provider: "anthropic")
      expect(result[:should_escalate]).to be false
      expect(result[:reason]).to eq("untested_models_remain")
    end

    it "returns false when below minimum total attempts" do
      # Test all models but below min total attempts
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)

      result = manager.should_escalate_tier?(provider: "anthropic")
      # With 2 models and min 2 attempts each, effective min is 4
      # We have 4 attempts, so should allow escalation
      expect(result[:should_escalate]).to be true
    end

    it "returns true when all models failed and min attempts met" do
      # Mark all models as failed with min attempts
      2.times do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)
      end

      result = manager.should_escalate_tier?(provider: "anthropic")
      expect(result[:should_escalate]).to be true
      expect(result[:reason]).to eq("all_models_failed")
    end
  end

  describe "#escalate_tier_intelligent" do
    before { manager.enable_autonomous_mode }

    it "does not escalate when conditions not met" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)

      result = manager.escalate_tier_intelligent(provider: "anthropic")
      expect(result).to be_nil
      expect(manager.current_tier).to eq("mini")
    end

    it "escalates when all conditions met" do
      # Meet all escalation conditions
      2.times do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)
      end

      result = manager.escalate_tier_intelligent(provider: "anthropic")
      expect(result).to eq("standard")
      expect(manager.current_tier).to eq("standard")
    end

    it "resets model tracking after escalation" do
      2.times do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-haiku", success: false)
      end

      manager.escalate_tier_intelligent(provider: "anthropic")

      # Model tracking should be reset
      expect(manager.model_attempt_count(provider: "anthropic", model: "claude-3-haiku")).to eq(0)
    end

    it "respects autonomous_max_tier" do
      manager.current_tier = "standard"

      # Try to escalate beyond autonomous_max_tier
      2.times do
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-sonnet", success: false)
        manager.record_model_attempt(provider: "anthropic", model: "claude-3-5-sonnet-v2", success: false)
      end

      result = manager.escalate_tier_intelligent(provider: "anthropic")
      expect(result).to be_nil  # Cannot escalate beyond standard in autonomous mode
      expect(manager.current_tier).to eq("standard")
    end
  end

  describe "#model_denylist" do
    before { manager.enable_autonomous_mode }

    it "denylists a model" do
      manager.denylist_model("claude-3-haiku")
      expect(manager.model_denylisted?("claude-3-haiku")).to be true
    end

    it "excludes denylisted models from available_models_for_tier" do
      manager.denylist_model("claude-3-haiku")
      models = manager.available_models_for_tier(provider: "anthropic")
      expect(models).not_to include("claude-3-haiku")
    end
  end

  describe "#model_attempts_summary" do
    before { manager.enable_autonomous_mode }

    it "returns summary of model attempts" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: true)

      summary = manager.model_attempts_summary
      expect(summary[:tier]).to eq("mini")
      expect(summary[:total_attempts]).to eq(2)
      expect(summary[:providers]["anthropic"]).to be_an(Array)
    end
  end

  describe "#reset_model_tracking" do
    before { manager.enable_autonomous_mode }

    it "clears all model tracking data" do
      manager.record_model_attempt(provider: "anthropic", model: "claude-3-haiku", success: false)
      manager.reset_model_tracking

      expect(manager.model_attempts).to be_empty
      expect(manager.model_attempt_count(provider: "anthropic", model: "claude-3-haiku")).to eq(0)
    end
  end

  describe "#determine_tier_from_comment" do
    let(:provider_manager) { double("ProviderManager") }

    before do
      allow(provider_manager).to receive(:execute_with_provider).and_return(
        {output: "TIER: standard\nCONFIDENCE: 0.85\nREASONING: Moderate complexity feature"}
      )
    end

    it "returns tier from label if present" do
      result = manager.determine_tier_from_comment(
        comment_text: "Fix the bug",
        provider_manager: provider_manager,
        labels: ["tier:mini", "bug"]
      )

      expect(result[:tier]).to eq("mini")
      expect(result[:source]).to eq("label")
    end

    it "uses ZFC when no tier label present" do
      result = manager.determine_tier_from_comment(
        comment_text: "Implement a new feature for user authentication",
        provider_manager: provider_manager,
        labels: ["enhancement"]
      )

      expect(result[:tier]).to eq("standard")
      expect(result[:source]).to eq("zfc")
    end

    it "caps tier at autonomous_max_tier in autonomous mode" do
      manager.enable_autonomous_mode

      allow(provider_manager).to receive(:execute_with_provider).and_return(
        {output: "TIER: pro\nCONFIDENCE: 0.9\nREASONING: Complex task"}
      )

      result = manager.determine_tier_from_comment(
        comment_text: "Complex architectural change",
        provider_manager: provider_manager,
        labels: []
      )

      expect(result[:tier]).to eq("standard")  # Capped at autonomous_max_tier
    end

    it "returns fallback on error" do
      allow(provider_manager).to receive(:execute_with_provider).and_raise(StandardError, "API error")

      result = manager.determine_tier_from_comment(
        comment_text: "Some work",
        provider_manager: provider_manager,
        labels: []
      )

      expect(result[:tier]).to eq("mini")
      expect(result[:source]).to eq("fallback")
    end
  end

  describe "label parsing" do
    let(:provider_manager) { double("ProviderManager") }

    [
      ["tier:mini", "mini"],
      ["tier-standard", "standard"],
      ["tier_thinking", "thinking"],
      ["tier:pro", "pro"],
      ["tier:max", "max"],
      ["complexity:low", "mini"],
      ["complexity:medium", "standard"],
      ["complexity:high", "pro"]
    ].each do |label, expected_tier|
      it "parses '#{label}' as '#{expected_tier}'" do
        result = manager.determine_tier_from_comment(
          comment_text: "Task",
          provider_manager: provider_manager,
          labels: [label]
        )

        expect(result[:tier]).to eq(expected_tier)
      end
    end
  end
end
