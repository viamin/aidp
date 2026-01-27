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

    it "accepts string key configuration" do
      connection = described_class.new(
        "target_host" => "string-key:7233",
        "namespace" => "string-ns"
      )

      expect(connection.target_host).to eq("string-key:7233")
      expect(connection.namespace).to eq("string-ns")
    end

    it "handles tls configuration with symbol key" do
      connection = described_class.new(tls: true)

      expect(connection.config[:tls]).to be true
    end

    it "handles tls configuration with string key" do
      connection = described_class.new("tls" => true)

      expect(connection.config[:tls]).to be true
    end

    it "handles api_key with symbol key" do
      connection = described_class.new(api_key: "test-key")

      expect(connection.config[:api_key]).to eq("test-key")
    end

    it "handles api_key with string key" do
      connection = described_class.new("api_key" => "test-key")

      expect(connection.config[:api_key]).to eq("test-key")
    end

    context "with environment variables" do
      around do |example|
        original_host = ENV["TEMPORAL_HOST"]
        original_namespace = ENV["TEMPORAL_NAMESPACE"]
        original_api_key = ENV["TEMPORAL_API_KEY"]

        ENV["TEMPORAL_HOST"] = "env-host:7233"
        ENV["TEMPORAL_NAMESPACE"] = "env-ns"
        ENV["TEMPORAL_API_KEY"] = "env-api-key"

        example.run

        ENV["TEMPORAL_HOST"] = original_host
        ENV["TEMPORAL_NAMESPACE"] = original_namespace
        ENV["TEMPORAL_API_KEY"] = original_api_key
      end

      it "uses environment variables when config not provided" do
        connection = described_class.new({})

        expect(connection.target_host).to eq("env-host:7233")
        expect(connection.namespace).to eq("env-ns")
        expect(connection.config[:api_key]).to eq("env-api-key")
      end

      it "prefers symbol config over environment" do
        connection = described_class.new(target_host: "symbol:7233")

        expect(connection.target_host).to eq("symbol:7233")
      end

      it "prefers string config over environment" do
        connection = described_class.new("target_host" => "string:7233")

        expect(connection.target_host).to eq("string:7233")
      end
    end
  end

  describe "#connected?" do
    it "returns false when not connected" do
      connection = described_class.new({})

      expect(connection.connected?).to be false
    end

    it "returns true when connected" do
      connection = described_class.new({})
      mock_client = instance_double(Temporalio::Client)

      allow(Temporalio::Client).to receive(:connect).and_return(mock_client)

      connection.connect

      expect(connection.connected?).to be true
    end
  end

  describe "#connect" do
    let(:mock_client) { instance_double(Temporalio::Client) }

    before do
      allow(Temporalio::Client).to receive(:connect).and_return(mock_client)
    end

    it "creates client without TLS or API key" do
      connection = described_class.new(target_host: "test:7233", namespace: "test-ns")

      connection.connect

      expect(Temporalio::Client).to have_received(:connect).with(
        target_host: "test:7233",
        namespace: "test-ns"
      )
    end

    it "includes TLS when enabled" do
      connection = described_class.new(
        target_host: "test:7233",
        namespace: "test-ns",
        tls: true
      )

      connection.connect

      expect(Temporalio::Client).to have_received(:connect).with(
        target_host: "test:7233",
        namespace: "test-ns",
        tls: true
      )
    end

    it "includes API key when provided" do
      connection = described_class.new(
        target_host: "test:7233",
        namespace: "test-ns",
        api_key: "test-api-key"
      )

      connection.connect

      expect(Temporalio::Client).to have_received(:connect).with(
        target_host: "test:7233",
        namespace: "test-ns",
        api_key: "test-api-key"
      )
    end

    it "includes both TLS and API key when both provided" do
      connection = described_class.new(
        target_host: "test:7233",
        namespace: "test-ns",
        tls: true,
        api_key: "test-api-key"
      )

      connection.connect

      expect(Temporalio::Client).to have_received(:connect).with(
        target_host: "test:7233",
        namespace: "test-ns",
        tls: true,
        api_key: "test-api-key"
      )
    end

    it "returns same client on subsequent calls" do
      connection = described_class.new({})

      client1 = connection.connect
      client2 = connection.connect

      expect(client1).to eq(client2)
      expect(Temporalio::Client).to have_received(:connect).once
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
