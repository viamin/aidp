# frozen_string_literal: true

require "tty-prompt"
require_relative "../database/storage_migrator"

module Aidp
  class CLI
    # Command handler for `aidp storage` subcommand
    #
    # Provides commands for managing AIDP storage:
    #   - migrate: Migrate file-based storage to SQLite
    #   - status: Show storage migration status
    #   - cleanup: Remove old file-based storage after migration
    #
    # Usage:
    #   aidp storage migrate
    #   aidp storage migrate --dry-run
    #   aidp storage migrate --no-backup
    #   aidp storage status
    #   aidp storage cleanup
    class StorageCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, project_dir: nil)
        @prompt = prompt
        @project_dir = project_dir || Dir.pwd
      end

      # Main entry point for storage command
      def run(args)
        subcommand = args.shift

        case subcommand
        when "migrate"
          run_migrate(args)
        when "status"
          run_status
        when "cleanup"
          run_cleanup(args)
        when "-h", "--help", nil
          display_usage
        else
          display_message("Unknown subcommand: #{subcommand}", type: :error)
          display_usage
        end
      end

      private

      def run_migrate(args)
        dry_run = false
        backup = true
        force = false

        until args.empty?
          token = args.shift
          case token
          when "--dry-run"
            dry_run = true
          when "--no-backup"
            backup = false
          when "--force"
            force = true
          when "-h", "--help"
            display_migrate_usage
            return
          else
            display_message("Unknown option: #{token}", type: :error)
            display_migrate_usage
            return
          end
        end

        migrator = Database::StorageMigrator.new(
          project_dir: @project_dir,
          dry_run: dry_run
        )

        # Check if migration is needed
        unless migrator.migration_needed?
          display_message("No file-based storage found. Nothing to migrate.", type: :info)
          return
        end

        # Check if already migrated
        if migrator.already_migrated? && !force
          display_message("Database already contains migrated data.", type: :warning)
          display_message("Use --force to migrate anyway (may create duplicates).", type: :info)
          return
        end

        # Confirm migration
        if dry_run
          display_message("DRY RUN: No changes will be made.", type: :highlight)
        else
          unless force
            confirmed = @prompt.yes?("Migrate file-based storage to SQLite?")
            return unless confirmed
          end
        end

        # Run migration
        display_message("Starting storage migration...", type: :info)

        result = migrator.migrate!(backup: backup)

        # Display results
        display_migration_results(result)
      end

      def run_status
        migrator = Database::StorageMigrator.new(project_dir: @project_dir)

        display_message("\nStorage Migration Status", type: :info)
        display_message("=" * 40, type: :muted)

        if migrator.migration_needed?
          display_message("File-based storage: Found", type: :warning)
          display_message("  Migration recommended", type: :info)
        else
          display_message("File-based storage: Not found", type: :success)
        end

        if migrator.already_migrated?
          display_message("SQLite database: Contains data", type: :success)
        else
          display_message("SQLite database: Empty or not initialized", type: :info)
        end

        db_file = ConfigPaths.database_file(@project_dir)
        if File.exist?(db_file)
          size = File.size(db_file)
          display_message("Database file: #{db_file}", type: :info)
          display_message("Database size: #{format_size(size)}", type: :info)
        end
      end

      def run_cleanup(args)
        keep_config = true
        force = false

        until args.empty?
          token = args.shift
          case token
          when "--include-config"
            keep_config = false
          when "--force"
            force = true
          when "-h", "--help"
            display_cleanup_usage
            return
          else
            display_message("Unknown option: #{token}", type: :error)
            display_cleanup_usage
            return
          end
        end

        migrator = Database::StorageMigrator.new(project_dir: @project_dir)

        # Verify migration was completed
        unless migrator.already_migrated?
          display_message("Cannot cleanup: No migrated data found in database.", type: :error)
          display_message("Run 'aidp storage migrate' first.", type: :info)
          return
        end

        unless migrator.migration_needed?
          display_message("No file-based storage to clean up.", type: :info)
          return
        end

        # Confirm cleanup
        unless force
          display_message("This will permanently delete old file-based storage.", type: :warning)
          confirmed = @prompt.yes?("Proceed with cleanup?")
          return unless confirmed
        end

        display_message("Cleaning up old storage...", type: :info)
        migrator.cleanup_old_storage!(keep_config: keep_config)

        display_message("Cleanup complete.", type: :success)
        display_message("Files removed: #{migrator.stats[:files_removed]}", type: :info)
      end

      def display_migration_results(result)
        display_message("\nMigration Results", type: :info)
        display_message("=" * 40, type: :muted)

        case result[:status]
        when :success
          display_message("Status: Success", type: :success)
        when :partial
          display_message("Status: Partial (some errors occurred)", type: :warning)
        when :skipped
          display_message("Status: Skipped - #{result[:reason]}", type: :info)
          return
        end

        if result[:dry_run]
          display_message("(Dry run - no changes made)", type: :highlight)
        end

        stats = result[:stats]
        if stats && !stats.empty?
          display_message("\nMigrated:", type: :info)
          stats.each do |key, count|
            next if count.zero?
            label = key.to_s.tr("_", " ").capitalize
            display_message("  #{label}: #{count}", type: :info)
          end
        end

        errors = result[:errors]
        if errors && !errors.empty?
          display_message("\nErrors:", type: :error)
          errors.each do |error|
            display_message("  #{error[:type]}: #{error[:error]}", type: :error)
          end
        end

        unless result[:dry_run]
          display_message("\nNext steps:", type: :info)
          display_message("  1. Verify data with 'aidp storage status'", type: :info)
          display_message("  2. Test AIDP functionality", type: :info)
          display_message("  3. Run 'aidp storage cleanup' to remove old files", type: :info)
        end
      end

      def display_usage
        display_message("\nUsage: aidp storage <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  migrate    Migrate file-based storage to SQLite", type: :info)
        display_message("  status     Show storage migration status", type: :info)
        display_message("  cleanup    Remove old file-based storage", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  -h, --help    Show this help message", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp storage migrate", type: :info)
        display_message("  aidp storage migrate --dry-run", type: :info)
        display_message("  aidp storage status", type: :info)
        display_message("  aidp storage cleanup", type: :info)
      end

      def display_migrate_usage
        display_message("\nUsage: aidp storage migrate [options]", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --dry-run      Show what would be migrated without making changes", type: :info)
        display_message("  --no-backup    Skip creating backup of .aidp directory", type: :info)
        display_message("  --force        Migrate even if database already has data", type: :info)
        display_message("  -h, --help     Show this help message", type: :info)
      end

      def display_cleanup_usage
        display_message("\nUsage: aidp storage cleanup [options]", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --include-config  Also remove aidp.yml config file", type: :info)
        display_message("  --force           Skip confirmation prompt", type: :info)
        display_message("  -h, --help        Show this help message", type: :info)
      end

      def format_size(bytes)
        units = %w[B KB MB GB]
        unit = 0
        size = bytes.to_f

        while size >= 1024 && unit < units.length - 1
          size /= 1024
          unit += 1
        end

        "%.1f %s" % [size, units[unit]]
      end
    end
  end
end
