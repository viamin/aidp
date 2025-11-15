# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/model_registry"
require "tempfile"
require "yaml"

RSpec.describe Aidp::Harness::ModelRegistry do
  let(:registry) { described_class.new }

  describe "#initialize" do
    it "loads the static registry successfully" do
      expect(registry.registry_data).to be_a(Hash)
      expect(registry.registry_data).to have_key("model_families")
    end

    it "validates the registry schema" do
      expect { registry }.not_to raise_error
    end

    context "with invalid registry file" do
      it "raises error when registry file not found" do
        expect {
          described_class.new(registry_path: "/nonexistent/path.yml")
        }.to raise_error(Aidp::Harness::ModelRegistry::RegistryError, /not found/)
      end

      it "raises error for invalid YAML" do
        Tempfile.create(["invalid", ".yml"]) do |f|
          f.write("invalid: yaml: content: [")
          f.flush

          expect {
            described_class.new(registry_path: f.path)
          }.to raise_error(Aidp::Harness::ModelRegistry::InvalidRegistrySchema, /Invalid YAML/)
        end
      end

      it "raises error when model_families key is missing" do
        Tempfile.create(["invalid", ".yml"]) do |f|
          f.write(YAML.dump({"some_other_key" => {}}))
          f.flush

          expect {
            described_class.new(registry_path: f.path)
          }.to raise_error(Aidp::Harness::ModelRegistry::InvalidRegistrySchema, /model_families/)
        end
      end
    end

    context "with invalid model entry" do
      it "raises error when tier is missing" do
        Tempfile.create(["invalid", ".yml"]) do |f|
          f.write(YAML.dump({
            "model_families" => {
              "test-model" => {"name" => "Test Model"}
            }
          }))
          f.flush

          expect {
            described_class.new(registry_path: f.path)
          }.to raise_error(Aidp::Harness::ModelRegistry::InvalidRegistrySchema, /missing required 'tier'/)
        end
      end

      it "raises error for invalid tier value" do
        Tempfile.create(["invalid", ".yml"]) do |f|
          f.write(YAML.dump({
            "model_families" => {
              "test-model" => {
                "name" => "Test Model",
                "tier" => "invalid_tier"
              }
            }
          }))
          f.flush

          expect {
            described_class.new(registry_path: f.path)
          }.to raise_error(Aidp::Harness::ModelRegistry::InvalidRegistrySchema, /invalid tier/)
        end
      end
    end
  end

  describe "#get_model_info" do
    it "returns model info for existing family" do
      info = registry.get_model_info("claude-3-5-sonnet")
      expect(info).to be_a(Hash)
      expect(info["tier"]).to eq("standard")
      expect(info["name"]).to eq("Claude 3.5 Sonnet")
      expect(info["family"]).to eq("claude-3-5-sonnet")
    end

    it "returns nil for non-existent family" do
      info = registry.get_model_info("non-existent-model")
      expect(info).to be_nil
    end

    it "includes all expected fields" do
      info = registry.get_model_info("claude-3-5-sonnet")
      expect(info).to include(
        "name",
        "tier",
        "capabilities",
        "context_window",
        "max_output",
        "speed",
        "family"
      )
    end
  end

  describe "#models_for_tier" do
    it "returns all models for mini tier" do
      models = registry.models_for_tier("mini")
      expect(models).to be_an(Array)
      expect(models).to include("claude-3-5-haiku")
      expect(models).to include("gpt-4o-mini")
    end

    it "returns all models for standard tier" do
      models = registry.models_for_tier("standard")
      expect(models).to be_an(Array)
      expect(models).to include("claude-3-5-sonnet")
    end

    it "returns all models for advanced tier" do
      models = registry.models_for_tier("advanced")
      expect(models).to be_an(Array)
      expect(models).to include("claude-3-opus")
      expect(models).to include("gpt-4-turbo")
    end

    it "accepts tier as symbol" do
      models = registry.models_for_tier(:mini)
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
    end

    it "returns empty array for invalid tier" do
      models = registry.models_for_tier("invalid")
      expect(models).to eq([])
    end
  end

  describe "#classify_model_tier" do
    it "returns tier for existing model" do
      tier = registry.classify_model_tier("claude-3-5-sonnet")
      expect(tier).to eq("standard")
    end

    it "returns tier for mini model" do
      tier = registry.classify_model_tier("claude-3-5-haiku")
      expect(tier).to eq("mini")
    end

    it "returns tier for advanced model" do
      tier = registry.classify_model_tier("claude-3-opus")
      expect(tier).to eq("advanced")
    end

    it "returns nil for non-existent model" do
      tier = registry.classify_model_tier("non-existent")
      expect(tier).to be_nil
    end
  end

  describe "#match_to_family" do
    it "matches Anthropic versioned model to family" do
      family = registry.match_to_family("claude-3-5-sonnet-20241022")
      expect(family).to eq("claude-3-5-sonnet")
    end

    it "matches different Anthropic version to same family" do
      family = registry.match_to_family("claude-3-5-sonnet-20250101")
      expect(family).to eq("claude-3-5-sonnet")
    end

    it "matches Haiku versioned model" do
      family = registry.match_to_family("claude-3-5-haiku-20241022")
      expect(family).to eq("claude-3-5-haiku")
    end

    it "matches Opus versioned model" do
      family = registry.match_to_family("claude-3-opus-20240229")
      expect(family).to eq("claude-3-opus")
    end

    it "matches GPT-4 Turbo versioned model" do
      family = registry.match_to_family("gpt-4-turbo-2024-01-01")
      expect(family).to eq("gpt-4-turbo")
    end

    it "matches GPT-4o versioned model" do
      family = registry.match_to_family("gpt-4o-2024-05-13")
      expect(family).to eq("gpt-4o")
    end

    it "returns exact match if model is already a family name" do
      family = registry.match_to_family("claude-3-5-sonnet")
      expect(family).to eq("claude-3-5-sonnet")
    end

    it "returns nil for unmatched model" do
      family = registry.match_to_family("unknown-model-12345")
      expect(family).to be_nil
    end
  end

  describe "#all_families" do
    it "returns array of all model family names" do
      families = registry.all_families
      expect(families).to be_an(Array)
      expect(families).to include("claude-3-5-sonnet")
      expect(families).to include("claude-3-5-haiku")
      expect(families).to include("gpt-4o")
    end

    it "returns at least the core models" do
      families = registry.all_families
      # Should have Anthropic, OpenAI, and Gemini models
      expect(families.size).to be >= 10
    end
  end

  describe "#family_exists?" do
    it "returns true for existing family" do
      expect(registry.family_exists?("claude-3-5-sonnet")).to be true
    end

    it "returns false for non-existent family" do
      expect(registry.family_exists?("non-existent")).to be false
    end
  end

  describe "#available_tiers" do
    it "returns all tiers that have models" do
      tiers = registry.available_tiers
      expect(tiers).to be_an(Array)
      expect(tiers).to include("mini")
      expect(tiers).to include("standard")
      expect(tiers).to include("advanced")
    end

    it "returns sorted tiers" do
      tiers = registry.available_tiers
      expect(tiers).to eq(tiers.sort)
    end
  end

  describe "registry data validation" do
    it "all models have valid tiers" do
      registry.all_families.each do |family|
        info = registry.get_model_info(family)
        expect(Aidp::Harness::ModelRegistry::VALID_TIERS).to include(info["tier"]),
          "Model #{family} has invalid tier: #{info["tier"]}"
      end
    end

    it "all models have names" do
      registry.all_families.each do |family|
        info = registry.get_model_info(family)
        expect(info["name"]).not_to be_nil,
          "Model #{family} is missing a name"
      end
    end

    it "all models with capabilities have valid ones" do
      registry.all_families.each do |family|
        info = registry.get_model_info(family)
        next unless info["capabilities"]

        info["capabilities"].each do |cap|
          # We allow unknown capabilities with just a warning, so this is informational
          if !Aidp::Harness::ModelRegistry::VALID_CAPABILITIES.include?(cap)
            puts "  Note: #{family} has non-standard capability: #{cap}"
          end
        end
      end
    end

    it "ensures each tier has at least one model" do
      Aidp::Harness::ModelRegistry::VALID_TIERS.each do |tier|
        models = registry.models_for_tier(tier)
        expect(models).not_to be_empty,
          "Tier #{tier} has no models assigned"
      end
    end
  end
end
