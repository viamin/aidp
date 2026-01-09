# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for checkpoint and checkpoint_history tables
      # Replaces checkpoint.yml and checkpoint_history.jsonl
      class CheckpointRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "checkpoints")
        end

        # Save or update current checkpoint
        #
        # @param step_name [String]
        # @param iteration [Integer]
        # @param status [String]
        # @param run_loop_started_at [String, nil]
        # @param metrics [Hash]
        # @return [Integer] Checkpoint ID
        def save_checkpoint(step_name:, iteration: nil, status: nil, run_loop_started_at: nil, metrics: {})
          data = {
            step_name: step_name,
            iteration: iteration,
            status: status,
            run_loop_started_at: run_loop_started_at,
            metrics: metrics
          }
          existing = current_checkpoint
          now = current_timestamp

          if existing
            existing_id = existing[:id]
            execute(
              <<~SQL,
                UPDATE checkpoints SET
                  step_name = ?,
                  step_index = ?,
                  status = ?,
                  run_loop_started_at = ?,
                  metadata = ?,
                  updated_at = ?
                WHERE id = ?
              SQL
              [
                data[:step_name],
                data[:iteration],
                data[:status],
                data[:run_loop_started_at],
                serialize_json(data[:metrics]),
                now,
                existing_id
              ]
            )
            Aidp.log_debug("checkpoint_repository", "updated", id: existing_id)
            existing_id
          else
            execute(
              insert_sql([
                :project_dir, :step_name, :step_index, :status,
                :run_loop_started_at, :metadata, :created_at, :updated_at
              ]),
              [
                project_dir,
                data[:step_name],
                data[:iteration],
                data[:status],
                data[:run_loop_started_at],
                serialize_json(data[:metrics]),
                now,
                now
              ]
            )
            id = last_insert_row_id
            Aidp.log_debug("checkpoint_repository", "created", id: id)
            id
          end
        end

        # Get current checkpoint for project
        #
        # @return [Hash, nil] Current checkpoint or nil
        def current_checkpoint
          row = query_one(
            "SELECT * FROM checkpoints WHERE project_dir = ? ORDER BY updated_at DESC LIMIT 1",
            [project_dir]
          )
          return nil unless row

          deserialize_checkpoint(row)
        end

        # Append checkpoint to history
        #
        # @param step_name [String]
        # @param iteration [Integer]
        # @param status [String]
        # @param timestamp [String, nil]
        # @param metrics [Hash]
        def append_history(step_name:, iteration: nil, status: nil, timestamp: nil, metrics: {})
          execute(
            <<~SQL,
              INSERT INTO checkpoint_history (project_dir, step_name, step_index, status, timestamp, metadata)
              VALUES (?, ?, ?, ?, ?, ?)
            SQL
            [
              project_dir,
              step_name,
              iteration,
              status,
              timestamp || current_timestamp,
              serialize_json(metrics)
            ]
          )
          Aidp.log_debug("checkpoint_repository", "history_appended", step: step_name)
        end

        # Get checkpoint history
        #
        # @param limit [Integer] Maximum entries to return
        # @return [Array<Hash>] Checkpoint history entries
        def history(limit: 100)
          rows = query(
            <<~SQL,
              SELECT * FROM checkpoint_history
              WHERE project_dir = ?
              ORDER BY timestamp DESC, id DESC
              LIMIT ?
            SQL
            [project_dir, limit]
          )

          rows.map { |row| deserialize_history_entry(row) }.reverse
        end

        # Clear all checkpoint data for project
        def clear
          transaction do
            execute("DELETE FROM checkpoints WHERE project_dir = ?", [project_dir])
            execute("DELETE FROM checkpoint_history WHERE project_dir = ?", [project_dir])
          end
          Aidp.log_debug("checkpoint_repository", "cleared", project_dir: project_dir)
        end

        private

        def deserialize_checkpoint(row)
          {
            id: row["id"],
            step_name: row["step_name"],
            iteration: row["step_index"],
            status: row["status"],
            run_loop_started_at: row["run_loop_started_at"],
            metrics: deserialize_json(row["metadata"]) || {},
            created_at: row["created_at"],
            updated_at: row["updated_at"]
          }
        end

        def deserialize_history_entry(row)
          {
            step_name: row["step_name"],
            iteration: row["step_index"],
            status: row["status"],
            timestamp: row["timestamp"],
            metrics: deserialize_json(row["metadata"]) || {}
          }
        end
      end
    end
  end
end
