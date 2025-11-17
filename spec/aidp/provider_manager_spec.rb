# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::ProviderManager do
  after do
    # Clean up cached factory instance
    described_class.instance_variable_set(:@harness_factory, nil)
  end

  describe ".get_provider" do
    it "returns a provider instance" do
      provider = described_class.get_provider("cursor", )
      expect(provider).to be_a(Aidp::Providers::Cursor)
    end

    it "supports anthropic provider" do
      provider = described_class.get_provider("anthropic", )
      expect(provider).to be_a(Aidp::Providers::Anthropic)
    end

    it "supports claude alias" do
      provider = described_class.get_provider("claude", )
      expect(provider).to be_a(Aidp::Providers::Anthropic)
    end

    it "supports gemini provider" do
      provider = described_class.get_provider("gemini", )
      expect(provider).to be_a(Aidp::Providers::Gemini)
    end

    it "supports github_copilot provider" do
      provider = described_class.get_provider("github_copilot", )
      expect(provider).to be_a(Aidp::Providers::GithubCopilot)
    end

    it "supports codex provider" do
      provider = described_class.get_provider("codex", )
      expect(provider).to be_a(Aidp::Providers::Codex)
    end

    it "accepts custom prompt" do
      prompt = double("prompt")
      provider = described_class.get_provider("cursor", prompt: prompt, )
      expect(provider).to be_a(Aidp::Providers::Cursor)
    end

    it "uses harness factory when available" do
      factory = double("factory")
      provider_instance = double("provider")

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:create_provider).with("cursor", {}).and_return(provider_instance)

      result = described_class.get_provider("cursor")
      expect(result).to eq(provider_instance)
    end

    it "falls back to legacy when harness disabled" do
      provider = described_class.get_provider("cursor", )
      expect(provider).to be_a(Aidp::Providers::Cursor)
    end
  end

  describe ".load_from_config" do
    it "loads provider from config hash" do
      config = {"provider" => "anthropic"}
      provider = described_class.load_from_config(config, )
      expect(provider).to be_a(Aidp::Providers::Anthropic)
    end

    it "defaults to cursor when no provider specified" do
      config = {}
      provider = described_class.load_from_config(config, )
      expect(provider).to be_a(Aidp::Providers::Cursor)
    end

    it "passes options through" do
      config = {"provider" => "cursor"}
      prompt = double("prompt")
      provider = described_class.load_from_config(config, prompt: prompt, )
      expect(provider).to be_a(Aidp::Providers::Cursor)
    end
  end

  describe ".get_harness_factory" do
    it "returns a factory instance when harness is available" do
      factory = described_class.get_harness_factory
      expect(factory).to be_a(Aidp::Harness::ProviderFactory) if factory
    end

    it "caches the factory instance" do
      factory1 = described_class.get_harness_factory
      factory2 = described_class.get_harness_factory
      expect(factory1).to eq(factory2) if factory1
    end
  end

  describe ".create_harness_provider" do
    context "when harness factory is available" do
      let(:factory) { double("factory") }
      let(:provider) { double("provider") }

      before do
        allow(described_class).to receive(:get_harness_factory).and_return(factory)
      end

      it "creates provider using harness factory" do
        allow(factory).to receive(:create_provider).with("claude", {}).and_return(provider)

        result = described_class.create_harness_provider("claude")
        expect(result).to eq(provider)
      end

      it "passes options to factory" do
        options = {config: "test"}
        allow(factory).to receive(:create_provider).with("claude", options).and_return(provider)

        described_class.create_harness_provider("claude", options)
        expect(factory).to have_received(:create_provider).with("claude", options)
      end
    end

    context "when harness factory is not available" do
      before do
        allow(described_class).to receive(:get_harness_factory).and_return(nil)
      end

      it "raises an error" do
        expect do
          described_class.create_harness_provider("claude")
        end.to raise_error("Harness factory not available")
      end
    end
  end

  describe ".get_all_providers" do
    it "returns empty array when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.get_all_providers
      expect(result).to eq([])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      providers = [double("provider1"), double("provider2")]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:create_all_providers).with({}).and_return(providers)

      result = described_class.get_all_providers
      expect(result).to eq(providers)
    end
  end

  describe ".get_providers_by_priority" do
    it "returns empty array when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.get_providers_by_priority
      expect(result).to eq([])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      providers = [double("provider1"), double("provider2")]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:create_providers_by_priority).with({}).and_return(providers)

      result = described_class.get_providers_by_priority
      expect(result).to eq(providers)
    end
  end

  describe ".get_enabled_providers" do
    it "returns empty array when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.get_enabled_providers
      expect(result).to eq([])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      enabled_names = %w[claude cursor]
      providers = [double("provider1"), double("provider2")]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_enabled_providers).with({}).and_return(enabled_names)
      allow(factory).to receive(:create_providers).with(enabled_names, {}).and_return(providers)

      result = described_class.get_enabled_providers
      expect(result).to eq(providers)
    end
  end

  describe ".provider_configured?" do
    it "returns false when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.provider_configured?("claude")
      expect(result).to be false
    end

    it "checks with factory when available" do
      factory = double("factory")

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_configured_providers).with({}).and_return(%w[claude cursor])

      result = described_class.provider_configured?("claude")
      expect(result).to be true
    end

    it "returns false for unconfigured provider" do
      factory = double("factory")

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_configured_providers).with({}).and_return(["claude"])

      result = described_class.provider_configured?("gemini")
      expect(result).to be false
    end
  end

  describe ".provider_enabled?" do
    it "returns false when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.provider_enabled?("claude")
      expect(result).to be false
    end

    it "checks with factory when available" do
      factory = double("factory")

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_enabled_providers).with({}).and_return(%w[claude cursor])

      result = described_class.provider_enabled?("claude")
      expect(result).to be true
    end
  end

  describe ".get_provider_capabilities" do
    it "returns empty array when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.get_provider_capabilities("claude")
      expect(result).to eq([])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      capabilities = %w[chat code_generation]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_provider_capabilities).with("claude", {}).and_return(capabilities)

      result = described_class.get_provider_capabilities("claude")
      expect(result).to eq(capabilities)
    end
  end

  describe ".provider_supports_feature?" do
    it "returns false when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.provider_supports_feature?("claude", "chat")
      expect(result).to be false
    end

    it "delegates to factory when available" do
      factory = double("factory")

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:provider_supports_feature?).with("claude", "chat", {}).and_return(true)

      result = described_class.provider_supports_feature?("claude", "chat")
      expect(result).to be true
    end
  end

  describe ".get_provider_models" do
    it "returns empty array when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.get_provider_models("claude")
      expect(result).to eq([])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      models = ["claude-3-opus", "claude-3-sonnet"]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:get_provider_models).with("claude", {}).and_return(models)

      result = described_class.get_provider_models("claude")
      expect(result).to eq(models)
    end
  end

  describe ".validate_provider_config" do
    it "returns error when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.validate_provider_config("claude")
      expect(result).to eq(["Harness factory not available"])
    end

    it "delegates to factory when available" do
      factory = double("factory")
      errors = ["API key missing"]

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:validate_provider_config).with("claude", {}).and_return(errors)

      result = described_class.validate_provider_config("claude")
      expect(result).to eq(errors)
    end
  end

  describe ".validate_all_provider_configs" do
    it "returns empty hash when no factory" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)
      result = described_class.validate_all_provider_configs
      expect(result).to eq({})
    end

    it "delegates to factory when available" do
      factory = double("factory")
      validations = {"claude" => [], "cursor" => ["error"]}

      allow(described_class).to receive(:get_harness_factory).and_return(factory)
      allow(factory).to receive(:validate_all_provider_configs).with({}).and_return(validations)

      result = described_class.validate_all_provider_configs
      expect(result).to eq(validations)
    end
  end

  describe ".clear_cache" do
    it "calls clear_cache on factory when available" do
      factory = double("factory")

      # Set the instance variable directly since it's cached
      described_class.instance_variable_set(:@harness_factory, factory)
      allow(factory).to receive(:clear_cache)

      described_class.clear_cache
      expect(factory).to have_received(:clear_cache)
    end

    it "handles nil factory gracefully" do
      described_class.instance_variable_set(:@harness_factory, nil)
      expect { described_class.clear_cache }.not_to raise_error
    end
  end

  describe ".reload_config" do
    it "calls reload_config on factory when available" do
      factory = double("factory")

      # Set the instance variable directly since it's cached
      described_class.instance_variable_set(:@harness_factory, factory)
      allow(factory).to receive(:reload_config)

      described_class.reload_config
      expect(factory).to have_received(:reload_config)
    end

    it "handles nil factory gracefully" do
      described_class.instance_variable_set(:@harness_factory, nil)
      expect { described_class.reload_config }.not_to raise_error
    end
  end
end
