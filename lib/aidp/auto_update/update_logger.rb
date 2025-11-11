# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"

module Aidp
  module AutoUpdate
    # Service for logging update events in JSON Lines format
    class UpdateLogger
      attr_reader :log_file

      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        @log_file = File.join(project_dir, ".aidp", "logs", "updates.log")
        ensure_log_directory
      end

      # Log an update check
      # @param update_check [UpdateCheck] Update check result
      def log_check(update_check)
        write_log_entry(
          event: "check",
          current_version: update_check.current_version,
          available_version: update_check.available_version,
          update_available: update_check.update_available,
          update_allowed: update_check.update_allowed,
          policy_reason: update_check.policy_reason,
          error: update_check.error
        )
      end

      # Log update initiation
      # @param checkpoint [Checkpoint] Checkpoint created for update
      # @param target_version [String] Version updating to
      def log_update_initiated(checkpoint, target_version: nil)
        write_log_entry(
          event: "update_initiated",
          checkpoint_id: checkpoint.checkpoint_id,
          from_version: checkpoint.aidp_version,
          to_version: target_version,
          mode: checkpoint.mode
        )
      end

      # Log successful checkpoint restoration
      # @param checkpoint [Checkpoint] Checkpoint that was restored
      def log_restore(checkpoint)
        write_log_entry(
          event: "restore",
          checkpoint_id: checkpoint.checkpoint_id,
          from_version: checkpoint.aidp_version,
          restored_version: Aidp::VERSION,
          mode: checkpoint.mode
        )
      end

      # Log update failure
      # @param reason [String] Failure reason
      # @param checkpoint_id [String, nil] Associated checkpoint ID
      def log_failure(reason, checkpoint_id: nil)
        write_log_entry(
          event: "failure",
          reason: reason,
          checkpoint_id: checkpoint_id,
          version: Aidp::VERSION
        )
      end

      # Log successful update completion
      # @param from_version [String] Version updated from
      # @param to_version [String] Version updated to
      def log_success(from_version:, to_version:)
        write_log_entry(
          event: "success",
          from_version: from_version,
          to_version: to_version
        )
      end

      # Log restart loop detection
      # @param failure_count [Integer] Number of consecutive failures
      def log_restart_loop(failure_count)
        write_log_entry(
          event: "restart_loop_detected",
          failure_count: failure_count,
          version: Aidp::VERSION
        )
      end

      # Read recent update log entries
      # @param limit [Integer] Maximum number of entries to return
      # @return [Array<Hash>] Recent log entries
      def recent_entries(limit: 10)
        return [] unless File.exist?(@log_file)

        entries = []
        File.readlines(@log_file).reverse_each do |line|
          break if entries.size >= limit
          begin
            entries << JSON.parse(line, symbolize_names: true)
          rescue JSON::ParserError
            # Skip malformed lines
          end
        end

        entries
      rescue => e
        Aidp.log_error("update_logger", "read_entries_failed",
          error: e.message)
        []
      end

      private

      def write_log_entry(data)
        entry = data.merge(
          timestamp: Time.now.utc.iso8601,
          hostname: Socket.gethostname
        )

        # Remove nil values
        entry = entry.compact

        File.open(@log_file, "a") do |f|
          f.puts(JSON.generate(entry))
        end

        Aidp.log_debug("update_logger", "log_entry_written",
          event: data[:event])
      rescue => e
        # Log to main logger but don't fail
        Aidp.log_error("update_logger", "write_failed",
          event: data[:event],
          error: e.message)
      end

      def ensure_log_directory
        FileUtils.mkdir_p(File.dirname(@log_file))
      rescue => e
        Aidp.log_error("update_logger", "mkdir_failed",
          dir: File.dirname(@log_file),
          error: e.message)
        raise
      end
    end
  end
end
