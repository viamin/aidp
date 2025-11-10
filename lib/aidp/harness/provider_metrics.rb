# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "../rescue_logging"

module Aidp
  module Harness
    # Persists provider metrics and rate limit information to disk
    # Enables the provider dashboard to display real-time state
    class ProviderMetrics
      include Aidp::RescueLogging

      attr_reader :project_dir, :metrics_file, :rate_limit_file

      def initialize(project_dir)
        @project_dir = project_dir
        @metrics_file = File.join(project_dir, ".aidp", "provider_metrics.yml")
        @rate_limit_file = File.join(project_dir, ".aidp", "provider_rate_limits.yml")
        ensure_directory
      end

      # Save provider metrics to disk
      def save_metrics(metrics_hash)
        return if metrics_hash.nil? || metrics_hash.empty?

        # Convert Time objects to ISO8601 strings for YAML serialization
        serializable_metrics = serialize_metrics(metrics_hash)

        File.write(@metrics_file, YAML.dump(serializable_metrics))
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "save_metrics", fallback: nil)
      end

      # Load provider metrics from disk
      def load_metrics
        return {} unless File.exist?(@metrics_file)

        data = YAML.safe_load_file(@metrics_file, permitted_classes: [Time, Date, Symbol], aliases: true)
        return {} unless data.is_a?(Hash)

        # Convert ISO8601 strings back to Time objects
        deserialize_metrics(data)
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "load_metrics", fallback: {})
        {}
      end

      # Save rate limit information to disk
      def save_rate_limits(rate_limit_hash)
        return if rate_limit_hash.nil? || rate_limit_hash.empty?

        # Convert Time objects to ISO8601 strings for YAML serialization
        serializable_rate_limits = serialize_rate_limits(rate_limit_hash)

        File.write(@rate_limit_file, YAML.dump(serializable_rate_limits))
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "save_rate_limits", fallback: nil)
      end

      # Load rate limit information from disk
      def load_rate_limits
        return {} unless File.exist?(@rate_limit_file)

        data = YAML.safe_load_file(@rate_limit_file, permitted_classes: [Time, Date, Symbol], aliases: true)
        return {} unless data.is_a?(Hash)

        # Convert ISO8601 strings back to Time objects
        deserialize_rate_limits(data)
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "load_rate_limits", fallback: {})
        {}
      end

      # Clear all persisted metrics
      def clear
        File.delete(@metrics_file) if File.exist?(@metrics_file)
        File.delete(@rate_limit_file) if File.exist?(@rate_limit_file)
      end

      private

      def ensure_directory
        aidp_dir = File.join(@project_dir, ".aidp")
        FileUtils.mkdir_p(aidp_dir) unless File.directory?(aidp_dir)
      end

      def serialize_metrics(metrics_hash)
        metrics_hash.transform_values do |provider_metrics|
          next provider_metrics unless provider_metrics.is_a?(Hash)

          provider_metrics.transform_values do |value|
            value.is_a?(Time) ? value.iso8601 : value
          end
        end
      end

      def deserialize_metrics(metrics_hash)
        metrics_hash.transform_values do |provider_metrics|
          next provider_metrics unless provider_metrics.is_a?(Hash)

          provider_metrics.transform_keys(&:to_sym).transform_values do |value|
            parse_time_if_string(value)
          end
        end
      end

      def serialize_rate_limits(rate_limit_hash)
        rate_limit_hash.transform_values do |limit_info|
          next limit_info unless limit_info.is_a?(Hash)

          limit_info.transform_values do |value|
            value.is_a?(Time) ? value.iso8601 : value
          end
        end
      end

      def deserialize_rate_limits(rate_limit_hash)
        rate_limit_hash.transform_values do |limit_info|
          next limit_info unless limit_info.is_a?(Hash)

          limit_info.transform_keys(&:to_sym).transform_values do |value|
            parse_time_if_string(value)
          end
        end
      end

      def parse_time_if_string(value)
        return value unless value.is_a?(String)

        # Try to parse ISO8601 timestamp
        Time.parse(value)
      rescue ArgumentError
        value
      end
    end
  end
end
