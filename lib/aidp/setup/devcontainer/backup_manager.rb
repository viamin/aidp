# frozen_string_literal: true

require "fileutils"
require "time"

module Aidp
  module Setup
    module Devcontainer
      # Manages backups of devcontainer.json before modifications
      class BackupManager
        class BackupError < StandardError; end

        def initialize(project_dir)
          @project_dir = project_dir
          @backup_dir = File.join(project_dir, ".aidp", "backups", "devcontainer")
        end

        # Create a backup of the devcontainer file
        # @param source_path [String] Path to devcontainer.json to backup
        # @param metadata [Hash] Optional metadata to store with backup
        # @return [String] Path to backup file
        def create_backup(source_path, metadata = {})
          unless File.exist?(source_path)
            raise BackupError, "Source file does not exist: #{source_path}"
          end

          ensure_backup_directory_exists

          timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
          backup_filename = "devcontainer-#{timestamp}.json"
          backup_path = File.join(@backup_dir, backup_filename)

          FileUtils.cp(source_path, backup_path)

          # Create metadata file
          if metadata.any?
            metadata_path = "#{backup_path}.meta"
            File.write(metadata_path, JSON.pretty_generate(metadata))
          end

          Aidp.log_info("backup_manager", "created backup",
            source: source_path,
            backup: backup_path)

          backup_path
        rescue => e
          raise BackupError, "Failed to create backup: #{e.message}"
        end

        # List all available backups
        # @return [Array<Hash>] Array of backup info hashes
        def list_backups
          return [] unless File.directory?(@backup_dir)

          Dir.glob(File.join(@backup_dir, "devcontainer-*.json"))
            .reject { |f| f.end_with?(".meta") }
            .map { |path| backup_info(path) }
            .sort_by { |info| info[:timestamp] }
            .reverse
        end

        # Restore a backup to the specified location
        # @param backup_path [String] Path to backup file
        # @param target_path [String] Where to restore the backup
        # @param create_backup [Boolean] Create backup of target before restoring
        # @return [Boolean] true if successful
        def restore_backup(backup_path, target_path, create_backup: true)
          unless File.exist?(backup_path)
            raise BackupError, "Backup file does not exist: #{backup_path}"
          end

          # Backup current file before restoring
          if create_backup && File.exist?(target_path)
            create_backup(target_path, {
              reason: "pre_restore",
              restoring_from: backup_path
            })
          end

          FileUtils.mkdir_p(File.dirname(target_path))
          FileUtils.cp(backup_path, target_path)

          Aidp.log_info("backup_manager", "restored backup",
            backup: backup_path,
            target: target_path)

          true
        rescue => e
          raise BackupError, "Failed to restore backup: #{e.message}"
        end

        # Delete old backups, keeping only the N most recent
        # @param keep_count [Integer] Number of backups to keep
        # @return [Integer] Number of backups deleted
        def cleanup_old_backups(keep_count = 10)
          backups = list_backups
          return 0 if backups.size <= keep_count

          to_delete = backups[keep_count..]
          deleted_count = 0

          to_delete.each do |backup|
            File.delete(backup[:path]) if File.exist?(backup[:path])

            metadata_path = "#{backup[:path]}.meta"
            File.delete(metadata_path) if File.exist?(metadata_path)

            deleted_count += 1
          end

          Aidp.log_info("backup_manager", "cleaned up old backups",
            deleted: deleted_count,
            kept: keep_count)

          deleted_count
        end

        # Get the most recent backup
        # @return [Hash, nil] Backup info or nil if no backups
        def latest_backup
          list_backups.first
        end

        # Calculate total size of all backups
        # @return [Integer] Total size in bytes
        def total_backup_size
          return 0 unless File.directory?(@backup_dir)

          Dir.glob(File.join(@backup_dir, "devcontainer-*.{json,meta}"))
            .sum { |f| File.size(f) }
        end

        private

        def ensure_backup_directory_exists
          FileUtils.mkdir_p(@backup_dir) unless File.directory?(@backup_dir)
        end

        def backup_info(path)
          filename = File.basename(path)
          timestamp_str = filename[/\d{8}_\d{6}/]

          info = {
            path: path,
            filename: filename,
            size: File.size(path),
            created_at: File.mtime(path),
            timestamp: parse_timestamp(timestamp_str)
          }

          # Load metadata if available
          metadata_path = "#{path}.meta"
          if File.exist?(metadata_path)
            begin
              metadata = JSON.parse(File.read(metadata_path))
              info[:metadata] = metadata
            rescue JSON::ParserError
              # Ignore invalid metadata
            end
          end

          info
        end

        def parse_timestamp(timestamp_str)
          return Time.now if timestamp_str.nil?

          Time.strptime(timestamp_str, "%Y%m%d_%H%M%S")
        rescue ArgumentError
          Time.now
        end
      end
    end
  end
end
