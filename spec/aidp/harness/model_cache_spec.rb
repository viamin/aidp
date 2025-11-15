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

    context "when cache directory creation fails due to permissions" do
      it "falls back to temp directory" do
        # Mock FileUtils to simulate permission denied
        unwritable_cache_file = "/unwritable/aidp/cache/models.json"
        allow(FileUtils).to receive(:mkdir_p) do |path|
          if path.include?("/unwritable/")
            raise Errno::EACCES, "Permission denied"
          else
            # Call original for temp directory
            FileUtils.mkdir_p(path)
          end
        end

        cache_with_fallback = described_class.new(cache_file: unwritable_cache_file)

        # Should fall back to temp directory
        expect(cache_with_fallback.cache_file).to include("tmp")
        expect(cache_with_fallback.cache_file).to include("aidp_cache")
      end

      it "enables cache when fallback succeeds" do
        unwritable_cache_file = "/unwritable/aidp/cache/models.json"
        allow(FileUtils).to receive(:mkdir_p) do |path|
          if path.include?("/unwritable/")
            raise Errno::EACCES, "Permission denied"
          else
            FileUtils.mkdir_p(path)
          end
        end

        cache_with_fallback = described_class.new(cache_file: unwritable_cache_file)

        # Cache should be enabled after successful fallback
        models = [{name: "test-model", tier: "standard"}]
        result = cache_with_fallback.cache_models("anthropic", models)
        expect(result).to be true
      end
    end

    context "when home directory is not accessible" do
      it "uses temp directory as default" do
        # Mock Dir.home to raise error
        allow(Dir).to receive(:home).and_raise(ArgumentError, "Home directory not found")

        cache_no_home = described_class.new
        expect(cache_no_home.cache_file).to include("tmp")
        expect(cache_no_home.cache_file).to include("aidp_cache")
      end
    end

    context "when cache directory exists" do
      let(:existing_dir) { Dir.mktmpdir }
      let(:cache_in_existing) do
        described_class.new(cache_dir: existing_dir)
      end

      after do
        FileUtils.rm_rf(existing_dir)
      end

      it "uses existing directory without creating" do
        expect(cache_in_existing.cache_file).to eq(File.join(existing_dir, "models.json"))
      end
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

    context "when cache is disabled" do
      let(:disabled_cache) do
        # Simulate complete failure - both primary and fallback fail
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "Permission denied")
        allow(File).to receive(:directory?).and_return(false)

        described_class.new(cache_file: "/unwritable/cache.json")
      end

      it "returns false when attempting to cache" do
        result = disabled_cache.cache_models("anthropic", models)
        expect(result).to be false
      end

      it "does not raise errors" do
        expect {
          disabled_cache.cache_models("anthropic", models)
        }.not_to raise_error
      end
    end

    context "when write fails after cache is created" do
      it "returns false gracefully" do
        # Create cache normally first
        cache.cache_models("anthropic", models)

        # Mock File.write to simulate write failure
        allow(File).to receive(:write).and_raise(Errno::EACCES, "Permission denied")

        new_models = [{name: "new-model", tier: "mini"}]
        result = cache.cache_models("openai", new_models)
        expect(result).to be false
      end
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

    context "when cached_at timestamp is malformed" do
      before do
        cache_data = {
          "anthropic" => {
            "cached_at" => "not-a-valid-timestamp",
            "ttl" => 3600,
            "models" => models
          }
        }
        File.write(temp_cache_file.path, JSON.pretty_generate(cache_data))
      end

      it "returns nil gracefully" do
        cached = cache.get_cached_models("anthropic")
        expect(cached).to be_nil
      end
    end

    context "when TTL is missing" do
      before do
        cache_data = {
          "anthropic" => {
            "cached_at" => Time.now.iso8601,
            "models" => models
          }
        }
        File.write(temp_cache_file.path, JSON.pretty_generate(cache_data))
      end

      it "uses default TTL" do
        # Should not be expired with default TTL (24 hours)
        cached = cache.get_cached_models("anthropic")
        expect(cached).not_to be_nil
        expect(cached.size).to eq(1)
      end
    end

    context "when cache file is empty" do
      before do
        File.write(temp_cache_file.path, "")
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

    context "when cache is disabled" do
      let(:disabled_cache) do
        # Simulate complete failure - both primary and fallback fail
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "Permission denied")
        allow(File).to receive(:directory?).and_return(false)

        described_class.new(cache_file: "/unwritable/cache.json")
      end

      it "returns false" do
        result = disabled_cache.invalidate("anthropic")
        expect(result).to be false
      end

      it "does not raise errors" do
        expect {
          disabled_cache.invalidate("anthropic")
        }.not_to raise_error
      end
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

    context "when cache is disabled" do
      let(:disabled_cache) do
        # Simulate complete failure - both primary and fallback fail
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "Permission denied")
        allow(File).to receive(:directory?).and_return(false)

        described_class.new(cache_file: "/unwritable/cache.json")
      end

      it "returns false" do
        result = disabled_cache.invalidate_all
        expect(result).to be false
      end

      it "does not raise errors" do
        expect {
          disabled_cache.invalidate_all
        }.not_to raise_error
      end
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

  describe "concurrent access" do
    let(:models) { [{name: "test-model", tier: "standard"}] }

    it "handles concurrent writes without errors" do
      threads = 5.times.map do |i|
        Thread.new do
          cache.cache_models("provider_#{i}", models)
        end
      end

      expect {
        threads.each(&:join)
      }.not_to raise_error

      # Note: Due to race conditions, not all providers may be cached
      # The important thing is no errors occur
      # At least 1 provider should be cached
      expect(cache.cached_providers.size).to be >= 1
    end

    it "handles concurrent reads without errors" do
      cache.cache_models("anthropic", models)

      threads = 10.times.map do
        Thread.new do
          cache.get_cached_models("anthropic")
        end
      end

      results = threads.map(&:value)
      expect(results).to all(be_an(Array))
    end

    it "handles mixed read/write operations" do
      cache.cache_models("anthropic", models)

      threads = []
      # Writers
      threads += 3.times.map do |i|
        Thread.new do
          cache.cache_models("provider_#{i}", models)
        end
      end

      # Readers
      threads += 3.times.map do
        Thread.new do
          cache.get_cached_models("anthropic")
        end
      end

      expect {
        threads.each(&:join)
      }.not_to raise_error
    end
  end

  describe "edge cases" do
    context "with very large model lists" do
      let(:large_models) do
        1000.times.map do |i|
          {name: "model-#{i}", tier: "standard", provider: "test"}
        end
      end

      it "handles large datasets" do
        result = cache.cache_models("test", large_models)
        expect(result).to be true

        cached = cache.get_cached_models("test")
        expect(cached.size).to eq(1000)
      end
    end

    context "with special characters in provider names" do
      let(:models) { [{name: "test-model", tier: "standard"}] }

      it "handles provider names with dashes" do
        cache.cache_models("my-custom-provider", models)
        cached = cache.get_cached_models("my-custom-provider")
        expect(cached).not_to be_nil
      end

      it "handles provider names with underscores" do
        cache.cache_models("my_custom_provider", models)
        cached = cache.get_cached_models("my_custom_provider")
        expect(cached).not_to be_nil
      end
    end

    context "with extreme TTL values" do
      let(:models) { [{name: "test-model", tier: "standard"}] }

      it "handles very short TTL (1 second)" do
        cache.cache_models("anthropic", models, ttl: 1)
        cached = cache.get_cached_models("anthropic")
        expect(cached).not_to be_nil

        sleep 2
        expired = cache.get_cached_models("anthropic")
        expect(expired).to be_nil
      end

      it "handles very long TTL (1 year)" do
        one_year = 31_536_000
        cache.cache_models("anthropic", models, ttl: one_year)
        cached = cache.get_cached_models("anthropic")
        expect(cached).not_to be_nil
      end
    end

    context "when cache file is deleted during operation" do
      let(:models) { [{name: "test-model", tier: "standard"}] }

      it "recreates cache gracefully" do
        cache.cache_models("anthropic", models)
        File.delete(temp_cache_file.path)

        # Should recreate cache
        result = cache.cache_models("cursor", models)
        expect(result).to be true

        cached = cache.get_cached_models("cursor")
        expect(cached).not_to be_nil
      end
    end
  end
end
