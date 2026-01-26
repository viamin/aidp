# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# System spec: Full workflow from CLI to completion
# Tests the golden path without mocking core application logic
# Only stubs external provider responses
RSpec.describe "AIDP Golden Path System Test", type: :system do
  let(:temp_project_dir) { Dir.mktmpdir("aidp_system_test") }

  let(:system_test_config) do
    {
      harness: {enabled: true, default_provider: "cursor", fallback_providers: ["claude"]},
      providers: {
        cursor: {type: "passthrough", models: ["cursor-default"]},
        claude: {type: "usage_based", api_key: "test_key_claude", models: ["claude-3-5-sonnet-20241022"]}
      }
    }
  end

  let(:system_test_config_manager) do
    instance_double(Aidp::Harness::ConfigManager, config: system_test_config)
  end

  let(:golden_path_cursor_provider) do
    instance_double(AgentHarness::Providers::Cursor).tap do |provider|
      call_sequence = [
        '{"complete": false, "questions": ["What is the main goal of this project?"], "reasoning": "need initial context"}',
        '{"complete": true, "questions": [], "reasoning": "have enough information"}',
        '{"steps": ["00_PRD", "16_IMPLEMENTATION"], "reasoning": "basic implementation workflow"}'
      ]
      call_index = 0
      allow(provider).to receive(:send_message) do |prompt:, session: nil|
        response = call_sequence[call_index] || call_sequence.last
        call_index += 1
        response
      end
    end
  end

  let(:golden_path_claude_provider) do
    instance_double(AgentHarness::Providers::Anthropic).tap do |provider|
      allow(provider).to receive(:send_message).and_return(
        '{"complete": true, "questions": [], "reasoning": "fallback response"}'
      )
    end
  end

  let(:system_test_provider_manager) do
    instance_double(Aidp::Harness::ProviderManager).tap do |manager|
      allow(manager).to receive(:current_provider).and_return("cursor", "claude")
      allow(manager).to receive(:configured_providers).and_return(["cursor", "claude"])
      allow(manager).to receive(:switch_provider_for_error).and_return("claude")
    end
  end

  let(:system_test_provider_factory) do
    instance_double(Aidp::Harness::ProviderFactory).tap do |factory|
      allow(factory).to receive(:create_provider).with("cursor", prompt: anything).and_return(golden_path_cursor_provider)
      allow(factory).to receive(:create_provider).with("claude", prompt: anything).and_return(golden_path_claude_provider)
    end
  end

  before do
    # Create necessary directory structure
    FileUtils.mkdir_p(File.join(temp_project_dir, "docs"))
    FileUtils.mkdir_p(File.join(temp_project_dir, ".aidp"))

    # Write minimal configuration with two providers
    config_content = <<~YAML
      harness:
        enabled: true
        default_provider: cursor
        fallback_providers:
          - claude
      providers:
        cursor:
          type: passthrough
          models:
            - cursor-default
        claude:
          type: usage_based
          api_key: test_key_claude
          models:
            - claude-3-5-sonnet-20241022
    YAML

    File.write(File.join(temp_project_dir, ".aidp", "aidp.yml"), config_content)

    allow(Aidp::Harness::ProviderFactory).to receive(:new).with(system_test_config_manager).and_return(system_test_provider_factory)
  end

  after do
    FileUtils.rm_rf(temp_project_dir)
  end

  it "completes a full planning workflow without errors" do
    # Use TestPrompt for deterministic answers
    test_prompt = TestPrompt.new(responses: {
      ask: ["Build a simple REST API", "Basic CRUD operations"], # Answers to planning questions
      yes?: true # Confirm plan is ready
    })

    # Create agent and run workflow with dependency injection
    agent = Aidp::Workflows::GuidedAgent.new(
      temp_project_dir,
      prompt: test_prompt,
      verbose: false,
      config_manager: system_test_config_manager,
      provider_manager: system_test_provider_manager
    )
    workflow = nil

    # Execute workflow
    expect { workflow = agent.select_workflow }.not_to raise_error

    # Verify workflow structure
    expect(workflow).to be_a(Hash)
    expect(workflow[:mode]).to eq(:execute)
    expect(workflow[:workflow_type]).to eq(:plan_and_execute)
    expect(workflow[:steps]).to be_an(Array)
    expect(workflow[:steps]).to include("00_PRD")
    expect(workflow[:user_input]).to be_a(Hash)
    expect(workflow[:user_input][:plan]).to be_a(Hash)

    # Verify PRD was generated
    prd_path = File.join(temp_project_dir, "docs", "prd.md")
    expect(File.exist?(prd_path)).to be true
    prd_content = File.read(prd_path)
    expect(prd_content).to include("# Product Requirements Document")
    expect(prd_content).to include("Build a simple REST API")
  end

  it "handles verbose mode with detailed output" do
    test_prompt = TestPrompt.new(responses: {
      ask: "Build a CLI tool",
      yes?: true
    })

    agent = Aidp::Workflows::GuidedAgent.new(
      temp_project_dir,
      prompt: test_prompt,
      verbose: true,
      config_manager: system_test_config_manager,
      provider_manager: system_test_provider_manager
    )

    # Capture display messages to verify verbose output
    displayed_messages = []
    allow(agent).to receive(:display_message) do |msg, **opts|
      displayed_messages << {message: msg, type: opts[:type]}
    end

    workflow = nil
    expect { workflow = agent.select_workflow }.not_to raise_error

    # Verify workflow completed
    expect(workflow[:mode]).to eq(:execute)

    # Verify key messages were displayed
    message_text = displayed_messages.map { |m| m[:message] }.join("\n")
    expect(message_text).to include("Welcome to AIDP Guided Workflow")
    expect(message_text).to include("Plan Phase")
  end

  it "completes workflow even with resource exhaustion fallback" do
    # Create test doubles with resource exhaustion behavior
    failing_then_recovering_cursor = instance_double(AgentHarness::Providers::Cursor).tap do |provider|
      call_count = 0
      allow(provider).to receive(:send_message) do |prompt:, session: nil|
        call_count += 1
        if call_count == 1
          raise "ConnectError: [resource_exhausted] Error"
        else
          '{"complete": true, "questions": [], "reasoning": "recovered after fallback"}'
        end
      end
    end

    successful_claude = instance_double(AgentHarness::Providers::Anthropic).tap do |provider|
      allow(provider).to receive(:send_message).and_return(
        '{"steps": ["00_PRD"], "reasoning": "minimal workflow"}'
      )
    end

    recovery_provider_factory = instance_double(Aidp::Harness::ProviderFactory).tap do |factory|
      allow(factory).to receive(:create_provider).with("cursor", prompt: anything).and_return(failing_then_recovering_cursor)
      allow(factory).to receive(:create_provider).with("claude", prompt: anything).and_return(successful_claude)
    end

    allow(Aidp::Harness::ProviderFactory).to receive(:new).with(system_test_config_manager).and_return(recovery_provider_factory)

    test_prompt = TestPrompt.new(responses: {ask: "Simple project", yes?: true})
    agent = Aidp::Workflows::GuidedAgent.new(
      temp_project_dir,
      prompt: test_prompt,
      verbose: false,
      config_manager: system_test_config_manager,
      provider_manager: system_test_provider_manager
    )

    workflow = nil
    expect { workflow = agent.select_workflow }.not_to raise_error
    expect(workflow[:mode]).to eq(:execute)
  end
end
