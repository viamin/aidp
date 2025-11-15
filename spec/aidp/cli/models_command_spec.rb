# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/cli/models_command"

RSpec.describe Aidp::CLI::ModelsCommand do
  let(:test_prompt) { TestPrompt.new(responses: {}) }
  let(:models_command) { described_class.new(prompt: test_prompt) }
  let(:temp_dir) { Dir.mktmpdir("models_command_test") }
  let(:mock_registry) { instance_double(Aidp::Harness::ModelRegistry) }
  let(:mock_discovery) { instance_double(Aidp::Harness::ModelDiscoveryService) }
  let(:mock_config) { instance_double(Aidp::Harness::Configuration) }

  before do
    allow(Aidp::Harness::ModelRegistry).to receive(:new).and_return(mock_registry)
    allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(mock_discovery)
    allow(models_command).to receive(:display_message)
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#run" do
    it "defaults to list command when no subcommand provided" do
      allow(models_command).to receive(:run_list_command)
      expect(models_command).to receive(:run_list_command).with([])
      models_command.run([])
    end

    it "routes to list command explicitly" do
      allow(models_command).to receive(:run_list_command)
      expect(models_command).to receive(:run_list_command).with([])
      models_command.run(["list"])
    end

    it "routes to discover command" do
      allow(models_command).to receive(:run_discover_command)
      expect(models_command).to receive(:run_discover_command).with([])
      models_command.run(["discover"])
    end

    it "routes to refresh command" do
      allow(models_command).to receive(:run_refresh_command)
      expect(models_command).to receive(:run_refresh_command).with([])
      models_command.run(["refresh"])
    end

    it "routes to validate command" do
      allow(models_command).to receive(:run_validate_command)
      expect(models_command).to receive(:run_validate_command).with([])
      models_command.run(["validate"])
    end

    it "shows error for unknown subcommand" do
      expect(models_command).to receive(:display_message).with("Unknown models subcommand: invalid", type: :error)
      expect(models_command).to receive(:display_help)
      result = models_command.run(["invalid"])
      expect(result).to eq(1)
    end
  end

  describe "#run_list_command" do
    let(:sample_families) { ["claude-3-5-sonnet", "gpt-4o"] }
    let(:claude_info) do
      {
        "tier" => "standard",
        "capabilities" => ["vision", "thinking"],
        "context_window" => 200_000,
        "speed" => "fast"
      }
    end
    let(:gpt_info) do
      {
        "tier" => "mini",
        "capabilities" => ["vision"],
        "context_window" => 128_000,
        "speed" => "fast"
      }
    end

    before do
      allow(mock_registry).to receive(:all_families).and_return(sample_families)
      allow(mock_registry).to receive(:get_model_info).with("claude-3-5-sonnet").and_return(claude_info)
      allow(mock_registry).to receive(:get_model_info).with("gpt-4o").and_return(gpt_info)
      allow(models_command).to receive(:find_providers_for_family).and_return(["anthropic"])
    end

    it "lists all models successfully" do
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(0)
    end

    it "filters models by tier" do
      allow(models_command).to receive(:find_providers_for_family).with("claude-3-5-sonnet").and_return(["anthropic"])
      allow(models_command).to receive(:find_providers_for_family).with("gpt-4o").and_return([])

      result = models_command.send(:run_list_command, ["--tier=standard"])
      expect(result).to eq(0)
    end

    it "filters models by provider" do
      result = models_command.send(:run_list_command, ["--provider=anthropic"])
      expect(result).to eq(0)
    end

    it "shows message when no models match criteria" do
      allow(mock_registry).to receive(:all_families).and_return([])
      expect(models_command).to receive(:display_message).with("No models found matching the specified criteria.", type: :info)
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(0)
    end

    it "handles registry errors gracefully" do
      allow(mock_registry).to receive(:all_families).and_raise(Aidp::Harness::ModelRegistry::RegistryError.new("Test error"))
      expect(models_command).to receive(:display_message).with("Error loading model registry: Test error", type: :error)
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(1)
    end

    it "handles unexpected errors gracefully" do
      allow(mock_registry).to receive(:all_families).and_raise(StandardError.new("Unexpected error"))
      expect(models_command).to receive(:display_message).with("Error listing models: Unexpected error", type: :error)
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(1)
    end
  end

  describe "#run_discover_command" do
    let(:discovered_models) do
      {
        "anthropic" => [
          {name: "claude-3-5-sonnet-20241022", family: "claude-3-5-sonnet", tier: "standard"},
          {name: "claude-3-haiku-20240307", family: "claude-3-haiku", tier: "mini"}
        ]
      }
    end

    before do
      allow(mock_discovery).to receive(:discover_all_models).and_return(discovered_models)
    end

    it "discovers models from all providers" do
      expect(mock_discovery).to receive(:discover_all_models).with(use_cache: false)
      result = models_command.send(:run_discover_command, [])
      expect(result).to eq(0)
    end

    it "discovers models from specific provider" do
      allow(mock_discovery).to receive(:discover_models).with("anthropic", use_cache: false).and_return(discovered_models["anthropic"])
      expect(mock_discovery).to receive(:discover_models).with("anthropic", use_cache: false)
      result = models_command.send(:run_discover_command, ["--provider=anthropic"])
      expect(result).to eq(0)
    end

    it "shows warning when no models discovered" do
      allow(mock_discovery).to receive(:discover_all_models).and_return({})
      expect(models_command).to receive(:display_message).with(/No models discovered/, type: :warning)
      result = models_command.send(:run_discover_command, [])
      expect(result).to eq(1)
    end

    it "handles discovery errors gracefully" do
      allow(mock_discovery).to receive(:discover_all_models).and_raise(StandardError.new("Discovery failed"))
      expect(models_command).to receive(:display_message).with("Error discovering models: Discovery failed", type: :error)
      result = models_command.send(:run_discover_command, [])
      expect(result).to eq(1)
    end
  end

  describe "#run_refresh_command" do
    before do
      allow(mock_discovery).to receive(:refresh_cache)
      allow(mock_discovery).to receive(:refresh_all_caches)
    end

    it "refreshes cache for all providers" do
      expect(mock_discovery).to receive(:refresh_all_caches)
      result = models_command.send(:run_refresh_command, [])
      expect(result).to eq(0)
    end

    it "refreshes cache for specific provider" do
      expect(mock_discovery).to receive(:refresh_cache).with("anthropic")
      result = models_command.send(:run_refresh_command, ["--provider=anthropic"])
      expect(result).to eq(0)
    end

    it "handles refresh errors gracefully" do
      allow(mock_discovery).to receive(:refresh_all_caches).and_raise(StandardError.new("Refresh failed"))
      expect(models_command).to receive(:display_message).with("Error refreshing cache: Refresh failed", type: :error)
      result = models_command.send(:run_refresh_command, [])
      expect(result).to eq(1)
    end
  end

  describe "#run_validate_command" do
    context "when configuration is valid" do
      before do
        # Setup valid configuration
        config_path = File.join(temp_dir, ".aidp", "aidp.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, YAML.dump({
          "schema_version" => 1,
          "providers" => {
            "anthropic" => {
              "type" => "usage_based",
              "thinking" => {
                "tiers" => {
                  "mini" => {"models" => [{"model" => "claude-3-haiku"}]},
                  "standard" => {"models" => [{"model" => "claude-3-5-sonnet"}]},
                  "advanced" => {"models" => [{"model" => "claude-3-opus"}]}
                }
              }
            }
          }
        }))

        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).with(temp_dir).and_return(true)

        # Mock provider class
        provider_class = class_double("Aidp::Providers::Anthropic")
        allow(provider_class).to receive(:model_family).and_return("claude-3-haiku")
        allow(provider_class).to receive(:supports_model_family?).and_return(true)
        allow(models_command).to receive(:get_provider_class).with("anthropic").and_return(provider_class)

        allow(mock_registry).to receive(:get_model_info).and_return({"tier" => "mini"})
      end

      it "validates successfully" do
        expect(models_command).to receive(:display_message).with("✅ Configuration is valid!\n", type: :success)
        result = models_command.send(:run_validate_command, [])
        expect(result).to eq(0)
      end
    end

    context "when configuration has tier coverage issues" do
      before do
        # Setup configuration missing advanced tier
        config_path = File.join(temp_dir, ".aidp", "aidp.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, YAML.dump({
          "schema_version" => 1,
          "providers" => {
            "anthropic" => {
              "type" => "usage_based",
              "thinking" => {
                "tiers" => {
                  "mini" => {"models" => [{"model" => "claude-3-haiku"}]},
                  "standard" => {"models" => [{"model" => "claude-3-5-sonnet"}]}
                }
              }
            }
          }
        }))

        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).with(temp_dir).and_return(true)

        provider_class = class_double("Aidp::Providers::Anthropic")
        allow(provider_class).to receive(:model_family).and_return("claude-3-haiku")
        allow(provider_class).to receive(:supports_model_family?).and_return(true)
        allow(models_command).to receive(:get_provider_class).with("anthropic").and_return(provider_class)

        allow(mock_registry).to receive(:get_model_info).and_return({"tier" => "mini"})
        allow(mock_registry).to receive(:models_for_tier).with("advanced").and_return(["claude-3-opus"])
      end

      it "reports tier coverage errors" do
        expect(models_command).to receive(:display_message).with(/Found \d+ configuration error/, type: :error)
        result = models_command.send(:run_validate_command, [])
        expect(result).to eq(1)
      end
    end

    context "when configuration file doesn't exist" do
      before do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).with(temp_dir).and_return(false)
      end

      it "shows error message" do
        expect(models_command).to receive(:display_message).with("❌ No aidp.yml configuration file found", type: :error)
        result = models_command.send(:run_validate_command, [])
        expect(result).to eq(1)
      end
    end

    context "when validation raises an error" do
      before do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).and_raise(StandardError.new("Validation error"))
      end

      it "handles errors gracefully" do
        expect(models_command).to receive(:display_message).with("Error validating configuration: Validation error", type: :error)
        result = models_command.send(:run_validate_command, [])
        expect(result).to eq(1)
      end
    end
  end

  describe "#validate_tier_coverage" do
    let(:config_with_all_tiers) do
      cfg = instance_double(Aidp::Harness::Configuration)
      allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
      allow(cfg).to receive(:provider_config).with("anthropic").and_return({
        thinking: {
          tiers: {
            mini: {models: [{model: "claude-3-haiku"}]},
            standard: {models: [{model: "claude-3-5-sonnet"}]},
            advanced: {models: [{model: "claude-3-opus"}]}
          }
        }
      })
      cfg
    end

    let(:config_missing_tier) do
      cfg = instance_double(Aidp::Harness::Configuration)
      allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
      allow(cfg).to receive(:provider_config).with("anthropic").and_return({
        thinking: {
          tiers: {
            mini: {models: [{model: "claude-3-haiku"}]},
            standard: {models: [{model: "claude-3-5-sonnet"}]}
          }
        }
      })
      cfg
    end

    before do
      allow(mock_registry).to receive(:models_for_tier).and_return(["claude-3-opus"])
    end

    it "passes when all tiers have models" do
      result = models_command.send(:validate_tier_coverage, config_with_all_tiers)
      expect(result[:errors]).to be_empty
    end

    it "reports errors for missing tiers" do
      result = models_command.send(:validate_tier_coverage, config_missing_tier)
      expect(result[:errors].size).to eq(1)
      expect(result[:errors].first[:tier]).to eq("advanced")
    end
  end

  describe "#validate_provider_models" do
    let(:config) do
      cfg = instance_double(Aidp::Harness::Configuration)
      allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
      allow(cfg).to receive(:provider_config).with("anthropic").and_return({
        thinking: {
          tiers: {
            mini: {models: [{model: "claude-3-haiku"}]}
          }
        }
      })
      cfg
    end

    before do
      provider_class = class_double("Aidp::Providers::Anthropic")
      allow(provider_class).to receive(:model_family).with("claude-3-haiku").and_return("claude-3-haiku")
      allow(provider_class).to receive(:supports_model_family?).with("claude-3-haiku").and_return(true)
      allow(models_command).to receive(:get_provider_class).with("anthropic").and_return(provider_class)
      allow(mock_registry).to receive(:get_model_info).with("claude-3-haiku").and_return({"tier" => "mini"})
    end

    it "validates models successfully" do
      result = models_command.send(:validate_provider_models, config)
      expect(result[:errors]).to be_empty
    end

    it "reports errors for unsupported models" do
      provider_class = class_double("Aidp::Providers::Anthropic")
      allow(provider_class).to receive(:model_family).with("claude-3-haiku").and_return("claude-3-haiku")
      allow(provider_class).to receive(:supports_model_family?).with("claude-3-haiku").and_return(false)
      allow(models_command).to receive(:get_provider_class).with("anthropic").and_return(provider_class)

      result = models_command.send(:validate_provider_models, config)
      expect(result[:errors].size).to be > 0
    end

    it "warns about models not in registry" do
      allow(mock_registry).to receive(:get_model_info).with("claude-3-haiku").and_return(nil)

      result = models_command.send(:validate_provider_models, config)
      expect(result[:warnings].size).to be > 0
    end
  end

  describe "helper methods" do
    describe "#format_context_window" do
      it "formats millions of tokens" do
        expect(models_command.send(:format_context_window, 2_000_000)).to eq("2M")
      end

      it "formats thousands of tokens" do
        expect(models_command.send(:format_context_window, 128_000)).to eq("128K")
      end

      it "formats small numbers" do
        expect(models_command.send(:format_context_window, 512)).to eq("512")
      end

      it "returns dash for nil" do
        expect(models_command.send(:format_context_window, nil)).to eq("-")
      end
    end

    describe "#build_table_row" do
      let(:model_info) do
        {
          "tier" => "standard",
          "capabilities" => ["vision", "thinking"],
          "context_window" => 200_000,
          "speed" => "fast"
        }
      end

      it "builds a table row with all fields" do
        row = models_command.send(:build_table_row, "anthropic", "claude-3-5-sonnet", model_info, "registry")
        expect(row[0]).to eq("anthropic")
        expect(row[1]).to eq("claude-3-5-sonnet")
        expect(row[2]).to eq("standard")
        expect(row[3]).to eq("vision,thinking")
        expect(row[4]).to eq("200K")
        expect(row[5]).to eq("fast")
      end

      it "handles nil provider" do
        row = models_command.send(:build_table_row, nil, "claude-3-5-sonnet", model_info, "registry")
        expect(row[0]).to eq("-")
      end

      it "handles empty capabilities" do
        info = model_info.merge("capabilities" => [])
        row = models_command.send(:build_table_row, "anthropic", "claude-3-5-sonnet", info, "registry")
        expect(row[3]).to eq("-")
      end
    end

    describe "#tier_has_model?" do
      let(:config) do
        cfg = instance_double(Aidp::Harness::Configuration)
        allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
        allow(cfg).to receive(:provider_config).with("anthropic").and_return({
          thinking: {
            tiers: {
              mini: {models: [{model: "claude-3-haiku"}]},
              standard: {models: [{model: "claude-3-5-sonnet"}]}
            }
          }
        })
        cfg
      end

      it "returns true when tier has models" do
        expect(models_command.send(:tier_has_model?, config, "mini")).to be true
      end

      it "returns false when tier has no models" do
        expect(models_command.send(:tier_has_model?, config, "advanced")).to be false
      end
    end

    describe "#get_provider_class" do
      it "returns provider class when it exists" do
        result = models_command.send(:get_provider_class, "anthropic")
        expect(result).to eq(Aidp::Providers::Anthropic)
      end

      it "returns nil for non-existent provider" do
        result = models_command.send(:get_provider_class, "nonexistent")
        expect(result).to be_nil
      end
    end
  end
end
