# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"

module Aidp
  class AnalysisDatabase
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
      @db_path = File.join(project_dir, ".aidp-analysis.db")
      ensure_database_exists
    end

    # Store analysis results with retention policies
    def store_analysis_result(step_name, data, metadata = {})
      db = connect

      # Store the main analysis result
      db.execute(
        "INSERT OR REPLACE INTO analysis_results (step_name, data, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [step_name, data.to_json, metadata.to_json, Time.now.iso8601, Time.now.iso8601]
      )

      # Store metrics for indefinite retention
      store_metrics(step_name, metadata[:metrics]) if metadata[:metrics]

      db.close
    end

    # Store metrics that should be retained indefinitely
    def store_metrics(step_name, metrics)
      db = connect

      metrics.each do |metric_name, value|
        db.execute(
          "INSERT OR REPLACE INTO analysis_metrics (step_name, metric_name, value, recorded_at) VALUES (?, ?, ?, ?)",
          [step_name, metric_name.to_s, value.to_json, Time.now.iso8601]
        )
      end

      db.close
    end

    # Store embedding vectors for future semantic analysis
    def store_embeddings(step_name, embeddings_data)
      db = connect

      db.execute(
        "INSERT OR REPLACE INTO embeddings (step_name, embeddings_data, created_at) VALUES (?, ?, ?)",
        [step_name, embeddings_data.to_json, Time.now.iso8601]
      )

      db.close
    end

    # Retrieve analysis results
    def get_analysis_result(step_name)
      db = connect
      result = db.execute("SELECT data, metadata, created_at, updated_at FROM analysis_results WHERE step_name = ?",
        [step_name]).first
      db.close

      return nil unless result

      {
        data: JSON.parse(result[0]),
        metadata: JSON.parse(result[1]),
        created_at: result[2],
        updated_at: result[3]
      }
    end

    # Retrieve metrics for a step
    def get_metrics(step_name)
      db = connect
      results = db.execute(
        "SELECT metric_name, value, recorded_at FROM analysis_metrics WHERE step_name = ? ORDER BY recorded_at DESC", [step_name]
      )
      db.close

      results.map do |row|
        {
          metric_name: row[0],
          value: JSON.parse(row[1]),
          recorded_at: row[2]
        }
      end
    end

    # Get all metrics for trend analysis
    def get_all_metrics
      db = connect
      results = db.execute("SELECT step_name, metric_name, value, recorded_at FROM analysis_metrics ORDER BY recorded_at DESC")
      db.close

      results.map do |row|
        {
          step_name: row[0],
          metric_name: row[1],
          value: JSON.parse(row[2]),
          recorded_at: row[2]
        }
      end
    end

    # Force overwrite analysis data (for --force/--rerun flags)
    def force_overwrite(step_name, data, metadata = {})
      db = connect

      # Delete existing data
      db.execute("DELETE FROM analysis_results WHERE step_name = ?", [step_name])
      db.execute("DELETE FROM embeddings WHERE step_name = ?", [step_name])

      # Store new data
      db.execute(
        "INSERT INTO analysis_results (step_name, data, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        [step_name, data.to_json, metadata.to_json, Time.now.iso8601, Time.now.iso8601]
      )

      # Store metrics (these are retained indefinitely)
      store_metrics(step_name, metadata[:metrics]) if metadata[:metrics]

      db.close
    end

    # Delete analysis data (for user cleanup)
    def delete_analysis_data(step_name)
      db = connect
      db.execute("DELETE FROM analysis_results WHERE step_name = ?", [step_name])
      db.execute("DELETE FROM embeddings WHERE step_name = ?", [step_name])
      # NOTE: metrics are NOT deleted as they should be retained indefinitely
      db.close
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

      stats = {
        total_analysis_results: db.execute("SELECT COUNT(*) FROM analysis_results").first[0],
        total_metrics: db.execute("SELECT COUNT(*) FROM analysis_metrics").first[0],
        total_embeddings: db.execute("SELECT COUNT(*) FROM embeddings").first[0],
        steps_analyzed: db.execute("SELECT DISTINCT step_name FROM analysis_results").map { |row| row[0] },
        oldest_metric: db.execute("SELECT MIN(recorded_at) FROM analysis_metrics").first[0],
        newest_metric: db.execute("SELECT MAX(recorded_at) FROM analysis_metrics").first[0]
      }

      db.close
      stats
    end

    private

    def ensure_database_exists
      return if File.exist?(@db_path)

      db = SQLite3::Database.new(@db_path)

      # Create analysis_results table
      db.execute(<<~SQL)
        CREATE TABLE analysis_results (
          step_name TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          metadata TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      SQL

      # Create analysis_metrics table (indefinite retention)
      db.execute(<<~SQL)
        CREATE TABLE analysis_metrics (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          value TEXT NOT NULL,
          recorded_at TEXT NOT NULL,
          UNIQUE(step_name, metric_name, recorded_at)
        )
      SQL

      # Create embeddings table (for future semantic analysis)
      db.execute(<<~SQL)
        CREATE TABLE embeddings (
          step_name TEXT PRIMARY KEY,
          embeddings_data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      SQL

      # Create indexes for better performance
      db.execute("CREATE INDEX idx_analysis_metrics_step_name ON analysis_metrics(step_name)")
      db.execute("CREATE INDEX idx_analysis_metrics_recorded_at ON analysis_metrics(recorded_at)")
      db.execute("CREATE INDEX idx_analysis_results_updated_at ON analysis_results(updated_at)")

      db.close
    end

    def connect
      SQLite3::Database.new(@db_path)
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
