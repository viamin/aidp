# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Workflows::GuidedAgent do
  let(:project_dir) { Dir.mktmpdir("guided_agent_spec") }

  before do
    # Create docs directory in temp location
    FileUtils.mkdir_p(File.join(project_dir, "docs"))
    # Configuration with two providers so fallback is possible
    allow_any_instance_of(Aidp::Harness::ConfigManager).to receive(:config).and_return({
      harness: {enabled: true, default_provider: "cursor", fallback_providers: ["claude"]},
      providers: {
        cursor: {type: "api", api_key: "x", models: ["cursor-default"]},
        claude: {type: "api", api_key: "y", models: ["claude-3-5-sonnet-20241022"]}
      }
    })

    # First provider (cursor) fails once with resource exhaustion
    call_counter = 0
    allow_any_instance_of(Aidp::Providers::Cursor).to receive(:send_message) do |instance, prompt:, session: nil|
      call_counter += 1
      if call_counter == 1
        raise "ConnectError: [resource_exhausted] Error"
      else
        '{"complete": true, "questions": [], "reasoning": "done"}'
      end
    end

    # Fallback provider succeeds immediately
    allow_any_instance_of(Aidp::Providers::Anthropic).to receive(:send_message).and_return('{"complete": true, "questions": [], "reasoning": "done"}')
  end

  after do
    FileUtils.rm_rf(project_dir) if project_dir && File.directory?(project_dir)
  end

  it "switches from cursor to claude after resource exhaustion and completes planning" do
    test_prompt = TestPrompt.new(responses: {ask: "answer", yes?: true})
    agent = described_class.new(project_dir, prompt: test_prompt, verbose: false)
    workflow = nil
    expect { workflow = agent.select_workflow }.not_to raise_error
    expect(workflow[:mode]).to eq(:execute)
  end
end
