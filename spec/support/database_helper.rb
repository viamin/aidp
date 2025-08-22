# frozen_string_literal: true

require "pg"
require "que"
require "sequel"

module DatabaseHelper
  def self.setup_test_db
    # Connect to postgres to create test database
    conn = PG.connect(
      host: "localhost",
      port: 5432,
      dbname: "postgres",
      user: ENV["USER"]
    )

    # Drop test database if it exists
    conn.exec("SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'aidp_test' AND pid <> pg_backend_pid()")
    conn.exec("DROP DATABASE IF EXISTS aidp_test")
    conn.exec("CREATE DATABASE aidp_test")
    conn.close

    # Connect to test database
    @db = PG.connect(
      host: "localhost",
      port: 5432,
      dbname: "aidp_test",
      user: ENV["USER"]
    )

    # Set up Que with Sequel
    @sequel_db = Sequel.connect(
      adapter: "postgres",
      host: "localhost",
      port: 5432,
      database: "aidp_test",
      user: ENV["USER"]
    )
    Que.connection = @sequel_db
    Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
  end

  def self.drop_test_db
    Que.connection = nil
    @sequel_db&.disconnect
    @db&.close
    @db = nil
    @sequel_db = nil

    conn = PG.connect(
      host: "localhost",
      port: 5432,
      dbname: "postgres",
      user: ENV["USER"]
    )
    conn.exec("DROP DATABASE IF EXISTS aidp_test")
    conn.close
  end

  def self.clear_que_tables
    @db.exec("TRUNCATE que_jobs CASCADE")
  end
end
