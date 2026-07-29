# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      class ExperienceEvaluationRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "experience_evaluations")
        end

        def record(run_id:, evaluator_name:, score:, passed:, summary: nil, metadata: {})
          execute(
            insert_sql([
              :project_dir, :run_id, :evaluator_name, :score, :passed, :summary, :metadata
            ]),
            [
              project_dir,
              run_id,
              evaluator_name,
              score,
              passed ? 1 : 0,
              summary,
              serialize_json(metadata || {})
            ]
          )
        end

        def list_for_run(run_id)
          rows = query(
            "SELECT * FROM experience_evaluations WHERE run_id = ? AND project_dir = ? ORDER BY id ASC",
            [run_id, project_dir]
          )
          rows.map do |row|
            {
              evaluator_name: row["evaluator_name"],
              score: row["score"],
              passed: row["passed"] == 1,
              summary: row["summary"],
              metadata: deserialize_json(row["metadata"]) || {},
              created_at: row["created_at"]
            }
          end
        end
      end
    end
  end
end
