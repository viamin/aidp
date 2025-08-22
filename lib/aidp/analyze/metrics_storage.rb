# frozen_string_literal: true

require "pg"
require "json"

module Aidp
  module Analyze
    class MetricsStorage
      # Database schema version
      SCHEMA_VERSION = 1

      def initialize(project_dir = Dir.pwd, db_config = nil)
        @project_dir = project_dir
        @db_config = db_config || default_db_config
        @db = nil

        ensure_database_exists
      end

      # Store step execution metrics
      def store_step_metrics(step_name, provider_name, duration, success, metadata = {})
        ensure_connection

        timestamp = Time.now

        result = @db.exec_params(
          "INSERT INTO step_executions (step_name, provider_name, duration, success, metadata, created_at) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
          [step_name, provider_name, duration, success, metadata.to_json, timestamp]
        )

        {
          id: result[0]["id"],
          step_name: step_name,
          provider_name: provider_name,
          duration: duration,
          success: success,
          stored_at: timestamp
        }
      end

      # Store provider activity metrics
      def store_provider_activity(provider_name, step_name, activity_summary)
        ensure_connection

        timestamp = Time.now

        result = @db.exec_params(
          "INSERT INTO provider_activities (provider_name, step_name, start_time, end_time, duration, final_state, stuck_detected, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
          [
            provider_name,
            step_name,
            activity_summary[:start_time],
            activity_summary[:end_time],
            activity_summary[:duration],
            activity_summary[:final_state].to_s,
            activity_summary[:stuck_detected],
            timestamp
          ]
        )

        {
          id: result[0]["id"],
          provider_name: provider_name,
          step_name: step_name,
          stored_at: timestamp
        }
      end

      # Get step execution statistics
      def get_step_statistics(step_name = nil, provider_name = nil, limit = 100)
        ensure_connection

        query = "SELECT * FROM step_executions WHERE 1=1"
        params = []
        param_index = 1

        if step_name
          query += " AND step_name = $#{param_index}"
          params << step_name
          param_index += 1
        end

        if provider_name
          query += " AND provider_name = $#{param_index}"
          params << provider_name
          param_index += 1
        end

        query += " ORDER BY created_at DESC LIMIT $#{param_index}"
        params << limit

        results = @db.exec_params(query, params)
        results.map { |row| parse_step_execution(row) }
      end

      # Get provider activity statistics
      def get_provider_activity_statistics(provider_name = nil, step_name = nil, limit = 100)
        ensure_connection

        query = "SELECT * FROM provider_activities WHERE 1=1"
        params = []
        param_index = 1

        if provider_name
          query += " AND provider_name = $#{param_index}"
          params << provider_name
          param_index += 1
        end

        if step_name
          query += " AND step_name = $#{param_index}"
          params << step_name
          param_index += 1
        end

        query += " ORDER BY created_at DESC LIMIT $#{param_index}"
        params << limit

        results = @db.exec_params(query, params)
        results.map { |row| parse_provider_activity(row) }
      end

      # Calculate timeout recommendations based on p95 of execution times
      def calculate_timeout_recommendations
        ensure_connection

        recommendations = {}

        # Get all step names
        step_names = @db.exec("SELECT DISTINCT step_name FROM step_executions WHERE success = true")

        step_names.each do |row|
          step_name = row["step_name"]

          # Get successful executions for this step
          durations = @db.exec_params(
            "SELECT duration FROM step_executions WHERE step_name = $1 AND success = true ORDER BY duration",
            [step_name]
          ).map { |r| r["duration"].to_f }

          next if durations.empty?

          # Calculate p95
          p95_index = (durations.length * 0.95).ceil - 1
          p95_duration = durations[p95_index]

          # Round up to nearest second and add 10% buffer
          recommended_timeout = (p95_duration * 1.1).ceil

          recommendations[step_name] = {
            p95_duration: p95_duration,
            recommended_timeout: recommended_timeout,
            sample_count: durations.length,
            min_duration: durations.first,
            max_duration: durations.last,
            avg_duration: durations.sum.to_f / durations.length
          }
        end

        recommendations
      end

      # Get overall metrics summary
      def get_metrics_summary
        ensure_connection

        summary = {}

        # Total executions
        total_executions = @db.exec("SELECT COUNT(*) FROM step_executions").first["count"].to_i
        summary[:total_executions] = total_executions

        # Successful executions
        successful_executions = @db.exec("SELECT COUNT(*) FROM step_executions WHERE success = true").first["count"].to_i
        summary[:successful_executions] = successful_executions

        # Success rate
        summary[:success_rate] = (total_executions > 0) ? (successful_executions.to_f / total_executions * 100).round(2) : 0

        # Average duration
        avg_duration = @db.exec("SELECT AVG(duration) FROM step_executions WHERE success = true").first["avg"]
        summary[:average_duration] = avg_duration ? avg_duration.to_f.round(2) : 0

        # Stuck detections
        stuck_count = @db.exec("SELECT COUNT(*) FROM provider_activities WHERE stuck_detected = true").first["count"].to_i
        summary[:stuck_detections] = stuck_count

        # Date range
        date_range = @db.exec("SELECT MIN(created_at), MAX(created_at) FROM step_executions").first
        if date_range && date_range["min"]
          summary[:date_range] = {
            start: Time.parse(date_range["min"]),
            end: Time.parse(date_range["max"])
          }
        end

        summary
      end

      # Clean up old metrics data
      def cleanup_old_metrics(retention_days = 30)
        ensure_connection

        cutoff_time = Time.now - (retention_days * 24 * 60 * 60)

        # Delete old step executions
        deleted_executions = @db.exec_params(
          "DELETE FROM step_executions WHERE created_at < $1 RETURNING id",
          [cutoff_time]
        ).ntuples

        # Delete old provider activities
        deleted_activities = @db.exec_params(
          "DELETE FROM provider_activities WHERE created_at < $1 RETURNING id",
          [cutoff_time]
        ).ntuples

        {
          deleted_executions: deleted_executions,
          deleted_activities: deleted_activities,
          cutoff_time: cutoff_time
        }
      end

      # Export metrics data
      def export_metrics(format = :json)
        ensure_connection

        case format
        when :json
          {
            step_executions: get_step_statistics(nil, nil, 1000),
            provider_activities: get_provider_activity_statistics(nil, nil, 1000),
            summary: get_metrics_summary,
            recommendations: calculate_timeout_recommendations,
            exported_at: Time.now.iso8601
          }
        when :csv
          # TODO: Implement CSV export
          raise NotImplementedError, "CSV export not yet implemented"
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end
      end

      private

      def default_db_config
        {
          host: ENV["AIDP_DB_HOST"] || "localhost",
          port: ENV["AIDP_DB_PORT"] || 5432,
          dbname: ENV["AIDP_DB_NAME"] || "aidp",
          user: ENV["AIDP_DB_USER"] || ENV["USER"],
          password: ENV["AIDP_DB_PASSWORD"]
        }
      end

      def ensure_connection
        return if @db

        @db = PG.connect(@db_config)
        @db.type_map_for_results = PG::BasicTypeMapForResults.new(@db)
      end

      def ensure_database_exists
        ensure_connection

        # Create step_executions table if it doesn't exist
        @db.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS step_executions (
            id SERIAL PRIMARY KEY,
            step_name TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            duration REAL NOT NULL,
            success BOOLEAN NOT NULL,
            metadata JSONB,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL
          )
        SQL

        # Create provider_activities table if it doesn't exist
        @db.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS provider_activities (
            id SERIAL PRIMARY KEY,
            provider_name TEXT NOT NULL,
            step_name TEXT NOT NULL,
            start_time TIMESTAMP WITH TIME ZONE,
            end_time TIMESTAMP WITH TIME ZONE,
            duration REAL,
            final_state TEXT,
            stuck_detected BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL
          )
        SQL

        # Create indexes separately
        @db.exec("CREATE INDEX IF NOT EXISTS idx_step_executions_step_name ON step_executions(step_name)")
        @db.exec("CREATE INDEX IF NOT EXISTS idx_step_executions_provider_name ON step_executions(provider_name)")
        @db.exec("CREATE INDEX IF NOT EXISTS idx_step_executions_created_at ON step_executions(created_at)")
        @db.exec("CREATE INDEX IF NOT EXISTS idx_provider_activities_provider_name ON provider_activities(provider_name)")
        @db.exec("CREATE INDEX IF NOT EXISTS idx_provider_activities_step_name ON provider_activities(step_name)")
        @db.exec("CREATE INDEX IF NOT EXISTS idx_provider_activities_created_at ON provider_activities(created_at)")

        # Create metrics_schema_version table if it doesn't exist
        @db.exec("CREATE TABLE IF NOT EXISTS metrics_schema_version (version INTEGER NOT NULL)")
        @db.exec_params("INSERT INTO metrics_schema_version (version) VALUES ($1) ON CONFLICT DO NOTHING", [SCHEMA_VERSION])
      end

      def parse_step_execution(row)
        {
          id: row["id"].to_i,
          step_name: row["step_name"],
          provider_name: row["provider_name"],
          duration: row["duration"].to_f,
          success: row["success"],
          metadata: row["metadata"] ? JSON.parse(row["metadata"]) : {},
          created_at: Time.parse(row["created_at"])
        }
      end

      def parse_provider_activity(row)
        {
          id: row["id"].to_i,
          provider_name: row["provider_name"],
          step_name: row["step_name"],
          start_time: row["start_time"] ? Time.parse(row["start_time"]) : nil,
          end_time: row["end_time"] ? Time.parse(row["end_time"]) : nil,
          duration: row["duration"].to_f,
          final_state: row["final_state"]&.to_sym,
          stuck_detected: row["stuck_detected"],
          created_at: Time.parse(row["created_at"])
        }
      end
    end
  end
end
