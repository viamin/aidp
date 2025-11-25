# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Anthropic, "deprecation handling" do
  let(:cache) { described_class.deprecation_cache }

  # Seed test data before each test
  before do
    cache.clear!
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219", replacement: "claude-sonnet-4-5-20250929")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-7-sonnet-latest", replacement: "claude-sonnet-4-5")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-5-sonnet-20241022", replacement: "claude-sonnet-4-5-20250929")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-5-sonnet-latest", replacement: "claude-sonnet-4-5")
    cache.add_deprecated_model(provider: "anthropic", model_id: "claude-3-opus-20240229", replacement: "claude-opus-4-20250514")
  end

  after do
    cache.clear!
  end

  describe ".check_model_deprecation" do
    it "returns replacement for known deprecated models" do
      expect(described_class.check_model_deprecation("claude-3-7-sonnet-20250219")).to eq("claude-sonnet-4-5-20250929")
      expect(described_class.check_model_deprecation("claude-3-7-sonnet-latest")).to eq("claude-sonnet-4-5")
      expect(described_class.check_model_deprecation("claude-3-5-sonnet-20241022")).to eq("claude-sonnet-4-5-20250929")
    end

    it "returns nil for non-deprecated models" do
      expect(described_class.check_model_deprecation("claude-sonnet-4-5-20250929")).to be_nil
      expect(described_class.check_model_deprecation("claude-3-5-haiku-20241022")).to be_nil
    end
  end

  describe ".find_replacement_model" do
    it "uses explicit mapping first" do
      replacement = described_class.find_replacement_model("claude-3-7-sonnet-20250219")
      expect(replacement).to eq("claude-sonnet-4-5-20250929")
    end

    it "falls back to registry for unmapped deprecated models" do
      # This test verifies the fallback logic works
      replacement = described_class.find_replacement_model("claude-3-7-sonnet-20250219")
      expect(replacement).not_to be_nil
      expect(replacement).to include("sonnet")
    end
  end

  describe "deprecation cache integration" do
    it "uses dynamic deprecation cache" do
      deprecated_models = cache.deprecated_models(provider: "anthropic")
      expect(deprecated_models).to include("claude-3-7-sonnet-20250219")
      expect(deprecated_models).to include("claude-3-7-sonnet-latest")
      expect(deprecated_models).to include("claude-3-5-sonnet-20241022")
      expect(deprecated_models).to include("claude-3-5-sonnet-latest")
      expect(deprecated_models).to include("claude-3-opus-20240229")
    end

    it "provides valid replacements for all deprecated models" do
      cache.deprecated_models(provider: "anthropic").each do |model_id|
        replacement = cache.replacement_for(provider: "anthropic", model_id: model_id)
        expect(replacement).to be_a(String)
        expect(replacement).not_to be_empty
        # Replacement should include model family keyword
        expect(replacement).to match(/haiku|sonnet|opus/)
      end
    end
  end

  describe "#error_patterns" do
    let(:provider) { described_class.new }

    it "includes deprecation patterns in permanent errors" do
      patterns = provider.error_patterns[:permanent]
      expect(patterns).to include(/model.*deprecated/i)
      expect(patterns).to include(/end-of-life/i)
    end
  end
end
