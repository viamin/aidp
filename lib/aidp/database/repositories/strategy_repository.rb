# frozen_string_literal: true

require "digest"
require_relative "../repository"

module Aidp
  module Database
    module Repositories
      class StrategyRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "strategies")
        end

        def upsert(name:, spec:)
          strategy_id = Digest::SHA256.hexdigest("#{project_dir}:#{name}:#{spec}")
          existing = query_one(
            "SELECT id FROM strategies WHERE project_dir = ? AND name = ?",
            [project_dir, name]
          )

          if existing
            execute(
              "UPDATE strategies SET id = ?, spec = ? WHERE project_dir = ? AND name = ?",
              [strategy_id, spec, project_dir, name]
            )
          else
            execute(
              insert_sql([:id, :project_dir, :name, :spec]),
              [strategy_id, project_dir, name, spec]
            )
          end

          {id: strategy_id, name: name}
        end

        def load(id)
          row = query_one("SELECT * FROM strategies WHERE id = ? AND project_dir = ?", [id, project_dir])
          deserialize_strategy(row)
        end

        def find_by_name(name)
          row = query_one(
            "SELECT * FROM strategies WHERE project_dir = ? AND name = ?",
            [project_dir, name]
          )
          deserialize_strategy(row)
        end

        private

        def deserialize_strategy(row)
          return nil unless row

          {
            id: row["id"],
            name: row["name"],
            spec: deserialize_json(row["spec"]) || {},
            created_at: row["created_at"]
          }
        end
      end
    end
  end
end
