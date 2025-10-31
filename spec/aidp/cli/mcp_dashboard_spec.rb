# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/mcp_dashboard"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::CLI::McpDashboard do
  let(:temp_dir) { Dir.mktmpdir }

  let(:mock_config) do
    double(
      "Configuration",
      providers: {"anthropic" => {"api_key" => "test-key", "model" => "claude-3-5-sonnet-20241022"}},
      provider_config: {"api_key" => "test-key", "model" => "claude-3-5-sonnet-20241022"},
      mcp_servers: [],
      root_dir: temp_dir,
      provider_names: ["anthropic"]
    )
  end

  let(:dashboard) do
    allow(Aidp::Harness::Configuration).to receive(:new).and_return(mock_config)
    described_class.new(temp_dir)
  end

  after { FileUtils.rm_rf(temp_dir) }

  before do
    # Create minimal config structure
    FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
    config_file = File.join(temp_dir, ".aidp", "config.yml")
    config_content = <<~YAML
      providers:
        anthropic:
          api_key: test-key
          model: claude-3-5-sonnet-20241022
    YAML
    File.write(config_file, config_content)

    # Mock ProviderInfo to avoid file system dependencies
    mock_provider_info = instance_double(Aidp::Harness::ProviderInfo,
      info: {mcp_support: true, mcp_servers: []})
    allow(Aidp::Harness::ProviderInfo).to receive(:new).and_return(mock_provider_info)
  end

  describe "#initialize" do
    it "accepts a root directory" do
      expect(dashboard.instance_variable_get(:@root_dir)).to eq(temp_dir)
    end

    it "defaults to current directory" do
      # Stub configuration for default directory to avoid CI dependence on real config
      allow(Aidp::Harness::Configuration).to receive(:new).and_return(mock_config)
      dashboard = described_class.new
      expect(dashboard.instance_variable_get(:@root_dir)).to eq(Dir.pwd)
    end

    it "initializes configuration" do
      expect(dashboard.instance_variable_get(:@configuration)).not_to be_nil
    end
  end

  describe "#display_dashboard" do
    it "displays dashboard without errors" do
      expect { dashboard.display_dashboard }.not_to raise_error
    end

    it "accepts no_color option" do
      expect { dashboard.display_dashboard(no_color: true) }.not_to raise_error
    end

    it "handles no MCP servers gracefully" do
      output = capture_output { dashboard.display_dashboard }
      expect(output).to include("MCP Server Dashboard")
    end
  end

  describe "#check_task_eligibility" do
    let(:required_servers) { ["filesystem", "github"] }

    it "returns eligibility information" do
      result = dashboard.check_task_eligibility(required_servers)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:required_servers)
      expect(result).to have_key(:eligible_providers)
      expect(result).to have_key(:total_providers)
    end

    it "returns correct required servers" do
      result = dashboard.check_task_eligibility(required_servers)
      expect(result[:required_servers]).to eq(required_servers)
    end

    it "returns array of eligible providers" do
      result = dashboard.check_task_eligibility(required_servers)
      expect(result[:eligible_providers]).to be_an(Array)
    end
  end

  describe "#display_task_eligibility" do
    let(:required_servers) { ["filesystem"] }

    it "displays eligibility check without errors" do
      expect { dashboard.display_task_eligibility(required_servers) }.not_to raise_error
    end

    it "shows required servers" do
      output = capture_output { dashboard.display_task_eligibility(required_servers) }
      expect(output).to include("filesystem")
    end

    it "shows eligible providers when servers are available" do
      # Mock provider info with enabled MCP servers
      mock_provider_info = instance_double(Aidp::Harness::ProviderInfo,
        info: {mcp_support: true, mcp_servers: [{name: "filesystem", enabled: true}]})
      allow(Aidp::Harness::ProviderInfo).to receive(:new).and_return(mock_provider_info)

      output = capture_output { dashboard.display_task_eligibility(["filesystem"]) }
      expect(output).to include("Eligible Providers")
    end

    it "shows warning when no providers are eligible" do
      output = capture_output { dashboard.display_task_eligibility(required_servers) }
      expect(output).to include("No providers have all required MCP servers")
    end
  end

  describe "private methods" do
    describe "#build_server_matrix" do
      it "includes providers with MCP support" do
        result = dashboard.send(:build_server_matrix)
        expect(result).to have_key(:servers)
        expect(result).to have_key(:provider_servers)
        expect(result).to have_key(:providers)
      end

      it "filters providers without MCP support" do
        mock_provider_info = instance_double(Aidp::Harness::ProviderInfo,
          info: {mcp_support: false})
        allow(Aidp::Harness::ProviderInfo).to receive(:new).and_return(mock_provider_info)

        result = dashboard.send(:build_server_matrix)
        expect(result[:providers]).to be_empty
      end
    end

    describe "#format_server_status" do
      it "formats enabled servers with color" do
        # Force non-TTY to ensure deterministic plain symbol output regardless of local terminal
        allow($stdout).to receive(:tty?).and_return(false)
        result = dashboard.send(:format_server_status, {enabled: true}, false)
        expect(result).to eq("✓")
      end

      it "formats disabled servers without color" do
        result = dashboard.send(:format_server_status, {enabled: false}, true)
        expect(result).to eq("✗")
      end

      it "uses ANSI colors for TTY" do
        allow($stdout).to receive(:tty?).and_return(true)
        result = dashboard.send(:format_server_status, {enabled: true}, false)
        expect(result).to include("\e[32m")
      end
    end

    describe "#normalize_provider_name" do
      it "normalizes anthropic to claude" do
        result = dashboard.send(:normalize_provider_name, "anthropic")
        expect(result).to eq("claude")
      end

      it "keeps other provider names unchanged" do
        result = dashboard.send(:normalize_provider_name, "openai")
        expect(result).to eq("openai")
      end
    end

    describe "#display_server_table" do
      it "handles empty providers gracefully" do
        matrix = {providers: [], servers: {}, provider_servers: {}}
        expect { dashboard.send(:display_server_table, matrix, true) }.not_to raise_error
      end

      it "displays table with servers" do
        matrix = {
          providers: ["anthropic"],
          servers: {"filesystem" => {providers: {"anthropic" => {name: "filesystem", enabled: true}}}},
          provider_servers: {"anthropic" => [{name: "filesystem", enabled: true}]}
        }
        expect { dashboard.send(:display_server_table, matrix, false) }.not_to raise_error
      end
    end

    describe "#display_eligibility_warnings" do
      it "shows warnings for partially configured servers" do
        matrix = {
          providers: ["anthropic", "openai"],
          servers: {
            "filesystem" => {
              providers: {"anthropic" => {name: "filesystem", enabled: true}}
            }
          },
          provider_servers: {}
        }
        expect { dashboard.send(:display_eligibility_warnings, matrix) }.not_to raise_error
      end

      it "skips warnings when all providers have servers" do
        matrix = {
          providers: ["anthropic"],
          servers: {
            "filesystem" => {
              providers: {"anthropic" => {name: "filesystem", enabled: true}}
            }
          },
          provider_servers: {}
        }
        expect { dashboard.send(:display_eligibility_warnings, matrix) }.not_to raise_error
      end
    end
  end

  def capture_output(&block)
    original_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
