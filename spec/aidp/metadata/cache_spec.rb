# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Cache do
  let(:cache_dir) { Dir.mktmpdir }
  let(:cache) { described_class.new(cache_dir: cache_dir) }

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe "#initialize" do
    it "creates cache directory if it doesn't exist" do
      new_dir = File.join(cache_dir, "new_cache")
      expect(File.exist?(new_dir)).to be false
      described_class.new(cache_dir: new_dir)
      expect(File.exist?(new_dir)).to be true
    end
  end

  describe "#get" do
    it "returns nil for non-existent key" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "returns cached value for existing key" do
      cache.set("test_key", "test_value")
      expect(cache.get("test_key")).to eq("test_value")
    end

    it "returns nil for expired cache entry" do
      cache.set("test_key", "test_value", ttl: 0)
      sleep 0.01
      expect(cache.get("test_key")).to be_nil
    end
  end

  describe "#set" do
    it "stores value in cache" do
      cache.set("key", "value")
      expect(cache.get("key")).to eq("value")
    end

    it "overwrites existing value" do
      cache.set("key", "old")
      cache.set("key", "new")
      expect(cache.get("key")).to eq("new")
    end

    it "respects TTL parameter" do
      cache.set("key", "value", ttl: 1)
      expect(cache.get("key")).to eq("value")
    end
  end

  describe "#delete" do
    it "removes cached value" do
      cache.set("key", "value")
      cache.delete("key")
      expect(cache.get("key")).to be_nil
    end

    it "returns true when key exists" do
      cache.set("key", "value")
      expect(cache.delete("key")).to be true
    end

    it "returns false when key doesn't exist" do
      expect(cache.delete("nonexistent")).to be false
    end
  end

  describe "#clear" do
    it "removes all cached values" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear
      expect(cache.get("key1")).to be_nil
      expect(cache.get("key2")).to be_nil
    end
  end

  describe "#size" do
    it "returns number of cached entries" do
      expect(cache.size).to eq(0)
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      expect(cache.size).to eq(2)
    end
  end

  describe "#keys" do
    it "returns array of cache keys" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      expect(cache.keys).to contain_exactly("key1", "key2")
    end

    it "returns empty array when cache is empty" do
      expect(cache.keys).to eq([])
    end
  end

  describe "#exist?" do
    it "returns true for existing key" do
      cache.set("key", "value")
      expect(cache.exist?("key")).to be true
    end

    it "returns false for non-existent key" do
      expect(cache.exist?("nonexistent")).to be false
    end
  end
end
