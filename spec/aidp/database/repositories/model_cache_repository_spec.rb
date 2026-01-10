# frozen_string_literal: true

require "spec_helper"
require "aidp/database"
require "aidp/database/repositories/model_cache_repository"

RSpec.describe Aidp::Database::Repositories::ModelCacheRepository do
  let(:temp_dir) { Dir.mktmpdir }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#cache_models" do
    it "stores models for a provider" do
      models = [
        {id: "claude-3-opus", name: "Claude 3 Opus"},
        {id: "claude-3-sonnet", name: "Claude 3 Sonnet"}
      ]

      result = repository.cache_models("anthropic", models)

      expect(result).to be true
    end

    it "updates existing cache" do
      models1 = [{id: "model-v1"}]
      models2 = [{id: "model-v2"}, {id: "model-v3"}]

      repository.cache_models("anthropic", models1)
      repository.cache_models("anthropic", models2)

      cached = repository.get_cached_models("anthropic")
      expect(cached.size).to eq(2)
      expect(cached.first[:id]).to eq("model-v2")
    end
  end

  describe "#get_cached_models" do
    it "returns cached models when valid" do
      models = [
        {id: "gpt-4", name: "GPT-4"},
        {id: "gpt-4-turbo", name: "GPT-4 Turbo"}
      ]
      repository.cache_models("openai", models, ttl: 3600)

      cached = repository.get_cached_models("openai")

      expect(cached.size).to eq(2)
      expect(cached.first[:id]).to eq("gpt-4")
    end

    it "returns nil for expired cache" do
      models = [{id: "expired-model"}]
      repository.cache_models("provider", models, ttl: -1)

      cached = repository.get_cached_models("provider")

      expect(cached).to be_nil
    end

    it "returns nil for non-existent provider" do
      cached = repository.get_cached_models("nonexistent")

      expect(cached).to be_nil
    end
  end

  describe "#invalidate" do
    it "removes cache for specific provider" do
      repository.cache_models("anthropic", [{id: "model1"}])
      repository.cache_models("openai", [{id: "model2"}])

      result = repository.invalidate("anthropic")

      expect(result).to be true
      expect(repository.get_cached_models("anthropic")).to be_nil
      expect(repository.get_cached_models("openai")).not_to be_nil
    end
  end

  describe "#invalidate_all" do
    it "removes all cached models" do
      repository.cache_models("anthropic", [{id: "model1"}])
      repository.cache_models("openai", [{id: "model2"}])

      result = repository.invalidate_all

      expect(result).to be true
      expect(repository.cached_providers).to be_empty
    end
  end

  describe "#cached_providers" do
    it "returns providers with valid caches" do
      repository.cache_models("anthropic", [{id: "m1"}], ttl: 3600)
      repository.cache_models("openai", [{id: "m2"}], ttl: 3600)
      repository.cache_models("expired", [{id: "m3"}], ttl: -1)

      providers = repository.cached_providers

      expect(providers).to contain_exactly("anthropic", "openai")
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      repository.cache_models("anthropic", [{id: "m1"}], ttl: 3600)
      repository.cache_models("openai", [{id: "m2"}], ttl: 3600)

      stats = repository.stats

      expect(stats[:total_providers]).to eq(2)
      expect(stats[:valid_count]).to eq(2)
      expect(stats[:cached_providers]).to contain_exactly("anthropic", "openai")
    end
  end

  describe "#cleanup_expired" do
    it "removes expired entries" do
      repository.cache_models("valid", [{id: "m1"}], ttl: 3600)
      repository.cache_models("expired1", [{id: "m2"}], ttl: -1)
      repository.cache_models("expired2", [{id: "m3"}], ttl: -1)

      count = repository.cleanup_expired

      expect(count).to eq(2)
      expect(repository.stats[:total_providers]).to eq(1)
    end
  end

  describe "#model_count" do
    it "returns number of cached models for provider" do
      models = [
        {id: "m1"},
        {id: "m2"},
        {id: "m3"}
      ]
      repository.cache_models("anthropic", models)

      count = repository.model_count("anthropic")

      expect(count).to eq(3)
    end

    it "returns 0 for non-existent or expired provider" do
      expect(repository.model_count("nonexistent")).to eq(0)
    end
  end
end
