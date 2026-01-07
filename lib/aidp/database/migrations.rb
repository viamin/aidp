# frozen_string_literal: true

require_relative "schema"

module Aidp
  module Database
    # Migration runner for SQLite database
    # Applies pending schema migrations in order
    module Migrations
      class << self
        # Run all pending migrations
        #
        # @param project_dir [String] Project directory path
        # @return [Array<Integer>] List of applied migration versions
        def run!(project_dir = Dir.pwd)
          db = Database.connection(project_dir)
          applied = []

          current_version = current_schema_version(db)
          pending = pending_migrations(current_version)

          return applied if pending.empty?

          Aidp.log_debug("migrations", "running_migrations",
            current: current_version,
            pending_count: pending.size)

          pending.each do |version|
            apply_migration!(db, version)
            applied << version
          end

          Aidp.log_debug("migrations", "migrations_complete",
            applied_count: applied.size,
            new_version: Schema.latest_version)

          applied
        end

        # Check if database needs migrations
        #
        # @param project_dir [String] Project directory path
        # @return [Boolean] True if migrations are pending
        def pending?(project_dir = Dir.pwd)
          db = Database.connection(project_dir)
          current = current_schema_version(db)
          current < Schema.latest_version
        end

        # Get list of pending migration versions
        #
        # @param project_dir [String] Project directory path
        # @return [Array<Integer>] Pending migration versions
        def pending_versions(project_dir = Dir.pwd)
          db = Database.connection(project_dir)
          pending_migrations(current_schema_version(db))
        end

        private

        # Get current schema version from database
        def current_schema_version(db)
          # Check if schema_migrations table exists
          table_exists = db.get_first_value(<<~SQL)
            SELECT COUNT(*) FROM sqlite_master
            WHERE type='table' AND name='schema_migrations'
          SQL

          return 0 unless table_exists.positive?

          version = db.get_first_value("SELECT MAX(version) FROM schema_migrations")
          version || 0
        end

        # Get list of pending migrations
        def pending_migrations(current_version)
          Schema.versions.select { |v| v > current_version }
        end

        # Apply a single migration
        def apply_migration!(db, version)
          sql = Schema.migration_sql(version)

          raise MigrationError, "No SQL found for migration version #{version}" unless sql

          Aidp.log_debug("migrations", "applying_migration", version: version)

          db.transaction do
            # Execute all statements in the migration
            sql.split(";").each do |statement|
              statement = statement.strip
              next if statement.empty?

              db.execute(statement)
            end

            # Record the migration
            db.execute(
              "INSERT INTO schema_migrations (version) VALUES (?)",
              [version]
            )
          end

          Aidp.log_debug("migrations", "migration_applied", version: version)
        rescue SQLite3::Exception => e
          Aidp.log_debug("migrations", "migration_failed",
            version: version,
            error: e.message)
          raise MigrationError, "Failed to apply migration #{version}: #{e.message}"
        end
      end
    end
  end
end
