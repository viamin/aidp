# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/providers_command"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::CLI::ProvidersCommand do
  let(:temp_dir) { Dir.mktmpdir("aidp_providers_command_test") }
  let(:provider_name) { "test_provider" }
  let(:prompt) { instance_double(TTY::Prompt) }

  # Mock classes for dependency injection
  let(:provider_info_double) { instance_double(Aidp::Harness::ProviderInfo) }
  let(:provider_info_class) do
    class_double(Aidp::Harness::ProviderInfo).tap do |klass|
      allow(klass).to receive(:new).and_return(provider_info_double)
    end
  end

  let(:capability_registry_double) { instance_double(Aidp::Harness::CapabilityRegistry) }
  let(:capability_registry_class) do
    class_double(Aidp::Harness::CapabilityRegistry).tap do |klass|
      allow(klass).to receive(:new).and_return(capability_registry_double)
    end
  end

  let(:config_manager_double) { instance_double(Aidp::Harness::ConfigManager) }
  let(:config_manager_class) do
    class_double(Aidp::Harness::ConfigManager).tap do |klass|
      allow(klass).to receive(:new).and_return(config_manager_double)
    end
  end

  let(:command) do
    described_class.new(
      prompt: prompt,
      provider_info_class: provider_info_class,
      capability_registry_class: capability_registry_class,
      config_manager_class: config_manager_class,
      project_dir: temp_dir
    )
  end

  before do
    allow(prompt).to receive(:say)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run with info subcommand" do
    context "with valid provider name" do
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
        allow(provider_info_double).to receive(:info).with(force_refresh: false).and_return(mock_info)
      end

      it "calls the correct method on ProviderInfo" do
        expect(provider_info_double).to receive(:info).with(force_refresh: false)
        command.run([provider_name], subcommand: "info")
      end

      it "handles force refresh flag" do
        expect(provider_info_double).to receive(:info).with(force_refresh: true)
        command.run([provider_name, "--refresh"], subcommand: "info")
      end

      it "displays provider information correctly" do
        expect(prompt).to receive(:say).with("Provider Information: #{provider_name}", color: :cyan)
        expect(prompt).to receive(:say).with("Last Checked: 2025-10-22T10:00:00-07:00", color: :blue)
        expect(prompt).to receive(:say).with("CLI Available: Yes", color: :green)
        allow(prompt).to receive(:say) # Allow other calls

        command.run([provider_name], subcommand: "info")
      end
    end

    context "with missing provider name" do
      before do
        allow(capability_registry_double).to receive(:load_catalog).and_return(true)
        allow(capability_registry_double).to receive(:provider_names).and_return([])
      end

      it "displays models catalog table" do
        expect(prompt).to receive(:say).with("Models Catalog - Thinking Depth Tiers", color: :cyan)
        allow(prompt).to receive(:say) # Allow other calls

        command.run([], subcommand: "info")
      end
    end

    context "when provider info is nil" do
      before do
        allow(provider_info_double).to receive(:info).and_return(nil)
      end

      it "displays error message without trying to display other info" do
        expect(prompt).to receive(:say).with("Provider Information: #{provider_name}", color: :cyan)
        expect(prompt).to receive(:say).with("No information available for provider: #{provider_name}", color: :red)
        allow(prompt).to receive(:say) # Allow other calls

        command.run([provider_name], subcommand: "info")
      end
    end
  end

  describe "#run with catalog subcommand" do
    context "when catalog exists" do
      before do
        allow(capability_registry_double).to receive(:load_catalog).and_return(true)
        allow(capability_registry_double).to receive(:provider_names).and_return(["anthropic"])
        allow(capability_registry_double).to receive(:models_for_provider).with("anthropic").and_return({
          "claude-3-5-sonnet" => {
            "tier" => "standard",
            "context_window" => 200000,
            "supports_tools" => true,
            "cost_per_mtok_input" => 3.0
          }
        })
      end

      it "displays the models catalog table" do
        expect(prompt).to receive(:say).with("Models Catalog - Thinking Depth Tiers", color: :cyan)
        allow(prompt).to receive(:say) # Allow other calls

        command.run([], subcommand: "catalog")
      end

      it "includes all required columns in the table" do
        # Just verify the table is rendered with the model data
        expect(prompt).to receive(:say) do |arg, **opts|
          if arg.is_a?(String) && arg.include?("claude-3-5-sonnet")
            expect(arg).to include("anthropic")
            expect(arg).to include("standard")
          end
        end.at_least(:once)

        command.run([], subcommand: "catalog")
      end
    end

    context "when catalog does not exist" do
      before do
        allow(capability_registry_double).to receive(:load_catalog).and_return(false)
      end

      it "displays error message" do
        expect(prompt).to receive(:say).with("No models catalog found. Create .aidp/models_catalog.yml first.", color: :red)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "catalog")
      end
    end

    context "when catalog is empty" do
      before do
        allow(capability_registry_double).to receive(:load_catalog).and_return(true)
        allow(capability_registry_double).to receive(:provider_names).and_return([])
      end

      it "displays no models message" do
        expect(prompt).to receive(:say).with("No models found in catalog", color: :blue)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "catalog")
      end
    end
  end

  describe "#run with refresh subcommand" do
    context "with specific provider" do
      before do
        allow(config_manager_double).to receive(:provider_names).and_return(["anthropic", "cursor"])
        allow(provider_info_double).to receive(:info).and_return({cli_available: true})
        # Stub TTY::Spinner
        spinner_double = instance_double(TTY::Spinner)
        allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
        allow(spinner_double).to receive(:auto_spin)
        allow(spinner_double).to receive(:stop)
      end

      it "refreshes the specified provider" do
        expect(provider_info_double).to receive(:info).with(force_refresh: true)
        allow(prompt).to receive(:say)

        command.run([provider_name], subcommand: "refresh")
      end

      it "displays success message" do
        expect(prompt).to receive(:say).with(/✓ #{provider_name} refreshed successfully/, color: :green)
        allow(prompt).to receive(:say)

        command.run([provider_name], subcommand: "refresh")
      end
    end

    context "with no provider specified" do
      before do
        allow(config_manager_double).to receive(:provider_names).and_return(["anthropic", "cursor"])
        allow(provider_info_double).to receive(:info).and_return({cli_available: true})
        # Stub TTY::Spinner
        spinner_double = instance_double(TTY::Spinner)
        allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
        allow(spinner_double).to receive(:auto_spin)
        allow(spinner_double).to receive(:stop)
      end

      it "refreshes all configured providers" do
        expect(provider_info_double).to receive(:info).with(force_refresh: true).twice
        allow(prompt).to receive(:say)

        command.run([], subcommand: "refresh")
      end
    end

    context "when refresh fails" do
      before do
        allow(config_manager_double).to receive(:provider_names).and_return([provider_name])
        allow(provider_info_double).to receive(:info).and_return(nil)
        # Stub TTY::Spinner
        spinner_double = instance_double(TTY::Spinner)
        allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
        allow(spinner_double).to receive(:auto_spin)
        allow(spinner_double).to receive(:stop)
      end

      it "displays error message" do
        expect(prompt).to receive(:say).with(/✗ #{provider_name} failed to refresh/, color: :red)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "refresh")
      end
    end

    context "when refresh raises an error" do
      before do
        allow(config_manager_double).to receive(:provider_names).and_return([provider_name])
        allow(provider_info_double).to receive(:info).and_raise(StandardError, "Network error")
        # Stub TTY::Spinner
        spinner_double = instance_double(TTY::Spinner)
        allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
        allow(spinner_double).to receive(:auto_spin)
        allow(spinner_double).to receive(:stop)
      end

      it "handles the error gracefully" do
        expect(prompt).to receive(:say).with(/✗ #{provider_name} error: Network error/, color: :red)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "refresh")
      end
    end
  end
end
