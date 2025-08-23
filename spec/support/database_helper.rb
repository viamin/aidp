# frozen_string_literal: true

require "pg"
require "que"
require "sequel"

module DatabaseHelper
  TEST_DB_NAME = "aidp_test"

  def self.validate_database_name(name)
    # Only allow alphanumeric characters, underscores, and hyphens
    raise ArgumentError, "Invalid database name" unless name.match?(/\A[a-zA-Z0-9_-]+\z/)
  end

  def self.setup_test_db
    validate_database_name(TEST_DB_NAME)

    # Connect to postgres to create test database
    conn = PG.connect(
      host: "localhost",
      port: 5432,
      dbname: "postgres",
      user: ENV["USER"]
    )

    begin
      # Drop test database if it exists
      conn.exec_params("SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = $1 AND pid <> pg_backend_pid()", [TEST_DB_NAME])
      conn.exec("DROP DATABASE IF EXISTS #{conn.escape_identifier(TEST_DB_NAME)}")
      conn.exec("CREATE DATABASE #{conn.escape_identifier(TEST_DB_NAME)}")
    rescue PG::Error => e
      puts "Error setting up test database: #{e.message}"
      raise
    ensure
      conn.close
    end

    begin
      # Connect to test database
      @db = PG.connect(
        host: "localhost",
        port: 5432,
        dbname: TEST_DB_NAME,
        user: ENV["USER"]
      )

      # Set up Que with Sequel
      @sequel_db = Sequel.connect(
        adapter: "postgres",
        host: "localhost",
        port: 5432,
        database: TEST_DB_NAME,
        user: ENV["USER"],
        max_connections: 10
      )
      Que.connection = @sequel_db
      Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
    rescue => e
      puts "Error connecting to test database: #{e.message}"
      raise
    end
  end

  def self.drop_test_db
    # Close Que connection first
    Que.connection = nil

    # Disconnect Sequel connection
    @sequel_db&.disconnect

    # Close direct PG connection
    @db&.close
    @db = nil
    @sequel_db = nil

    # Connect to postgres to drop the test database
    conn = PG.connect(
      host: "localhost",
      port: 5432,
      dbname: "postgres",
      user: ENV["USER"]
    )

    begin
      # Terminate all connections to the test database
      conn.exec_params("SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = $1 AND pid <> pg_backend_pid()", [TEST_DB_NAME])

      # Wait a moment for connections to close
      sleep 0.1

      # Drop the database
      conn.exec("DROP DATABASE IF EXISTS #{conn.escape_identifier(TEST_DB_NAME)}")
    rescue PG::Error => e
      puts "Warning: Could not drop test database: #{e.message}"
      # Don't raise the error - this is cleanup and shouldn't fail tests
    ensure
      conn.close
    end
  end

  def self.clear_que_tables
    # Reconnect if needed
    if @db.nil? || @db.status != PG::CONNECTION_OK
      @db = PG.connect(
        host: "localhost",
        port: 5432,
        dbname: TEST_DB_NAME,
        user: ENV["USER"]
      )
    end

    begin
      @db.exec("TRUNCATE que_jobs CASCADE")
    rescue PG::Error => e
      puts "Error clearing que tables: #{e.message}"
      # Try to reconnect and retry once
      setup_test_db
      @db.exec("TRUNCATE que_jobs CASCADE")
    end
  end
end
