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
        def save_metrics(provider_name, metrics)
          now = current_timestamp

          metrics.each do |metric_type, value|
            next if value.nil?

            # Convert Time to ISO8601 string
            stored_value = value.is_a?(Time) ? value.iso8601 : value

            execute(
              insert_sql([:project_dir, :provider_name, :metric_type, :value, :recorded_at]),
              [project_dir, provider_name, metric_type.to_s, stored_value.to_f, now]
            )
          end

          Aidp.log_debug("provider_metrics_repository", "saved_metrics",
            provider: provider_name, metrics_count: metrics.size)
        end

        # Load metrics for all providers
        #
        # @return [Hash] Map of provider_name => metrics hash
        def load_metrics
          # Get the latest metric of each type for each provider
          rows = query(
            <<~SQL,
              SELECT provider_name, metric_type, value, recorded_at
              FROM provider_metrics
              WHERE project_dir = ?
              AND id IN (
                SELECT MAX(id) FROM provider_metrics
                WHERE project_dir = ?
                GROUP BY provider_name, metric_type
              )
            SQL
            [project_dir, project_dir]
          )

          result = {}
          rows.each do |row|
            provider = row["provider_name"]
            result[provider] ||= {}
            result[provider][row["metric_type"].to_sym] = row["value"]
            result[provider][:recorded_at] = row["recorded_at"]
          end

          result
        end

        # Load metrics for a specific provider
        #
        # @param provider_name [String] Provider name
        # @return [Hash] Metrics
        def load_provider_metrics(provider_name)
          rows = query(
            <<~SQL,
              SELECT metric_type, value, recorded_at
              FROM provider_metrics
              WHERE project_dir = ? AND provider_name = ?
              AND id IN (
                SELECT MAX(id) FROM provider_metrics
                WHERE project_dir = ? AND provider_name = ?
                GROUP BY metric_type
              )
            SQL
            [project_dir, provider_name, project_dir, provider_name]
          )

          metrics = {}
          rows.each do |row|
            metrics[row["metric_type"].to_sym] = row["value"]
          end
          metrics
        end

        # Save rate limit info for a provider
        #
        # @param provider_name [String] Provider name
        # @param rate_limits [Hash] Rate limit data
        def save_rate_limits(provider_name, rate_limits)
          now = current_timestamp

          rate_limits.each do |limit_type, info|
            next unless info.is_a?(Hash)

            # Convert Time values to strings
            limit_value = info[:limit] || info["limit"]
            remaining = info[:remaining] || info["remaining"]
            reset_at = info[:reset_at] || info["reset_at"]
            reset_at = reset_at.iso8601 if reset_at.is_a?(Time)

            upsert_rate_limit(
              provider_name: provider_name,
              limit_type: limit_type.to_s,
              limit_value: limit_value,
              remaining: remaining,
              reset_at: reset_at,
              updated_at: now
            )
          end

          Aidp.log_debug("provider_metrics_repository", "saved_rate_limits",
            provider: provider_name)
        end

        # Load rate limits for all providers
        #
        # @return [Hash] Map of provider_name => rate limits hash
        def load_rate_limits
          rows = query(
            "SELECT * FROM provider_rate_limits WHERE project_dir = ?",
            [project_dir]
          )

          result = {}
          rows.each do |row|
            provider = row["provider_name"]
            limit_type = row["limit_type"]

            result[provider] ||= {}
            result[provider][limit_type.to_sym] = {
              limit: row["limit_value"],
              remaining: row["remaining"],
              reset_at: parse_time(row["reset_at"])
            }
          end

          result
        end

        # Load rate limits for a specific provider
        #
        # @param provider_name [String] Provider name
        # @return [Hash] Rate limits
        def load_provider_rate_limits(provider_name)
          rows = query(
            "SELECT * FROM provider_rate_limits WHERE project_dir = ? AND provider_name = ?",
            [project_dir, provider_name]
          )

          limits = {}
          rows.each do |row|
            limits[row["limit_type"].to_sym] = {
              limit: row["limit_value"],
              remaining: row["remaining"],
              reset_at: parse_time(row["reset_at"])
            }
          end
          limits
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
        # @param metric_type [String] Metric type
        # @param limit [Integer] Max records
        # @return [Array<Hash>] Historical values
        def metrics_history(provider_name, metric_type, limit: 100)
          rows = query(
            <<~SQL,
              SELECT value, recorded_at
              FROM provider_metrics
              WHERE project_dir = ? AND provider_name = ? AND metric_type = ?
              ORDER BY recorded_at DESC
              LIMIT ?
            SQL
            [project_dir, provider_name, metric_type.to_s, limit]
          )

          rows.map do |row|
            { value: row["value"], recorded_at: row["recorded_at"] }
          end
        end

        private

        def upsert_rate_limit(provider_name:, limit_type:, limit_value:, remaining:, reset_at:, updated_at:)
          existing = query_one(
            "SELECT id FROM provider_rate_limits WHERE project_dir = ? AND provider_name = ? AND limit_type = ?",
            [project_dir, provider_name, limit_type]
          )

          if existing
            execute(
              <<~SQL,
                UPDATE provider_rate_limits SET
                  limit_value = ?, remaining = ?, reset_at = ?, updated_at = ?
                WHERE project_dir = ? AND provider_name = ? AND limit_type = ?
              SQL
              [limit_value, remaining, reset_at, updated_at, project_dir, provider_name, limit_type]
            )
          else
            execute(
              <<~SQL,
                INSERT INTO provider_rate_limits
                  (project_dir, provider_name, limit_type, limit_value, remaining, reset_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
              SQL
              [project_dir, provider_name, limit_type, limit_value, remaining, reset_at, updated_at]
            )
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
