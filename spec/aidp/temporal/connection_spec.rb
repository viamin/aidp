# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Temporal::Connection do
  describe "#initialize" do
    it "uses default configuration" do
      connection = described_class.new({})

      expect(connection.target_host).to eq("localhost:7233")
      expect(connection.namespace).to eq("default")
    end

    it "accepts custom configuration" do
      connection = described_class.new(
        target_host: "custom:7233",
        namespace: "custom-ns"
      )

      expect(connection.target_host).to eq("custom:7233")
      expect(connection.namespace).to eq("custom-ns")
    end

    context "with environment variables" do
      around do |example|
        original_host = ENV["TEMPORAL_HOST"]
        ENV["TEMPORAL_HOST"] = "env-host:7233"

        example.run

        ENV["TEMPORAL_HOST"] = original_host
      end

      it "uses environment variables when config not provided" do
        connection = described_class.new({})

        expect(connection.target_host).to eq("env-host:7233")
      end
    end
  end

  describe "#connected?" do
    it "returns false when not connected" do
      connection = described_class.new({})

      expect(connection.connected?).to be false
    end
  end

  describe "#close" do
    it "clears the client" do
      connection = described_class.new({})

      connection.close

      expect(connection.connected?).to be false
    end
  end
end
