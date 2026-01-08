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
        # @param data [Hash] Checkpoint data with keys:
        #   - step_name [String]
        #   - iteration [Integer]
        #   - timestamp [String]
        #   - run_loop_started_at [String]
        #   - metrics [Hash]
        #   - status [String]
        # @return [Integer] Checkpoint ID
        def save_checkpoint(data)
          existing = current_checkpoint
          now = current_timestamp

          if existing
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
                existing["id"]
              ]
            )
            Aidp.log_debug("checkpoint_repository", "updated", id: existing["id"])
            existing["id"]
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
        # @param data [Hash] Checkpoint data
        def append_history(data)
          execute(
            insert_sql([:project_dir, :step_name, :step_index, :status, :timestamp, :metadata]),
            [
              project_dir,
              data[:step_name],
              data[:iteration],
              data[:status],
              data[:timestamp] || current_timestamp,
              serialize_json(data[:metrics])
            ]
          )
          Aidp.log_debug("checkpoint_repository", "history_appended", step: data[:step_name])
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
              ORDER BY timestamp DESC
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
