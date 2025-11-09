# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Anthropic do
  let(:provider) { described_class.new }

  before do
    # Mock availability check
    allow(described_class).to receive(:available?).and_return(true)
    allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")
  end

  describe "#available?" do
    it "returns true when claude CLI is available" do
      expect(provider.available?).to be true
    end

    it "returns false when claude CLI is not available" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(provider.available?).to be false
    end
  end

  describe "#name" do
    it "returns the correct name" do
      expect(provider.name).to eq("anthropic")
    end
  end

  describe "#display_name" do
    it "returns the correct display name" do
      expect(provider.display_name).to eq("Anthropic Claude CLI")
    end
  end

  describe "#supports_mcp?" do
    it "returns true" do
      expect(provider.supports_mcp?).to be true
    end
  end

  describe "#send" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Test response", err: "") }
    let(:failed_result) { double("result", exit_status: 1, out: "", err: "Error message") }

    before do
      allow(provider).to receive(:debug_execute_command).and_return(successful_result)
      allow(provider).to receive(:debug_command)
      allow(provider).to receive(:debug_provider)
      allow(provider).to receive(:debug_log)
      allow(provider).to receive(:debug_error)
      allow(provider).to receive(:display_message)
      # Shorten timeout for faster loop exit
      allow(provider).to receive(:calculate_timeout).and_return(1)
      # Provide spinner double with required interface so background loop safely updates it
      spinner_double = double("Spinner", auto_spin: nil, success: nil, error: nil, update: nil, stop: nil)
      allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
      # Use original state transitions (do not stub mark_completed/mark_failed) to ensure loop breaks
    end

    include_context "provider_thread_cleanup", "providers/anthropic.rb"

    context "when streaming is disabled" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV.delete("DEBUG")
      end

      it "uses text output format" do
        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--output-format=text"],
          input: prompt,
          timeout: 1,
          streaming: false
        )
      end

      it "returns the output directly" do
        result = provider.send_message(prompt: prompt)
        expect(result).to eq("Test response")
      end
    end

    context "when streaming is enabled via AIDP_STREAMING" do
      before do
        ENV["AIDP_STREAMING"] = "1"
        ENV.delete("DEBUG")
      end

      after do
        ENV.delete("AIDP_STREAMING")
      end

      it "uses stream-json output format" do
        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--verbose", "--output-format=stream-json", "--include-partial-messages"],
          input: prompt,
          timeout: 1,
          streaming: true
        )
      end

      it "shows true streaming message" do
        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:display_message).with(
          "📺 True streaming enabled - real-time chunks from Claude API",
          type: :info
        )
      end

      it "parses stream-json output" do
        allow(successful_result).to receive(:out).and_return('{"type":"content_block_delta","delta":{"text":"Hello"}}')
        allow(provider).to receive(:parse_stream_json_output).and_return("Hello")

        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:parse_stream_json_output).with('{"type":"content_block_delta","delta":{"text":"Hello"}}')
      end
    end

    context "when streaming is enabled via DEBUG" do
      before do
        ENV.delete("AIDP_STREAMING")
        ENV["DEBUG"] = "1"
      end

      after do
        ENV.delete("DEBUG")
      end

      it "uses stream-json output format" do
        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: ["--print", "--verbose", "--output-format=stream-json", "--include-partial-messages"],
          input: prompt,
          timeout: 1,
          streaming: true
        )
      end
    end

    context "when harness config requests full permissions" do
      let(:config_double) { double("configuration", should_use_full_permissions?: true) }
      let(:harness_context) { double("harness_context", config: config_double) }

      before do
        provider.instance_variable_set(:@harness_context, harness_context)
      end

      after do
        provider.instance_variable_set(:@harness_context, nil)
      end

      it "includes the skip permissions flag" do
        provider.send_message(prompt: prompt)

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          hash_including(args: array_including("--dangerously-skip-permissions"))
        )
      end
    end

    context "when command fails" do
      before do
        allow(provider).to receive(:debug_execute_command).and_return(failed_result)
      end

      it "raises an error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(RuntimeError, "claude failed with exit code 1: Error message")
      end

      it "logs the error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error

        expect(provider).to have_received(:debug_error).at_least(:once)
      end
    end

    context "when authentication fails" do
      let(:auth_error_result) { double("result", exit_status: 1, out: '{"error":{"type":"authentication_error"}}', err: "") }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(auth_error_result)
      end

      it "raises authentication error message" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/Authentication error from Claude CLI/)
      end

      it "logs the authentication error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error

        expect(provider).to have_received(:debug_error).at_least(:once)
      end
    end

    context "when oauth token expired" do
      let(:oauth_error_result) { double("result", exit_status: 1, out: "", err: "OAuth token has expired") }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(oauth_error_result)
      end

      it "raises oauth token expired error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/token expired or invalid/)
      end
    end

    context "when claude CLI is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "raises error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error("claude CLI not available")
      end
    end

    context "when debug_execute_command raises error" do
      before do
        allow(provider).to receive(:debug_execute_command).and_raise(StandardError.new("Command failed"))
      end

      it "logs and re-raises the error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(StandardError, "Command failed")

        expect(provider).to have_received(:debug_error).with(
          instance_of(StandardError),
          hash_including(provider: "claude", prompt_length: prompt.length)
        )
      end
    end
  end

  describe "#parse_stream_json_output" do
    context "with valid stream-json output" do
      it "extracts content from content_block_delta" do
        output = '{"type":"content_block_delta","delta":{"text":"Hello"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" world"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from message structure" do
        output = '{"message":{"content":[{"text":"Hello world"}]}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "extracts content from array content structure" do
        output = '{"content":[{"text":"Hello"},{"text":" world"}]}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end

      it "handles string content in message" do
        output = '{"message":{"content":"Hello world"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Hello world")
      end
    end

    context "with invalid JSON" do
      it "treats invalid JSON lines as plain text" do
        output = "Invalid JSON line\n" + '{"type":"content_block_delta","delta":{"text":"Valid"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Invalid JSON lineValid")
      end

      it "handles completely invalid JSON gracefully" do
        output = "Not JSON at all"

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Not JSON at all")
      end
    end

    context "with empty or nil input" do
      it "handles nil input" do
        result = provider.__send__(:parse_stream_json_output, nil)
        expect(result).to be_nil
      end

      it "handles empty input" do
        result = provider.__send__(:parse_stream_json_output, "")
        expect(result).to eq("")
      end
    end

    context "with mixed content" do
      it "combines multiple content blocks" do
        output = '{"type":"content_block_delta","delta":{"text":"First"}}' + "\n" \
          '{"type":"content_block_delta","delta":{"text":" second"}}' + "\n" \
          '{"message":{"content":"Third"}}'

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("First secondThird")
      end
    end

    context "when parsing fails" do
      it "returns original output on parsing error" do
        output = "Some output"
        allow(provider).to receive(:debug_log)

        # Temporarily stub JSON.parse to raise an error for this test
        original_parse = JSON.method(:parse)
        allow(JSON).to receive(:parse) do |*args|
          if args.first.include?("Some output")
            raise StandardError.new("Parse error")
          else
            original_parse.call(*args)
          end
        end

        result = provider.__send__(:parse_stream_json_output, output)
        expect(result).to eq("Some output")
      end
    end
  end

  describe "#calculate_timeout" do
    before do
      allow(provider).to receive(:display_message)
    end

    after do
      ENV.delete("AIDP_QUICK_MODE")
      ENV.delete("AIDP_ANTHROPIC_TIMEOUT")
      ENV.delete("AIDP_CURRENT_STEP")
    end

    context "when AIDP_QUICK_MODE is set" do
      it "returns quick mode timeout" do
        ENV["AIDP_QUICK_MODE"] = "1"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_QUICK_MODE)
        expect(provider).to have_received(:display_message).with(/Quick mode enabled/, type: :highlight)
      end
    end

    context "when AIDP_ANTHROPIC_TIMEOUT is set" do
      it "returns custom timeout" do
        ENV["AIDP_ANTHROPIC_TIMEOUT"] = "600"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(600)
      end
    end

    context "when adaptive timeout is available" do
      it "returns adaptive timeout for REPOSITORY_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "REPOSITORY_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REPOSITORY_ANALYSIS)
        expect(provider).to have_received(:display_message).with(/adaptive timeout/, type: :info)
      end

      it "returns adaptive timeout for ARCHITECTURE_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "ARCHITECTURE_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_ARCHITECTURE_ANALYSIS)
      end

      it "returns adaptive timeout for TEST_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_TEST_ANALYSIS)
      end

      it "returns adaptive timeout for FUNCTIONALITY_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "FUNCTIONALITY_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_FUNCTIONALITY_ANALYSIS)
      end

      it "returns adaptive timeout for DOCUMENTATION_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "DOCUMENTATION_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DOCUMENTATION_ANALYSIS)
      end

      it "returns adaptive timeout for STATIC_ANALYSIS" do
        ENV["AIDP_CURRENT_STEP"] = "STATIC_ANALYSIS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_STATIC_ANALYSIS)
      end

      it "returns adaptive timeout for REFACTORING_RECOMMENDATIONS" do
        ENV["AIDP_CURRENT_STEP"] = "REFACTORING_RECOMMENDATIONS"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_REFACTORING_RECOMMENDATIONS)
      end
    end

    context "when no special conditions" do
      it "returns default timeout" do
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DEFAULT)
        expect(provider).to have_received(:display_message).with(/default timeout/, type: :info)
      end
    end

    context "with unknown step type" do
      it "returns default timeout" do
        ENV["AIDP_CURRENT_STEP"] = "UNKNOWN_STEP"
        timeout = provider.__send__(:calculate_timeout)
        expect(timeout).to eq(Aidp::Providers::Base::TIMEOUT_DEFAULT)
      end
    end
  end

  describe "#adaptive_timeout" do
    after do
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "caches the result" do
      ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"
      first_call = provider.__send__(:adaptive_timeout)
      second_call = provider.__send__(:adaptive_timeout)
      expect(first_call).to eq(second_call)
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
    let(:mcp_list_result) { double("result", exit_status: 0, out: mcp_output) }
    let(:mcp_output) do
      "dash-api: uvx --from git+https://example.com - ✓ Connected\nfilesystem: /path/to/mcp - ✗ Connection failed"
    end

    before do
      allow(provider).to receive(:debug_execute_command).and_return(mcp_list_result)
      allow(provider).to receive(:debug_log)
    end

    context "when claude CLI is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "returns empty array" do
        result = provider.fetch_mcp_servers
        expect(result).to eq([])
      end
    end

    context "when command succeeds" do
      it "executes claude mcp list command" do
        provider.fetch_mcp_servers
        expect(provider).to have_received(:debug_execute_command).with("claude", args: ["mcp", "list"], timeout: 5)
      end

      it "parses the output" do
        result = provider.fetch_mcp_servers
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result[0][:name]).to eq("dash-api")
        expect(result[0][:status]).to eq("connected")
        expect(result[1][:name]).to eq("filesystem")
        expect(result[1][:status]).to eq("error")
      end
    end

    context "when command fails" do
      before do
        allow(mcp_list_result).to receive(:exit_status).and_return(1)
      end

      it "returns empty array" do
        result = provider.fetch_mcp_servers
        expect(result).to eq([])
      end
    end

    context "when command raises error" do
      before do
        allow(provider).to receive(:debug_execute_command).and_raise(StandardError.new("Command error"))
      end

      it "returns empty array" do
        result = provider.fetch_mcp_servers
        expect(result).to eq([])
      end

      it "logs the error" do
        provider.fetch_mcp_servers
        expect(provider).to have_received(:debug_log).with(/Failed to fetch MCP servers/, level: :debug)
      end
    end
  end

  describe "#parse_claude_mcp_output" do
    context "with Claude format output" do
      it "parses connected server" do
        output = "dash-api: uvx --from git+https://example.com - ✓ Connected"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("dash-api")
        expect(servers[0][:status]).to eq("connected")
        expect(servers[0][:enabled]).to be true
        expect(servers[0][:description]).to eq("uvx --from git+https://example.com")
        expect(servers[0][:error]).to be_nil
        expect(servers[0][:source]).to eq("claude_cli")
      end

      it "parses errored server" do
        output = "filesystem: /path/to/mcp - ✗ Connection failed"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("filesystem")
        expect(servers[0][:status]).to eq("error")
        expect(servers[0][:enabled]).to be false
        expect(servers[0][:error]).to eq("Connection failed")
      end

      it "parses multiple servers" do
        output = "server1: cmd1 - ✓ Connected\nserver2: cmd2 - ✗ Failed"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(2)
      end
    end

    context "with legacy table format" do
      it "parses table rows" do
        output = "filesystem        connected   File access\napi-server        enabled     API integration"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(2)
        expect(servers[0][:name]).to eq("filesystem")
        expect(servers[0][:status]).to eq("connected")
        expect(servers[0][:enabled]).to be true
        expect(servers[0][:description]).to eq("File access")
      end

      it "skips header rows" do
        output = "Name              Status      Description\nfilesystem        connected   File access"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("filesystem")
      end

      it "skips separator rows" do
        output = "----------------\nfilesystem        connected   File access"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
      end

      it "skips rows with less than 2 parts" do
        output = "onlyname\nfilesystem        connected   File access"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("filesystem")
      end

      it "handles enabled status" do
        output = "server        enabled   Description"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers[0][:enabled]).to be true
      end

      it "handles rows without description" do
        output = "filesystem        connected"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers[0][:description]).to eq("")
      end
    end

    context "with health check messages" do
      it "filters out health check messages" do
        output = "checking mcp server health...\nserver: cmd - ✓ Connected"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(1)
        expect(servers[0][:name]).to eq("server")
      end
    end

    context "with empty or nil input" do
      it "returns empty array for nil" do
        servers = provider.__send__(:parse_claude_mcp_output, nil)
        expect(servers).to eq([])
      end

      it "returns empty array for empty string" do
        servers = provider.__send__(:parse_claude_mcp_output, "")
        expect(servers).to eq([])
      end

      it "skips empty lines" do
        output = "server: cmd - ✓ Connected\n\n\nserver2: cmd2 - ✓ Connected"
        servers = provider.__send__(:parse_claude_mcp_output, output)

        expect(servers.size).to eq(2)
      end
    end
  end
end
