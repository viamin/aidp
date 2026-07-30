# frozen_string_literal: true

require "securerandom"
require_relative "../repository"

module Aidp
  module Database
    module Repositories
      class ExperienceRunRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "experience_runs")
        end

        def start(task_id:, strategy_id:, workflow_id:, depth:, input_payload:, parent_run_id: nil, branch_key: nil, metadata: {})
          run_id = SecureRandom.uuid

          execute(
            insert_sql([
              :id, :project_dir, :task_id, :strategy_id, :workflow_id, :parent_run_id,
              :branch_key, :status, :depth, :input_payload, :metadata
            ]),
            [
              run_id,
              project_dir,
              task_id,
              strategy_id,
              workflow_id,
              parent_run_id,
              branch_key,
              "running",
              depth,
              serialize_json(input_payload || {}),
              serialize_json(metadata || {})
            ]
          )

          load(run_id)
        end

        def complete(run_id:, status:, output_payload:, metadata: {})
          merged_metadata = existing_metadata(run_id).merge(metadata || {})

          execute(
            <<~SQL,
              UPDATE experience_runs
              SET status = ?, output_payload = ?, metadata = ?, completed_at = ?
              WHERE id = ? AND project_dir = ?
            SQL
            [
              status,
              serialize_json(output_payload || {}),
              serialize_json(merged_metadata),
              current_timestamp,
              run_id,
              project_dir
            ]
          )

          load(run_id)
        end

        def load(run_id)
          row = query_one(
            "SELECT * FROM experience_runs WHERE id = ? AND project_dir = ?",
            [run_id, project_dir]
          )
          deserialize_run(row)
        end

        def bundle_for_replay(run_id)
          row = query_one(
            <<~SQL,
              SELECT runs.*, tasks.title AS task_title, tasks.description AS task_description,
                     tasks.input_payload AS task_input_payload, tasks.context AS task_context,
                     tasks.source_run_id AS task_source_run_id
              FROM experience_runs runs
              JOIN experience_tasks tasks ON tasks.id = runs.task_id
              WHERE runs.id = ? AND runs.project_dir = ?
            SQL
            [run_id, project_dir]
          )
          return nil unless row

          run = deserialize_run(row)
          run.merge(
            task: {
              id: row["task_id"],
              title: row["task_title"],
              description: row["task_description"],
              input_payload: deserialize_json(row["task_input_payload"]) || {},
              context: deserialize_json(row["task_context"]) || {},
              source_run_id: row["task_source_run_id"]
            }
          )
        end

        def children(parent_run_id)
          rows = query(
            "SELECT * FROM experience_runs WHERE parent_run_id = ? AND project_dir = ? ORDER BY started_at ASC",
            [parent_run_id, project_dir]
          )
          rows.map { |row| deserialize_run(row) }
        end

        private

        def existing_metadata(run_id)
          load(run_id)&.fetch(:metadata, {}) || {}
        end

        def deserialize_run(row)
          return nil unless row

          {
            id: row["id"],
            task_id: row["task_id"],
            strategy_id: row["strategy_id"],
            workflow_id: row["workflow_id"],
            parent_run_id: row["parent_run_id"],
            branch_key: row["branch_key"],
            status: row["status"],
            depth: row["depth"],
            input_payload: deserialize_json(row["input_payload"]) || {},
            output_payload: deserialize_json(row["output_payload"]) || {},
            metadata: deserialize_json(row["metadata"]) || {},
            started_at: row["started_at"],
            completed_at: row["completed_at"]
          }
        end
      end
    end
  end
end
