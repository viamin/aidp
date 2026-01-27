# frozen_string_literal: true

require "date"
require "yaml"

module Aidp
  module Temporal
    # Configuration management for Temporal integration
    # Loads settings from aidp.yml and environment variables
    class Configuration
      DEFAULT_CONFIG = {
        enabled: false,  # Disabled by default - users must explicitly opt-in
        target_host: "localhost:7233",
        namespace: "default",
        task_queue: "aidp-workflows",
        tls: false,
        worker: {
          max_concurrent_activities: 10,
          max_concurrent_workflows: 10,
          shutdown_grace_period: 30
        },
        timeouts: {
          workflow_execution: 86400,     # 24 hours
          workflow_run: 3600,            # 1 hour
          activity_start_to_close: 600,  # 10 minutes
          activity_schedule_to_close: 1800, # 30 minutes
          activity_heartbeat: 60         # 1 minute
        },
        retry: {
          initial_interval: 1,
          backoff_coefficient: 2.0,
          maximum_interval: 60,
          maximum_attempts: 3
        }
      }.freeze

      attr_reader :config

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @config = load_config
      end

      # Check if Temporal is enabled
      def enabled?
        @config[:enabled]
      end

      # Get connection configuration
      def connection_config
        {
          target_host: @config[:target_host],
          namespace: @config[:namespace],
          tls: @config[:tls],
          api_key: @config[:api_key]
        }
      end

      # Get worker configuration
      def worker_config
        {
          task_queue: @config[:task_queue],
          max_concurrent_activities: @config.dig(:worker, :max_concurrent_activities),
          max_concurrent_workflows: @config.dig(:worker, :max_concurrent_workflows),
          shutdown_grace_period: @config.dig(:worker, :shutdown_grace_period)
        }
      end

      # Get timeout configuration
      def timeout_config
        @config[:timeouts] || {}
      end

      # Get retry policy configuration
      def retry_config
        @config[:retry] || {}
      end

      # Get task queue name
      def task_queue
        @config[:task_queue]
      end

      # Get target host
      def target_host
        @config[:target_host]
      end

      # Get namespace
      def namespace
        @config[:namespace]
      end

      # Build a connection with this configuration
      def build_connection
        Connection.new(connection_config)
      end

      # Build a worker with this configuration
      def build_worker(connection: nil)
        conn = connection || build_connection
        Worker.new(connection: conn, config: worker_config)
      end

      # Build a workflow client with this configuration
      def build_workflow_client(connection: nil)
        conn = connection || build_connection
        WorkflowClient.new(connection: conn)
      end

      private

      def load_config
        base_config = deep_merge(DEFAULT_CONFIG.dup, load_yaml_config)
        apply_environment_overrides(base_config)
      end

      def load_yaml_config
        config_path = File.join(@project_dir, ".aidp", "aidp.yml")
        return {} unless File.exist?(config_path)

        full_config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true)
        temporal_config = full_config["temporal"] || full_config[:temporal] || {}

        symbolize_keys(temporal_config)
      rescue => e
        Aidp.log_warn("temporal_config", "load_failed", error: e.message)
        {}
      end

      def apply_environment_overrides(config)
        # Environment variables take precedence
        config[:target_host] = ENV["TEMPORAL_HOST"] if ENV["TEMPORAL_HOST"]
        config[:namespace] = ENV["TEMPORAL_NAMESPACE"] if ENV["TEMPORAL_NAMESPACE"]
        config[:task_queue] = ENV["TEMPORAL_TASK_QUEUE"] if ENV["TEMPORAL_TASK_QUEUE"]
        config[:api_key] = ENV["TEMPORAL_API_KEY"] if ENV["TEMPORAL_API_KEY"]
        config[:enabled] = ENV["TEMPORAL_ENABLED"] != "false" if ENV.key?("TEMPORAL_ENABLED")

        if ENV["TEMPORAL_TLS"]
          config[:tls] = ENV["TEMPORAL_TLS"] == "true"
        end

        config
      end

      def deep_merge(base, override)
        return base if override.nil? || override.empty?

        base.merge(override) do |_key, base_val, override_val|
          if base_val.is_a?(Hash) && override_val.is_a?(Hash)
            deep_merge(base_val, override_val)
          else
            override_val.nil? ? base_val : override_val
          end
        end
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
          result[new_key] = new_value
        end
      end
    end
  end
end
