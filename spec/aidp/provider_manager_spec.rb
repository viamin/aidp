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
    described_class.instance_variable_set(:@harness_factory, nil)
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
end
