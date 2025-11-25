# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::RubyLLMRegistry do
  let(:registry) { described_class.new }

  describe "#initialize" do
    it "initializes without errors" do
      expect { described_class.new }.not_to raise_error
    end

    it "logs initialization with model count" do
      expect(Aidp).to receive(:log_info).with("ruby_llm_registry", "initialized", hash_including(:models))
      described_class.new
    end
  end

  describe "#resolve_model" do
    context "with Anthropic models" do
      it "resolves claude-3-5-haiku to versioned name" do
        result = registry.resolve_model("claude-3-5-haiku", provider: "anthropic")
        # Should return either versioned or -latest variant
        expect(result).to be_a(String).and(match(/claude-3-5-haiku/))
      end

      it "resolves claude-3-opus to versioned name" do
        result = registry.resolve_model("claude-3-opus", provider: "anthropic")
        expect(result).to be_a(String).and(match(/claude-3-opus/))
      end

      it "returns already versioned model as-is" do
        result = registry.resolve_model("claude-3-5-haiku-20241022", provider: "anthropic")
        expect(result).to eq("claude-3-5-haiku-20241022")
      end

      it "returns nil for unknown model" do
        result = registry.resolve_model("claude-unknown-model-xyz", provider: "anthropic")
        expect(result).to be_nil
      end

      it "logs warning for unknown model" do
        expect(Aidp).to receive(:log_warn).with("ruby_llm_registry", "model not found",
          hash_including(:model, :provider))
        registry.resolve_model("claude-unknown-model-xyz", provider: "anthropic")
      end
    end

    context "with OpenAI models" do
      it "resolves gpt-4 to versioned name" do
        result = registry.resolve_model("gpt-4", provider: "openai")
        expect(result).to be_a(String).and(match(/gpt-4/))
      end

      it "resolves gpt-3.5-turbo to versioned name" do
        result = registry.resolve_model("gpt-3.5-turbo", provider: "openai")
        expect(result).to be_a(String).and(match(/gpt-3\.5-turbo/))
      end

      it "returns nil for unknown model" do
        result = registry.resolve_model("gpt-unknown-xyz", provider: "openai")
        expect(result).to be_nil
      end
    end

    context "with fuzzy matching" do
      it "finds models with partial names" do
        result = registry.resolve_model("claude-haiku", provider: "anthropic")
        expect(result).to be_a(String).and(match(/haiku/))
      end

      it "handles model names without exact match" do
        # Fuzzy match should find something or return nil gracefully
        result = registry.resolve_model("gpt4", provider: "openai")
        expect(result).to be_a(String).or be_nil
      end
    end

    context "with nil provider" do
      it "searches across all providers" do
        result = registry.resolve_model("claude-3-5-haiku", provider: nil)
        expect(result).to be_a(String).and(match(/haiku/))
      end
    end
  end

  describe "#get_model_info" do
    it "returns model information for valid ID" do
      # Get a known model ID first
      model_id = registry.resolve_model("claude-3-5-haiku", provider: "anthropic")
      info = registry.get_model_info(model_id)

      expect(info).to be_a(Hash)
      expect(info).to have_key(:id)
      expect(info).to have_key(:name)
      expect(info).to have_key(:provider)
      expect(info).to have_key(:tier)
      expect(info[:provider]).to eq("anthropic")
    end

    it "returns nil for unknown model ID" do
      info = registry.get_model_info("nonexistent-model-xyz")
      expect(info).to be_nil
    end

    it "includes capabilities array" do
      model_id = registry.resolve_model("claude-3-5-haiku", provider: "anthropic")
      info = registry.get_model_info(model_id)

      expect(info).to have_key(:capabilities)
      expect(info[:capabilities]).to be_an(Array)
    end
  end

  describe "#models_for_tier" do
    it "returns array of model IDs for mini tier" do
      models = registry.models_for_tier("mini")
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.first).to be_a(String)
    end

    it "returns array of model IDs for standard tier" do
      models = registry.models_for_tier("standard")
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
    end

    it "returns array of model IDs for advanced tier" do
      models = registry.models_for_tier("advanced")
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
    end

    it "returns empty array for unknown tier" do
      models = registry.models_for_tier("unknown")
      expect(models).to eq([])
    end

    it "logs warning for invalid tier" do
      expect(Aidp).to receive(:log_warn).with("ruby_llm_registry", "invalid tier", hash_including(:tier))
      registry.models_for_tier("invalid_tier")
    end

    it "classifies Claude Haiku models as mini" do
      models = registry.models_for_tier("mini")
      haiku_models = models.select { |id| id.include?("haiku") }
      expect(haiku_models).not_to be_empty
    end

    it "classifies Claude Opus models as advanced" do
      models = registry.models_for_tier("advanced")
      opus_models = models.select { |id| id.include?("opus") }
      expect(opus_models).not_to be_empty
    end

    it "filters by provider when specified" do
      models = registry.models_for_tier("mini", provider: "anthropic")
      expect(models).to be_an(Array)
      # All returned models should be anthropic models
      models.each do |model_id|
        info = registry.get_model_info(model_id)
        expect(info[:provider]).to eq("anthropic") if info
      end
    end

    it "logs debug info with count" do
      expect(Aidp).to receive(:log_debug).with("ruby_llm_registry", "found models for tier",
        hash_including(:tier, :count))
      registry.models_for_tier("mini")
    end
  end

  describe "#models_for_provider" do
    it "returns model IDs for anthropic provider" do
      models = registry.models_for_provider("anthropic")
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.first).to be_a(String)
      # Verify they're anthropic models
      expect(models.any? { |id| id.include?("claude") }).to be true
    end

    it "returns model IDs for openai provider" do
      models = registry.models_for_provider("openai")
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.any? { |id| id.include?("gpt") }).to be true
    end

    it "maps codex provider to openai models" do
      codex_models = registry.models_for_provider("codex")
      openai_models = registry.models_for_provider("openai")
      expect(codex_models).to eq(openai_models)
      expect(codex_models.any? { |id| id.include?("gpt-4o-mini") }).to be true
      expect(codex_models.any? { |id| id.include?("gpt-3.5-turbo") }).to be true
    end

    it "maps gemini provider to google models" do
      gemini_models = registry.models_for_provider("gemini")
      expect(gemini_models).not_to be_empty
      expect(gemini_models.any? { |id| id.include?("gemini") }).to be true
    end

    it "returns empty array for unknown provider" do
      models = registry.models_for_provider("unknown_provider_xyz")
      expect(models).to eq([])
    end
  end

  describe "#classify_tier" do
    it "classifies haiku models as mini" do
      model_id = registry.resolve_model("claude-3-5-haiku", provider: "anthropic")
      info = registry.get_model_info(model_id)
      expect(info[:tier]).to eq("mini")
    end

    it "classifies opus models as advanced" do
      model_id = registry.resolve_model("claude-3-opus", provider: "anthropic")
      info = registry.get_model_info(model_id)
      expect(info[:tier]).to eq("advanced")
    end
  end

  describe "#refresh!" do
    it "refreshes the registry and rebuilds indexes" do
      # Allow initialization log, expect refresh log
      allow(Aidp).to receive(:log_info).with("ruby_llm_registry", "initialized", any_args)
      allow(RubyLLM::Models).to receive(:refresh!)
      expect(Aidp).to receive(:log_info).with("ruby_llm_registry", "refreshed", hash_including(:models))
      registry.refresh!
    end

    it "maintains functionality after refresh" do
      allow(RubyLLM::Models).to receive(:refresh!)
      registry.refresh!
      result = registry.resolve_model("claude-3-5-haiku", provider: "anthropic")
      expect(result).to be_a(String)
    end
  end

  describe "error handling" do
    it "handles registry initialization errors" do
      allow(RubyLLM::Models).to receive(:instance).and_raise(StandardError, "Registry unavailable")
      expect { described_class.new }.to raise_error(StandardError, /Registry unavailable/)
    end
  end
end
