# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CLI do
  let(:cli) { described_class.new }

  describe "#detect" do
    it "outputs provider name when available" do
      # Mock the runner to return a provider
      mock_runner = double("Runner")
      mock_provider = double("Provider", name: "cursor")
      allow(Aidp::Runner).to receive(:new).and_return(mock_runner)
      allow(mock_runner).to receive(:detect_provider).and_return(mock_provider)

      expect { cli.detect }.to output("Provider: cursor\n").to_stdout
    end

    it "outputs error message when no provider available" do
      # Mock the runner to raise an error
      allow(Aidp::Runner).to receive(:new).and_raise("No supported provider found. Install Cursor CLI (preferred), Claude CLI, or Gemini CLI.")

      expect { cli.detect }.to raise_error(SystemExit)
    end
  end

  describe "#execute" do
    it "raises error for invalid step" do
      expect { cli.execute("invalid_step") }.to raise_error(SystemExit)
    end
  end
end
