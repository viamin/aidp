# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Config do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, "aidp.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".load" do
    context "when aidp.yml exists" do
      before do
        File.write(config_file, {
          harness: {
            default_provider: "test_provider"
          }
        }.to_yaml)
      end

      it "loads the configuration from aidp.yml" do
        config = described_class.load(temp_dir)
        expect(config["harness"]["default_provider"]).to eq("test_provider")
      end
    end

    context "when only .aidp.yml exists" do
      let(:legacy_config_file) { File.join(temp_dir, ".aidp.yml") }

      before do
        File.write(legacy_config_file, {
          harness: {
            default_provider: "legacy_provider"
          }
        }.to_yaml)
      end

      it "loads the configuration from .aidp.yml" do
        config = described_class.load(temp_dir)
        expect(config["harness"]["default_provider"]).to eq("legacy_provider")
      end
    end

    context "when no configuration file exists" do
      it "returns empty hash" do
        config = described_class.load(temp_dir)
        expect(config).to eq({})
      end
    end
  end

  describe ".load_harness_config" do
    it "returns default configuration when no file exists" do
      config = described_class.load_harness_config(temp_dir)

      expect(config[:harness][:default_provider]).to eq("cursor")
      expect(config[:harness][:max_retries]).to eq(2)
      expect(config[:providers]).to have_key(:cursor)
      expect(config[:providers]).to have_key(:claude)
      expect(config[:providers]).to have_key(:gemini)
    end

    it "merges user configuration with defaults" do
      File.write(config_file, {
        harness: {
          default_provider: "custom_provider",
          max_retries: 5
        },
        providers: {
          custom_provider: {
            type: "api",
            max_tokens: 200000
          }
        }
      }.to_yaml)

      config = described_class.load_harness_config(temp_dir)

      expect(config[:harness][:default_provider]).to eq("custom_provider")
      expect(config[:harness][:max_retries]).to eq(5)
      expect(config[:providers][:custom_provider][:type]).to eq("api")
      expect(config[:providers][:custom_provider][:max_tokens]).to eq(200000)

      # Default providers should still be present
      expect(config[:providers]).to have_key(:cursor)
    end
  end

  describe ".validate_harness_config" do
    it "returns no errors for valid configuration" do
      config = {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "package",
            default_flags: []
          }
        }
      }

      errors = described_class.validate_harness_config(config)
      expect(errors).to be_empty
    end

    it "returns errors for invalid configuration" do
      config = {
        harness: {
          default_provider: "nonexistent"
        },
        providers: {
          cursor: {
            type: "invalid_type"
          }
        }
      }

      errors = described_class.validate_harness_config(config)
      expect(errors).not_to be_empty
      expect(errors).to include(match(/invalid type/))
    end
  end

  describe ".create_example_config" do
    it "creates example configuration file" do
      result = described_class.create_example_config(temp_dir)

      expect(result).to be true
      expect(File.exist?(config_file)).to be true

      config = YAML.load_file(config_file)
      expect(config).to have_key("harness")
      expect(config).to have_key("providers")
    end

    it "returns false if file already exists" do
      File.write(config_file, "existing content")

      result = described_class.create_example_config(temp_dir)
      expect(result).to be false
    end
  end

  describe ".config_exists?" do
    it "returns true when aidp.yml exists" do
      File.write(config_file, "test")
      expect(described_class.config_exists?(temp_dir)).to be true
    end

    it "returns true when .aidp.yml exists" do
      legacy_file = File.join(temp_dir, ".aidp.yml")
      File.write(legacy_file, "test")
      expect(described_class.config_exists?(temp_dir)).to be true
    end

    it "returns false when no config file exists" do
      expect(described_class.config_exists?(temp_dir)).to be false
    end
  end
end
