# frozen_string_literal: true

require "sqlite3"
require "json"
require "fileutils"
Kernel.require("set") unless defined?(Set)

module Aidp
  # Database module for SQLite-based storage
  # Provides connection management, schema migrations, and base repository functionality
  module Database
    class Error < StandardError; end
    class MigrationError < Error; end
    class ConnectionError < Error; end

    # Thread-safe connection cache
    @connections = {}
    @mutex = Mutex.new
    @migrated_projects = Set.new
    @migration_mutex = Mutex.new

    class << self
      # Get or create a database connection for the given project directory
      # Connections are cached per project_dir and are thread-safe
      #
      # @param project_dir [String] Project directory path
      # @return [SQLite3::Database] Database connection
      def connection(project_dir = Dir.pwd)
        db_path = ConfigPaths.database_file(project_dir)

        @mutex.synchronize do
          invalidate_missing_connection!(db_path)

          # Return cached connection if valid
          if @connections[db_path]&.closed? == false
            return @connections[db_path]
          end

          # Ensure directory exists
          FileUtils.mkdir_p(File.dirname(db_path))

          # Create new connection with optimal settings
          db = SQLite3::Database.new(db_path)
          configure_connection(db)

          @connections[db_path] = db
          Aidp.log_debug("database", "connection_opened", path: db_path)
          db
        end
      end

      # Run pending migrations for the given project
      #
      # @param project_dir [String] Project directory path
      # @return [Array<Integer>] List of applied migration versions
      def migrate!(project_dir = Dir.pwd)
        require_relative "database/migrations"
        Migrations.run!(project_dir)
      end

      # Run pending migrations at most once per process for each project directory.
      #
      # @param project_dir [String] Project directory path
      # @return [Array<Integer>] List of applied migration versions
      def migrate_once!(project_dir = Dir.pwd)
        expanded_project_dir = File.expand_path(project_dir)
        require_relative "database/migrations"

        @migration_mutex.synchronize do
          return [] if migration_current?(expanded_project_dir)

          migrate!(expanded_project_dir).tap do
            @migrated_projects << expanded_project_dir
          end
        end
      end

      # Check if database exists and is initialized
      #
      # @param project_dir [String] Project directory path
      # @return [Boolean] True if database exists
      def exists?(project_dir = Dir.pwd)
        File.exist?(ConfigPaths.database_file(project_dir))
      end

      # Get current schema version
      #
      # @param project_dir [String] Project directory path
      # @return [Integer] Current schema version (0 if not initialized)
      def schema_version(project_dir = Dir.pwd)
        return 0 unless exists?(project_dir)

        db = connection(project_dir)
        result = db.get_first_value("SELECT MAX(version) FROM schema_migrations")
        result || 0
      rescue SQLite3::SQLException
        # Table doesn't exist yet
        0
      end

      # Close connection for a specific project
      #
      # @param project_dir [String] Project directory path
      def close(project_dir = Dir.pwd)
        db_path = ConfigPaths.database_file(project_dir)

        @mutex.synchronize do
          if @connections[db_path] && !@connections[db_path].closed?
            @connections[db_path].close
            Aidp.log_debug("database", "connection_closed", path: db_path)
          end
          @connections.delete(db_path)
        end
      end

      # Close all open connections
      def close_all
        @mutex.synchronize do
          @connections.each do |path, db|
            db.close unless db.closed?
            Aidp.log_debug("database", "connection_closed", path: path)
          end
          @connections.clear
        end
      end

      # Execute a block within a transaction
      #
      # @param project_dir [String] Project directory path
      # @yield [db] Block to execute within transaction
      # @return [Object] Result of the block
      def transaction(project_dir = Dir.pwd)
        db = connection(project_dir)
        db.transaction do
          yield db
        end
      end

      private

      # Configure database connection with optimal settings
      def configure_connection(db)
        db.results_as_hash = true

        # Enable WAL mode for better concurrency
        db.execute("PRAGMA journal_mode = WAL")

        # Enable foreign keys
        db.execute("PRAGMA foreign_keys = ON")

        # Optimize for performance
        db.execute("PRAGMA synchronous = NORMAL")
        db.execute("PRAGMA cache_size = -2000") # 2MB cache
        db.execute("PRAGMA temp_store = MEMORY")

        # Set busy timeout to 5 seconds
        db.busy_timeout = 5000
      end

      def invalidate_missing_connection!(db_path)
        db = @connections[db_path]
        return unless db
        return if db.closed?
        return if File.exist?(db_path)

        db.close
        @connections.delete(db_path)
      end

      def migration_current?(project_dir)
        @migrated_projects.include?(project_dir) &&
          exists?(project_dir) &&
          !Migrations.pending?(project_dir)
      end
    end
  end
end
