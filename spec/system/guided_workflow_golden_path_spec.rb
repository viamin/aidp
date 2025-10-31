# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# System spec: Full workflow from CLI to completion
# Tests the golden path without mocking core application logic
# Only stubs external provider responses
RSpec.describe "AIDP Golden Path System Test", type: :system do
  let(:temp_project_dir) { Dir.mktmpdir("aidp_system_test") }

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

    # Stub provider responses with realistic planning conversation
    # First call: ask initial question
    # Second call: confirm plan complete
    # Third call: identify steps
    call_sequence = [
      '{"complete": false, "questions": ["What is the main goal of this project?"], "reasoning": "need initial context"}',
      '{"complete": true, "questions": [], "reasoning": "have enough information"}',
      '{"steps": ["00_PRD", "16_IMPLEMENTATION"], "reasoning": "basic implementation workflow"}'
    ]

    call_index = 0
    allow_any_instance_of(Aidp::Providers::Cursor).to receive(:send_message) do |instance, prompt:, session: nil|
      response = call_sequence[call_index] || call_sequence.last
      call_index += 1
      response
    end

    # Fallback provider (should not be needed in golden path)
    allow_any_instance_of(Aidp::Providers::Anthropic).to receive(:send_message).and_return(
      '{"complete": true, "questions": [], "reasoning": "fallback response"}'
    )
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

    # Create agent and run workflow
    agent = Aidp::Workflows::GuidedAgent.new(temp_project_dir, prompt: test_prompt, verbose: false)
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

    agent = Aidp::Workflows::GuidedAgent.new(temp_project_dir, prompt: test_prompt, verbose: true)

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
    # First provider fails once, then succeeds
    call_count = 0
    allow_any_instance_of(Aidp::Providers::Cursor).to receive(:send_message) do |instance, prompt:, session: nil|
      call_count += 1
      if call_count == 1
        raise "ConnectError: [resource_exhausted] Error"
      else
        '{"complete": true, "questions": [], "reasoning": "recovered after fallback"}'
      end
    end

    # Claude fallback provider succeeds
    allow_any_instance_of(Aidp::Providers::Anthropic).to receive(:send_message).and_return(
      '{"steps": ["00_PRD"], "reasoning": "minimal workflow"}'
    )

    test_prompt = TestPrompt.new(responses: {ask: "Simple project", yes?: true})
    agent = Aidp::Workflows::GuidedAgent.new(temp_project_dir, prompt: test_prompt, verbose: false)

    workflow = nil
    expect { workflow = agent.select_workflow }.not_to raise_error
    expect(workflow[:mode]).to eq(:execute)
  end
end
