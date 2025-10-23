# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"
require "aidp/harness/provider_info"
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
      it "displays usage information" do
        expect(Aidp::CLI).to receive(:display_message).with("Usage: aidp providers info <provider_name>", type: :info)
        expect(Aidp::CLI).to receive(:display_message).with("Example: aidp providers info claude", type: :info)

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
end
