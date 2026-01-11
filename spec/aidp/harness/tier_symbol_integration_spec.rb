# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/config_paths"
require_relative "../../../lib/aidp/harness/thinking_depth_manager"
require_relative "../../../lib/aidp/harness/capability_registry"
require_relative "../../../lib/aidp/harness/configuration"

RSpec.describe "Tier Symbol/String Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:catalog_path) { File.join(temp_dir, "models_catalog.yml") }
  let(:config_path) { File.join(temp_dir, "aidp.yml") }

  let(:sample_catalog) do
    {
      "schema_version" => "1.0",
      "providers" => {
        "anthropic" => {
          "display_name" => "Anthropic",
          "models" => {
            "claude-3-haiku" => {
              "tier" => "mini",
              "context_window" => 200000,
              "cost_per_mtok_input" => 0.25
            }
          }
        }
      }
    }
  end

  let(:sample_config) do
    {
      "thinking" => {
        "default_tier" => "mini",  # This will be loaded as a symbol by YAML
        "max_tier" => "max"
      }
    }
  end

  before do
    # Create catalog file
    File.write(catalog_path, sample_catalog.to_yaml)

    # Create config file
    File.write(config_path, sample_config.to_yaml)

    # Stub the config path
    allow(Aidp::ConfigPaths).to receive(:config_file).and_return(config_path)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "handles symbol tier values from YAML configuration" do
    # Create a configuration object with symbolized values
    # This simulates the issue where YAML loads tier values as symbols
    config = instance_double("Aidp::Harness::Configuration",
      default_tier: :mini,  # Symbol!
      max_tier: :max,
      autonomous_max_tier: :standard,
      escalation_config: {enabled: true},
      allow_provider_switch_for_tier?: true,
      project_dir: temp_dir)

    # Create registry
    registry = Aidp::Harness::CapabilityRegistry.new(catalog_path: catalog_path)

    # This should NOT raise an error even with symbol tiers
    expect {
      manager = Aidp::Harness::ThinkingDepthManager.new(config, registry: registry)
      manager.current_tier  # Access tier which triggers validation
    }.not_to raise_error

    # Create manager and verify it works
    manager = Aidp::Harness::ThinkingDepthManager.new(config, registry: registry)

    # All these should work with symbol tiers
    expect(manager.current_tier).to eq(:mini).or eq("mini")
    expect { manager.current_tier = :standard }.not_to raise_error
    expect { manager.can_escalate? }.not_to raise_error
    expect { manager.escalate_tier(reason: "testing") }.not_to raise_error
  end

  it "handles string tier values from YAML configuration" do
    config = instance_double("Aidp::Harness::Configuration",
      default_tier: "mini",  # String
      max_tier: "max",
      autonomous_max_tier: "standard",
      escalation_config: {enabled: true},
      allow_provider_switch_for_tier?: true,
      project_dir: temp_dir)

    registry = Aidp::Harness::CapabilityRegistry.new(catalog_path: catalog_path)

    expect {
      manager = Aidp::Harness::ThinkingDepthManager.new(config, registry: registry)
      manager.current_tier
    }.not_to raise_error

    manager = Aidp::Harness::ThinkingDepthManager.new(config, registry: registry)
    expect(manager.current_tier).to eq("mini")
  end

  it "handles mixed symbol and string comparisons" do
    registry = Aidp::Harness::CapabilityRegistry.new(catalog_path: catalog_path)

    # Symbol tier should work
    expect(registry.valid_tier?(:mini)).to be true
    expect(registry.valid_tier?("mini")).to be true

    # Tier priority should work with both
    expect(registry.tier_priority(:mini)).to eq(0)
    expect(registry.tier_priority("mini")).to eq(0)

    # Comparisons should work
    expect(registry.compare_tiers(:mini, "standard")).to eq(-1)
    expect(registry.compare_tiers("mini", :standard)).to eq(-1)
  end
end
