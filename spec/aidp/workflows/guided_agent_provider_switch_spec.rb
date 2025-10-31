# frozen_string_literal: true

require "spec_helper"
require "aidp/workflows/guided_agent"

RSpec.describe Aidp::Workflows::GuidedAgent do
  let(:project_dir) { Dir.mktmpdir }
  let(:provider_manager) { instance_double("ProviderManager", current_provider: "cursor") }
  let(:config_manager) { instance_double("Aidp::Harness::ConfigManager") }
  let(:prompt) { instance_double("TTY::Prompt") }
  let(:agent) { described_class.new(project_dir, prompt: prompt, verbose: false) }
  let(:provider_factory) { instance_double("Aidp::Harness::ProviderFactory") }
  let(:provider) { instance_double("Provider", send_message: nil) }

  before do
    allow(Aidp::Harness::ProviderFactory).to receive(:new).and_return(provider_factory)
    allow(provider_factory).to receive(:create_provider).and_return(provider)
    allow(prompt).to receive(:ask).and_return("Goal")
    allow(agent.instance_variable_get(:@config_manager)).to receive(:respond_to?).and_return(false)
    agent.instance_variable_set(:@provider_manager, provider_manager)
    allow(provider).to receive(:send_message).and_raise(StandardError, "ConnectError: [resource_exhausted] Error")
    allow(provider_manager).to receive(:configured_providers).and_return(["cursor"])
    allow(provider_manager).to receive(:switch_provider_for_error).and_return("cursor")

    # Stub logger
    mock_logger = instance_double("Aidp::Logger")
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:warn)
    allow(mock_logger).to receive(:error)
    allow(Aidp).to receive(:logger).and_return(mock_logger)

    # Silence display_message output
    allow(agent).to receive(:display_message)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  it "logs no-op provider switch via debug when provider remains the same" do
    expect(provider_manager).to receive(:switch_provider_for_error).and_return("cursor")
    expect(Aidp.logger).to receive(:debug).with("guided_agent", "provider_switch_noop", hash_including(provider: "cursor", reason: "resource_exhausted"))
    expect { agent.send(:call_provider_for_analysis, "system", "user") }.to raise_error(StandardError)
  end
end
