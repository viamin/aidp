# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Harness::Configuration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, "aidp.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "loads configuration successfully" do
      expect { described_class.new(temp_dir) }.not_to raise_error
    end

    it "raises error for invalid configuration" do
      File.write(config_file, {
        harness: {
          default_provider: "nonexistent_provider"
        }
      }.to_yaml)

      expect { described_class.new(temp_dir) }.to raise_error(Aidp::Harness::Configuration::ConfigurationError)
    end
  end

  describe "#harness_config" do
    it "returns harness configuration" do
      config = described_class.new(temp_dir)
      harness_config = config.harness_config

      expect(harness_config).to have_key(:default_provider)
      expect(harness_config).to have_key(:max_retries)
      expect(harness_config).to have_key(:fallback_providers)
    end
  end

  describe "#provider_config" do
    it "returns provider configuration" do
      config = described_class.new(temp_dir)
      provider_config = config.provider_config("cursor")

      expect(provider_config).to have_key(:type)
      expect(provider_config[:type]).to eq("package")
    end

    it "returns empty hash for unknown provider" do
      config = described_class.new(temp_dir)
      provider_config = config.provider_config("unknown")

      expect(provider_config).to eq({})
    end
  end

  describe "#configured_providers" do
    it "returns list of configured providers" do
      config = described_class.new(temp_dir)
      providers = config.configured_providers

      expect(providers).to include("cursor", "claude", "gemini")
    end
  end

  describe "#default_provider" do
    it "returns default provider" do
      config = described_class.new(temp_dir)
      expect(config.default_provider).to eq("cursor")
    end
  end

  describe "#fallback_providers" do
    it "returns fallback providers" do
      config = described_class.new(temp_dir)
      fallback_providers = config.fallback_providers

      expect(fallback_providers).to include("claude", "gemini")
    end
  end

  describe "#max_retries" do
    it "returns max retries" do
      config = described_class.new(temp_dir)
      expect(config.max_retries).to eq(2)
    end
  end

  describe "#provider_type" do
    it "returns provider type" do
      config = described_class.new(temp_dir)
      expect(config.provider_type("cursor")).to eq("package")
      expect(config.provider_type("claude")).to eq("api")
    end

    it "returns unknown for unknown provider" do
      config = described_class.new(temp_dir)
      expect(config.provider_type("unknown")).to eq("unknown")
    end
  end

  describe "#max_tokens" do
    it "returns max tokens for API provider" do
      config = described_class.new(temp_dir)
      expect(config.max_tokens("claude")).to eq(100_000)
      expect(config.max_tokens("gemini")).to eq(50_000)
    end

    it "returns nil for non-API provider" do
      config = described_class.new(temp_dir)
      expect(config.max_tokens("cursor")).to be_nil
    end
  end

  describe "#default_flags" do
    it "returns default flags" do
      config = described_class.new(temp_dir)
      expect(config.default_flags("cursor")).to eq([])
    end
  end

  describe "#provider_configured?" do
    it "returns true for configured provider" do
      config = described_class.new(temp_dir)
      expect(config.provider_configured?("cursor")).to be true
    end

    it "returns false for unconfigured provider" do
      config = described_class.new(temp_dir)
      expect(config.provider_configured?("unknown")).to be false
    end
  end

  describe "#available_providers" do
    it "returns all providers when not restricted" do
      config = described_class.new(temp_dir)
      providers = config.available_providers

      expect(providers).to include("cursor", "claude", "gemini")
    end

    it "filters out BYOK providers when restricted" do
      File.write(config_file, {
        harness: {
          restrict_to_non_byok: true
        },
        providers: {
          cursor: { type: "package" },
          claude: { type: "api" },
          byok_provider: { type: "byok" }
        }
      }.to_yaml)

      config = described_class.new(temp_dir)
      providers = config.available_providers

      expect(providers).to include("cursor", "claude")
      expect(providers).not_to include("byok_provider")
    end
  end

  describe "#config_exists?" do
    it "returns true when config file exists" do
      File.write(config_file, "test")
      config = described_class.new(temp_dir)
      expect(config.config_exists?).to be true
    end

    it "returns false when config file does not exist" do
      config = described_class.new(temp_dir)
      expect(config.config_exists?).to be false
    end
  end

  describe "#create_example_config" do
    it "creates example configuration file" do
      config = described_class.new(temp_dir)
      result = config.create_example_config

      expect(result).to be true
      expect(File.exist?(config_file)).to be true
    end
  end

  describe "#raw_config" do
    it "returns raw configuration hash" do
      config = described_class.new(temp_dir)
      raw_config = config.raw_config

      expect(raw_config).to be_a(Hash)
      expect(raw_config).to have_key(:harness)
      expect(raw_config).to have_key(:providers)
    end
  end
end
