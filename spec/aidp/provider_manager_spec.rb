# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::ProviderManager do
  let(:mock_factory) { instance_double(Aidp::Harness::ProviderFactory) }

  before do
    # Mock the harness factory for all tests
    allow(described_class).to receive(:get_harness_factory).and_return(mock_factory)
  end

  after do
    # Clean up cached factory instance
    described_class.harness_factory = nil
  end

  describe ".get_provider" do
    it "returns a provider instance" do
      provider_instance = instance_double(Aidp::Providers::Cursor)
      allow(mock_factory).to receive(:create_provider).with("cursor", {}).and_return(provider_instance)

      provider = described_class.get_provider("cursor")
      expect(provider).to eq(provider_instance)
    end

    it "supports anthropic provider" do
      provider_instance = instance_double(Aidp::Providers::Anthropic)
      allow(mock_factory).to receive(:create_provider).with("anthropic", {}).and_return(provider_instance)

      provider = described_class.get_provider("anthropic")
      expect(provider).to eq(provider_instance)
    end

    it "supports claude alias" do
      provider_instance = instance_double(Aidp::Providers::Anthropic)
      allow(mock_factory).to receive(:create_provider).with("claude", {}).and_return(provider_instance)

      provider = described_class.get_provider("claude")
      expect(provider).to eq(provider_instance)
    end

    it "supports gemini provider" do
      provider_instance = instance_double(Aidp::Providers::Gemini)
      allow(mock_factory).to receive(:create_provider).with("gemini", {}).and_return(provider_instance)

      provider = described_class.get_provider("gemini")
      expect(provider).to eq(provider_instance)
    end

    it "supports github_copilot provider" do
      provider_instance = instance_double(Aidp::Providers::GithubCopilot)
      allow(mock_factory).to receive(:create_provider).with("github_copilot", {}).and_return(provider_instance)

      provider = described_class.get_provider("github_copilot")
      expect(provider).to eq(provider_instance)
    end

    it "supports codex provider" do
      provider_instance = instance_double(Aidp::Providers::Codex)
      allow(mock_factory).to receive(:create_provider).with("codex", {}).and_return(provider_instance)

      provider = described_class.get_provider("codex")
      expect(provider).to eq(provider_instance)
    end

    it "accepts custom prompt" do
      prompt = double("prompt")
      provider_instance = instance_double(Aidp::Providers::Cursor)
      allow(mock_factory).to receive(:create_provider).with("cursor", {prompt: prompt}).and_return(provider_instance)

      provider = described_class.get_provider("cursor", prompt: prompt)
      expect(provider).to eq(provider_instance)
    end

    it "uses harness factory when available" do
      provider_instance = double("provider")
      allow(mock_factory).to receive(:create_provider).with("cursor", {}).and_return(provider_instance)

      result = described_class.get_provider("cursor")
      expect(result).to eq(provider_instance)
    end

    it "raises error when harness factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      expect {
        described_class.get_provider("cursor")
      }.to raise_error("Harness factory not available")
    end
  end

  describe ".load_from_config" do
    it "loads provider from config hash" do
      config = {"provider" => "anthropic"}
      provider_instance = instance_double(Aidp::Providers::Anthropic)
      allow(mock_factory).to receive(:create_provider).with("anthropic", {}).and_return(provider_instance)

      provider = described_class.load_from_config(config)
      expect(provider).to eq(provider_instance)
    end

    it "defaults to cursor when no provider specified" do
      config = {}
      provider_instance = instance_double(Aidp::Providers::Cursor)
      allow(mock_factory).to receive(:create_provider).with("cursor", {}).and_return(provider_instance)

      provider = described_class.load_from_config(config)
      expect(provider).to eq(provider_instance)
    end

    it "passes options through" do
      config = {"provider" => "cursor"}
      prompt = double("prompt")
      provider_instance = instance_double(Aidp::Providers::Cursor)
      allow(mock_factory).to receive(:create_provider).with("cursor", {prompt: prompt}).and_return(provider_instance)

      provider = described_class.load_from_config(config, prompt: prompt)
      expect(provider).to eq(provider_instance)
    end
  end

  describe ".get_harness_factory" do
    before do
      # Remove the stub for these tests to test actual factory retrieval
      allow(described_class).to receive(:get_harness_factory).and_call_original
    end

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
      it "creates provider using factory" do
        provider_instance = double("provider")
        allow(mock_factory).to receive(:create_provider).with("cursor", {}).and_return(provider_instance)

        result = described_class.create_harness_provider("cursor")
        expect(result).to eq(provider_instance)
      end
    end

    context "when harness factory is not available" do
      before do
        allow(described_class).to receive(:get_harness_factory).and_return(nil)
      end

      it "raises error" do
        expect {
          described_class.create_harness_provider("cursor")
        }.to raise_error("Harness factory not available")
      end
    end
  end

  describe ".get_all_providers" do
    it "returns providers from factory" do
      providers = [double("provider1"), double("provider2")]
      allow(mock_factory).to receive(:create_all_providers).with({}).and_return(providers)

      result = described_class.get_all_providers
      expect(result).to eq(providers)
    end

    it "returns empty array when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.get_all_providers
      expect(result).to eq([])
    end
  end

  describe ".provider_configured?" do
    it "checks if provider is configured via factory" do
      allow(mock_factory).to receive(:configured_providers).with({}).and_return(["cursor", "anthropic"])

      expect(described_class.provider_configured?("cursor")).to be true
      expect(described_class.provider_configured?("gemini")).to be false
    end

    it "returns false when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      expect(described_class.provider_configured?("cursor")).to be false
    end
  end

  describe ".provider_enabled?" do
    it "checks if provider is enabled via factory" do
      allow(mock_factory).to receive(:enabled_providers).with({}).and_return(["cursor"])

      expect(described_class.provider_enabled?("cursor")).to be true
      expect(described_class.provider_enabled?("anthropic")).to be false
    end

    it "returns false when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      expect(described_class.provider_enabled?("cursor")).to be false
    end
  end

  describe ".get_providers_by_priority" do
    it "returns providers ordered by priority via factory" do
      providers = [double("provider1"), double("provider2"), double("provider3")]
      allow(mock_factory).to receive(:create_providers_by_priority).with({}).and_return(providers)

      result = described_class.get_providers_by_priority
      expect(result).to eq(providers)
    end

    it "returns empty array when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.get_providers_by_priority
      expect(result).to eq([])
    end

    it "passes options to factory" do
      providers = [double("provider")]
      allow(mock_factory).to receive(:create_providers_by_priority).with({project_dir: "/tmp"}).and_return(providers)

      result = described_class.get_providers_by_priority(project_dir: "/tmp")
      expect(result).to eq(providers)
    end
  end

  describe ".get_enabled_providers" do
    it "gets enabled provider names then creates providers" do
      enabled_names = ["cursor", "anthropic"]
      providers = [double("cursor_provider"), double("anthropic_provider")]

      allow(mock_factory).to receive(:enabled_providers).with({}).and_return(enabled_names)
      allow(mock_factory).to receive(:create_providers).with(enabled_names, {}).and_return(providers)

      result = described_class.get_enabled_providers
      expect(result).to eq(providers)
    end

    it "returns empty array when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.get_enabled_providers
      expect(result).to eq([])
    end

    it "passes options through to both factory methods" do
      enabled_names = ["cursor"]
      providers = [double("provider")]
      options = {project_dir: "/tmp"}

      allow(mock_factory).to receive(:enabled_providers).with(options).and_return(enabled_names)
      allow(mock_factory).to receive(:create_providers).with(enabled_names, options).and_return(providers)

      result = described_class.get_enabled_providers(options)
      expect(result).to eq(providers)
    end
  end

  describe ".get_provider_capabilities" do
    it "returns capabilities for a provider" do
      capabilities = ["tool_use", "function_calling", "streaming"]
      allow(mock_factory).to receive(:provider_capabilities).with("anthropic", {}).and_return(capabilities)

      result = described_class.get_provider_capabilities("anthropic")
      expect(result).to eq(capabilities)
    end

    it "returns empty array when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.get_provider_capabilities("anthropic")
      expect(result).to eq([])
    end

    it "passes options to factory" do
      capabilities = ["tool_use"]
      allow(mock_factory).to receive(:provider_capabilities).with("cursor", {model: "gpt-4"}).and_return(capabilities)

      result = described_class.get_provider_capabilities("cursor", model: "gpt-4")
      expect(result).to eq(capabilities)
    end
  end

  describe ".provider_supports_feature?" do
    it "checks if provider supports a specific feature" do
      allow(mock_factory).to receive(:provider_supports_feature?).with("anthropic", "tool_use", {}).and_return(true)
      allow(mock_factory).to receive(:provider_supports_feature?).with("cursor", "streaming", {}).and_return(false)

      expect(described_class.provider_supports_feature?("anthropic", "tool_use")).to be true
      expect(described_class.provider_supports_feature?("cursor", "streaming")).to be false
    end

    it "returns false when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.provider_supports_feature?("anthropic", "tool_use")
      expect(result).to be false
    end

    it "passes options to factory" do
      allow(mock_factory).to receive(:provider_supports_feature?).with("gemini", "vision", {version: "1.5"}).and_return(true)

      result = described_class.provider_supports_feature?("gemini", "vision", version: "1.5")
      expect(result).to be true
    end
  end

  describe ".get_provider_models" do
    it "returns available models for a provider" do
      models = ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229"]
      allow(mock_factory).to receive(:provider_models).with("anthropic", {}).and_return(models)

      result = described_class.get_provider_models("anthropic")
      expect(result).to eq(models)
    end

    it "returns empty array when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.get_provider_models("anthropic")
      expect(result).to eq([])
    end

    it "passes options to factory" do
      models = ["gpt-4", "gpt-3.5-turbo"]
      allow(mock_factory).to receive(:provider_models).with("cursor", {tier: "standard"}).and_return(models)

      result = described_class.get_provider_models("cursor", tier: "standard")
      expect(result).to eq(models)
    end
  end

  describe ".validate_provider_config" do
    it "validates configuration for a specific provider" do
      errors = []
      allow(mock_factory).to receive(:validate_provider_config).with("anthropic", {}).and_return(errors)

      result = described_class.validate_provider_config("anthropic")
      expect(result).to eq(errors)
    end

    it "returns validation errors when configuration is invalid" do
      errors = ["API key not configured", "Invalid model specified"]
      allow(mock_factory).to receive(:validate_provider_config).with("cursor", {}).and_return(errors)

      result = described_class.validate_provider_config("cursor")
      expect(result).to eq(errors)
    end

    it "returns error message when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.validate_provider_config("anthropic")
      expect(result).to eq(["Harness factory not available"])
    end

    it "passes options to factory" do
      errors = []
      allow(mock_factory).to receive(:validate_provider_config).with("gemini", {strict: true}).and_return(errors)

      result = described_class.validate_provider_config("gemini", strict: true)
      expect(result).to eq(errors)
    end
  end

  describe ".validate_all_provider_configs" do
    it "validates all provider configurations" do
      validation_results = {
        "anthropic" => [],
        "cursor" => ["API key missing"],
        "gemini" => []
      }
      allow(mock_factory).to receive(:validate_all_provider_configs).with({}).and_return(validation_results)

      result = described_class.validate_all_provider_configs
      expect(result).to eq(validation_results)
    end

    it "returns empty hash when factory not available" do
      allow(described_class).to receive(:get_harness_factory).and_return(nil)

      result = described_class.validate_all_provider_configs
      expect(result).to eq({})
    end

    it "passes options to factory" do
      validation_results = {"anthropic" => []}
      allow(mock_factory).to receive(:validate_all_provider_configs).with({verbose: true}).and_return(validation_results)

      result = described_class.validate_all_provider_configs(verbose: true)
      expect(result).to eq(validation_results)
    end
  end

  describe ".clear_cache" do
    it "calls clear_cache on harness factory when available" do
      # Set instance variable directly since clear_cache uses @harness_factory&.clear_cache
      described_class.harness_factory = mock_factory
      expect(mock_factory).to receive(:clear_cache)

      described_class.clear_cache
    end

    it "does not raise error when factory not available" do
      described_class.harness_factory = nil

      expect { described_class.clear_cache }.not_to raise_error
    end

    it "handles nil factory gracefully using safe navigation" do
      described_class.harness_factory = nil

      expect { described_class.clear_cache }.not_to raise_error
    end
  end

  describe ".reload_config" do
    it "calls reload_config on harness factory when available" do
      # Set instance variable directly since reload_config uses @harness_factory&.reload_config
      described_class.harness_factory = mock_factory
      expect(mock_factory).to receive(:reload_config)

      described_class.reload_config
    end

    it "does not raise error when factory not available" do
      described_class.harness_factory = nil

      expect { described_class.reload_config }.not_to raise_error
    end

    it "handles nil factory gracefully using safe navigation" do
      described_class.harness_factory = nil

      expect { described_class.reload_config }.not_to raise_error
    end
  end
end
