# frozen_string_literal: true

require "pg"
require "json"
require "yaml"

module Aidp
  class AnalysisStorage
    # Database schema version
    SCHEMA_VERSION = 1

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
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
      @db.exec_params(
        <<~SQL,
          INSERT INTO analysis_results (execution_id, step_name, data, metadata, created_at, updated_at)
          VALUES ($1, $2, $3, $4, $5, $6)
          ON CONFLICT (execution_id, step_name)
          DO UPDATE SET
            data = EXCLUDED.data,
            metadata = EXCLUDED.metadata,
            updated_at = EXCLUDED.updated_at
        SQL
        [
          execution_id,
          step_name,
          data.to_json,
          analysis_data[:metadata].to_json,
          timestamp,
          timestamp
        ]
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
        @db.exec_params(
          <<~SQL,
            INSERT INTO metrics (execution_id, step_name, metric_name, metric_value, metric_type, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
          SQL
          [
            execution_id,
            step_name,
            metric_name,
            metric_value.to_s,
            metric_value.class.name,
            timestamp
          ]
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
        @db.exec_params(
          <<~SQL,
            SELECT * FROM analysis_results
            WHERE execution_id = $1 AND step_name = $2
            ORDER BY updated_at DESC
            LIMIT 1
          SQL
          [execution_id, step_name]
        )
      else
        # Get all results for execution
        @db.exec_params(
          <<~SQL,
            SELECT * FROM analysis_results
            WHERE execution_id = $1
            ORDER BY updated_at DESC
          SQL
          [execution_id]
        )
      end

      return nil if result.ntuples.zero?

      if result.ntuples > 1
        # Multiple results
        result.map { |row| parse_analysis_result(row) }
      else
        # Single result
        parse_analysis_result(result[0])
      end
    end

    # Retrieve metrics
    def get_metrics(execution_id = nil, step_name = nil, metric_name = nil, limit = 100)
      ensure_connection

      query = "SELECT * FROM metrics WHERE 1=1"
      params = []
      param_index = 1

      if execution_id
        query += " AND execution_id = $#{param_index}"
        params << execution_id
        param_index += 1
      end

      if step_name
        query += " AND step_name = $#{param_index}"
        params << step_name
        param_index += 1
      end

      if metric_name
        query += " AND metric_name = $#{param_index}"
        params << metric_name
        param_index += 1
      end

      query += " ORDER BY created_at DESC"
      query += " LIMIT $#{param_index}"
      params << limit

      results = @db.exec_params(query, params)
      results.map { |row| parse_metric(row) }
    end

    # Get aggregated metrics
    def get_aggregated_metrics(execution_id = nil, step_name = nil, metric_name = nil)
      ensure_connection

      query = "SELECT * FROM aggregated_metrics WHERE 1=1"
      params = []
      param_index = 1

      if execution_id
        query += " AND execution_id = $#{param_index}"
        params << execution_id
        param_index += 1
      end

      if step_name
        query += " AND step_name = $#{param_index}"
        params << step_name
        param_index += 1
      end

      if metric_name
        query += " AND metric_name = $#{param_index}"
        params << metric_name
        param_index += 1
      end

      query += " ORDER BY created_at DESC"

      results = @db.exec_params(query, params)
      results.map { |row| parse_aggregated_metric(row) }
    end

    # Get execution history
    def get_execution_history(limit = 50)
      ensure_connection

      results = @db.exec_params(
        <<~SQL,
          SELECT DISTINCT execution_id, step_name, created_at, updated_at
          FROM analysis_results
          ORDER BY created_at DESC
          LIMIT $1
        SQL
        [limit]
      )

      results.map { |row| parse_execution_history(row) }
    end

    # Get analysis statistics
    def get_analysis_statistics
      ensure_connection

      stats = {}

      # Total executions
      total_executions = @db.exec("SELECT COUNT(DISTINCT execution_id) FROM analysis_results").first["count"].to_i
      stats[:total_executions] = total_executions

      # Total steps
      total_steps = @db.exec("SELECT COUNT(*) FROM analysis_results").first["count"].to_i
      stats[:total_steps] = total_steps

      # Steps by type
      steps_by_type = @db.exec("SELECT step_name, COUNT(*) FROM analysis_results GROUP BY step_name")
      stats[:steps_by_type] = steps_by_type.each_with_object({}) do |row, hash|
        hash[row["step_name"]] = row["count"].to_i
      end

      # Total metrics
      total_metrics = @db.exec("SELECT COUNT(*) FROM metrics").first["count"].to_i
      stats[:total_metrics] = total_metrics

      # Metrics by type
      metrics_by_type = @db.exec("SELECT metric_name, COUNT(*) FROM metrics GROUP BY metric_name")
      stats[:metrics_by_type] = metrics_by_type.each_with_object({}) do |row, hash|
        hash[row["metric_name"]] = row["count"].to_i
      end

      # Date range
      date_range = @db.exec("SELECT MIN(created_at), MAX(created_at) FROM analysis_results").first
      stats[:date_range] = {
        earliest: date_range["min"] ? Time.parse(date_range["min"]) : nil,
        latest: date_range["max"] ? Time.parse(date_range["max"]) : nil
      }

      stats
    end

    # Force overwrite analysis data (retains metrics)
    def force_overwrite(execution_id, step_name, data, options = {})
      ensure_connection

      # Delete existing analysis result
      @db.exec_params(
        "DELETE FROM analysis_results WHERE execution_id = $1 AND step_name = $2",
        [execution_id, step_name]
      )

      # Store new analysis result
      store_analysis_result(step_name, data, options.merge(execution_id: execution_id))
    end

    # Delete analysis data (retains metrics)
    def delete_analysis_data(execution_id = nil, step_name = nil)
      ensure_connection

      if execution_id && step_name
        @db.exec_params(
          "DELETE FROM analysis_results WHERE execution_id = $1 AND step_name = $2",
          [execution_id, step_name]
        )
      elsif execution_id
        @db.exec_params("DELETE FROM analysis_results WHERE execution_id = $1", [execution_id])
      elsif step_name
        @db.exec_params("DELETE FROM analysis_results WHERE step_name = $1", [step_name])
      else
        @db.exec("DELETE FROM analysis_results")
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
        YAML.safe_load(data)
      else
        raise "Unsupported import format: #{format}"
      end

      # Import analysis results
      parsed_data["analysis_results"]&.each do |result|
        @db.exec_params(
          <<~SQL,
            INSERT INTO analysis_results (execution_id, step_name, data, metadata, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (execution_id, step_name)
            DO UPDATE SET
              data = EXCLUDED.data,
              metadata = EXCLUDED.metadata,
              updated_at = EXCLUDED.updated_at
          SQL
          [
            result["execution_id"],
            result["step_name"],
            result["data"],
            result["metadata"],
            result["created_at"],
            result["updated_at"]
          ]
        )
      end

      # Import metrics
      parsed_data["metrics"]&.each do |metric|
        @db.exec_params(
          <<~SQL,
            INSERT INTO metrics (execution_id, step_name, metric_name, metric_value, metric_type, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT DO NOTHING
          SQL
          [
            metric["execution_id"],
            metric["step_name"],
            metric["metric_name"],
            metric["metric_value"],
            metric["metric_type"],
            metric["created_at"]
          ]
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
      ensure_connection
      create_schema
    end

    def ensure_connection
      return if @db

      @db = PG.connect(
        host: ENV["AIDP_DB_HOST"] || "localhost",
        port: ENV["AIDP_DB_PORT"] || 5432,
        dbname: ENV["AIDP_DB_NAME"] || "aidp",
        user: ENV["AIDP_DB_USER"] || ENV["USER"],
        password: ENV["AIDP_DB_PASSWORD"]
      )
      @db.type_map_for_results = PG::BasicTypeMapForResults.new(@db)
    end

    def create_schema
      # Create analysis_results table
      @db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS analysis_results (
          id SERIAL PRIMARY KEY,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          data JSONB NOT NULL,
          metadata JSONB,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL,
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
          UNIQUE(execution_id, step_name)
        )
      SQL

      # Create metrics table (indefinite retention)
      @db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS metrics (
          id SERIAL PRIMARY KEY,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          metric_value TEXT NOT NULL,
          metric_type TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL
        )
      SQL

      # Create aggregated_metrics table
      @db.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS aggregated_metrics (
          id SERIAL PRIMARY KEY,
          execution_id TEXT NOT NULL,
          step_name TEXT NOT NULL,
          metric_name TEXT NOT NULL,
          min_value DOUBLE PRECISION,
          max_value DOUBLE PRECISION,
          avg_value DOUBLE PRECISION,
          count INTEGER NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL
        )
      SQL

      # Create indexes
      @db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_results_execution_id ON analysis_results(execution_id)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_results_step_name ON analysis_results(step_name)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_analysis_results_created_at ON analysis_results(created_at)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_metrics_execution_id ON metrics(execution_id)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_metrics_step_name ON metrics(step_name)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_metrics_metric_name ON metrics(metric_name)")
      @db.exec("CREATE INDEX IF NOT EXISTS idx_metrics_created_at ON metrics(created_at)")

      # Store schema version
      @db.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
      @db.exec_params("INSERT INTO schema_version (version) VALUES ($1) ON CONFLICT DO NOTHING", [SCHEMA_VERSION])
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
        existing = @db.exec_params(
          <<~SQL,
            SELECT * FROM aggregated_metrics
            WHERE execution_id = $1 AND step_name = $2 AND metric_name = $3
          SQL
          [execution_id, step_name, metric_name]
        ).first

        if existing
          # Update existing aggregated metric
          count = existing["count"].to_i + 1
          min_value = [existing["min_value"].to_f, metric_value].min
          max_value = [existing["max_value"].to_f, metric_value].max
          avg_value = ((existing["avg_value"].to_f * existing["count"].to_i) + metric_value) / count

          @db.exec_params(
            <<~SQL,
              UPDATE aggregated_metrics
              SET min_value = $1, max_value = $2, avg_value = $3, count = $4, created_at = $5
              WHERE id = $6
            SQL
            [min_value, max_value, avg_value, count, timestamp, existing["id"]]
          )
        else
          # Create new aggregated metric
          @db.exec_params(
            <<~SQL,
              INSERT INTO aggregated_metrics (execution_id, step_name, metric_name, min_value, max_value, avg_value, count, created_at)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            SQL
            [execution_id, step_name, metric_name, metric_value, metric_value, metric_value, 1, timestamp]
          )
        end
      end
    end

    def parse_analysis_result(row)
      return nil unless row

      {
        id: row["id"].to_i,
        execution_id: row["execution_id"],
        step_name: row["step_name"],
        data: JSON.parse(row["data"]),
        metadata: JSON.parse(row["metadata"] || "{}"),
        created_at: Time.parse(row["created_at"]),
        updated_at: Time.parse(row["updated_at"])
      }
    end

    def parse_metric(row)
      return nil unless row

      {
        id: row["id"].to_i,
        execution_id: row["execution_id"],
        step_name: row["step_name"],
        metric_name: row["metric_name"],
        metric_value: row["metric_value"],
        metric_type: row["metric_type"],
        created_at: Time.parse(row["created_at"])
      }
    end

    def parse_aggregated_metric(row)
      return nil unless row

      {
        id: row["id"].to_i,
        execution_id: row["execution_id"],
        step_name: row["step_name"],
        metric_name: row["metric_name"],
        min_value: row["min_value"].to_f,
        max_value: row["max_value"].to_f,
        avg_value: row["avg_value"].to_f,
        count: row["count"].to_i,
        created_at: Time.parse(row["created_at"])
      }
    end

    def parse_execution_history(row)
      return nil unless row

      {
        execution_id: row["execution_id"],
        step_name: row["step_name"],
        created_at: Time.parse(row["created_at"]),
        updated_at: Time.parse(row["updated_at"])
      }
    end

    def export_analysis_results(options = {})
      ensure_connection

      query = "SELECT * FROM analysis_results"
      params = []
      param_index = 1

      if options[:execution_id]
        query += " WHERE execution_id = $#{param_index}"
        params << options[:execution_id]
        param_index += 1
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT $#{param_index}"
        params << options[:limit]
      end

      results = @db.exec_params(query, params)
      results.map { |row| parse_analysis_result(row) }
    end

    def export_metrics(options = {})
      ensure_connection

      query = "SELECT * FROM metrics"
      params = []
      param_index = 1

      if options[:execution_id]
        query += " WHERE execution_id = $#{param_index}"
        params << options[:execution_id]
        param_index += 1
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT $#{param_index}"
        params << options[:limit]
      end

      results = @db.exec_params(query, params)
      results.map { |row| parse_metric(row) }
    end

    def export_aggregated_metrics(options = {})
      ensure_connection

      query = "SELECT * FROM aggregated_metrics"
      params = []
      param_index = 1

      if options[:execution_id]
        query += " WHERE execution_id = $#{param_index}"
        params << options[:execution_id]
        param_index += 1
      end

      query += " ORDER BY created_at DESC"

      if options[:limit]
        query += " LIMIT $#{param_index}"
        params << options[:limit]
      end

      results = @db.exec_params(query, params)
      results.map { |row| parse_aggregated_metric(row) }
    end
  end
end
