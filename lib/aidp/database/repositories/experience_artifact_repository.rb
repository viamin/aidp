# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      class ExperienceArtifactRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "experience_artifacts")
        end

        def record(run_id:, role:, path:, metadata: {})
          execute(
            insert_sql([:project_dir, :run_id, :role, :path, :metadata]),
            [project_dir, run_id, role, path, serialize_json(metadata || {})]
          )

          Aidp.log_debug("experience_artifact_repository", "recorded",
            run_id: run_id, role: role, path: path)
        end

        def list_for_run(run_id)
          rows = query(
            "SELECT * FROM experience_artifacts WHERE run_id = ? AND project_dir = ? ORDER BY id ASC",
            [run_id, project_dir]
          )
          rows.map do |row|
            {
              role: row["role"],
              path: row["path"],
              metadata: deserialize_json(row["metadata"]) || {},
              created_at: row["created_at"]
            }
          end
        end
      end
    end
  end
end
