# frozen_string_literal: true

require "pg"
require "json"
require "fileutils"

module Aidp
  class AnalysisDatabase
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
      ensure_database_exists
    end

    # Store analysis results with retention policies
    def store_analysis_result(step_name, data, metadata = {})
      db = connect

      # Store the main analysis result
      db.exec_params(
        <<~SQL,
          INSERT INTO analysis_results (step_name, data, metadata, created_at, updated_at)
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (step_name)
          DO UPDATE SET
            data = EXCLUDED.data,
            metadata = EXCLUDED.metadata,
            updated_at = EXCLUDED.updated_at
        SQL
        [step_name, data.to_json, metadata.to_json, Time.now, Time.now]
      )

      # Store metrics for indefinite retention
      store_metrics(step_name, metadata[:metrics]) if metadata[:metrics]
    end

    # Store metrics that should be retained indefinitely
    def store_metrics(step_name, metrics)
      db = connect

      metrics.each do |metric_name, value|
        db.exec_params(
          <<~SQL,
            INSERT INTO analysis_metrics (step_name, metric_name, value, recorded_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (step_name, metric_name, recorded_at)
            DO UPDATE SET value = EXCLUDED.value
          SQL
          [step_name, metric_name.to_s, value.to_json, Time.now]
        )
      end
    end

    # Store embedding vectors for future semantic analysis
    def store_embeddings(step_name, embeddings_data)
      db = connect

      db.exec_params(
        <<~SQL,
          INSERT INTO embeddings (step_name, embeddings_data, created_at)
          VALUES ($1, $2, $3)
          ON CONFLICT (step_name)
          DO UPDATE SET
            embeddings_data = EXCLUDED.embeddings_data,
            created_at = EXCLUDED.created_at
        SQL
        [step_name, embeddings_data.to_json, Time.now]
      )
    end

    # Retrieve analysis results
    def get_analysis_result(step_name)
      db = connect
      result = db.exec_params(
        "SELECT data, metadata, created_at, updated_at FROM analysis_results WHERE step_name = $1",
        [step_name]
      ).first

      return nil unless result

      {
        data: JSON.parse(result["data"]),
        metadata: JSON.parse(result["metadata"]),
        created_at: result["created_at"],
        updated_at: result["updated_at"]
      }
    end

    # Retrieve metrics for a step
    def get_metrics(step_name)
      db = connect
      results = db.exec_params(
        "SELECT metric_name, value, recorded_at FROM analysis_metrics WHERE step_name = $1 ORDER BY recorded_at DESC",
        [step_name]
      )

      results.map do |row|
        {
          metric_name: row["metric_name"],
          value: JSON.parse(row["value"]),
          recorded_at: row["recorded_at"]
        }
      end
    end

    # Get all metrics for trend analysis
    def get_all_metrics
      db = connect
      results = db.exec("SELECT step_name, metric_name, value, recorded_at FROM analysis_metrics ORDER BY recorded_at DESC")

      results.map do |row|
        {
          step_name: row["step_name"],
          metric_name: row["metric_name"],
          value: JSON.parse(row["value"]),
          recorded_at: row["recorded_at"]
        }
      end
    end

    # Force overwrite analysis data (for --force/--rerun flags)
    def force_overwrite(step_name, data, metadata = {})
      db = connect

      # Delete existing data
      db.exec_params("DELETE FROM analysis_results WHERE step_name = $1", [step_name])
      db.exec_params("DELETE FROM embeddings WHERE step_name = $1", [step_name])

      # Store new data
      db.exec_params(
        <<~SQL,
          INSERT INTO analysis_results (step_name, data, metadata, created_at, updated_at)
          VALUES ($1, $2, $3, $4, $5)
        SQL
        [step_name, data.to_json, metadata.to_json, Time.now, Time.now]
      )

      # Store metrics (these are retained indefinitely)
      store_metrics(step_name, metadata[:metrics]) if metadata[:metrics]
    end

    # Delete analysis data (for user cleanup)
    def delete_analysis_data(step_name)
      db = connect
      db.exec_params("DELETE FROM analysis_results WHERE step_name = $1", [step_name])
      db.exec_params("DELETE FROM embeddings WHERE step_name = $1", [step_name])
      # NOTE: metrics are NOT deleted as they should be retained indefinitely
    end

    # Export data in different formats
    def export_data(step_name, format = "json")
      result = get_analysis_result(step_name)
      return nil unless result

      case format.downcase
      when "json"
        result.to_json
      when "csv"
        export_to_csv(result)
      else
        raise "Unsupported export format: #{format}"
      end
    end

    # Get database statistics
    def get_statistics
      db = connect

      {
        total_analysis_results: db.exec("SELECT COUNT(*) FROM analysis_results").first["count"].to_i,
        total_metrics: db.exec("SELECT COUNT(*) FROM analysis_metrics").first["count"].to_i,
        total_embeddings: db.exec("SELECT COUNT(*) FROM embeddings").first["count"].to_i,
        steps_analyzed: db.exec("SELECT DISTINCT step_name FROM analysis_results").map { |row| row["step_name"] },
        oldest_metric: db.exec("SELECT MIN(recorded_at) FROM analysis_metrics").first["min"],
        newest_metric: db.exec("SELECT MAX(recorded_at) FROM analysis_metrics").first["max"]
      }
    end

    private

    def ensure_database_exists
      db = connect
      create_schema(db)
    end

    def connect
      @db ||= PG.connect(
        host: ENV["AIDP_DB_HOST"] || "localhost",
        port: ENV["AIDP_DB_PORT"] || 5432,
        dbname: ENV["AIDP_DB_NAME"] || "aidp",
        user: ENV["AIDP_DB_USER"] || ENV["USER"],
        password: ENV["AIDP_DB_PASSWORD"]
      )
      @db.type_map_for_results = PG::BasicTypeMapForResults.new(@db)
      @db
    end

    def create_schema(db)
      # Create analysis_results table
      db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS analysis_results (
          step_name TEXT PRIMARY KEY,
          data JSONB NOT NULL,
          metadata JSONB,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL,
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL
        )
      SQL

      # Create analysis_metrics table (indefinite retention)
      db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS analysis_metrics (
          id SERIAL PRIMARY KEY,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          value JSONB NOT NULL,
          recorded_at TIMESTAMP WITH TIME ZONE NOT NULL,
          UNIQUE(step_name, metric_name, recorded_at)
        )
      SQL

      # Create embeddings table (for future semantic analysis)
      db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS embeddings (
          step_name TEXT PRIMARY KEY,
          embeddings_data JSONB NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL
        )
      SQL

      # Create indexes for better performance
      db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_metrics_step_name ON analysis_metrics(step_name)")
      db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_metrics_recorded_at ON analysis_metrics(recorded_at)")
      db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_results_updated_at ON analysis_results(updated_at)")
    end

    def export_to_csv(data)
      require "csv"

      # For now, export a simplified CSV format
      # This can be enhanced based on specific data structures
      CSV.generate do |csv|
        csv << %w[Field Value]
        csv << ["created_at", data[:created_at]]
        csv << ["updated_at", data[:updated_at]]

        # Add metadata fields
        data[:metadata].each do |key, value|
          csv << ["metadata_#{key}", value]
        end

        # Add data summary
        if data[:data].is_a?(Hash)
          data[:data].each do |key, value|
            csv << ["data_#{key}", value.to_s[0..100]] # Truncate long values
          end
        end
      end
    end
  end
end
