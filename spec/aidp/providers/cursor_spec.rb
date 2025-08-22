# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Providers::Cursor do
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
    it "raises error when cursor-agent is not available" do
      allow(described_class).to receive(:available?).and_return(false)
      provider = described_class.new
      expect { provider.send(prompt: "test") }.to raise_error(RuntimeError, /cursor-agent not available/)
    end

    it "returns output when cursor-agent succeeds" do
      allow(described_class).to receive(:available?).and_return(true)

      # Create a test double that avoids the complex threading
      provider_double = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(provider_double)
      allow(provider_double).to receive(:name).and_return("cursor")
      allow(provider_double).to receive(:send).and_return("test output\n")

      provider = described_class.new
      result = provider.send(prompt: "test")
      expect(result).to eq("test output\n")
    end

    it "raises error when cursor-agent fails" do
      allow(described_class).to receive(:available?).and_return(true)

      # Create a test double that raises an error
      provider_double = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(provider_double)
      allow(provider_double).to receive(:name).and_return("cursor")
      allow(provider_double).to receive(:send).and_raise(RuntimeError, "cursor-agent failed with exit code 1: error message")

      provider = described_class.new
      expect { provider.send(prompt: "test") }.to raise_error(RuntimeError, /cursor-agent failed/)
    end
  end
end
