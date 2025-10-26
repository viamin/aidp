# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"
require "aidp/harness/provider_info"
require "aidp/harness/capability_registry"
require "tmpdir"
require "fileutils"

RSpec.describe "CLI Providers Info Command" do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_providers_info_test") }
  let(:provider_name) { "test_provider" }

  before do
    @original_dir = Dir.pwd
    Dir.chdir(temp_dir)
  end

  after do
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "run_providers_info_command" do
    context "with valid provider name" do
      let(:provider_info_double) { instance_double(Aidp::Harness::ProviderInfo) }
      let(:mock_info) do
        {
          last_checked: "2025-10-22T10:00:00-07:00",
          cli_available: true,
          mcp_support: false,
          capabilities: {session_management: true},
          flags: {
            "help" => {flag: "--help", description: "Show help"}
          }
        }
      end

      before do
        # Use proper dependency injection instead of any_instance_of
        allow(Aidp::Harness::ProviderInfo).to receive(:new).with(provider_name, Dir.pwd).and_return(provider_info_double)
        allow(provider_info_double).to receive(:info).with(force_refresh: false).and_return(mock_info)
      end

      it "calls the correct method on ProviderInfo" do
        expect(provider_info_double).to receive(:info).with(force_refresh: false)

        # Capture output to avoid cluttering test output
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_info_command, [provider_name])
      end

      it "handles force refresh flag" do
        expect(provider_info_double).to receive(:info).with(force_refresh: true)

        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_info_command, [provider_name, "--refresh"])
      end

      it "displays provider information correctly" do
        # Test that it shows basic info - just verify the key calls
        expect(Aidp::CLI).to receive(:display_message).with("Provider Information: #{provider_name}", type: :highlight)
        expect(Aidp::CLI).to receive(:display_message).with("Last Checked: 2025-10-22T10:00:00-07:00", type: :info)
        expect(Aidp::CLI).to receive(:display_message).with("CLI Available: Yes", type: :success)
        # Allow other display_message calls without being specific about them
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_info_command, [provider_name])
      end
    end

    context "with missing provider name" do
      it "displays models catalog table" do
        # When no provider is specified, it should call run_providers_models_catalog
        expect(Aidp::CLI).to receive(:run_providers_models_catalog)

        Aidp::CLI.send(:run_providers_info_command, [])
      end
    end

    context "when provider info is nil" do
      let(:provider_info_double) { instance_double(Aidp::Harness::ProviderInfo) }

      before do
        allow(Aidp::Harness::ProviderInfo).to receive(:new).and_return(provider_info_double)
        allow(provider_info_double).to receive(:info).and_return(nil)
      end

      it "displays error message without trying to display other info" do
        # It should show the header first, then detect nil and show error
        expect(Aidp::CLI).to receive(:display_message).with("Provider Information: #{provider_name}", type: :highlight)
        expect(Aidp::CLI).to receive(:display_message).with("No information available for provider: #{provider_name}", type: :error)
        # Allow other display_message calls
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_info_command, [provider_name])
      end
    end
  end

  describe "run_providers_models_catalog" do
    context "with valid models catalog" do
      let(:registry_double) { instance_double(Aidp::Harness::CapabilityRegistry) }
      let(:models_data) do
        {
          "claude-3-5-sonnet" => {
            "tier" => "standard",
            "context_window" => 200000,
            "supports_tools" => true,
            "cost_per_mtok_input" => 3.0
          },
          "claude-3-opus" => {
            "tier" => "pro",
            "context_window" => 200000,
            "supports_tools" => true,
            "cost_per_mtok_input" => 15.0
          }
        }
      end

      before do
        allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(registry_double)
        allow(registry_double).to receive(:load_catalog).and_return(true)
        allow(registry_double).to receive(:provider_names).and_return(["anthropic"])
        allow(registry_double).to receive(:models_for_provider).with("anthropic").and_return(models_data)
      end

      it "displays models catalog table" do
        expect(Aidp::CLI).to receive(:display_message).with("Models Catalog - Thinking Depth Tiers", type: :highlight)
        expect(Aidp::CLI).to receive(:display_message).with(/Provider.*Model.*Tier/, type: :info)
        # Allow other display_message calls
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_models_catalog)
      end

      it "shows model details in table" do
        # Capture all display_message calls
        messages = []
        allow(Aidp::CLI).to receive(:display_message) do |msg, **_opts|
          messages << msg
        end

        Aidp::CLI.send(:run_providers_models_catalog)

        # Check that table contains our model data
        table_output = messages.find { |m| m.to_s.include?("claude-3-5-sonnet") }
        expect(table_output).not_to be_nil
        expect(table_output).to include("standard")
        expect(table_output).to include("200k")
      end
    end

    context "with empty catalog" do
      let(:registry_double) { instance_double(Aidp::Harness::CapabilityRegistry) }

      before do
        allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(registry_double)
        allow(registry_double).to receive(:load_catalog).and_return(true)
        allow(registry_double).to receive(:provider_names).and_return([])
      end

      it "displays empty catalog message" do
        expect(Aidp::CLI).to receive(:display_message).with("No models found in catalog", type: :info)
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_models_catalog)
      end
    end

    context "when catalog cannot be loaded" do
      let(:registry_double) { instance_double(Aidp::Harness::CapabilityRegistry) }

      before do
        allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(registry_double)
        allow(registry_double).to receive(:load_catalog).and_return(false)
      end

      it "displays error message" do
        expect(Aidp::CLI).to receive(:display_message).with(/No models catalog found/, type: :error)
        allow(Aidp::CLI).to receive(:display_message)

        Aidp::CLI.send(:run_providers_models_catalog)
      end
    end
  end
end
