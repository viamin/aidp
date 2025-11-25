# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Anthropic do
  let(:provider) { described_class.new }

  describe "#available?" do
    it "returns true when claude CLI is available" do
      allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")
      expect(described_class.available?).to be true
      expect(provider.available?).to be true
    end

    it "returns false when claude CLI is not available" do
      allow(Aidp::Util).to receive(:which).with("claude").and_return(nil)
      expect(described_class.available?).to be false
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

  describe "#configure" do
    let(:mock_registry) { instance_double(Aidp::Harness::RubyLLMRegistry) }

    before do
      allow(Aidp::Harness::RubyLLMRegistry).to receive(:new).and_return(mock_registry)
    end

    it "resolves model family to versioned model using registry" do
      allow(mock_registry).to receive(:resolve_model).with("claude-3-5-haiku", provider: "anthropic").and_return("claude-3-5-haiku-20241022")

      provider.configure(model: "claude-3-5-haiku")
      expect(provider.model).to eq("claude-3-5-haiku-20241022")
    end

    it "preserves already versioned model names" do
      allow(mock_registry).to receive(:resolve_model).with("claude-3-opus-20240229", provider: "anthropic").and_return("claude-3-opus-20240229")

      provider.configure(model: "claude-3-opus-20240229")
      expect(provider.model).to eq("claude-3-opus-20240229")
    end

    it "falls back to using model name as-is when registry returns nil" do
      allow(mock_registry).to receive(:resolve_model).with("unknown-model", provider: "anthropic").and_return(nil)
      expect(Aidp).to receive(:log_warn).with("anthropic", "Model not found in registry, using as-is", model: "unknown-model")

      provider.configure(model: "unknown-model")
      expect(provider.model).to eq("unknown-model")
    end

    it "handles registry errors gracefully" do
      allow(mock_registry).to receive(:resolve_model).and_raise(StandardError, "Registry error")
      expect(Aidp).to receive(:log_error).with("anthropic", "Registry lookup failed, using model name as-is",
        model: "claude-3-5-haiku",
        error: "Registry error")

      provider.configure(model: "claude-3-5-haiku")
      expect(provider.model).to eq("claude-3-5-haiku")
    end

    it "does not set model when not provided" do
      provider.configure({})
      expect(provider.model).to be_nil
    end
  end

  describe "#send" do
    let(:prompt) { "Test prompt" }
    let(:successful_result) { double("result", exit_status: 0, out: "Test response", err: "") }
    let(:failed_result) { double("result", exit_status: 1, out: "", err: "Error message") }

    before do
      # Mock CLI availability for provider instantiation
      allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")

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

    it "uses text output format" do
      provider.send_message(prompt: prompt)

      # In devcontainer, expect --dangerously-skip-permissions flag
      expected_args = ["--print", "--output-format=text"]
      expected_args << "--dangerously-skip-permissions" if ENV["REMOTE_CONTAINERS"] == "true" || ENV["CODESPACES"] == "true"

      expect(provider).to have_received(:debug_execute_command).with(
        "claude",
        args: expected_args,
        input: prompt,
        timeout: 1
      )
    end

    it "returns the output directly" do
      result = provider.send_message(prompt: prompt)
      expect(result).to eq("Test response")
    end

    context "when model is configured" do
      let(:mock_registry) { instance_double(Aidp::Harness::RubyLLMRegistry) }

      before do
        allow(Aidp::Harness::RubyLLMRegistry).to receive(:new).and_return(mock_registry)
        allow(mock_registry).to receive(:resolve_model).with("claude-3-5-haiku", provider: "anthropic").and_return("claude-3-5-haiku-20241022")
        provider.configure(model: "claude-3-5-haiku")
      end

      it "includes the model in command arguments" do
        provider.send_message(prompt: prompt)

        # In devcontainer, expect --dangerously-skip-permissions flag
        expected_args = ["--print", "--output-format=text", "--model", "claude-3-5-haiku-20241022"]
        expected_args << "--dangerously-skip-permissions" if ENV["REMOTE_CONTAINERS"] == "true" || ENV["CODESPACES"] == "true"

        expect(provider).to have_received(:debug_execute_command).with(
          "claude",
          args: expected_args,
          input: prompt,
          timeout: 1
        )
      end
    end

    context "when harness config requests full permissions" do
      let(:config_double) { double("configuration", should_use_full_permissions?: true) }
      let(:harness_context) { double("harness_context", config: config_double) }

      before do
        provider.set_harness_context(harness_context)
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
        }.to raise_error(RuntimeError)

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
        }.to raise_error(RuntimeError)

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

    context "when rate limit is reached" do
      let(:rate_limit_result) { double("result", exit_status: 1, out: "Session limit reached ∙ resets 4am", err: "") }
      let(:harness_context) { double("harness_context") }
      let(:provider_manager) { double("provider_manager") }

      before do
        allow(provider).to receive(:debug_execute_command).and_return(rate_limit_result)
        allow(harness_context).to receive(:provider_manager).and_return(provider_manager)
        allow(harness_context).to receive(:config).and_return(nil)
        allow(provider_manager).to receive(:mark_rate_limited)
        provider.set_harness_context(harness_context)
      end

      it "raises rate limit error" do
        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/Rate limit reached/)
      end

      it "logs rate limit detection" do
        expect(Aidp).to receive(:log_debug).with("anthropic_provider", "rate_limit_detected", anything).at_least(:once)
        allow(Aidp).to receive(:log_debug) # Allow other log_debug calls

        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/Rate limit reached/)
      end

      it "notifies provider manager about rate limit" do
        expect(provider_manager).to receive(:mark_rate_limited).with("anthropic", kind_of(Time))

        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/Rate limit reached/)
      end

      it "extracts reset time from message" do
        # With "resets 4am" message, should calculate next 4am
        now = Time.new(2025, 1, 20, 14, 0, 0) # 2pm today
        allow(Time).to receive(:now).and_return(now)

        expected_reset = Time.new(2025, 1, 21, 4, 0, 0) # 4am tomorrow

        expect(provider_manager).to receive(:mark_rate_limited).with("anthropic", expected_reset)

        expect {
          provider.send_message(prompt: prompt)
        }.to raise_error(/Rate limit reached/)
      end

      context "when reset time is in the future today" do
        let(:rate_limit_result) { double("result", exit_status: 1, out: "Session limit reached ∙ resets 11:30pm", err: "") }

        it "extracts reset time for today" do
          now = Time.new(2025, 1, 20, 10, 0, 0) # 10am today
          allow(Time).to receive(:now).and_return(now)

          expected_reset = Time.new(2025, 1, 20, 23, 30, 0) # 11:30pm today

          expect(provider_manager).to receive(:mark_rate_limited).with("anthropic", expected_reset)

          expect {
            provider.send_message(prompt: prompt)
          }.to raise_error(/Rate limit reached/)
        end
      end

      context "when message is in stderr" do
        let(:rate_limit_result) { double("result", exit_status: 1, out: "", err: "Session limit reached ∙ resets 4am") }

        it "detects rate limit from stderr" do
          expect {
            provider.send_message(prompt: prompt)
          }.to raise_error(/Rate limit reached/)
        end
      end

      context "when harness context is not available" do
        before do
          provider.instance_variable_set(:@harness_context, nil)
        end

        it "still raises rate limit error without notifying" do
          expect {
            provider.send_message(prompt: prompt)
          }.to raise_error(/Rate limit reached/)
        end
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
      # Mock CLI availability for provider instantiation
      allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")

      allow(provider).to receive(:debug_execute_command).and_return(mcp_list_result)
      allow(provider).to receive(:debug_log)
    end

    context "when claude CLI is not available" do
      before do
        allow(Aidp::Util).to receive(:which).with("claude").and_return(nil)
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

  describe ".model_family" do
    it "strips date suffix from versioned model names" do
      expect(described_class.model_family("claude-3-5-sonnet-20241022")).to eq("claude-3-5-sonnet")
    end

    it "handles different date versions" do
      expect(described_class.model_family("claude-3-5-sonnet-20250101")).to eq("claude-3-5-sonnet")
    end

    it "handles Haiku models" do
      expect(described_class.model_family("claude-3-5-haiku-20241022")).to eq("claude-3-5-haiku")
    end

    it "handles Opus models" do
      expect(described_class.model_family("claude-3-opus-20240229")).to eq("claude-3-opus")
    end

    it "returns unmodified name if no date suffix" do
      expect(described_class.model_family("claude-3-5-sonnet")).to eq("claude-3-5-sonnet")
    end

    it "handles Claude 3 Sonnet" do
      expect(described_class.model_family("claude-3-sonnet-20240229")).to eq("claude-3-sonnet")
    end

    it "handles Claude 3 Haiku" do
      expect(described_class.model_family("claude-3-haiku-20240307")).to eq("claude-3-haiku")
    end
  end

  describe ".provider_model_name" do
    it "returns family name as-is for flexibility" do
      result = described_class.provider_model_name("claude-3-5-sonnet")
      expect(result).to eq("claude-3-5-sonnet")
    end

    it "returns family name for Haiku" do
      result = described_class.provider_model_name("claude-3-5-haiku")
      expect(result).to eq("claude-3-5-haiku")
    end

    it "returns family name for Opus" do
      result = described_class.provider_model_name("claude-3-opus")
      expect(result).to eq("claude-3-opus")
    end

    it "returns provided name for any model" do
      result = described_class.provider_model_name("unknown-model")
      expect(result).to eq("unknown-model")
    end
  end

  describe ".supports_model_family?" do
    it "returns true for supported Claude 3.5 Sonnet" do
      expect(described_class.supports_model_family?("claude-3-5-sonnet")).to be true
    end

    it "returns true for supported Claude 3.5 Haiku" do
      expect(described_class.supports_model_family?("claude-3-5-haiku")).to be true
    end

    it "returns true for supported Claude 3 Opus" do
      expect(described_class.supports_model_family?("claude-3-opus")).to be true
    end

    it "returns true for versioned Claude models" do
      expect(described_class.supports_model_family?("claude-3-5-sonnet-20241022")).to be true
      expect(described_class.supports_model_family?("claude-3-opus-20240229")).to be true
    end

    it "returns false for unsupported model" do
      expect(described_class.supports_model_family?("gpt-4")).to be false
    end

    it "returns false for non-existent model" do
      expect(described_class.supports_model_family?("unknown-model")).to be false
    end
  end
end
