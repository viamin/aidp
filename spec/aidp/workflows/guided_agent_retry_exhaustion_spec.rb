# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Workflows::GuidedAgent do
  let(:project_dir) { Dir.pwd }

  before do
    # Configuration with only one provider (no fallback possible)
    allow_any_instance_of(Aidp::Harness::ConfigManager).to receive(:config).and_return({
      harness: {enabled: true, default_provider: "cursor"},
      providers: {
        cursor: {type: "api", api_key: "x", models: ["cursor-default"]}
      }
    })

    # Provider always fails with resource exhaustion
    allow_any_instance_of(Aidp::Providers::Cursor).to receive(:send_message) do |instance, prompt:, session: nil|
      raise "ConnectError: [resource_exhausted] Error"
    end
  end

  it "raises ConversationError after exhausting retries when only one provider configured" do
    test_prompt = TestPrompt.new(responses: {ask: "answer", yes?: true})
    agent = described_class.new(project_dir, prompt: test_prompt, verbose: false)

    expect { agent.select_workflow }.to raise_error(
      Aidp::Workflows::GuidedAgent::ConversationError,
      /Failed to guide workflow selection.*resource_exhausted/i
    )
  end

  it "does not log provider switch messages when no fallback available" do
    test_prompt = TestPrompt.new(responses: {ask: "answer", yes?: true})
    agent = described_class.new(project_dir, prompt: test_prompt, verbose: false)

    # Capture display messages to verify no "Switched to provider" appears
    displayed_messages = []
    allow(agent).to receive(:display_message) do |msg, **_opts|
      displayed_messages << msg
    end

    expect { agent.select_workflow }.to raise_error(Aidp::Workflows::GuidedAgent::ConversationError)

    # Should show warning about resource exhaustion but NOT switch confirmation
    expect(displayed_messages.any? { |msg| msg.include?("resource exhausted") }).to be true
    expect(displayed_messages.any? { |msg| msg.include?("Switched to provider") }).to be false
  end
end
