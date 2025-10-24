# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"
require "aidp/harness/provider_info"

RSpec.describe "Aidp::CLI providers info edge cases" do
  # Inject a stubbed ProviderInfo to control returned info structure
  let(:provider_name) { "claude" }
  let(:info_object) { instance_double(Aidp::Harness::ProviderInfo) }

  before do
    allow(Aidp::Harness::ProviderInfo).to receive(:new).with(provider_name, anything).and_return(info_object)
  end

  def run_info(args)
    Aidp::CLI.run(["providers", "info", *args])
  end

  context "when capabilities include false values" do
    let(:info_hash) do
      {
        last_checked: Time.now.utc.iso8601,
        cli_available: true,
        auth_method: "api_key",
        mcp_support: true,
        mcp_servers: [],
        permission_modes: ["read-only", "read-write"],
        capabilities: {
          code_navigation: true,
          test_generation: false,   # should be filtered out
          security_audit: true,
          inline_refactor: false    # should be filtered out
        },
        flags: {
          fast_mode: {flag: "--fast", description: "Enable fast responses"}
        }
      }
    end

    before do
      allow(info_object).to receive(:info).with(force_refresh: false).and_return(info_hash)
    end

    it "only displays capabilities with truthy values" do
      expect { run_info([provider_name]) }.to output(/Capabilities:/).to_stdout
      expect { run_info([provider_name]) }.to output(/code navigation/i).to_stdout
      expect { run_info([provider_name]) }.to output(/security audit/i).to_stdout
      expect { run_info([provider_name]) }.not_to output(/test generation/i).to_stdout
      expect { run_info([provider_name]) }.not_to output(/inline refactor/i).to_stdout
    end
  end

  context "permission modes variations" do
    let(:info_hash) do
      {
        last_checked: Time.now.utc.iso8601,
        cli_available: false,
        auth_method: "oauth",
        mcp_support: false,
        mcp_servers: nil,
        permission_modes: ["read-only", "privileged"],
        capabilities: {},
        flags: {}
      }
    end

    before do
      allow(info_object).to receive(:info).with(force_refresh: false).and_return(info_hash)
    end

    it "lists all provided permission modes" do
      expect { run_info([provider_name]) }.to output(/Permission Modes:/).to_stdout
      expect { run_info([provider_name]) }.to output(/read-only/).to_stdout
      expect { run_info([provider_name]) }.to output(/privileged/).to_stdout
    end
  end

  context "when info returns nil" do
    before do
      allow(info_object).to receive(:info).with(force_refresh: false).and_return(nil)
    end

    it "shows error for missing provider info" do
      expect { run_info([provider_name]) }.to output(/No information available/).to_stdout
    end
  end

  context "with --refresh flag" do
    let(:refreshed_hash) do
      {
        last_checked: Time.now.utc.iso8601,
        cli_available: true,
        auth_method: nil,
        mcp_support: false,
        mcp_servers: [],
        permission_modes: [],
        capabilities: {tracing: true},
        flags: {}
      }
    end

    before do
      allow(info_object).to receive(:info).with(force_refresh: true).and_return(refreshed_hash)
    end

    it "passes force_refresh to ProviderInfo" do
      expect(info_object).to receive(:info).with(force_refresh: true)
      run_info([provider_name, "--refresh"])
    end
  end
end
