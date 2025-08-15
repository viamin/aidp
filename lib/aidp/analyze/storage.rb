# frozen_string_literal: true

require "sqlite3"
require "json"
require "yaml"

module Aidp
  class AnalysisStorage
    # Database schema version
    SCHEMA_VERSION = 1

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
      @db_path = config[:db_path] || File.join(project_dir, ".aidp-analysis.db")
      @db = nil

      ensure_database_exists
    end

    # Store analysis result
    def store_analysis_result(step_name, data, options = {})
      ensure_connection

      timestamp = Time.now
      execution_id = options[:execution_id] || generate_execution_id

      # Store main analysis data
      analysis_data = {
        execution_id: execution_id,
        step_name: step_name,
        data: data,
        metadata: options[:metadata] || {},
        created_at: timestamp,
        updated_at: timestamp
      }

      # Insert or update analysis result
      @db.execute(
        "INSERT OR REPLACE INTO analysis_results (execution_id, step_name, data, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        execution_id,
        step_name,
        JSON.generate(data),
        JSON.generate(analysis_data[:metadata]),
        timestamp.to_i,
        timestamp.to_i
      )

      # Store metrics with indefinite retention
      store_metrics(execution_id, step_name, data, options)

      {
        execution_id: execution_id,
        step_name: step_name,
        stored_at: timestamp,
        success: true
      }
    rescue => e
      {
        success: false,
        error: e.message,
        execution_id: execution_id,
        step_name: step_name
      }
    end

    # Store metrics with indefinite retention
    def store_metrics(execution_id, step_name, data, options = {})
      ensure_connection

      timestamp = Time.now
      metrics = extract_metrics(data)

      metrics.each do |metric_name, metric_value|
        @db.execute(
          "INSERT INTO metrics (execution_id, step_name, metric_name, metric_value, metric_type, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          execution_id,
          step_name,
          metric_name,
          metric_value.to_s,
          metric_value.class.name,
          timestamp.to_i
        )
      end

      # Store aggregated metrics
      store_aggregated_metrics(execution_id, step_name, metrics, timestamp)
    end

    # Retrieve analysis result
    def get_analysis_result(execution_id, step_name = nil)
      ensure_connection

      result = if step_name
        # Get specific step result
        @db.execute(
          "SELECT * FROM analysis_results WHERE execution_id = ? AND step_name = ? ORDER BY updated_at DESC LIMIT 1",
          execution_id,
          step_name
        ).first
      else
        # Get all results for execution
        @db.execute(
          "SELECT * FROM analysis_results WHERE execution_id = ? ORDER BY updated_at DESC",
          execution_id
        )
      end

      return nil unless result

      if result.is_a?(Array) && result.length > 1
        # Multiple results
        result.map { |row| parse_analysis_result(row) }
      else
        # Single result
        row = result.is_a?(Array) ? result.first : result
        parse_analysis_result(row)
      end
    end

    # Retrieve metrics
    def get_metrics(execution_id = nil, step_name = nil, metric_name = nil, limit = 100)
      ensure_connection

      query = "SELECT * FROM metrics WHERE 1=1"
      params = []

      if execution_id
        query += " AND execution_id = ?"
        params << execution_id
      end

      if step_name
        query += " AND step_name = ?"
        params << step_name
      end

      if metric_name
        query += " AND metric_name = ?"
        params << metric_name
      end

      query += " ORDER BY created_at DESC LIMIT ?"
      params << limit

      results = @db.execute(query, *params)
      results.map { |row| parse_metric(row) }
    end

    # Get aggregated metrics
    def get_aggregated_metrics(execution_id = nil, step_name = nil, metric_name = nil)
      ensure_connection

      query = "SELECT * FROM aggregated_metrics WHERE 1=1"
      params = []

      if execution_id
        query += " AND execution_id = ?"
        params << execution_id
      end

      if step_name
        query += " AND step_name = ?"
        params << step_name
      end

      if metric_name
        query += " AND metric_name = ?"
        params << metric_name
      end

      query += " ORDER BY created_at DESC"

      results = @db.execute(query, *params)
      results.map { |row| parse_aggregated_metric(row) }
    end

    # Get execution history
    def get_execution_history(limit = 50)
      ensure_connection

      results = @db.execute(
        "SELECT DISTINCT execution_id, step_name, created_at, updated_at FROM analysis_results ORDER BY created_at DESC LIMIT ?",
        limit
      )

      results.map { |row| parse_execution_history(row) }
    end

    # Get analysis statistics
    def get_analysis_statistics
      ensure_connection

      stats = {}

      # Total executions
      total_executions = @db.execute("SELECT COUNT(DISTINCT execution_id) FROM analysis_results").first[0]
      stats[:total_executions] = total_executions

      # Total steps
      total_steps = @db.execute("SELECT COUNT(*) FROM analysis_results").first[0]
      stats[:total_steps] = total_steps

      # Steps by type
      steps_by_type = @db.execute("SELECT step_name, COUNT(*) FROM analysis_results GROUP BY step_name")
      stats[:steps_by_type] = steps_by_type.to_h

      # Total metrics
      total_metrics = @db.execute("SELECT COUNT(*) FROM metrics").first[0]
      stats[:total_metrics] = total_metrics

      # Metrics by type
      metrics_by_type = @db.execute("SELECT metric_name, COUNT(*) FROM metrics GROUP BY metric_name")
      stats[:metrics_by_type] = metrics_by_type.to_h

      # Date range
      date_range = @db.execute("SELECT MIN(created_at), MAX(created_at) FROM analysis_results").first
      stats[:date_range] = {
        earliest: date_range[0] ? Time.at(date_range[0]) : nil,
        latest: date_range[1] ? Time.at(date_range[1]) : nil
      }

      stats
    end

    # Force overwrite analysis data (retains metrics)
    def force_overwrite(execution_id, step_name, data, options = {})
      ensure_connection

      # Delete existing analysis result
      @db.execute(
        "DELETE FROM analysis_results WHERE execution_id = ? AND step_name = ?",
        execution_id,
        step_name
      )

      # Store new analysis result
      store_analysis_result(step_name, data, options.merge(execution_id: execution_id))
    end

    # Delete analysis data (retains metrics)
    def delete_analysis_data(execution_id = nil, step_name = nil)
      ensure_connection

      if execution_id && step_name
        @db.execute(
          "DELETE FROM analysis_results WHERE execution_id = ? AND step_name = ?",
          execution_id,
          step_name
        )
      elsif execution_id
        @db.execute("DELETE FROM analysis_results WHERE execution_id = ?", execution_id)
      elsif step_name
        @db.execute("DELETE FROM analysis_results WHERE step_name = ?", step_name)
      else
        @db.execute("DELETE FROM analysis_results")
      end

      {success: true, deleted_execution_id: execution_id, deleted_step_name: step_name}
    end

    # Export data
    def export_data(format = "json", options = {})
      ensure_connection

      data = {
        analysis_results: export_analysis_results(options),
        metrics: export_metrics(options),
        aggregated_metrics: export_aggregated_metrics(options),
        statistics: get_analysis_statistics
      }

      case format.downcase
      when "json"
        JSON.pretty_generate(data)
      when "yaml"
        YAML.dump(data)
      else
        raise "Unsupported export format: #{format}"
      end
    end

    # Import data
    def import_data(data, format = "json")
      ensure_connection

      parsed_data = case format.downcase
      when "json"
        JSON.parse(data)
      when "yaml"
        YAML.load(data)
      else
        raise "Unsupported import format: #{format}"
      end

      # Import analysis results
      parsed_data["analysis_results"]&.each do |result|
        @db.execute(
          "INSERT OR REPLACE INTO analysis_results (execution_id, step_name, data, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
          result["execution_id"],
          result["step_name"],
          result["data"],
          result["metadata"],
          result["created_at"],
          result["updated_at"]
        )
      end

      # Import metrics
      parsed_data["metrics"]&.each do |metric|
        @db.execute(
          "INSERT OR REPLACE INTO metrics (execution_id, step_name, metric_name, metric_value, metric_type, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          metric["execution_id"],
          metric["step_name"],
          metric["metric_name"],
          metric["metric_value"],
          metric["metric_type"],
          metric["created_at"]
        )
      end

      {success: true, imported_records: parsed_data.length}
    end

    # Close database connection
    def close
      @db&.close
      @db = nil
    end

    private

    def ensure_database_exists
      return if File.exist?(@db_path)

      @db = SQLite3::Database.new(@db_path)
      create_schema
    end

    def ensure_connection
      @db ||= SQLite3::Database.new(@db_path)
    end

    def create_schema
      # Create analysis_results table
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS analysis_results (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          data TEXT NOT NULL,
          metadata TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE(execution_id, step_name)
        )
      SQL

      # Create metrics table (indefinite retention)
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS metrics (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          metric_value TEXT NOT NULL,
          metric_type TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      SQL

      # Create aggregated_metrics table
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS aggregated_metrics (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          min_value REAL,
          max_value REAL,
          avg_value REAL,
          count INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      SQL

      # Create indexes
      @db.execute("CREATE INDEX IF NOT EXISTS idx_analysis_results_execution_id ON analysis_results(execution_id)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_analysis_results_step_name ON analysis_results(step_name)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_analysis_results_created_at ON analysis_results(created_at)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_metrics_execution_id ON metrics(execution_id)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_metrics_step_name ON metrics(step_name)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_metrics_metric_name ON metrics(metric_name)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_metrics_created_at ON metrics(created_at)")

      # Store schema version
      @db.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
      @db.execute("INSERT OR REPLACE INTO schema_version (version) VALUES (?)", SCHEMA_VERSION)
    end

    def generate_execution_id
      "exec_#{Time.now.to_i}_#{rand(1000)}"
    end

    def extract_metrics(data)
      metrics = {}

      case data
      when Hash
        data.each do |key, value|
          if value.is_a?(Numeric)
            metrics[key] = value
          elsif value.is_a?(Hash)
            metrics.merge!(extract_metrics(value))
          elsif value.is_a?(Array) && value.all?(Numeric)
            metrics["#{key}_count"] = value.length
            metrics["#{key}_sum"] = value.sum
            metrics["#{key}_avg"] = value.sum.to_f / value.length
          end
        end
      when Array
        metrics["count"] = data.length
        if data.all?(Numeric)
          metrics["sum"] = data.sum
          metrics["avg"] = data.sum.to_f / data.length
        end
      end

      metrics
    end

    def store_aggregated_metrics(execution_id, step_name, metrics, timestamp)
      ensure_connection

      metrics.each do |metric_name, metric_value|
        next unless metric_value.is_a?(Numeric)

        # Get existing aggregated metric
        existing = @db.execute(
          "SELECT * FROM aggregated_metrics WHERE execution_id = ? AND step_name = ? AND metric_name = ?",
          execution_id,
          step_name,
          metric_name
        ).first

        if existing
          # Update existing aggregated metric
          count = existing[7] + 1
          min_value = [existing[3], metric_value].min
          max_value = [existing[4], metric_value].max
          avg_value = ((existing[5] * existing[7]) + metric_value) / count

          @db.execute(
            "UPDATE aggregated_metrics SET min_value = ?, max_value = ?, avg_value = ?, count = ?, created_at = ? WHERE id = ?",
            min_value,
            max_value,
            avg_value,
            count,
            timestamp.to_i,
            existing[0]
          )
        else
          # Create new aggregated metric
          @db.execute(
            "INSERT INTO aggregated_metrics (execution_id, step_name, metric_name, min_value, max_value, avg_value, count, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            execution_id,
            step_name,
            metric_name,
            metric_value,
            metric_value,
            metric_value,
            1,
            timestamp.to_i
          )
        end
      end
    end

    def parse_analysis_result(row)
      return nil unless row

      {
        id: row[0],
        execution_id: row[1],
        step_name: row[2],
        data: JSON.parse(row[3]),
        metadata: JSON.parse(row[4] || "{}"),
        created_at: Time.at(row[5]),
        updated_at: Time.at(row[6])
      }
    end

    def parse_metric(row)
      return nil unless row

      {
        id: row[0],
        execution_id: row[1],
        step_name: row[2],
        metric_name: row[3],
        metric_value: row[4],
        metric_type: row[5],
        created_at: Time.at(row[6])
      }
    end

    def parse_aggregated_metric(row)
      return nil unless row

      {
        id: row[0],
        execution_id: row[1],
        step_name: row[2],
        metric_name: row[3],
        min_value: row[4],
        max_value: row[5],
        avg_value: row[6],
        count: row[7],
        created_at: Time.at(row[8])
      }
    end

    def parse_execution_history(row)
      return nil unless row

      {
        execution_id: row[0],
        step_name: row[1],
        created_at: Time.at(row[2]),
        updated_at: Time.at(row[3])
      }
    end

    def export_analysis_results(options = {})
      ensure_connection

      query = "SELECT * FROM analysis_results"
      params = []

      if options[:execution_id]
        query += " WHERE execution_id = ?"
        params << options[:execution_id]
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT ?"
        params << options[:limit]
      end

      results = @db.execute(query, *params)
      results.map { |row| parse_analysis_result(row) }
    end

    def export_metrics(options = {})
      ensure_connection

      query = "SELECT * FROM metrics"
      params = []

      if options[:execution_id]
        query += " WHERE execution_id = ?"
        params << options[:execution_id]
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT ?"
        params << options[:limit]
      end

      results = @db.execute(query, *params)
      results.map { |row| parse_metric(row) }
    end

    def export_aggregated_metrics(options = {})
      ensure_connection

      query = "SELECT * FROM aggregated_metrics"
      params = []

      if options[:execution_id]
        query += " WHERE execution_id = ?"
        params << options[:execution_id]
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT ?"
        params << options[:limit]
      end

      results = @db.execute(query, *params)
      results.map { |row| parse_aggregated_metric(row) }
    end
  end
end
