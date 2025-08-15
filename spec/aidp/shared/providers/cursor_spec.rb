# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Shared::Providers::Cursor do
  describe ".available?" do
    it "returns boolean value" do
      expect([true, false]).to include(described_class.available?)
    end
  end

  describe "#name" do
    it "returns cursor" do
      provider = described_class.new
      expect(provider.name).to eq("cursor")
    end
  end

  describe "#send" do
    let(:provider) { described_class.new }

    it "raises error when cursor-agent is not available" do
      allow(described_class).to receive(:available?).and_return(false)
      expect { provider.send(prompt: "test") }.to raise_error(RuntimeError, /cursor-agent not available/)
    end

    it "returns :ok when cursor-agent succeeds" do
      allow(described_class).to receive(:available?).and_return(true)

      # Mock Open3.popen3 to avoid actual command execution
      mock_process_status = double("Process::Status")
      allow(mock_process_status).to receive(:success?).and_return(true)
      mock_wait = double("Wait")
      allow(mock_wait).to receive(:value).and_return(mock_process_status)
      mock_stdin = double("stdin")
      allow(mock_stdin).to receive(:puts)
      allow(mock_stdin).to receive(:close)
      allow(Open3).to receive(:popen3).and_yield(mock_stdin, nil, nil, mock_wait)

      result = provider.send(prompt: "test")
      expect(result).to eq(:ok)
    end

    it "raises error when cursor-agent fails" do
      allow(described_class).to receive(:available?).and_return(true)

      # Mock Open3.popen3 to simulate failed execution
      mock_process_status = double("Process::Status")
      allow(mock_process_status).to receive(:success?).and_return(false)
      allow(mock_process_status).to receive(:exitstatus).and_return(1)
      mock_wait = double("Wait")
      allow(mock_wait).to receive(:value).and_return(mock_process_status)
      mock_stdin = double("stdin")
      allow(mock_stdin).to receive(:puts)
      allow(mock_stdin).to receive(:close)
      allow(Open3).to receive(:popen3).and_yield(mock_stdin, nil, nil, mock_wait)

      expect { provider.send(prompt: "test") }.to raise_error(RuntimeError, /cursor-agent failed/)
    end
  end
end
