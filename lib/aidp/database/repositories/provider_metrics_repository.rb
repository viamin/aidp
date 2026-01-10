# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for provider_metrics and provider_rate_limits tables
      # Replaces provider_metrics.yml and provider_rate_limits.yml
      class ProviderMetricsRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "provider_metrics")
        end

        # Save metrics for a provider
        #
        # @param provider_name [String] Provider name
        # @param metrics [Hash] Metrics data (success_count, error_count, avg_latency, etc.)
        # @param model_name [String, nil] Optional model name
        def save_metrics(provider_name, metrics, model_name: nil)
          now = current_timestamp

          # Convert Time values to ISO8601 strings
          normalized = metrics.transform_values do |value|
            value.is_a?(Time) ? value.iso8601 : value
          end

          execute(
            insert_sql([:project_dir, :provider_name, :model_name, :metrics, :recorded_at]),
            [project_dir, provider_name, model_name, serialize_json(normalized), now]
          )

          Aidp.log_debug("provider_metrics_repository", "saved_metrics",
            provider: provider_name, metrics_count: metrics.size)
        end

        # Load metrics for all providers
        #
        # @return [Hash] Map of provider_name => metrics hash
        def load_metrics
          # Get the latest metrics for each provider
          rows = query(
            <<~SQL,
              SELECT provider_name, model_name, metrics, recorded_at
              FROM provider_metrics
              WHERE project_dir = ?
              AND id IN (
                SELECT MAX(id) FROM provider_metrics
                WHERE project_dir = ?
                GROUP BY provider_name
              )
            SQL
            [project_dir, project_dir]
          )

          result = {}
          rows.each do |row|
            provider = row["provider_name"]
            metrics = deserialize_json(row["metrics"]) || {}
            result[provider] = symbolize_keys(metrics)
            result[provider][:recorded_at] = row["recorded_at"]
          end

          result
        end

        # Load metrics for a specific provider
        #
        # @param provider_name [String] Provider name
        # @return [Hash] Metrics
        def load_provider_metrics(provider_name)
          row = query_one(
            <<~SQL,
              SELECT metrics, recorded_at
              FROM provider_metrics
              WHERE project_dir = ? AND provider_name = ?
              ORDER BY recorded_at DESC
              LIMIT 1
            SQL
            [project_dir, provider_name]
          )

          return {} unless row

          metrics = deserialize_json(row["metrics"]) || {}
          symbolize_keys(metrics)
        end

        # Save rate limit info for a provider
        #
        # @param provider_name [String] Provider name
        # @param rate_limits [Hash] Rate limit data
        # @param model_name [String, nil] Optional model name
        def save_rate_limits(provider_name, rate_limits, model_name: nil)
          now = current_timestamp

          # Convert Time values to ISO8601 strings
          normalized = rate_limits.transform_values do |info|
            next info unless info.is_a?(Hash)

            info.transform_values do |value|
              value.is_a?(Time) ? value.iso8601 : value
            end
          end

          upsert_rate_limit(
            provider_name: provider_name,
            model_name: model_name,
            rate_limit_info: serialize_json(normalized),
            updated_at: now
          )

          Aidp.log_debug("provider_metrics_repository", "saved_rate_limits",
            provider: provider_name)
        end

        # Load rate limits for all providers
        #
        # @return [Hash] Map of provider_name => rate limits hash
        def load_rate_limits
          rows = query(
            "SELECT provider_name, model_name, rate_limit_info, updated_at FROM provider_rate_limits WHERE project_dir = ?",
            [project_dir]
          )

          result = {}
          rows.each do |row|
            provider = row["provider_name"]
            limits = deserialize_json(row["rate_limit_info"]) || {}
            result[provider] = symbolize_keys_deep(limits)
          end

          result
        end

        # Load rate limits for a specific provider
        #
        # @param provider_name [String] Provider name
        # @return [Hash] Rate limits
        def load_provider_rate_limits(provider_name)
          row = query_one(
            "SELECT rate_limit_info, updated_at FROM provider_rate_limits WHERE project_dir = ? AND provider_name = ?",
            [project_dir, provider_name]
          )

          return {} unless row

          limits = deserialize_json(row["rate_limit_info"]) || {}
          symbolize_keys_deep(limits)
        end

        # Clear all metrics and rate limits
        def clear
          transaction do
            execute("DELETE FROM provider_metrics WHERE project_dir = ?", [project_dir])
            execute("DELETE FROM provider_rate_limits WHERE project_dir = ?", [project_dir])
          end
          Aidp.log_debug("provider_metrics_repository", "cleared")
        end

        # Get metrics history for a provider
        #
        # @param provider_name [String] Provider name
        # @param metric_type [String, nil] Metric type to extract (optional)
        # @param limit [Integer] Max records
        # @return [Array<Hash>] Historical values
        def metrics_history(provider_name, metric_type = nil, limit: 100)
          rows = query(
            <<~SQL,
              SELECT metrics, recorded_at
              FROM provider_metrics
              WHERE project_dir = ? AND provider_name = ?
              ORDER BY recorded_at DESC
              LIMIT ?
            SQL
            [project_dir, provider_name, limit]
          )

          rows.map do |row|
            metrics = deserialize_json(row["metrics"]) || {}
            if metric_type
              {value: metrics[metric_type.to_s] || metrics[metric_type.to_sym], recorded_at: row["recorded_at"]}
            else
              {metrics: symbolize_keys(metrics), recorded_at: row["recorded_at"]}
            end
          end
        end

        private

        def upsert_rate_limit(provider_name:, model_name:, rate_limit_info:, updated_at:)
          existing = query_one(
            "SELECT id FROM provider_rate_limits WHERE project_dir = ? AND provider_name = ? AND (model_name = ? OR (model_name IS NULL AND ? IS NULL))",
            [project_dir, provider_name, model_name, model_name]
          )

          if existing
            execute(
              <<~SQL,
                UPDATE provider_rate_limits SET
                  rate_limit_info = ?, updated_at = ?
                WHERE id = ?
              SQL
              [rate_limit_info, updated_at, existing["id"]]
            )
          else
            execute(
              <<~SQL,
                INSERT INTO provider_rate_limits
                  (project_dir, provider_name, model_name, rate_limit_info, updated_at)
                VALUES (?, ?, ?, ?, ?)
              SQL
              [project_dir, provider_name, model_name, rate_limit_info, updated_at]
            )
          end
        end

        def symbolize_keys(hash)
          return {} unless hash

          hash.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = value
          end
        end

        def symbolize_keys_deep(hash)
          return {} unless hash

          hash.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = value.is_a?(Hash) ? symbolize_keys_deep(value) : value
          end
        end

        def parse_time(value)
          return nil if value.nil?
          return value if value.is_a?(Time)

          Time.parse(value)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
