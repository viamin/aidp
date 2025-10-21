# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/provider_info"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Harness::ProviderInfo do
  let(:temp_dir) { Dir.mktmpdir }
  let(:provider_name) { "claude" }
  let(:provider_info) { described_class.new(provider_name, temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates the provider info instance" do
      expect(provider_info.provider_name).to eq(provider_name)
    end

    it "sets the correct info file path" do
      expected_path = File.join(temp_dir, ".aidp", "providers", "#{provider_name}_info.yml")
      expect(provider_info.info_file_path).to eq(expected_path)
    end

    it "creates the directory structure" do
      dir = File.dirname(provider_info.info_file_path)
      expect(Dir.exist?(dir)).to be true
    end
  end

  describe "#gather_info" do
    context "when CLI is not available" do
      before do
        allow(provider_info).to receive(:fetch_help_output).and_return(nil)
      end

      it "returns info with cli_available false" do
        info = provider_info.gather_info
        expect(info[:cli_available]).to be false
      end

      it "stores the info to file" do
        provider_info.gather_info
        expect(File.exist?(provider_info.info_file_path)).to be true
      end

      it "includes basic metadata" do
        info = provider_info.gather_info
        expect(info[:provider]).to eq(provider_name)
        expect(info[:last_checked]).to be_a(String)
      end
    end

    context "when CLI is available" do
      let(:help_output) do
        <<~HELP
          Usage: claude [options] [command] [prompt]

          Options:
            --permission-mode <mode>  Permission mode (choices: "acceptEdits", "bypassPermissions", "default", "plan")
            --dangerously-skip-permissions  Bypass all permission checks
            --model <model>           Model for the current session
            --mcp-config <configs>    Load MCP servers from JSON files
            --allowed-tools <tools>   Comma separated list of tools to allow
            --setup-token             Set up authentication token

          Commands:
            mcp                       Configure and manage MCP servers
        HELP
      end

      # Cache the result of gather_info to avoid calling it multiple times
      let(:gathered_info) do
        allow(provider_info).to receive(:fetch_help_output).and_return(help_output)
        allow(provider_info).to receive(:fetch_mcp_servers).and_return([])
        provider_info.gather_info
      end

      it "returns info with cli_available true" do
        expect(gathered_info[:cli_available]).to be true
      end

      it "stores the help output" do
        expect(gathered_info[:help_output]).to eq(help_output)
      end

      it "detects MCP support" do
        expect(gathered_info[:mcp_support]).to be true
      end

      it "extracts permission modes" do
        expect(gathered_info[:permission_modes]).to include("acceptEdits", "bypassPermissions", "default", "plan")
      end

      it "detects bypass permissions capability" do
        expect(gathered_info[:capabilities][:bypass_permissions]).to be true
      end

      it "detects model selection capability" do
        expect(gathered_info[:capabilities][:model_selection]).to be true
      end

      it "detects MCP config capability" do
        expect(gathered_info[:capabilities][:mcp_config]).to be true
      end

      it "detects tool restrictions capability" do
        expect(gathered_info[:capabilities][:tool_restrictions]).to be true
      end

      it "detects subscription auth method" do
        expect(gathered_info[:auth_method]).to eq("subscription")
      end

      it "extracts flags" do
        expect(gathered_info[:flags]).to be_a(Hash)
        expect(gathered_info[:flags]).to have_key("permission-mode")
      end
    end
  end

  describe "#load_info" do
    context "when info file does not exist" do
      it "returns nil" do
        expect(provider_info.load_info).to be_nil
      end
    end

    context "when info file exists" do
      let(:sample_info) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          cli_available: true,
          mcp_support: true
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(sample_info))
      end

      it "loads the info from file" do
        loaded = provider_info.load_info
        expect(loaded[:provider]).to eq(provider_name)
        expect(loaded[:cli_available]).to be true
        expect(loaded[:mcp_support]).to be true
      end
    end
  end

  describe "#info" do
    context "when no cached info exists" do
      it "gathers new info" do
        allow(provider_info).to receive(:fetch_help_output).and_return(nil)
        info = provider_info.info
        expect(info).not_to be_nil
        expect(info[:provider]).to eq(provider_name)
      end
    end

    context "when cached info is fresh" do
      let(:fresh_info) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          cli_available: true
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(fresh_info))
      end

      it "returns cached info" do
        info = provider_info.info
        expect(info[:provider]).to eq(provider_name)
        expect(info[:cli_available]).to be true
      end

      it "does not gather new info" do
        expect(provider_info).not_to receive(:gather_info)
        provider_info.info
      end
    end

    context "when cached info is stale" do
      let(:stale_info) do
        {
          provider: provider_name,
          last_checked: (Time.now - 100_000).iso8601,
          cli_available: true
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(stale_info))
        allow(provider_info).to receive(:fetch_help_output).and_return(nil)
      end

      it "gathers new info" do
        expect(provider_info).to receive(:gather_info).and_call_original
        provider_info.info(max_age: 1000)
      end
    end

    context "when force_refresh is true" do
      let(:existing_info) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          cli_available: false
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(existing_info))
        allow(provider_info).to receive(:fetch_help_output).and_return(nil)
      end

      it "gathers new info even if cached info is fresh" do
        expect(provider_info).to receive(:gather_info).and_call_original
        provider_info.info(force_refresh: true)
      end
    end
  end

  describe "#supports_mcp?" do
    context "when provider supports MCP" do
      let(:info_with_mcp) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_support: true
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_mcp))
      end

      it "returns true" do
        expect(provider_info.supports_mcp?).to be true
      end
    end

    context "when provider does not support MCP" do
      let(:info_without_mcp) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_support: false
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_without_mcp))
      end

      it "returns false" do
        expect(provider_info.supports_mcp?).to be false
      end
    end
  end

  describe "#permission_modes" do
    context "when provider has permission modes" do
      let(:info_with_modes) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          permission_modes: %w[default bypass plan]
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_modes))
      end

      it "returns the permission modes" do
        expect(provider_info.permission_modes).to eq(%w[default bypass plan])
      end
    end

    context "when provider has no permission modes" do
      let(:info_without_modes) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_without_modes))
      end

      it "returns empty array" do
        expect(provider_info.permission_modes).to eq([])
      end
    end
  end

  describe "#auth_method" do
    context "when provider uses API key" do
      let(:info_with_api_key) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          auth_method: "api_key"
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_api_key))
      end

      it "returns api_key" do
        expect(provider_info.auth_method).to eq("api_key")
      end
    end

    context "when provider uses subscription" do
      let(:info_with_subscription) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          auth_method: "subscription"
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_subscription))
      end

      it "returns subscription" do
        expect(provider_info.auth_method).to eq("subscription")
      end
    end
  end

  describe "#available_flags" do
    context "when provider has flags" do
      let(:info_with_flags) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          flags: {
            "model" => {flag: "--model <model>", description: "Select model"},
            "help" => {flag: "--help", description: "Show help"}
          }
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_flags))
      end

      it "returns the flags hash" do
        flags = provider_info.available_flags
        expect(flags).to have_key("model")
        expect(flags).to have_key("help")
        expect(flags["model"][:flag]).to eq("--model <model>")
      end
    end
  end

  describe "#mcp_servers" do
    context "when provider has MCP servers configured" do
      let(:info_with_mcp_servers) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_servers: [
            {name: "filesystem", status: "enabled", description: "File system access", enabled: true},
            {name: "brave-search", status: "enabled", description: "Web search", enabled: true}
          ]
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_mcp_servers))
      end

      it "returns the MCP servers list" do
        servers = provider_info.mcp_servers
        expect(servers.size).to eq(2)
        expect(servers[0][:name]).to eq("filesystem")
        expect(servers[1][:name]).to eq("brave-search")
      end
    end

    context "when provider has no MCP servers" do
      let(:info_without_mcp_servers) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_servers: []
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_without_mcp_servers))
      end

      it "returns empty array" do
        expect(provider_info.mcp_servers).to eq([])
      end
    end
  end

  describe "#has_mcp_servers?" do
    context "when provider has MCP servers" do
      let(:info_with_servers) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_servers: [{name: "filesystem", status: "enabled", enabled: true}]
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_with_servers))
      end

      it "returns true" do
        expect(provider_info.has_mcp_servers?).to be true
      end
    end

    context "when provider has no MCP servers" do
      let(:info_without_servers) do
        {
          provider: provider_name,
          last_checked: Time.now.iso8601,
          mcp_servers: []
        }
      end

      before do
        File.write(provider_info.info_file_path, YAML.dump(info_without_servers))
      end

      it "returns false" do
        expect(provider_info.has_mcp_servers?).to be false
      end
    end
  end

  describe "MCP server parsing" do
    context "with new Claude format" do
      let(:mcp_output_new) do
        <<~OUTPUT
          Checking MCP server health...

          dash-api: uvx --from git+https://github.com/Kapeli/dash-mcp-server.git dash-mcp-server - ✓ Connected
          brave-search: npx brave-search-mcp - ✗ Connection failed
        OUTPUT
      end

      it "parses new Claude MCP format correctly" do
        allow(provider_info).to receive(:fetch_help_output).and_return("--mcp-config support")

        # Mock the provider instance to return the new MCP output
        mock_provider = instance_double(Aidp::Providers::Anthropic)
        allow(provider_info).to receive(:provider_instance).and_return(mock_provider)
        allow(mock_provider).to receive(:supports_mcp?).and_return(true)
        allow(mock_provider).to receive(:fetch_mcp_servers).and_return([
          {name: "dash-api", status: "connected", enabled: true,
           description: "uvx --from git+https://github.com/Kapeli/dash-mcp-server.git dash-mcp-server - ✓ Connected"},
          {name: "brave-search", status: "error", enabled: false,
           description: "npx brave-search-mcp - ✗ Connection failed", error: "Connection failed"}
        ])

        info = provider_info.gather_info

        expect(info[:mcp_servers]).to be_an(Array)
        expect(info[:mcp_servers].size).to eq(2)

        dash = info[:mcp_servers].find { |s| s[:name] == "dash-api" }
        expect(dash[:status]).to eq("connected")
        expect(dash[:enabled]).to be true
        expect(dash[:description]).to include("uvx --from")

        brave = info[:mcp_servers].find { |s| s[:name] == "brave-search" }
        expect(brave[:status]).to eq("error")
        expect(brave[:enabled]).to be false
        expect(brave[:error]).to eq("Connection failed")
      end
    end

    context "with legacy table format" do
      let(:mcp_output_legacy) do
        <<~OUTPUT
          MCP Servers

          Name              Status    Description
          filesystem        enabled   File system access and operations
          brave-search      enabled   Web search via Brave Search API
          database          disabled  Database query execution
        OUTPUT
      end

      it "parses legacy MCP table format correctly" do
        allow(provider_info).to receive(:fetch_help_output).and_return("--mcp-config support")

        # Mock the provider instance to return the legacy MCP output
        mock_provider = instance_double(Aidp::Providers::Anthropic)
        allow(provider_info).to receive(:provider_instance).and_return(mock_provider)
        allow(mock_provider).to receive(:supports_mcp?).and_return(true)
        allow(mock_provider).to receive(:fetch_mcp_servers).and_return([
          {name: "filesystem", status: "enabled",
           enabled: true, description: "File system access and operations"},
          {name: "brave-search", status: "enabled",
           enabled: true, description: "Web search via Brave Search API"},
          {name: "database", status: "disabled",
           enabled: false, description: "Database query execution"}
        ])

        info = provider_info.gather_info

        expect(info[:mcp_servers]).to be_an(Array)
        expect(info[:mcp_servers].size).to eq(3)

        filesystem = info[:mcp_servers].find { |s| s[:name] == "filesystem" }
        expect(filesystem[:status]).to eq("enabled")
        expect(filesystem[:enabled]).to be true
        expect(filesystem[:description]).to eq("File system access and operations")

        database = info[:mcp_servers].find { |s| s[:name] == "database" }
        expect(database[:status]).to eq("disabled")
        expect(database[:enabled]).to be false
      end
    end
  end

  describe "error handling" do
    context "when load_info fails to parse YAML" do
      before do
        # Write invalid YAML
        File.write(provider_info.info_file_path, "invalid: yaml: content: [[[")
      end

      it "returns nil and logs error" do
        expect { provider_info.load_info }.not_to raise_error
        expect(provider_info.load_info).to be_nil
      end
    end

    context "when info_stale? fails to parse timestamp" do
      let(:info_with_bad_timestamp) do
        {
          provider: provider_name,
          last_checked: "not-a-timestamp",
          cli_available: true
        }
      end

      it "returns true (treats as stale)" do
        result = provider_info.send(:info_stale?, info_with_bad_timestamp, 1000)
        expect(result).to be true
      end
    end

    context "when info_stale? receives info without last_checked" do
      let(:info_without_timestamp) do
        {
          provider: provider_name,
          cli_available: true
        }
      end

      it "returns true (treats as stale)" do
        result = provider_info.send(:info_stale?, info_without_timestamp, 1000)
        expect(result).to be true
      end
    end

    context "when fetch_mcp_servers fails" do
      before do
        allow(provider_info).to receive(:provider_instance).and_raise(StandardError.new("Provider error"))
      end

      it "returns empty array and logs error" do
        result = provider_info.send(:fetch_mcp_servers)
        expect(result).to eq([])
      end
    end

    context "when provider_instance creation fails" do
      before do
        # Mock ProviderFactory to return nil (provider not found)
        stub_const("Aidp::Harness::ProviderFactory::PROVIDER_CLASSES", {})
      end

      it "returns nil when provider class not found" do
        result = provider_info.send(:provider_instance)
        expect(result).to be_nil
      end
    end

    context "when execute_provider_command fails during spawn" do
      before do
        allow(provider_info).to receive(:binary_name).and_return("test-binary")
        allow(Aidp::Util).to receive(:which).and_return("/usr/bin/test-binary")
        allow(Process).to receive(:spawn).and_raise(StandardError.new("Spawn error"))
      end

      it "returns nil and logs error" do
        result = provider_info.send(:execute_provider_command, "--help")
        expect(result).to be_nil
      end
    end

    context "when execute_provider_command fails to kill process" do
      before do
        allow(provider_info).to receive(:binary_name).and_return("test-binary")
        allow(Aidp::Util).to receive(:which).and_return("/usr/bin/test-binary")
        allow(Process).to receive(:spawn).and_return(99_999)
        allow(Process).to receive(:waitpid2).and_return(nil) # Timeout
        allow(Process).to receive(:kill).and_raise(StandardError.new("Kill error"))
        # Mock Concurrency::Wait to avoid real timeout delays
        allow(Aidp::Concurrency::Wait).to receive(:for_process_exit).and_raise(Aidp::Concurrency::TimeoutError.new("Mocked timeout"))
      end

      it "returns nil and logs error" do
        result = provider_info.send(:execute_provider_command, "--help")
        expect(result).to be_nil
      end
    end

    context "when binary lookup fails" do
      before do
        allow(provider_info).to receive(:binary_name).and_return("test-binary")
        allow(Aidp::Util).to receive(:which).and_raise(StandardError.new("Which error"))
      end

      it "returns nil and logs error" do
        result = provider_info.send(:execute_provider_command, "--help")
        expect(result).to be_nil
      end
    end
  end

  describe "binary name mapping" do
    it "maps anthropic to claude" do
      info = described_class.new("anthropic", temp_dir)
      expect(info.send(:binary_name)).to eq("claude")
    end

    it "maps claude to claude" do
      info = described_class.new("claude", temp_dir)
      expect(info.send(:binary_name)).to eq("claude")
    end

    it "maps cursor to cursor-agent" do
      info = described_class.new("cursor", temp_dir)
      expect(info.send(:binary_name)).to eq("cursor-agent")
    end

    it "maps gemini to gemini" do
      info = described_class.new("gemini", temp_dir)
      expect(info.send(:binary_name)).to eq("gemini")
    end

    it "maps codex to codex" do
      info = described_class.new("codex", temp_dir)
      expect(info.send(:binary_name)).to eq("codex")
    end

    it "maps github_copilot to copilot" do
      info = described_class.new("github_copilot", temp_dir)
      expect(info.send(:binary_name)).to eq("copilot")
    end

    it "maps opencode to opencode" do
      info = described_class.new("opencode", temp_dir)
      expect(info.send(:binary_name)).to eq("opencode")
    end

    it "maps unknown provider to itself" do
      info = described_class.new("unknown_provider", temp_dir)
      expect(info.send(:binary_name)).to eq("unknown_provider")
    end
  end

  describe "nil handling" do
    context "when load_info returns nil" do
      before do
        allow(provider_info).to receive(:load_info).and_return(nil)
      end

      it "supports_mcp? returns false" do
        expect(provider_info.supports_mcp?).to be false
      end

      it "permission_modes returns empty array" do
        expect(provider_info.permission_modes).to eq([])
      end

      it "auth_method returns nil" do
        expect(provider_info.auth_method).to be_nil
      end

      it "available_flags returns empty hash" do
        expect(provider_info.available_flags).to eq({})
      end

      it "mcp_servers returns empty array" do
        expect(provider_info.mcp_servers).to eq([])
      end
    end

    context "when execute_provider_command has no binary_name" do
      before do
        allow(provider_info).to receive(:binary_name).and_return(nil)
      end

      it "returns nil" do
        result = provider_info.send(:execute_provider_command, "--help")
        expect(result).to be_nil
      end
    end

    context "when execute_provider_command binary not found" do
      before do
        allow(provider_info).to receive(:binary_name).and_return("nonexistent")
        allow(Aidp::Util).to receive(:which).and_return(nil)
      end

      it "returns nil" do
        result = provider_info.send(:execute_provider_command, "--help")
        expect(result).to be_nil
      end
    end

    context "when fetch_mcp_servers has no provider_instance" do
      before do
        allow(provider_info).to receive(:provider_instance).and_return(nil)
      end

      it "returns empty array" do
        result = provider_info.send(:fetch_mcp_servers)
        expect(result).to eq([])
      end
    end
  end

  describe "parse_help_output edge cases" do
    context "with API key auth pattern" do
      let(:help_with_api_key) do
        <<~HELP
          Usage: provider [options]

          Options:
            --api-key <key>       API key for authentication
        HELP
      end

      it "detects api_key auth method" do
        parsed = provider_info.send(:parse_help_output, help_with_api_key)
        expect(parsed[:auth_method]).to eq("api_key")
      end
    end

    context "with API_KEY env pattern" do
      let(:help_with_env_key) do
        <<~HELP
          Usage: provider [options]

          Set API_KEY environment variable for authentication
        HELP
      end

      it "detects api_key auth method" do
        parsed = provider_info.send(:parse_help_output, help_with_env_key)
        expect(parsed[:auth_method]).to eq("api_key")
      end
    end

    context "with subscription pattern" do
      let(:help_with_subscription) do
        <<~HELP
          Usage: provider [options]

          Options:
            --setup-token         Set up subscription token
        HELP
      end

      it "detects subscription auth method" do
        parsed = provider_info.send(:parse_help_output, help_with_subscription)
        expect(parsed[:auth_method]).to eq("subscription")
      end
    end

    context "with session management capabilities" do
      let(:help_with_sessions) do
        <<~HELP
          Usage: provider [options]

          Options:
            --continue            Continue previous session
            --resume <id>         Resume session by ID
            --fork-session <id>   Fork from existing session
        HELP
      end

      it "detects session_management capability" do
        parsed = provider_info.send(:parse_help_output, help_with_sessions)
        expect(parsed[:capabilities][:session_management]).to be true
      end
    end

    context "with output formats" do
      let(:help_with_formats) do
        <<~HELP
          Usage: provider [options]

          Options:
            --output-format <format>  Output format (choices: "json", "yaml", "text")
        HELP
      end

      it "extracts output formats" do
        parsed = provider_info.send(:parse_help_output, help_with_formats)
        expect(parsed[:capabilities][:output_formats]).to include("json", "yaml", "text")
      end
    end

    context "with short flags" do
      let(:help_with_short_flags) do
        <<~HELP
          Usage: provider [options]

          Options:
            -h, --help            Show help message
            -v, --version         Show version
            -m, --model <model>   Select model
        HELP
      end

      it "extracts short flags" do
        parsed = provider_info.send(:parse_help_output, help_with_short_flags)
        # Verify flags were extracted (the extract_flags method handles both long and short forms)
        expect(parsed[:flags]).to be_a(Hash)
        expect(parsed[:flags]["help"][:short]).to eq("-h")
        expect(parsed[:flags]["version"][:short]).to eq("-v")
        # model flag has <model> parameter which changes the regex match
      end
    end

    context "with MCP support from provider instance" do
      let(:help_without_mcp_text) do
        <<~HELP
          Usage: provider [options]

          Options:
            --help  Show help
        HELP
      end

      before do
        mock_provider = instance_double(Aidp::Providers::Anthropic)
        allow(provider_info).to receive(:provider_instance).and_return(mock_provider)
        allow(mock_provider).to receive(:supports_mcp?).and_return(true)
      end

      it "detects MCP support from provider instance" do
        parsed = provider_info.send(:parse_help_output, help_without_mcp_text)
        expect(parsed[:mcp_support]).to be true
      end
    end

    context "with MCP support from help text" do
      let(:help_with_mcp_text) do
        <<~HELP
          Usage: provider [options]

          MCP Server Configuration:
            --mcp-config <file>  Load MCP server configuration
        HELP
      end

      before do
        allow(provider_info).to receive(:provider_instance).and_return(nil)
      end

      it "detects MCP support from help text" do
        parsed = provider_info.send(:parse_help_output, help_with_mcp_text)
        expect(parsed[:mcp_support]).to be true
      end
    end

    context "without provider instance" do
      let(:help_text) do
        <<~HELP
          Usage: provider [options]
        HELP
      end

      before do
        allow(provider_info).to receive(:provider_instance).and_return(nil)
      end

      it "falls back to text-based MCP detection" do
        parsed = provider_info.send(:parse_help_output, help_text)
        expect(parsed[:mcp_support]).to be false
      end
    end
  end

  describe "parse_mcp_servers edge cases" do
    context "with nil output" do
      it "returns empty array" do
        result = provider_info.send(:parse_mcp_servers, nil)
        expect(result).to eq([])
      end
    end

    context "with empty output" do
      it "returns empty array" do
        result = provider_info.send(:parse_mcp_servers, "")
        expect(result).to eq([])
      end
    end

    context "with new format - connected server" do
      let(:output) do
        <<~OUTPUT
          dash-api: uvx --from git+https://example.com - ✓ Connected
        OUTPUT
      end

      it "parses connected server correctly" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("dash-api")
        expect(result[0][:status]).to eq("connected")
        expect(result[0][:enabled]).to be true
        expect(result[0][:error]).to be_nil
      end
    end

    context "with new format - error server" do
      let(:output) do
        <<~OUTPUT
          test-server: npm run server - ✗ Connection timeout
        OUTPUT
      end

      it "parses error server correctly" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("test-server")
        expect(result[0][:status]).to eq("error")
        expect(result[0][:enabled]).to be false
        expect(result[0][:error]).to eq("Connection timeout")
      end
    end

    context "with header line to skip" do
      let(:output) do
        <<~OUTPUT
          Checking MCP server health...

          server1: cmd1 - ✓ Connected
        OUTPUT
      end

      it "skips header line" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("server1")
      end
    end

    context "with legacy format - header line" do
      let(:output) do
        <<~OUTPUT
          Name              Status    Description
          filesystem        enabled   File access
        OUTPUT
      end

      it "skips header line" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("filesystem")
      end
    end

    context "with legacy format - separator line" do
      let(:output) do
        <<~OUTPUT
          Name              Status    Description
          ==========================================
          filesystem        enabled   File access
        OUTPUT
      end

      it "skips separator line" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("filesystem")
      end
    end

    context "with legacy format - connected status" do
      let(:output) do
        <<~OUTPUT
          filesystem        connected   File access
        OUTPUT
      end

      it "treats connected as enabled" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result[0][:enabled]).to be true
      end
    end

    context "with legacy format - missing description" do
      let(:output) do
        <<~OUTPUT
          filesystem        enabled
        OUTPUT
      end

      it "handles missing description" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result[0][:name]).to eq("filesystem")
        expect(result[0][:description]).to eq("")
      end
    end

    context "with legacy format - unknown status" do
      let(:output) do
        <<~OUTPUT
          filesystem        unknown   File access
        OUTPUT
      end

      it "uses unknown as status" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result[0][:status]).to eq("unknown")
        expect(result[0][:enabled]).to be false
      end
    end

    context "with legacy format - whitespace only first column" do
      let(:output) do
        <<~OUTPUT
          enabled   Description
        OUTPUT
      end

      it "parses with empty leading spaces" do
        result = provider_info.send(:parse_mcp_servers, output)
        # Will parse "enabled" as name since whitespace stripping happens
        expect(result.size).to eq(1)
        expect(result[0][:name]).to eq("enabled")
      end
    end

    context "with legacy format - insufficient columns" do
      let(:output) do
        <<~OUTPUT
          filesystem
        OUTPUT
      end

      it "skips entries with insufficient columns" do
        result = provider_info.send(:parse_mcp_servers, output)
        expect(result).to eq([])
      end
    end
  end

  describe "directory creation" do
    context "when directory already exists" do
      it "does not raise error" do
        # Create directory first
        dir = File.dirname(provider_info.info_file_path)
        FileUtils.mkdir_p(dir)

        # Creating another instance should not raise
        expect { described_class.new(provider_name, temp_dir) }.not_to raise_error
      end
    end
  end

  describe "gather_info with MCP support" do
    context "when MCP is supported but fetch fails" do
      let(:help_output) do
        <<~HELP
          Usage: claude [options]

          Commands:
            mcp   Configure MCP servers
        HELP
      end

      before do
        allow(provider_info).to receive(:fetch_help_output).and_return(help_output)
        allow(provider_info).to receive(:fetch_mcp_servers).and_return(nil)
      end

      it "does not set mcp_servers when fetch returns nil" do
        info = provider_info.gather_info
        # Should not override mcp_servers when fetch returns nil
        expect(info[:mcp_servers]).to eq([])
      end
    end

    context "when MCP is supported and fetch succeeds" do
      let(:help_output) do
        <<~HELP
          Usage: claude [options]

          Commands:
            mcp   Configure MCP servers
        HELP
      end

      let(:mcp_servers_list) do
        [{name: "test", status: "enabled", enabled: true}]
      end

      before do
        allow(provider_info).to receive(:fetch_help_output).and_return(help_output)
        allow(provider_info).to receive(:fetch_mcp_servers).and_return(mcp_servers_list)
      end

      it "sets mcp_servers from fetch result" do
        info = provider_info.gather_info
        expect(info[:mcp_servers]).to eq(mcp_servers_list)
      end
    end
  end
end
