# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Aidp
  # Handles database migrations for AIDP
  class DatabaseMigration
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
      @old_db_path = File.join(project_dir, ".aidp-analysis.db")
      @new_db_path = File.join(project_dir, ".aidp.db")
    end

    # Migrate database from old to new format
    def migrate
      # If neither database exists, create new one directly
      if !File.exist?(@old_db_path) && !File.exist?(@new_db_path)
        create_new_database
        return true
      end

      # If new database already exists, skip migration
      if File.exist?(@new_db_path)
        puts "Database .aidp.db already exists, skipping migration"
        return false
      end

      # Rename old database to new name
      FileUtils.mv(@old_db_path, @new_db_path)

      # Open database connection
      db = SQLite3::Database.new(@new_db_path)

      # Create new tables for job management
      create_job_tables(db)

      # Close connection
      db.close

      true
    rescue => e
      puts "Error during database migration: #{e.message}"
      # Try to restore old database if something went wrong
      if File.exist?(@new_db_path) && !File.exist?(@old_db_path)
        FileUtils.mv(@new_db_path, @old_db_path)
      end
      false
    end

    private

    def create_new_database
      db = SQLite3::Database.new(@new_db_path)

      # Create original tables
      create_original_tables(db)

      # Create new job tables
      create_job_tables(db)

      db.close
    end

    def create_original_tables(db)
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

      # Create analysis_metrics table
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

      # Create embeddings table
      db.execute(<<~SQL)
        CREATE TABLE embeddings (
          step_name TEXT PRIMARY KEY,
          embeddings_data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      SQL

      # Create indexes
      db.execute("CREATE INDEX idx_analysis_metrics_step_name ON analysis_metrics(step_name)")
      db.execute("CREATE INDEX idx_analysis_metrics_recorded_at ON analysis_metrics(recorded_at)")
      db.execute("CREATE INDEX idx_analysis_results_updated_at ON analysis_results(updated_at)")
    end

    def create_job_tables(db)
      # Create jobs table
      db.execute(<<~SQL)
        CREATE TABLE jobs (
          id INTEGER PRIMARY KEY,
          job_type TEXT NOT NULL,
          provider TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          started_at INTEGER,
          completed_at INTEGER,
          error TEXT,
          metadata TEXT
        )
      SQL

      # Create job_executions table
      db.execute(<<~SQL)
        CREATE TABLE job_executions (
          id INTEGER PRIMARY KEY,
          job_id INTEGER NOT NULL,
          attempt INTEGER NOT NULL,
          status TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          completed_at INTEGER,
          error TEXT,
          FOREIGN KEY (job_id) REFERENCES jobs(id)
        )
      SQL

      # Create job_logs table
      db.execute(<<~SQL)
        CREATE TABLE job_logs (
          id INTEGER PRIMARY KEY,
          job_id INTEGER NOT NULL,
          execution_id INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          message TEXT NOT NULL,
          level TEXT NOT NULL,
          metadata TEXT,
          FOREIGN KEY (job_id) REFERENCES jobs(id),
          FOREIGN KEY (execution_id) REFERENCES job_executions(id)
        )
      SQL

      # Create indexes for job tables
      db.execute("CREATE INDEX idx_jobs_status ON jobs(status)")
      db.execute("CREATE INDEX idx_jobs_provider ON jobs(provider)")
      db.execute("CREATE INDEX idx_job_executions_job_id ON job_executions(job_id)")
      db.execute("CREATE INDEX idx_job_logs_job_id ON job_logs(job_id)")
      db.execute("CREATE INDEX idx_job_logs_execution_id ON job_logs(execution_id)")
      db.execute("CREATE INDEX idx_job_logs_timestamp ON job_logs(timestamp)")
    end
  end
end
