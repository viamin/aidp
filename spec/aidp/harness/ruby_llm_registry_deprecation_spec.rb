# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::RubyLLMRegistry, "deprecation handling" do
  let(:registry) { described_class.new }
  let(:cache) { registry.deprecation_cache }

  # Seed test data before each test
  before do
    # Clear and seed with test data
    cache.clear!
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219", replacement: "claude-sonnet-4-5-20250929")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-7-sonnet-latest", replacement: "claude-sonnet-4-5")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-5-sonnet-20241022", replacement: "claude-sonnet-4-5-20250929")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-opus-20240229", replacement: "claude-opus-4-20250514")
  end

  after do
    # Clean up test cache
    cache.clear!
  end

  describe "#model_deprecated?" do
    it "returns true for deprecated Anthropic models" do
      expect(registry.model_deprecated?("claude-3-7-sonnet-20250219", "anthropic")).to be true
      expect(registry.model_deprecated?("claude-3-7-sonnet-latest", "anthropic")).to be true
      expect(registry.model_deprecated?("claude-3-5-sonnet-20241022", "anthropic")).to be true
      expect(registry.model_deprecated?("claude-3-opus-20240229", "anthropic")).to be true
    end

    it "returns false for non-deprecated models" do
      expect(registry.model_deprecated?("claude-sonnet-4-5-20250929", "anthropic")).to be false
      expect(registry.model_deprecated?("claude-3-5-haiku-20241022", "anthropic")).to be false
    end

    it "returns false when provider is nil" do
      expect(registry.model_deprecated?("claude-3-7-sonnet-20250219", nil)).to be false
    end
  end

  describe "#find_replacement_model" do
    it "finds replacement for deprecated Claude 3.7 Sonnet" do
      replacement = registry.find_replacement_model("claude-3-7-sonnet-20250219", provider: "anthropic")
      expect(replacement).not_to be_nil
      expect(replacement).to include("sonnet")
      expect(replacement).not_to eq("claude-3-7-sonnet-20250219")
      # Should be a newer model
      expect(["claude-sonnet-4-5-20250929", "claude-sonnet-4-5", "claude-sonnet-4-0"]).to include(replacement)
    end

    it "returns nil for unknown provider" do
      replacement = registry.find_replacement_model("claude-3-7-sonnet-20250219", provider: "unknown")
      expect(replacement).to be_nil
    end

    it "returns nil for non-existent deprecated model" do
      replacement = registry.find_replacement_model("nonexistent-model", provider: "anthropic")
      expect(replacement).to be_nil
    end
  end

  describe "#resolve_model with skip_deprecated" do
    it "returns nil for deprecated model when skip_deprecated is true" do
      result = registry.resolve_model("claude-3-7-sonnet-20250219", provider: "anthropic", skip_deprecated: true)
      expect(result).to be_nil
    end

    it "returns model ID for deprecated model when skip_deprecated is false" do
      result = registry.resolve_model("claude-3-7-sonnet-20250219", provider: "anthropic", skip_deprecated: false)
      expect(result).to eq("claude-3-7-sonnet-20250219")
    end

    it "returns non-deprecated model regardless of skip_deprecated" do
      result_skip = registry.resolve_model("claude-sonnet-4-5-20250929", provider: "anthropic", skip_deprecated: true)
      result_no_skip = registry.resolve_model("claude-sonnet-4-5-20250929", provider: "anthropic", skip_deprecated: false)

      expect(result_skip).to eq("claude-sonnet-4-5-20250929")
      expect(result_no_skip).to eq("claude-sonnet-4-5-20250929")
    end
  end

  describe "#models_for_tier with skip_deprecated" do
    it "excludes deprecated models from standard tier when skip_deprecated is true" do
      models = registry.models_for_tier("standard", provider: "anthropic", skip_deprecated: true)

      expect(models).not_to include("claude-3-7-sonnet-20250219")
      expect(models).not_to include("claude-3-7-sonnet-latest")
      expect(models).not_to include("claude-3-5-sonnet-20241022")
    end

    it "includes deprecated models when skip_deprecated is false" do
      models = registry.models_for_tier("standard", provider: "anthropic", skip_deprecated: false)

      expect(models).to include("claude-3-7-sonnet-20250219")
    end

    it "still returns non-deprecated models" do
      models = registry.models_for_tier("standard", provider: "anthropic", skip_deprecated: true)

      # Should have at least some standard tier models
      expect(models).not_to be_empty
      # Should include newer sonnet models
      expect(models.any? { |m| m.include?("sonnet-4") }).to be true
    end
  end

  describe "#extract_family_keyword" do
    it "extracts sonnet from model IDs" do
      expect(registry.send(:extract_family_keyword, "claude-3-7-sonnet-20250219")).to eq("sonnet")
      expect(registry.send(:extract_family_keyword, "claude-sonnet-4-5")).to eq("sonnet")
    end

    it "extracts haiku from model IDs" do
      expect(registry.send(:extract_family_keyword, "claude-3-5-haiku-20241022")).to eq("haiku")
    end

    it "extracts opus from model IDs" do
      expect(registry.send(:extract_family_keyword, "claude-3-opus-20240229")).to eq("opus")
    end

    it "returns nil for unknown families" do
      expect(registry.send(:extract_family_keyword, "gpt-4")).to eq("gpt-4")
      expect(registry.send(:extract_family_keyword, "unknown-model")).to be_nil
    end
  end
end
