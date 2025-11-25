# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Aidp::Harness::DeprecationCache do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cache_path) { File.join(temp_dir, "deprecated_models.json") }
  let(:cache) { described_class.new(cache_path: cache_path) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#add_deprecated_model" do
    it "adds a model to the deprecation cache" do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "claude-3-7-sonnet-20250219",
        replacement: "claude-sonnet-4-5-20250929",
        reason: "Model deprecated by Anthropic"
      )

      expect(cache.deprecated?(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")).to be true
    end

    it "saves the cache to disk" do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "test-model",
        replacement: "new-model"
      )

      expect(File.exist?(cache_path)).to be true

      # Verify persistence by creating a new cache instance
      new_cache = described_class.new(cache_path: cache_path)
      expect(new_cache.deprecated?(provider: "anthropic", model_id: "test-model")).to be true
    end

    it "allows adding models without replacements" do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "old-model",
        replacement: nil,
        reason: "Deprecated without replacement"
      )

      expect(cache.deprecated?(provider: "anthropic", model_id: "old-model")).to be true
      expect(cache.replacement_for(provider: "anthropic", model_id: "old-model")).to be_nil
    end
  end

  describe "#deprecated?" do
    before do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "claude-3-7-sonnet-20250219",
        replacement: "claude-sonnet-4-5-20250929"
      )
    end

    it "returns true for deprecated models" do
      expect(cache.deprecated?(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")).to be true
    end

    it "returns false for non-deprecated models" do
      expect(cache.deprecated?(provider: "anthropic", model_id: "claude-sonnet-4-5-20250929")).to be false
    end

    it "returns false for unknown providers" do
      expect(cache.deprecated?(provider: "unknown", model_id: "some-model")).to be false
    end
  end

  describe "#replacement_for" do
    before do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "old-model",
        replacement: "new-model"
      )
    end

    it "returns replacement for deprecated models" do
      expect(cache.replacement_for(provider: "anthropic", model_id: "old-model")).to eq("new-model")
    end

    it "returns nil for non-deprecated models" do
      expect(cache.replacement_for(provider: "anthropic", model_id: "new-model")).to be_nil
    end
  end

  describe "#deprecated_models" do
    before do
      cache.add_deprecated_model(provider: "anthropic", model_id: "model-1", replacement: "new-1")
      cache.add_deprecated_model(provider: "anthropic", model_id: "model-2", replacement: "new-2")
      cache.add_deprecated_model(provider: "openai", model_id: "gpt-old", replacement: "gpt-new")
    end

    it "returns all deprecated models for a provider" do
      models = cache.deprecated_models(provider: "anthropic")
      expect(models).to contain_exactly("model-1", "model-2")
    end

    it "returns empty array for providers with no deprecated models" do
      expect(cache.deprecated_models(provider: "unknown")).to eq([])
    end
  end

  describe "#remove_deprecated_model" do
    before do
      cache.add_deprecated_model(provider: "anthropic", model_id: "test-model", replacement: "new-model")
    end

    it "removes a model from the cache" do
      cache.remove_deprecated_model(provider: "anthropic", model_id: "test-model")
      expect(cache.deprecated?(provider: "anthropic", model_id: "test-model")).to be false
    end

    it "persists the removal" do
      cache.remove_deprecated_model(provider: "anthropic", model_id: "test-model")

      new_cache = described_class.new(cache_path: cache_path)
      expect(new_cache.deprecated?(provider: "anthropic", model_id: "test-model")).to be false
    end
  end

  describe "#info" do
    before do
      cache.add_deprecated_model(
        provider: "anthropic",
        model_id: "old-model",
        replacement: "new-model",
        reason: "Deprecated by provider"
      )
    end

    it "returns full deprecation metadata" do
      info = cache.info(provider: "anthropic", model_id: "old-model")

      expect(info).to be_a(Hash)
      expect(info["replacement"]).to eq("new-model")
      expect(info["reason"]).to eq("Deprecated by provider")
      expect(info["deprecated_at"]).to match(/^\d{4}-\d{2}-\d{2}T/)
    end

    it "returns nil for non-deprecated models" do
      expect(cache.info(provider: "anthropic", model_id: "unknown")).to be_nil
    end
  end

  describe "#clear!" do
    before do
      cache.add_deprecated_model(provider: "anthropic", model_id: "model-1", replacement: "new-1")
      cache.add_deprecated_model(provider: "openai", model_id: "model-2", replacement: "new-2")
    end

    it "removes all deprecations" do
      cache.clear!

      expect(cache.deprecated?(provider: "anthropic", model_id: "model-1")).to be false
      expect(cache.deprecated?(provider: "openai", model_id: "model-2")).to be false
    end

    it "persists the clearing" do
      cache.clear!

      new_cache = described_class.new(cache_path: cache_path)
      expect(new_cache.stats[:total_deprecated]).to eq(0)
    end
  end

  describe "#stats" do
    before do
      cache.add_deprecated_model(provider: "anthropic", model_id: "model-1", replacement: "new-1")
      cache.add_deprecated_model(provider: "anthropic", model_id: "model-2", replacement: "new-2")
      cache.add_deprecated_model(provider: "openai", model_id: "gpt-old", replacement: "gpt-new")
    end

    it "returns cache statistics" do
      stats = cache.stats

      expect(stats[:total_deprecated]).to eq(3)
      expect(stats[:providers]).to contain_exactly("anthropic", "openai")
      expect(stats[:by_provider]).to eq({"anthropic" => 2, "openai" => 1})
    end
  end

  describe "persistence" do
    it "loads existing cache on initialization" do
      cache.add_deprecated_model(provider: "anthropic", model_id: "test-model", replacement: "new-model")

      new_cache = described_class.new(cache_path: cache_path)
      expect(new_cache.deprecated?(provider: "anthropic", model_id: "test-model")).to be true
    end

    it "handles corrupted cache files gracefully" do
      File.write(cache_path, "invalid json{{{")

      # Should not raise, should reset cache
      expect { described_class.new(cache_path: cache_path) }.not_to raise_error
    end

    it "creates cache directory if missing" do
      deep_path = File.join(temp_dir, "nested", "deep", "cache.json")
      new_cache = described_class.new(cache_path: deep_path)

      new_cache.add_deprecated_model(provider: "test", model_id: "model", replacement: "new")

      expect(File.exist?(deep_path)).to be true
    end
  end
end
