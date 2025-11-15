# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/model_cache"
require "tempfile"
require "json"

RSpec.describe Aidp::Harness::ModelCache do
  let(:temp_cache_file) { Tempfile.new(["model_cache", ".json"]) }
  let(:cache) { described_class.new(cache_file: temp_cache_file.path) }

  after do
    temp_cache_file.close
    temp_cache_file.unlink
  end

  describe "#initialize" do
    it "creates cache with default file path" do
      default_cache = described_class.new
      expect(default_cache.cache_file).to include(".aidp/cache/models.json")
    end

    it "creates cache with custom file path" do
      expect(cache.cache_file).to eq(temp_cache_file.path)
    end
  end

  describe "#cache_models" do
    let(:models) do
      [
        {name: "claude-3-5-sonnet-20241022", tier: "standard", provider: "anthropic"},
        {name: "claude-3-5-haiku-20241022", tier: "mini", provider: "anthropic"}
      ]
    end

    it "caches models for a provider" do
      cache.cache_models("anthropic", models)

      cached_data = JSON.parse(File.read(temp_cache_file.path))
      expect(cached_data).to have_key("anthropic")
      expect(cached_data["anthropic"]["models"]).to eq(JSON.parse(models.to_json))
    end

    it "stores timestamp" do
      cache.cache_models("anthropic", models)

      cached_data = JSON.parse(File.read(temp_cache_file.path))
      expect(cached_data["anthropic"]["cached_at"]).not_to be_nil
      expect { Time.parse(cached_data["anthropic"]["cached_at"]) }.not_to raise_error
    end

    it "stores TTL" do
      cache.cache_models("anthropic", models, ttl: 3600)

      cached_data = JSON.parse(File.read(temp_cache_file.path))
      expect(cached_data["anthropic"]["ttl"]).to eq(3600)
    end

    it "uses default TTL when not specified" do
      cache.cache_models("anthropic", models)

      cached_data = JSON.parse(File.read(temp_cache_file.path))
      expect(cached_data["anthropic"]["ttl"]).to eq(Aidp::Harness::ModelCache::DEFAULT_TTL)
    end
  end

  describe "#get_cached_models" do
    let(:models) do
      [
        {name: "claude-3-5-sonnet-20241022", tier: "standard", provider: "anthropic"}
      ]
    end

    context "when cache is fresh" do
      before do
        cache.cache_models("anthropic", models, ttl: 3600)
      end

      it "returns cached models" do
        cached = cache.get_cached_models("anthropic")
        expect(cached).to be_an(Array)
        expect(cached.size).to eq(1)
        expect(cached.first["name"]).to eq("claude-3-5-sonnet-20241022")
      end
    end

    context "when cache is expired" do
      before do
        # Cache with very short TTL
        cache.cache_models("anthropic", models, ttl: 1)
        sleep 2 # Wait for expiration
      end

      it "returns nil for expired cache" do
        cached = cache.get_cached_models("anthropic")
        expect(cached).to be_nil
      end
    end

    context "when provider not cached" do
      it "returns nil" do
        cached = cache.get_cached_models("nonexistent")
        expect(cached).to be_nil
      end
    end

    context "when cache file is corrupted" do
      before do
        File.write(temp_cache_file.path, "invalid json {")
      end

      it "returns nil gracefully" do
        cached = cache.get_cached_models("anthropic")
        expect(cached).to be_nil
      end
    end
  end

  describe "#invalidate" do
    let(:models) { [{name: "test-model", tier: "standard"}] }

    before do
      cache.cache_models("anthropic", models)
      cache.cache_models("cursor", models)
    end

    it "invalidates cache for specific provider" do
      cache.invalidate("anthropic")

      cached = cache.get_cached_models("anthropic")
      expect(cached).to be_nil

      # Other provider should still be cached
      cursor_cached = cache.get_cached_models("cursor")
      expect(cursor_cached).not_to be_nil
    end
  end

  describe "#invalidate_all" do
    let(:models) { [{name: "test-model", tier: "standard"}] }

    before do
      cache.cache_models("anthropic", models)
      cache.cache_models("cursor", models)
    end

    it "invalidates all cached providers" do
      cache.invalidate_all

      expect(cache.get_cached_models("anthropic")).to be_nil
      expect(cache.get_cached_models("cursor")).to be_nil
    end
  end

  describe "#cached_providers" do
    let(:models) { [{name: "test-model", tier: "standard"}] }

    before do
      cache.cache_models("anthropic", models, ttl: 3600)
      cache.cache_models("cursor", models, ttl: 1)
      sleep 2 # Expire cursor cache
    end

    it "returns only non-expired providers" do
      providers = cache.cached_providers
      expect(providers).to include("anthropic")
      expect(providers).not_to include("cursor")
    end
  end

  describe "#stats" do
    let(:models) { [{name: "test-model", tier: "standard"}] }

    before do
      cache.cache_models("anthropic", models)
      cache.cache_models("cursor", models)
    end

    it "returns cache statistics" do
      stats = cache.stats
      expect(stats).to be_a(Hash)
      expect(stats[:total_providers]).to eq(2)
      expect(stats[:cached_providers]).to be_an(Array)
      expect(stats[:cache_file_size]).to be_a(Integer)
      expect(stats[:cache_file_size]).to be > 0
    end

    context "when cache file doesn't exist" do
      it "returns safe defaults" do
        temp_cache_file.unlink
        stats = cache.stats
        expect(stats[:cache_file_size]).to eq(0)
      end
    end
  end
end
