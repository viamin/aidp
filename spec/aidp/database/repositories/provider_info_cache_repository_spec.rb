# frozen_string_literal: true

require "spec_helper"
require "aidp/database"
require "aidp/database/repositories/provider_info_cache_repository"

RSpec.describe Aidp::Database::Repositories::ProviderInfoCacheRepository do
  let(:temp_dir) { Dir.mktmpdir}
  let(:repository) { described_class.new(project_dir: temp_dir)}

  before do
    Aidp::Database.initialize!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#cache" do
    it "stores provider info with TTL" do
      info = {
        provider: "claude",
        cli_available: true,
        mcp_support: true,
        capabilities: {model_selection: true}
     }

      result = repository.cache("claude", info, ttl: 3600)

      expect(result).to be true
    end

    it "updates existing cache entry" do
      info1 = {provider: "claude", version: 1}
      info2 = {provider: "claude", version: 2}

      repository.cache("claude", info1)
      repository.cache("claude", info2)

      cached = repository.get("claude")
      expect(cached[:version]).to eq(2)
    end
  end

  describe "#get" do
    it "returns cached info when valid" do
      info = {provider: "cursor", cli_available: true}
      repository.cache("cursor", info, ttl: 3600)

      result = repository.get("cursor")

      expect(result[:provider]).to eq("cursor")
      expect(result[:cli_available]).to be true
    end

    it "returns nil for expired cache" do
      info = {provider: "claude"}
      repository.cache("claude", info, ttl: -1)

      result = repository.get("claude")

      expect(result).to be_nil
    end

    it "returns nil for non-existent provider" do
      result = repository.get("nonexistent")

      expect(result).to be_nil
    end
  end

  describe "#get_stale" do
    it "returns info even when expired" do
      info = {provider: "claude", data: "test"}
      repository.cache("claude", info, ttl: -1)

      result = repository.get_stale("claude")

      expect(result[:provider]).to eq("claude")
    end
  end

  describe "#stale?" do
    it "returns true when cache is older than max_age" do
      info = {provider: "claude"}
      repository.cache("claude", info, ttl: 3600)

      # With a very short max_age, any cache should be considered stale
      expect(repository.stale?("claude", max_age: -1)).to be true
    end

    it "returns false when cache is fresh" do
      info = {provider: "claude"}
      repository.cache("claude", info, ttl: 3600)

      expect(repository.stale?("claude", max_age: 7200)).to be false
    end

    it "returns true for non-existent provider" do
      expect(repository.stale?("nonexistent")).to be true
    end
  end

  describe "#invalidate" do
    it "removes specific provider cache" do
      repository.cache("claude", {provider: "claude"})
      repository.cache("cursor", {provider: "cursor"})

      repository.invalidate("claude")

      expect(repository.get_stale("claude")).to be_nil
      expect(repository.get_stale("cursor")).not_to be_nil
    end
  end

  describe "#invalidate_all" do
    it "removes all provider caches" do
      repository.cache("claude", {provider: "claude"})
      repository.cache("cursor", {provider: "cursor"})

      repository.invalidate_all

      expect(repository.cached_providers(include_expired: true)).to be_empty
    end
  end

  describe "#cached_providers" do
    it "returns list of cached provider names" do
      repository.cache("claude", {provider: "claude"}, ttl: 3600)
      repository.cache("cursor", {provider: "cursor"}, ttl: 3600)

      providers = repository.cached_providers

      expect(providers).to contain_exactly("claude", "cursor")
    end

    it "excludes expired entries by default" do
      repository.cache("claude", {provider: "claude"}, ttl: 3600)
      repository.cache("cursor", {provider: "cursor"}, ttl: -1)

      providers = repository.cached_providers

      expect(providers).to eq(["claude"])
    end

    it "includes expired entries when requested" do
      repository.cache("claude", {provider: "claude"}, ttl: 3600)
      repository.cache("cursor", {provider: "cursor"}, ttl: -1)

      providers = repository.cached_providers(include_expired: true)

      expect(providers).to contain_exactly("claude", "cursor")
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      repository.cache("claude", {provider: "claude"}, ttl: 3600)
      repository.cache("cursor", {provider: "cursor"}, ttl: -1)

      stats = repository.stats

      expect(stats[:total_cached]).to eq(2)
      expect(stats[:valid_entries]).to eq(1)
      expect(stats[:expired_entries]).to eq(1)
      expect(stats[:providers]).to contain_exactly("claude", "cursor")
    end
  end

  describe "#cleanup_expired" do
    it "removes expired entries and returns count" do
      repository.cache("claude", {provider: "claude"}, ttl: 3600)
      repository.cache("cursor", {provider: "cursor"}, ttl: -1)
      repository.cache("gemini", {provider: "gemini"}, ttl: -1)

      count = repository.cleanup_expired

      expect(count).to eq(2)
      expect(repository.cached_providers(include_expired: true)).to eq(["claude"])
    end
  end
end
