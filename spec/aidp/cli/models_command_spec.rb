# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "yaml"
require_relative "../../../lib/aidp/cli/models_command"

RSpec.describe Aidp::CLI::ModelsCommand do
  let(:test_prompt) { TestPrompt.new(responses: {}) }
  let(:mock_registry) { instance_double(Aidp::Harness::ModelRegistry) }
  let(:mock_ruby_llm_registry) { instance_double(Aidp::Harness::RubyLLMRegistry) }
  let(:mock_config) { instance_double(Aidp::Harness::Configuration) }
  let(:models_command) { described_class.new(prompt: test_prompt, registry: mock_registry, ruby_llm_registry: mock_ruby_llm_registry) }
  let(:temp_dir) { Dir.mktmpdir("models_command_test") }

  before do
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
    let(:anthropic_models) { ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001"] }
    let(:claude_sonnet_info) do
      {
        id: "claude-sonnet-4-5-20250929",
        tier: :standard,
        capabilities: ["vision", "thinking"],
        context_window: 200_000
      }
    end
    let(:claude_haiku_info) do
      {
        id: "claude-haiku-4-5-20251001",
        tier: :mini,
        capabilities: ["vision"],
        context_window: 128_000
      }
    end

    before do
      # Mock ruby_llm_registry.models_for_provider for all known providers
      %w[anthropic openai google azure bedrock openrouter].each do |provider|
        if provider == "anthropic"
          allow(mock_ruby_llm_registry).to receive(:models_for_provider).with(provider).and_return(anthropic_models)
        else
          allow(mock_ruby_llm_registry).to receive(:models_for_provider).with(provider).and_return([])
        end
      end

      # Mock ruby_llm_registry.get_model_info to return model details
      allow(mock_ruby_llm_registry).to receive(:get_model_info).with("claude-sonnet-4-5-20250929").and_return(claude_sonnet_info)
      allow(mock_ruby_llm_registry).to receive(:get_model_info).with("claude-haiku-4-5-20251001").and_return(claude_haiku_info)
    end

    it "lists all models successfully" do
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(0)
    end

    it "filters models by tier" do
      result = models_command.send(:run_list_command, ["--tier=standard"])
      expect(result).to eq(0)
    end

    it "filters models by provider" do
      result = models_command.send(:run_list_command, ["--provider=anthropic"])
      expect(result).to eq(0)
    end

    it "shows message when no models match criteria" do
      %w[anthropic openai google azure bedrock openrouter].each do |provider|
        allow(mock_ruby_llm_registry).to receive(:models_for_provider).with(provider).and_return([])
      end
      expect(models_command).to receive(:display_message).with("No models found matching the specified criteria.", type: :info)
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(0)
    end

    it "handles registry errors gracefully" do
      allow(mock_ruby_llm_registry).to receive(:models_for_provider).and_raise(StandardError.new("Test error"))
      expect(models_command).to receive(:display_message).with("Error listing models: Test error", type: :error)
      result = models_command.send(:run_list_command, [])
      expect(result).to eq(1)
    end

    it "handles unexpected errors gracefully" do
      allow(mock_ruby_llm_registry).to receive(:models_for_provider).and_raise(StandardError.new("Unexpected error"))
      expect(models_command).to receive(:display_message).with("Error listing models: Unexpected error", type: :error)
      result = models_command.send(:run_list_command, [])
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
              "thinking_tiers" => {
                "mini" => {"models" => ["claude-3-haiku"]},
                "standard" => {"models" => ["claude-3-5-sonnet"]},
                "advanced" => {"models" => ["claude-3-opus"]}
              }
            }
          }
        }))

        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).with(temp_dir).and_return(true)

        # Mock provider class
        provider_class = class_double("AgentHarness::Providers::Anthropic")
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
              "thinking_tiers" => {
                "mini" => {"models" => ["claude-3-haiku"]},
                "standard" => {"models" => ["claude-3-5-sonnet"]}
              }
            }
          }
        }))

        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(Aidp::Config).to receive(:config_exists?).with(temp_dir).and_return(true)

        provider_class = class_double("AgentHarness::Providers::Anthropic")
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
        thinking_tiers: {
          mini: {models: ["claude-3-haiku"]},
          standard: {models: ["claude-3-5-sonnet"]},
          advanced: {models: ["claude-3-opus"]}
        }
      })
      cfg
    end

    let(:config_missing_tier) do
      cfg = instance_double(Aidp::Harness::Configuration)
      allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
      allow(cfg).to receive(:provider_config).with("anthropic").and_return({
        thinking_tiers: {
          mini: {models: ["claude-3-haiku"]},
          standard: {models: ["claude-3-5-sonnet"]}
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
        thinking_tiers: {
          mini: {models: ["claude-3-haiku"]}
        }
      })
      cfg
    end

    before do
      provider_class = class_double("AgentHarness::Providers::Anthropic")
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
      provider_class = class_double("AgentHarness::Providers::Anthropic")
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
          tier: :standard,
          capabilities: ["vision", "thinking"],
          context_window: 200_000
        }
      end

      it "builds a table row with all fields" do
        row = models_command.send(:build_table_row, "anthropic", "claude-3-5-sonnet", model_info, "standard")
        expect(row[0]).to eq("anthropic")
        expect(row[1]).to eq("claude-3-5-sonnet")
        expect(row[2]).to eq("standard")
        expect(row[3]).to eq("vision,thinking")
        expect(row[4]).to eq("200K")
        expect(row[5]).to eq("-") # Speed not available in registry
      end

      it "handles nil provider" do
        row = models_command.send(:build_table_row, nil, "claude-3-5-sonnet", model_info, "standard")
        expect(row[0]).to eq("-")
      end

      it "handles empty capabilities" do
        info = model_info.merge(capabilities: [])
        row = models_command.send(:build_table_row, "anthropic", "claude-3-5-sonnet", info, "standard")
        expect(row[3]).to eq("-")
      end
    end

    describe "#tier_has_model?" do
      let(:config) do
        cfg = instance_double(Aidp::Harness::Configuration)
        allow(cfg).to receive(:configured_providers).and_return(["anthropic"])
        allow(cfg).to receive(:provider_config).with("anthropic").and_return({
          thinking_tiers: {
            mini: {models: ["claude-3-haiku"]},
            standard: {models: ["claude-3-5-sonnet"]}
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
        expect(result).to eq(AgentHarness::Providers::Anthropic)
      end

      it "returns nil for non-existent provider" do
        result = models_command.send(:get_provider_class, "nonexistent")
        expect(result).to be_nil
      end
    end
  end
end
