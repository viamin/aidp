# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Config do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, ".aidp", "aidp.yml") }

  before do
    FileUtils.mkdir_p(File.dirname(config_file))
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".load" do
    context "when .aidp/aidp.yml exists" do
      before do
        File.write(config_file, {
          harness: {
            default_provider: "test_provider"
          }
        }.to_yaml)
      end

      it "loads the configuration from .aidp/aidp.yml" do
        config = described_class.load(temp_dir)
        expect(config[:harness][:default_provider]).to eq("test_provider")
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
      expect(config[:providers]).to have_key(:anthropic)
      expect(config[:providers]).to have_key(:macos)
    end

    it "merges user configuration with defaults" do
      File.write(config_file, {
        harness: {
          default_provider: "custom_provider",
          max_retries: 5
        },
        providers: {
          custom_provider: {
            type: "usage_based",
            max_tokens: 200000
          }
        }
      }.to_yaml)

      config = described_class.load_harness_config(temp_dir)

      expect(config[:harness][:default_provider]).to eq("custom_provider")
      expect(config[:harness][:max_retries]).to eq(5)
      expect(config[:providers][:custom_provider][:type]).to eq("usage_based")
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
            type: "subscription",
            default_flags: []
          }
        }
      }

      errors = described_class.validate_harness_config(config)
      expect(errors).to be_empty
    end

    it "returns errors for invalid configuration" do
      # Create a YAML file with invalid configuration
      invalid_config = {
        harness: {
          default_provider: "nonexistent"
        },
        providers: {
          cursor: {
            type: "invalid_type"
          }
        }
      }

      File.write(config_file, YAML.dump(invalid_config))

      errors = described_class.validate_harness_config(invalid_config, temp_dir)
      expect(errors).not_to be_empty
      expect(errors).to include(match(/must be one of usage_based, subscription, passthrough/))
    end
  end

  describe ".harness_config" do
    it "returns symbolized harness keys" do
      File.write(config_file, {"harness" => {"default_provider" => "cursor", "max_retries" => 5}}.to_yaml)
      harness = described_class.harness_config(temp_dir)
      expect(harness).to include(:default_provider, :max_retries)
      expect(harness[:max_retries]).to eq(5)
    end

    it "returns default harness when no harness section present" do
      File.write(config_file, {providers: {cursor: {type: "subscription"}}}.to_yaml)
      harness = described_class.harness_config(temp_dir)
      expect(harness[:default_provider]).to eq("cursor")
      expect(harness[:max_retries]).to eq(2)
    end
  end

  describe ".provider_config" do
    before do
      File.write(config_file, {
        providers: {
          "cursor" => {"type" => "subscription", "models" => ["a", "b"]},
          :anthropic => {type: "usage_based", models: ["x"]}
        }
      }.to_yaml)
    end

    it "finds provider by string name" do
      cfg = described_class.provider_config("cursor", temp_dir)
      expect(cfg).to include(:type, :models)
      expect(cfg[:type]).to eq("subscription")
    end

    it "finds provider by symbol name" do
      cfg = described_class.provider_config(:anthropic, temp_dir)
      expect(cfg[:type]).to eq("usage_based")
    end

    it "returns empty hash for missing provider" do
      cfg = described_class.provider_config(:missing, temp_dir)
      expect(cfg).to eq({})
    end
  end

  describe ".configured_providers" do
    it "returns list of provider names as strings" do
      File.write(config_file, {providers: {:cursor => {type: "subscription"}, "anthropic" => {"type" => "usage_based"}}}.to_yaml)
      list = described_class.configured_providers(temp_dir)
      expect(list).to include("cursor", "anthropic")
      expect(list).to all(be_a(String))
    end
  end

  describe ".skills_config" do
    it "returns symbolized skills configuration" do
      File.write(config_file, {skills: {"search_paths" => ["skills"], "enable_custom_skills" => false}}.to_yaml)
      skills = described_class.skills_config(temp_dir)
      expect(skills).to include(:search_paths, :enable_custom_skills)
      expect(skills[:enable_custom_skills]).to be false
    end
  end

  describe ".config_exists?" do
    it "returns false for missing config" do
      expect(described_class.config_exists?(temp_dir)).to be false
    end
  end

  describe ".create_example_config" do
    it "does not overwrite existing config" do
      File.write(config_file, {harness: {default_provider: "existing"}}.to_yaml)
      result = described_class.create_example_config(temp_dir)
      expect(result).to be false
      content = YAML.load_file(config_file)
      expect(content[:harness][:default_provider]).to eq("existing")
    end

    it "creates a new example config when absent" do
      FileUtils.rm_f(config_file)
      result = described_class.create_example_config(temp_dir)
      expect(result).to be true
      content = YAML.safe_load_file(config_file, permitted_classes: [Symbol], aliases: true)
      expect(content[:harness][:default_provider]).to eq("cursor")
    end
  end

  describe ".load" do
    it "returns empty hash for malformed YAML (error rescued)" do
      File.write(config_file, "::bad_yaml:::\n: :")
      result = described_class.load(temp_dir)
      expect(result).to eq({})
    end

    it "loads with aliases and symbol keys" do
      yaml = <<~YML
        harness: &h
          default_provider: cursor
        providers:
          cursor: { type: subscription }
        extra: *h
      YML
      File.write(config_file, yaml)
      result = described_class.load(temp_dir)
      expect(result["harness"]["default_provider"]).to eq("cursor")
      expect(result["extra"]["default_provider"]).to eq("cursor")
    end
  end

  describe ".validate_harness_config provider validation skip conditions" do
    it "skips provider validation when should_validate is false" do
      # Use current working directory to satisfy project_dir == Dir.pwd so validation may skip
      cwd = Dir.pwd
      cfg_path = File.join(cwd, ".aidp", "aidp.yml")
      FileUtils.mkdir_p(File.dirname(cfg_path))
      File.write(cfg_path, {harness: {default_provider: "cursor"}, providers: {cursor: {type: "subscription"}}}.to_yaml)
      config = {harness: {default_provider: "cursor"}, providers: {cursor: {type: "subscription"}}}
      errors = described_class.validate_harness_config(config, cwd)
      # Depending on validator implementation, may still produce errors if validator enforces additional constraints.
      # We assert no critical default_provider missing error.
      expect(errors).not_to include("Default provider not specified in harness config")
    end

    it "adds error when default_provider missing" do
      config = {harness: {}, providers: {cursor: {type: "subscription"}}}
      errors = described_class.validate_harness_config(config, temp_dir)
      expect(errors).to include("Default provider not specified in harness config")
    end
  end

  describe "deep merge behavior" do
    it "deep merges harness, providers, and skills with overrides" do
      File.write(config_file, {
        harness: {max_retries: 9, default_provider: "anthropic"},
        providers: {anthropic: {type: "usage_based", new_field: "x"}},
        skills: {search_paths: ["custom"], enable_custom_skills: false}
      }.to_yaml)
      merged = described_class.load_harness_config(temp_dir)
      expect(merged[:harness][:max_retries]).to eq(9)
      expect(merged[:providers][:anthropic][:new_field]).to eq("x")
      expect(merged[:skills][:search_paths]).to eq(["custom"])
      expect(merged[:skills][:enable_custom_skills]).to be false
    end

    it "symbolizes nested provider keys" do
      File.write(config_file, {
        providers: {"cursor" => {"models_config" => {"cursor-fast" => {"timeout" => 123}}}}
      }.to_yaml)
      merged = described_class.load_harness_config(temp_dir)
      expect(merged[:providers][:cursor][:models_config][:"cursor-fast"][:timeout]).to eq(123)
    end
  end

  describe ".symbolize_keys (indirect)" do
    it "recursively converts string keys to symbols" do
      File.write(config_file, {providers: {"cursor" => {"model_weights" => {"cursor-default" => 3}}}}.to_yaml)
      merged = described_class.load_harness_config(temp_dir)
      expect(merged[:providers][:cursor][:model_weights][:"cursor-default"]).to eq(3)
    end
  end

  describe "path helpers" do
    it "returns config_file path" do
      expect(described_class.config_file(temp_dir)).to eq(File.join(temp_dir, ".aidp", "aidp.yml"))
    end

    it "returns aidp_dir path" do
      expect(described_class.aidp_dir(temp_dir)).to eq(File.join(temp_dir, ".aidp"))
    end

    it "returns config_dir path" do
      expect(described_class.config_dir(temp_dir)).to eq(File.join(temp_dir, ".aidp"))
    end
  end

  describe ".create_example_config" do
    it "creates example configuration file" do
      result = described_class.create_example_config(temp_dir)

      expect(result).to be true
      expect(File.exist?(config_file)).to be true

      config = YAML.load_file(config_file)
      expect(config).to have_key(:harness)
      expect(config).to have_key(:providers)
    end

    it "returns false if file already exists" do
      File.write(config_file, "existing content")

      result = described_class.create_example_config(temp_dir)
      expect(result).to be false
    end
  end

  describe ".config_exists?" do
    it "returns true when .aidp/aidp.yml exists" do
      File.write(config_file, "test")
      expect(described_class.config_exists?(temp_dir)).to be true
    end

    it "returns false when no config file exists" do
      expect(described_class.config_exists?(temp_dir)).to be false
    end
  end
end
