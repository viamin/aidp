# frozen_string_literal: true

require "securerandom"
require_relative "../repository"

module Aidp
  module Database
    module Repositories
      class ExperienceTaskRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "experience_tasks")
        end

        def create(description:, title: nil, input_payload: {}, context: {}, source_run_id: nil)
          task_id = SecureRandom.uuid

          execute(
            insert_sql([:id, :project_dir, :title, :description, :input_payload, :context, :source_run_id]),
            [
              task_id,
              project_dir,
              title,
              description,
              serialize_json(input_payload || {}),
              serialize_json(context || {}),
              source_run_id
            ]
          )

          load(task_id)
        end

        def load(task_id)
          row = query_one(
            "SELECT * FROM experience_tasks WHERE id = ? AND project_dir = ?",
            [task_id, project_dir]
          )
          deserialize_task(row)
        end

        private

        def deserialize_task(row)
          return nil unless row

          {
            id: row["id"],
            title: row["title"],
            description: row["description"],
            input_payload: deserialize_json(row["input_payload"]) || {},
            context: deserialize_json(row["context"]) || {},
            source_run_id: row["source_run_id"],
            created_at: row["created_at"]
          }
        end
      end
    end
  end
end
