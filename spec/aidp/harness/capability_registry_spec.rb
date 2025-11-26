# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/harness/capability_registry"

RSpec.describe Aidp::Harness::CapabilityRegistry do
  let(:temp_dir) { Dir.mktmpdir }
  let(:catalog_path) { File.join(temp_dir, "models_catalog.yml") }

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
            },
            "claude-3-5-sonnet" => {
              "tier" => "standard",
              "context_window" => 200000,
              "cost_per_mtok_input" => 3.0
            },
            "claude-3-opus" => {
              "tier" => "pro",
              "context_window" => 200000,
              "cost_per_mtok_input" => 15.0
            }
          }
        },
        "openai" => {
          "display_name" => "OpenAI",
          "models" => {
            "gpt-4o-mini" => {
              "tier" => "mini",
              "context_window" => 128000,
              "cost_per_mtok_input" => 0.15
            },
            "o1-preview" => {
              "tier" => "thinking",
              "context_window" => 128000,
              "cost_per_mtok_input" => 15.0
            }
          }
        }
      },
      "tier_order" => %w[mini standard thinking pro max],
      "tier_recommendations" => {
        "simple_edit" => {
          "recommended_tier" => "mini",
          "complexity_threshold" => 0.2
        },
        "standard_feature" => {
          "recommended_tier" => "standard",
          "complexity_threshold" => 0.5
        },
        "complex_refactor" => {
          "recommended_tier" => "thinking",
          "complexity_threshold" => 0.7
        }
      }
    }
  end

  before do
    File.write(catalog_path, YAML.dump(sample_catalog))
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "accepts custom catalog path" do
      registry = described_class.new(catalog_path: catalog_path)
      expect(registry.catalog_path).to eq(catalog_path)
    end

    it "uses default path when not specified" do
      registry = described_class.new(root_dir: temp_dir)
      expect(registry.catalog_path).to eq(File.join(temp_dir, ".aidp", "models_catalog.yml"))
    end
  end

  describe "#load_catalog" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "loads catalog from YAML file" do
      expect(registry.load_catalog).to be true
      expect(registry.catalog["schema_version"]).to eq("1.0")
    end

    it "returns false when file does not exist" do
      registry = described_class.new(catalog_path: "/nonexistent/path.yml")
      expect(registry.load_catalog).to be false
    end

    it "returns false on invalid YAML" do
      File.write(catalog_path, "invalid: yaml: content: [")
      expect(registry.load_catalog).to be false
    end

    it "validates catalog structure" do
      invalid_catalog = {"schema_version" => "1.0"}
      File.write(catalog_path, YAML.dump(invalid_catalog))

      expect(registry.load_catalog).to be false
    end
  end

  describe "#provider_names" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns all provider names" do
      expect(registry.provider_names).to contain_exactly("anthropic", "openai")
    end

    it "returns empty array when catalog is empty" do
      File.write(catalog_path, YAML.dump({"providers" => {}}))
      registry.reload
      expect(registry.provider_names).to eq([])
    end
  end

  describe "#models_for_provider" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns all models for a provider" do
      models = registry.models_for_provider("anthropic")
      expect(models.keys).to contain_exactly("claude-3-haiku", "claude-3-5-sonnet", "claude-3-opus")
    end

    it "returns empty hash for non-existent provider" do
      expect(registry.models_for_provider("nonexistent")).to eq({})
    end
  end

  describe "#tier_for_model" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns tier for a specific model" do
      expect(registry.tier_for_model("anthropic", "claude-3-haiku")).to eq("mini")
      expect(registry.tier_for_model("anthropic", "claude-3-5-sonnet")).to eq("standard")
      expect(registry.tier_for_model("openai", "o1-preview")).to eq("thinking")
    end

    it "returns nil for non-existent model" do
      expect(registry.tier_for_model("anthropic", "nonexistent")).to be_nil
    end

    it "returns nil for non-existent provider" do
      expect(registry.tier_for_model("nonexistent", "model")).to be_nil
    end
  end

  describe "#models_by_tier" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns all models matching a tier across all providers" do
      results = registry.models_by_tier("mini")
      expect(results["anthropic"]).to contain_exactly("claude-3-haiku")
      expect(results["openai"]).to contain_exactly("gpt-4o-mini")
    end

    it "filters by specific provider" do
      results = registry.models_by_tier("mini", provider: "anthropic")
      expect(results.keys).to contain_exactly("anthropic")
      expect(results["anthropic"]).to contain_exactly("claude-3-haiku")
    end

    it "returns empty hash when no models match" do
      results = registry.models_by_tier("max")
      expect(results).to eq({})
    end

    it "raises error for invalid tier" do
      expect { registry.models_by_tier("invalid") }.to raise_error(ArgumentError, /Invalid tier/)
    end
  end

  describe "#model_info" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns complete model information" do
      info = registry.model_info("anthropic", "claude-3-5-sonnet")
      expect(info["tier"]).to eq("standard")
      expect(info["context_window"]).to eq(200000)
      expect(info["cost_per_mtok_input"]).to eq(3.0)
    end

    it "returns nil for non-existent model" do
      expect(registry.model_info("anthropic", "nonexistent")).to be_nil
    end
  end

  describe "#provider_display_name" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns display name from catalog" do
      expect(registry.provider_display_name("anthropic")).to eq("Anthropic")
    end

    it "returns provider name when display name not set" do
      expect(registry.provider_display_name("unknown")).to eq("unknown")
    end
  end

  describe "#supported_tiers" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns all tiers supported by a provider in priority order" do
      tiers = registry.supported_tiers("anthropic")
      expect(tiers).to eq(%w[mini standard pro])
    end

    it "returns empty array for non-existent provider" do
      expect(registry.supported_tiers("nonexistent")).to eq([])
    end
  end

  describe "#valid_tier?" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "returns true for valid tiers" do
      %w[mini standard thinking pro max].each do |tier|
        expect(registry.valid_tier?(tier)).to be true
      end
    end

    it "returns true for valid tiers as symbols" do
      %i[mini standard thinking pro max].each do |tier|
        expect(registry.valid_tier?(tier)).to be true
      end
    end

    it "returns false for invalid tiers" do
      expect(registry.valid_tier?("invalid")).to be false
      expect(registry.valid_tier?(nil)).to be false
      expect(registry.valid_tier?("")).to be false
    end
  end

  describe "#tier_priority" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "returns priority for each tier" do
      expect(registry.tier_priority("mini")).to eq(0)
      expect(registry.tier_priority("standard")).to eq(1)
      expect(registry.tier_priority("thinking")).to eq(2)
      expect(registry.tier_priority("pro")).to eq(3)
      expect(registry.tier_priority("max")).to eq(4)
    end

    it "returns priority for each tier as symbols" do
      expect(registry.tier_priority(:mini)).to eq(0)
      expect(registry.tier_priority(:standard)).to eq(1)
      expect(registry.tier_priority(:thinking)).to eq(2)
      expect(registry.tier_priority(:pro)).to eq(3)
      expect(registry.tier_priority(:max)).to eq(4)
    end

    it "returns nil for invalid tier" do
      expect(registry.tier_priority("invalid")).to be_nil
    end
  end

  describe "#compare_tiers" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "compares tiers correctly" do
      expect(registry.compare_tiers("mini", "standard")).to eq(-1)
      expect(registry.compare_tiers("standard", "standard")).to eq(0)
      expect(registry.compare_tiers("pro", "thinking")).to eq(1)
    end
  end

  describe "#next_tier" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "returns next higher tier" do
      expect(registry.next_tier("mini")).to eq("standard")
      expect(registry.next_tier("standard")).to eq("thinking")
      expect(registry.next_tier("thinking")).to eq("pro")
      expect(registry.next_tier("pro")).to eq("max")
    end

    it "returns nil when already at max" do
      expect(registry.next_tier("max")).to be_nil
    end

    it "raises error for invalid tier" do
      expect { registry.next_tier("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#previous_tier" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "returns next lower tier" do
      expect(registry.previous_tier("max")).to eq("pro")
      expect(registry.previous_tier("pro")).to eq("thinking")
      expect(registry.previous_tier("thinking")).to eq("standard")
      expect(registry.previous_tier("standard")).to eq("mini")
    end

    it "returns nil when already at mini" do
      expect(registry.previous_tier("mini")).to be_nil
    end

    it "raises error for invalid tier" do
      expect { registry.previous_tier("invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#best_model_for_tier" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns cheapest model for tier" do
      model_name, model_data = registry.best_model_for_tier("mini", "anthropic")
      expect(model_name).to eq("claude-3-haiku")
      expect(model_data["cost_per_mtok_input"]).to eq(0.25)
    end

    it "returns nil when provider has no models for tier" do
      result = registry.best_model_for_tier("max", "anthropic")
      expect(result).to be_nil
    end

    it "raises error for invalid tier" do
      expect { registry.best_model_for_tier("invalid", "anthropic") }.to raise_error(ArgumentError)
    end
  end

  describe "#tier_recommendations" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "returns tier recommendations from catalog" do
      recommendations = registry.tier_recommendations
      expect(recommendations["simple_edit"]["recommended_tier"]).to eq("mini")
      expect(recommendations["complex_refactor"]["recommended_tier"]).to eq("thinking")
    end
  end

  describe "#recommend_tier_for_complexity" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "recommends mini for low complexity" do
      expect(registry.recommend_tier_for_complexity(0.1)).to eq("mini")
    end

    it "recommends standard for medium complexity" do
      expect(registry.recommend_tier_for_complexity(0.4)).to eq("standard")
    end

    it "recommends thinking for high complexity" do
      expect(registry.recommend_tier_for_complexity(0.65)).to eq("thinking")
    end

    it "recommends max for very high complexity" do
      expect(registry.recommend_tier_for_complexity(0.99)).to eq("max")
    end
  end

  describe "#reload" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "reloads catalog from disk" do
      registry.load_catalog
      expect(registry.provider_names).to include("anthropic")

      # Modify catalog file
      new_catalog = sample_catalog.dup
      new_catalog["providers"]["newprovider"] = {"models" => {}}
      File.write(catalog_path, YAML.dump(new_catalog))

      registry.reload
      expect(registry.provider_names).to include("newprovider")
    end
  end

  describe "#stale?" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "returns true when not loaded" do
      expect(registry.stale?).to be true
    end

    it "returns false when recently loaded" do
      registry.load_catalog
      expect(registry.stale?(3600)).to be false
    end

    it "returns true when file modified after load" do
      registry.load_catalog
      sleep 0.1
      FileUtils.touch(catalog_path)
      expect(registry.stale?).to be true
    end
  end

  describe "#export_for_display" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    before { registry.load_catalog }

    it "exports structured data for display" do
      data = registry.export_for_display
      expect(data[:schema_version]).to eq("1.0")
      expect(data[:providers]).to be_an(Array)
      expect(data[:tier_order]).to eq(%w[mini standard thinking pro max])
    end

    it "includes provider details" do
      data = registry.export_for_display
      anthropic = data[:providers].find { |p| p[:name] == "anthropic" }
      expect(anthropic[:display_name]).to eq("Anthropic")
      expect(anthropic[:tiers]).to include("mini", "standard", "pro")
    end
  end

  describe "lazy loading" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "loads catalog on first access" do
      expect(registry.instance_variable_get(:@catalog_data)).to be_nil
      registry.provider_names
      expect(registry.instance_variable_get(:@catalog_data)).not_to be_nil
    end
  end

  describe "error handling" do
    let(:registry) { described_class.new(catalog_path: catalog_path) }

    it "handles missing tier gracefully" do
      invalid_catalog = sample_catalog.dup
      invalid_catalog["providers"]["test"] = {
        "models" => {
          "model1" => {"context_window" => 1000}
        }
      }
      File.write(catalog_path, YAML.dump(invalid_catalog))

      expect(registry.load_catalog).to be false
    end

    it "handles invalid tier value" do
      invalid_catalog = sample_catalog.dup
      invalid_catalog["providers"]["test"] = {
        "models" => {
          "model1" => {"tier" => "invalid_tier"}
        }
      }
      File.write(catalog_path, YAML.dump(invalid_catalog))

      expect(registry.load_catalog).to be false
    end
  end
end
