# frozen_string_literal: true

require "temporalio/client"

module Aidp
  module Temporal
    # Manages Temporal client connections
    # Handles connection pooling, configuration, and lifecycle
    class Connection
      DEFAULT_TARGET_HOST = "localhost:7233"
      DEFAULT_NAMESPACE = "default"

      attr_reader :client, :config

      def initialize(config = {})
        @config = normalize_config(config)
        @client = nil
        @mutex = Mutex.new
      end

      # Get or create a connected client
      # Thread-safe lazy initialization
      def connect
        @mutex.synchronize do
          @client ||= create_client
        end
      end

      # Check if connected
      def connected?
        @mutex.synchronize { !@client.nil? }
      end

      # Close the connection
      def close
        @mutex.synchronize do
          @client = nil
        end
      end

      # Get target host
      def target_host
        @config[:target_host]
      end

      # Get namespace
      def namespace
        @config[:namespace]
      end

      private

      def normalize_config(config)
        {
          target_host: config[:target_host] || config["target_host"] || ENV["TEMPORAL_HOST"] || DEFAULT_TARGET_HOST,
          namespace: config[:namespace] || config["namespace"] || ENV["TEMPORAL_NAMESPACE"] || DEFAULT_NAMESPACE,
          tls: config[:tls] || config["tls"] || false,
          api_key: config[:api_key] || config["api_key"] || ENV["TEMPORAL_API_KEY"]
        }
      end

      def create_client
        Aidp.log_debug("temporal_connection", "connecting",
          target_host: @config[:target_host],
          namespace: @config[:namespace],
          tls: @config[:tls])

        options = {
          target_host: @config[:target_host],
          namespace: @config[:namespace]
        }

        # Add TLS configuration if enabled
        if @config[:tls]
          options[:tls] = true
        end

        # Add API key if provided (for Temporal Cloud)
        if @config[:api_key]
          options[:api_key] = @config[:api_key]
        end

        client = Temporalio::Client.connect(**options)

        Aidp.log_info("temporal_connection", "connected",
          target_host: @config[:target_host],
          namespace: @config[:namespace])

        client
      end
    end
  end
end
