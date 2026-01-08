# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "../rescue_logging"
require_relative "../util"

module Aidp
  module Harness
    # Persists provider metrics and rate limit information to disk
    # Enables the provider dashboard to display real-time state
    class ProviderMetrics
      include Aidp::RescueLogging

      attr_reader :project_dir, :metrics_file, :rate_limit_file, :usage_tracking_dir

      def initialize(project_dir)
        # Store metrics at the repository root so different worktrees/modes share state
        @project_dir = Aidp::Util.find_project_root(project_dir)
        @metrics_file = File.join(@project_dir, ".aidp", "provider_metrics.yml")
        @rate_limit_file = File.join(@project_dir, ".aidp", "provider_rate_limits.yml")
        @usage_tracking_dir = File.join(@project_dir, ".aidp", "usage_tracking")
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
        clear_usage_tracking
      end

      # Save usage tracking data for a provider
      #
      # @param provider_name [String] Name of the provider
      # @param usage_data [Hash] Usage tracking data
      def save_usage_tracking(provider_name, usage_data)
        return if usage_data.nil? || usage_data.empty?

        ensure_usage_tracking_directory
        usage_file = usage_tracking_file(provider_name)

        # Serialize Time objects for YAML
        serializable_data = serialize_usage_tracking(usage_data)

        # Write atomically using temp file + rename
        temp_file = "#{usage_file}.tmp"
        File.write(temp_file, YAML.dump(serializable_data))
        File.rename(temp_file, usage_file)
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "save_usage_tracking", fallback: nil)
        File.delete(temp_file) if defined?(temp_file) && File.exist?(temp_file)
      end

      # Load usage tracking data for a provider
      #
      # @param provider_name [String] Name of the provider
      # @return [Hash] Usage tracking data or empty hash
      def load_usage_tracking(provider_name)
        usage_file = usage_tracking_file(provider_name)
        return {} unless File.exist?(usage_file)

        data = YAML.safe_load_file(usage_file, permitted_classes: [Time, Date, Symbol], aliases: true)
        return {} unless data.is_a?(Hash)

        deserialize_usage_tracking(data)
      rescue => e
        log_rescue(e, component: "provider_metrics", action: "load_usage_tracking", fallback: {})
        {}
      end

      # Clear usage tracking data for a specific provider
      #
      # @param provider_name [String] Name of the provider (optional, clears all if nil)
      def clear_usage_tracking(provider_name = nil)
        if provider_name
          usage_file = usage_tracking_file(provider_name)
          File.delete(usage_file) if File.exist?(usage_file)
        else
          # Clear all usage tracking files
          return unless File.directory?(@usage_tracking_dir)

          Dir.glob(File.join(@usage_tracking_dir, "*.yml")).each do |file|
            File.delete(file)
          rescue => e
            log_rescue(e, component: "provider_metrics", action: "clear_usage_file", fallback: nil)
          end
        end
      end

      # List all providers with usage tracking data
      #
      # @return [Array<String>] Array of provider names
      def providers_with_usage_tracking
        return [] unless File.directory?(@usage_tracking_dir)

        Dir.glob(File.join(@usage_tracking_dir, "*.yml")).map do |file|
          File.basename(file, ".yml")
        end
      end

      private

      def ensure_directory
        aidp_dir = File.join(@project_dir, ".aidp")
        FileUtils.mkdir_p(aidp_dir) unless File.directory?(aidp_dir)
      end

      def ensure_usage_tracking_directory
        FileUtils.mkdir_p(@usage_tracking_dir) unless File.directory?(@usage_tracking_dir)
      end

      def usage_tracking_file(provider_name)
        File.join(@usage_tracking_dir, "#{provider_name}.yml")
      end

      def serialize_usage_tracking(data)
        deep_transform_values(data) do |value|
          value.is_a?(Time) ? value.iso8601 : value
        end
      end

      def deserialize_usage_tracking(data)
        deep_transform_values(data) do |value|
          parse_time_if_string(value)
        end
      end

      def deep_transform_values(obj, &block)
        case obj
        when Hash
          obj.transform_values { |v| deep_transform_values(v, &block) }
        when Array
          obj.map { |v| deep_transform_values(v, &block) }
        else
          yield(obj)
        end
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
