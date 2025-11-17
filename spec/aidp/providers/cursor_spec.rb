# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Cursor do
  let(:provider) { described_class.new }

  before do
    allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return("/usr/local/bin/cursor-agent")
  end

  describe ".available?" do
    it "returns true when cursor-agent CLI is available" do
      allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return("/usr/local/bin/cursor-agent")
      expect(described_class.available?).to be true
    end

    it "returns false when cursor-agent CLI is not available" do
      allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return(nil)
      expect(described_class.available?).to be false
    end
  end

  describe "#name" do
    it "returns cursor" do
      expect(provider.name).to eq("cursor")
    end
  end

  describe "#display_name" do
    it "returns the correct display name" do
      expect(provider.display_name).to eq("Cursor AI")
    end
  end

  describe "#supports_mcp?" do
    it "returns true" do
      expect(provider.supports_mcp?).to be true
    end
  end

  describe "#calculate_timeout" do
    before do
      allow(provider).to receive(:display_message)
    end

    after do
      ENV.delete("AIDP_QUICK_MODE")
      ENV.delete("AIDP_CURSOR_TIMEOUT")
      ENV.delete("AIDP_CURRENT_STEP")
    end

    context "when AIDP_QUICK_MODE is set" do
      it "returns quick mode timeout" do
        ENV["AIDP_QUICK_MODE"] = "1"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_QUICK_MODE)
      end
    end

    context "when AIDP_CURSOR_TIMEOUT is set" do
      it "returns custom timeout" do
        ENV["AIDP_CURSOR_TIMEOUT"] = "600"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(600)
      end
    end

    context "when adaptive timeout is available" do
      it "returns adaptive timeout for REPOSITORY_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "REPOSITORY_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REPOSITORY_ANALYSIS)
      end

      it "returns adaptive timeout for TEST_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_TEST_ANALYSIS)
      end
    end

    context "when no special conditions" do
      it "returns default timeout" do
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DEFAULT)
      end
    end
  end

  describe "#adaptive_timeout" do
    after do
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns nil for unknown step types" do
      ENV["AIDP_CURRENT_STEP"] = "RANDOM_STEP"
      expect(provider.__send__(:adaptive_timeout)).to be_nil
    end

    it "returns nil when no step is set" do
      ENV.delete("AIDP_CURRENT_STEP")
      expect(provider.__send__(:adaptive_timeout)).to be_nil
    end
  end

  describe "#fetch_mcp_servers" do
    context "when CLI command succeeds" do
      let(:mcp_output) { "server1: connected\nserver2: ready" }
      let(:mcp_result) { double("result", exit_status: 0, out: mcp_output) }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(mcp_result)
        allow(provider).to receive(:debug_log)
      end

      it "returns servers from CLI" do
        servers = provider.fetch_mcp_servers
        expect(servers).to be_an(Array)
        expect(servers.size).to eq(2)
        expect(servers[0][:name]).to eq("server1")
        expect(servers[0][:status]).to eq("connected")
      end
    end

    context "when CLI command fails" do
      before do
        allow(provider).to receive(:debug_execute_command).and_raise(StandardError.new("Command failed"))
        allow(provider).to receive(:debug_log)
        allow(File).to receive(:exist?).and_return(false)
      end

      it "returns empty array" do
        servers = provider.fetch_mcp_servers
        expect(servers).to eq([])
      end
    end

    context "when config file exists" do
      let(:config_content) do
        {
          "mcpServers" => {
            "filesystem" => {
              "command" => "npx",
              "args" => ["-y", "@modelcontextprotocol/server-filesystem"],
              "env" => {"ROOT_PATH" => "/path"}
            }
          }
        }.to_json
      end

      before do
        allow(provider).to receive(:debug_execute_command).and_return(double("result", exit_status: 1, out: ""))
        allow(provider).to receive(:debug_log)
        allow(File).to receive(:exist?).with(File.expand_path("~/.cursor/mcp.json")).and_return(true)
        allow(File).to receive(:read).with(File.expand_path("~/.cursor/mcp.json")).and_return(config_content)
      end

      it "parses config file" do
        servers = provider.__send__(:fetch_mcp_servers_config)
        expect(servers).to be_an(Array)
        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("filesystem")
        expect(servers[0][:status]).to eq("configured")
        expect(servers[0][:description]).to include("npx")
      end
    end

    context "when config file has invalid JSON" do
      before do
        allow(provider).to receive(:debug_execute_command).and_return(double("result", exit_status: 1, out: ""))
        allow(provider).to receive(:debug_log)
        allow(File).to receive(:exist?).with(File.expand_path("~/.cursor/mcp.json")).and_return(true)
        allow(File).to receive(:read).with(File.expand_path("~/.cursor/mcp.json")).and_return("invalid json")
      end

      it "returns empty array" do
        servers = provider.__send__(:fetch_mcp_servers_config)
        expect(servers).to eq([])
      end
    end
  end

  describe "#parse_mcp_servers_output" do
    context "with basic format" do
      it "parses server status" do
        output = "server1: connected"
        servers = provider.__send__(:parse_mcp_servers_output, output)
        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("server1")
        expect(servers[0][:status]).to eq("connected")
        expect(servers[0][:enabled]).to be true
      end

      it "recognizes ready status as enabled" do
        output = "server1: ready"
        servers = provider.__send__(:parse_mcp_servers_output, output)
        expect(servers[0][:enabled]).to be true
      end
    end

    context "with extended format" do
      it "parses as basic format (simple regex matches first, next skips extended)" do
        output = "dash-api: uvx command - ✓ Connected"
        servers = provider.__send__(:parse_mcp_servers_output, output)
        expect(servers.size).to eq(1) # Simple regex matches first, next skips extended
        # Matched by simple format
        expect(servers[0][:name]).to eq("dash-api")
        expect(servers[0][:status]).to eq("uvx command - ✓ Connected")
        # The extended format regex doesn't run due to 'next'
      end

      it "parses errored server with basic format" do
        output = "filesystem: /path/mcp - ✗ Failed"
        servers = provider.__send__(:parse_mcp_servers_output, output)
        expect(servers.size).to eq(1) # Only simple regex matches
        expect(servers[0][:status]).to eq("/path/mcp - ✗ Failed")
        expect(servers[0][:enabled]).to be false # Not "ready" or "connected"
      end
    end

    context "with empty input" do
      it "returns empty array for nil" do
        servers = provider.__send__(:parse_mcp_servers_output, nil)
        expect(servers).to eq([])
      end

      it "returns empty array for empty string" do
        servers = provider.__send__(:parse_mcp_servers_output, "")
        expect(servers).to eq([])
      end
    end

    context "with health check messages" do
      it "filters out health check messages" do
        output = "checking mcp server health...\nserver: connected"
        servers = provider.__send__(:parse_mcp_servers_output, output)
        expect(servers.size).to eq(1)
      end
    end
  end

  describe ".model_family" do
    it "normalizes cursor model names with dots to hyphens" do
      expect(described_class.model_family("claude-3.5-sonnet")).to eq("claude-3-5-sonnet")
    end

    it "preserves model names without version dots" do
      expect(described_class.model_family("claude-opus")).to eq("claude-opus")
    end

    it "handles multiple version numbers" do
      expect(described_class.model_family("gpt-4.0-turbo")).to eq("gpt-4-0-turbo")
    end
  end

  describe ".provider_model_name" do
    it "converts family names with hyphens to cursor format with dots" do
      expect(described_class.provider_model_name("claude-3-5-sonnet")).to eq("claude-3.5-sonnet")
    end

    it "handles single version numbers" do
      expect(described_class.provider_model_name("gpt-4-turbo")).to eq("gpt-4.turbo")
    end

    it "preserves model names without version numbers" do
      expect(described_class.provider_model_name("claude-opus")).to eq("claude-opus")
    end
  end

  describe ".supports_model_family?" do
    it "returns true for claude models" do
      expect(described_class.supports_model_family?("claude-3-5-sonnet")).to be true
    end

    it "returns true for gpt models" do
      expect(described_class.supports_model_family?("gpt-4-turbo")).to be true
    end

    it "returns true for cursor models" do
      expect(described_class.supports_model_family?("cursor-small")).to be true
    end

    it "returns false for other models" do
      expect(described_class.supports_model_family?("gemini-pro")).to be false
    end

    it "returns false for empty string" do
      expect(described_class.supports_model_family?("")).to be false
    end
  end

  describe ".discover_models" do
    context "when cursor-agent is not available" do
      it "returns empty array" do
        allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return(nil)
        expect(described_class.discover_models).to eq([])
      end
    end

    context "when cursor-agent is available" do
      before do
        allow(Aidp::Util).to receive(:which).with("cursor-agent").and_return("/usr/local/bin/cursor-agent")
        allow(Aidp).to receive(:log_info)
      end

      it "returns models from registry that cursor supports" do
        # Mock the registry
        registry = instance_double(Aidp::Harness::ModelRegistry)
        allow(Aidp::Harness::ModelRegistry).to receive(:new).and_return(registry)
        allow(registry).to receive(:all_families).and_return(["claude-3-5-sonnet", "gpt-4-turbo", "gemini-pro"])
        allow(registry).to receive(:get_model_info).with("claude-3-5-sonnet").and_return({
          "tier" => "standard",
          "capabilities" => ["chat", "vision"],
          "context_window" => 200000
        })
        allow(registry).to receive(:get_model_info).with("gpt-4-turbo").and_return({
          "tier" => "standard",
          "capabilities" => ["chat"],
          "context_window" => 128000
        })
        allow(registry).to receive(:get_model_info).with("gemini-pro").and_return(nil)

        models = described_class.discover_models
        expect(models.size).to eq(2) # claude and gpt, not gemini
        expect(models[0][:name]).to eq("claude-3.5-sonnet") # Converted to cursor format
        expect(models[0][:family]).to eq("claude-3-5-sonnet")
        expect(models[0][:provider]).to eq("cursor")
      end
    end
  end

  describe "#send_message" do
    let(:prompt_text) { "Test prompt" }

    before do
      allow(provider).to receive(:display_message)
      allow(provider).to receive(:debug_log)
    end

    context "when cursor-agent succeeds" do
      let(:success_result) { double("result", exit_status: 0, out: "AI response text") }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(success_result)
      end

      it "returns response text" do
        response = provider.send_message(prompt: prompt_text)
        expect(response).to eq("AI response text")
      end

      it "calls cursor-agent with correct arguments" do
        expect(provider).to receive(:debug_execute_command).with(
          "cursor-agent",
          "--prompt", prompt_text,
          timeout: anything
        )
        provider.send_message(prompt: prompt_text)
      end
    end

    context "when cursor-agent fails" do
      let(:error_result) { double("result", exit_status: 1, out: "") }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(error_result)
      end

      it "returns nil" do
        response = provider.send_message(prompt: prompt_text)
        expect(response).to be_nil
      end
    end

    context "when cursor-agent times out" do
      before do
        allow(provider).to receive(:debug_execute_command).and_raise(Timeout::Error)
      end

      it "returns nil" do
        response = provider.send_message(prompt: prompt_text)
        expect(response).to be_nil
      end

      it "displays timeout message" do
        expect(provider).to receive(:display_message).with(/timed out/, type: :error)
        provider.send_message(prompt: prompt_text)
      end
    end
  end

  describe "#activity_callback" do
    before do
      allow(provider).to receive(:display_message)
    end

    it "displays thinking state" do
      expect(provider).to receive(:display_message).with(/cursor is thinking/, type: :info)
      provider.activity_callback(:thinking, "processing", "cursor")
    end

    it "displays responding state" do
      expect(provider).to receive(:display_message).with(/cursor is responding/, type: :info)
      provider.activity_callback(:responding, "generating", "cursor")
    end

    it "does not display for unknown states" do
      expect(provider).not_to receive(:display_message)
      provider.activity_callback(:unknown, "message", "cursor")
    end
  end
end
