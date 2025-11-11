# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "checkpoint"

module Aidp
  module AutoUpdate
    # Repository for persisting and restoring checkpoint state
    class CheckpointStore
      attr_reader :checkpoint_dir

      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        @checkpoint_dir = File.join(project_dir, ".aidp", "checkpoints")
        ensure_checkpoint_directory
      end

      # Save checkpoint atomically
      # @param checkpoint [Checkpoint] State to persist
      # @return [Boolean] Success status
      def save_checkpoint(checkpoint)
        Aidp.log_info("checkpoint_store", "saving_checkpoint",
          id: checkpoint.checkpoint_id,
          mode: checkpoint.mode)

        unless checkpoint.valid?
          Aidp.log_error("checkpoint_store", "invalid_checkpoint",
            id: checkpoint.checkpoint_id,
            error: "Checksum validation failed")
          return false
        end

        # Write to temp file first
        temp_file = "#{checkpoint_path(checkpoint.checkpoint_id)}.tmp"
        File.write(temp_file, JSON.pretty_generate(checkpoint.to_h))

        # Atomic rename
        File.rename(temp_file, checkpoint_path(checkpoint.checkpoint_id))

        Aidp.log_info("checkpoint_store", "checkpoint_saved",
          id: checkpoint.checkpoint_id,
          path: checkpoint_path(checkpoint.checkpoint_id))
        true
      rescue => e
        Aidp.log_error("checkpoint_store", "save_failed",
          id: checkpoint.checkpoint_id,
          error: e.message)
        File.delete(temp_file) if temp_file && File.exist?(temp_file)
        false
      end

      # Find most recent checkpoint for restoration
      # @return [Checkpoint, nil] Most recent checkpoint or nil
      def latest_checkpoint
        checkpoints = list_checkpoints

        if checkpoints.empty?
          Aidp.log_debug("checkpoint_store", "no_checkpoints_found")
          return nil
        end

        # Sort by created_at descending
        latest = checkpoints.max_by { |cp| cp.created_at }

        Aidp.log_info("checkpoint_store", "found_latest_checkpoint",
          id: latest.checkpoint_id,
          created_at: latest.created_at.iso8601)

        latest
      rescue => e
        Aidp.log_error("checkpoint_store", "latest_checkpoint_failed",
          error: e.message)
        nil
      end

      # List all checkpoints
      # @return [Array<Checkpoint>] All available checkpoints
      def list_checkpoints
        checkpoint_files = Dir.glob(File.join(@checkpoint_dir, "*.json"))

        checkpoints = checkpoint_files.filter_map do |file|
          load_checkpoint_file(file)
        end

        Aidp.log_debug("checkpoint_store", "listed_checkpoints",
          count: checkpoints.size)

        checkpoints
      rescue => e
        Aidp.log_error("checkpoint_store", "list_failed", error: e.message)
        []
      end

      # Delete checkpoint after successful restoration
      # @param checkpoint_id [String] Checkpoint UUID
      # @return [Boolean] Success status
      def delete_checkpoint(checkpoint_id)
        path = checkpoint_path(checkpoint_id)

        unless File.exist?(path)
          Aidp.log_warn("checkpoint_store", "checkpoint_not_found",
            id: checkpoint_id,
            path: path)
          return false
        end

        File.delete(path)

        Aidp.log_info("checkpoint_store", "checkpoint_deleted",
          id: checkpoint_id)
        true
      rescue => e
        Aidp.log_error("checkpoint_store", "delete_failed",
          id: checkpoint_id,
          error: e.message)
        false
      end

      # Clean up old checkpoints (retention policy)
      # @param max_age_days [Integer] Maximum age to retain
      # @return [Integer] Number of checkpoints deleted
      def cleanup_old_checkpoints(max_age_days: 7)
        Aidp.log_info("checkpoint_store", "cleaning_old_checkpoints",
          max_age_days: max_age_days)

        cutoff_time = Time.now - (max_age_days * 24 * 60 * 60)
        deleted_count = 0

        list_checkpoints.each do |checkpoint|
          if checkpoint.created_at < cutoff_time
            if delete_checkpoint(checkpoint.checkpoint_id)
              deleted_count += 1
            end
          end
        end

        Aidp.log_info("checkpoint_store", "cleanup_complete",
          deleted: deleted_count,
          max_age_days: max_age_days)

        deleted_count
      rescue => e
        Aidp.log_error("checkpoint_store", "cleanup_failed",
          error: e.message)
        0
      end

      private

      def checkpoint_path(checkpoint_id)
        File.join(@checkpoint_dir, "#{checkpoint_id}.json")
      end

      def ensure_checkpoint_directory
        FileUtils.mkdir_p(@checkpoint_dir)
      rescue => e
        Aidp.log_error("checkpoint_store", "mkdir_failed",
          dir: @checkpoint_dir,
          error: e.message)
        raise
      end

      def load_checkpoint_file(file_path)
        data = JSON.parse(File.read(file_path))
        checkpoint = Checkpoint.from_h(data)

        unless checkpoint.valid?
          Aidp.log_warn("checkpoint_store", "invalid_checkpoint_checksum",
            file: file_path)
          return nil
        end

        checkpoint
      rescue JSON::ParserError => e
        Aidp.log_warn("checkpoint_store", "invalid_checkpoint_json",
          file: file_path,
          error: e.message)
        nil
      rescue => e
        Aidp.log_warn("checkpoint_store", "checkpoint_load_failed",
          file: file_path,
          error: e.message)
        nil
      end
    end
  end
end
