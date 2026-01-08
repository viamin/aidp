# frozen_string_literal: true

require "spec_helper"
require "aidp/database"
require "aidp/database/repositories/deprecated_models_repository"

RSpec.describe Aidp::Database::Repositories::DeprecatedModelsRepository do
  let(:temp_dir) { Dir.mktmpdir }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    Aidp::Database.initialize!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#add" do
    it "adds a deprecated model" do
      result = repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3-sonnet",
        reason: "Model deprecated in favor of Claude 3"
      )

      expect(result).to be true
    end

    it "updates existing deprecation entry" do
      repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3-haiku"
      )
      repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3-sonnet"
      )

      replacement = repository.replacement_for(
        provider_name: "anthropic",
        model_name: "claude-2"
      )

      expect(replacement).to eq("claude-3-sonnet")
    end
  end

  describe "#deprecated?" do
    it "returns true for deprecated models" do
      repository.add(provider_name: "anthropic", model_name: "claude-2")

      expect(repository.deprecated?(provider_name: "anthropic", model_name: "claude-2")).to be true
    end

    it "returns false for non-deprecated models" do
      expect(repository.deprecated?(provider_name: "anthropic", model_name: "claude-3")).to be false
    end
  end

  describe "#replacement_for" do
    it "returns replacement model when available" do
      repository.add(
        provider_name: "openai",
        model_name: "gpt-4-0314",
        replacement: "gpt-4-turbo"
      )

      replacement = repository.replacement_for(
        provider_name: "openai",
        model_name: "gpt-4-0314"
      )

      expect(replacement).to eq("gpt-4-turbo")
    end

    it "returns nil when no replacement specified" do
      repository.add(provider_name: "openai", model_name: "old-model")

      replacement = repository.replacement_for(
        provider_name: "openai",
        model_name: "old-model"
      )

      expect(replacement).to be_nil
    end
  end

  describe "#deprecated_models" do
    it "returns all deprecated models for provider" do
      repository.add(provider_name: "anthropic", model_name: "claude-1")
      repository.add(provider_name: "anthropic", model_name: "claude-2")
      repository.add(provider_name: "openai", model_name: "gpt-3")

      models = repository.deprecated_models(provider_name: "anthropic")

      expect(models).to contain_exactly("claude-1", "claude-2")
    end

    it "returns empty array for provider with no deprecations" do
      models = repository.deprecated_models(provider_name: "nonexistent")

      expect(models).to eq([])
    end
  end

  describe "#info" do
    it "returns full deprecation info" do
      repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3",
        reason: "End of life"
      )

      info = repository.info(provider_name: "anthropic", model_name: "claude-2")

      expect(info[:replacement]).to eq("claude-3")
      expect(info[:reason]).to eq("End of life")
      expect(info[:detected_at]).not_to be_nil
    end

    it "returns nil for non-deprecated model" do
      info = repository.info(provider_name: "anthropic", model_name: "nonexistent")

      expect(info).to be_nil
    end
  end

  describe "#remove" do
    it "removes model from deprecation cache" do
      repository.add(provider_name: "anthropic", model_name: "claude-2")

      repository.remove(provider_name: "anthropic", model_name: "claude-2")

      expect(repository.deprecated?(provider_name: "anthropic", model_name: "claude-2")).to be false
    end
  end

  describe "#clear!" do
    it "removes all deprecations" do
      repository.add(provider_name: "anthropic", model_name: "claude-2")
      repository.add(provider_name: "openai", model_name: "gpt-3")

      repository.clear!

      stats = repository.stats
      expect(stats[:total_deprecated]).to eq(0)
    end
  end

  describe "#stats" do
    it "returns deprecation statistics" do
      repository.add(provider_name: "anthropic", model_name: "claude-1")
      repository.add(provider_name: "anthropic", model_name: "claude-2")
      repository.add(provider_name: "openai", model_name: "gpt-3")

      stats = repository.stats

      expect(stats[:providers]).to contain_exactly("anthropic", "openai")
      expect(stats[:total_deprecated]).to eq(3)
      expect(stats[:by_provider]["anthropic"]).to eq(2)
      expect(stats[:by_provider]["openai"]).to eq(1)
    end
  end

  describe "#list_all" do
    it "returns all deprecated models with full info" do
      repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3"
      )
      repository.add(
        provider_name: "openai",
        model_name: "gpt-3",
        reason: "Deprecated"
      )

      all = repository.list_all

      expect(all.size).to eq(2)
      expect(all.first[:provider]).to eq("anthropic")
      expect(all.first[:model]).to eq("claude-2")
    end
  end

  describe "#with_replacements" do
    it "returns only models with replacements" do
      repository.add(
        provider_name: "anthropic",
        model_name: "claude-2",
        replacement: "claude-3"
      )
      repository.add(provider_name: "openai", model_name: "gpt-3")

      with_replacements = repository.with_replacements

      expect(with_replacements.size).to eq(1)
      expect(with_replacements.first[:model]).to eq("claude-2")
      expect(with_replacements.first[:replacement]).to eq("claude-3")
    end
  end
end
