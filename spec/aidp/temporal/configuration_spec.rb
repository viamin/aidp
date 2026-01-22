# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Temporal::Configuration do
  let(:project_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(project_dir, ".aidp") }
  let(:config_path) { File.join(config_dir, "aidp.yml") }

  before do
    FileUtils.mkdir_p(config_dir)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#initialize" do
    context "with no config file" do
      it "uses default configuration" do
        config = described_class.new(project_dir)

        expect(config.target_host).to eq("localhost:7233")
        expect(config.namespace).to eq("default")
        expect(config.task_queue).to eq("aidp-workflows")
      end
    end

    context "with config file" do
      before do
        File.write(config_path, <<~YAML)
          temporal:
            target_host: "temporal.example.com:7233"
            namespace: "aidp-prod"
            task_queue: "custom-queue"
            tls: true
        YAML
      end

      it "loads configuration from file" do
        config = described_class.new(project_dir)

        expect(config.target_host).to eq("temporal.example.com:7233")
        expect(config.namespace).to eq("aidp-prod")
        expect(config.task_queue).to eq("custom-queue")
      end
    end

    context "with environment variables" do
      around do |example|
        original_host = ENV["TEMPORAL_HOST"]
        original_ns = ENV["TEMPORAL_NAMESPACE"]

        ENV["TEMPORAL_HOST"] = "env-temporal:7233"
        ENV["TEMPORAL_NAMESPACE"] = "env-namespace"

        example.run

        ENV["TEMPORAL_HOST"] = original_host
        ENV["TEMPORAL_NAMESPACE"] = original_ns
      end

      it "environment variables override file config" do
        File.write(config_path, <<~YAML)
          temporal:
            target_host: "file-temporal:7233"
            namespace: "file-namespace"
        YAML

        config = described_class.new(project_dir)

        expect(config.target_host).to eq("env-temporal:7233")
        expect(config.namespace).to eq("env-namespace")
      end
    end
  end

  describe "#enabled?" do
    it "returns false by default (opt-in)" do
      config = described_class.new(project_dir)
      expect(config.enabled?).to be false
    end

    context "when enabled in config" do
      before do
        File.write(config_path, <<~YAML)
          temporal:
            enabled: true
        YAML
      end

      it "returns true" do
        config = described_class.new(project_dir)
        expect(config.enabled?).to be true
      end
    end

    context "when explicitly disabled in config" do
      before do
        File.write(config_path, <<~YAML)
          temporal:
            enabled: false
        YAML
      end

      it "returns false" do
        config = described_class.new(project_dir)
        expect(config.enabled?).to be false
      end
    end
  end

  describe "#connection_config" do
    it "returns connection settings" do
      config = described_class.new(project_dir)

      conn_config = config.connection_config

      expect(conn_config).to include(
        target_host: "localhost:7233",
        namespace: "default",
        tls: false
      )
    end
  end

  describe "#worker_config" do
    it "returns worker settings" do
      config = described_class.new(project_dir)

      worker_config = config.worker_config

      expect(worker_config).to include(
        task_queue: "aidp-workflows",
        max_concurrent_activities: 10,
        max_concurrent_workflows: 10
      )
    end
  end

  describe "#timeout_config" do
    it "returns timeout settings" do
      config = described_class.new(project_dir)

      timeout_config = config.timeout_config

      expect(timeout_config).to include(
        workflow_execution: 86400,
        activity_start_to_close: 600
      )
    end
  end

  describe "#retry_config" do
    it "returns retry settings" do
      config = described_class.new(project_dir)

      retry_config = config.retry_config

      expect(retry_config).to include(
        initial_interval: 1,
        backoff_coefficient: 2.0,
        maximum_attempts: 3
      )
    end
  end

  describe "#build_connection" do
    it "returns a Connection instance" do
      config = described_class.new(project_dir)

      connection = config.build_connection

      expect(connection).to be_a(Aidp::Temporal::Connection)
      expect(connection.target_host).to eq(config.target_host)
    end
  end

  describe "#build_worker" do
    it "returns a Worker instance" do
      config = described_class.new(project_dir)

      worker = config.build_worker

      expect(worker).to be_a(Aidp::Temporal::Worker)
      expect(worker.task_queue).to eq(config.task_queue)
    end
  end
end
