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

        def register(name:, spec:)
          strategy_id = Digest::SHA256.hexdigest("#{project_dir}:#{name}:#{spec}")

          # Concurrent sibling child workflows can register the identical
          # strategy at the same time (same deterministic strategy_id), so
          # the insert must be idempotent rather than a check-then-insert to
          # avoid a primary-key race between them.
          execute(
            "INSERT OR IGNORE INTO #{table_name} (id, project_dir, name, spec) VALUES (?, ?, ?, ?)",
            [strategy_id, project_dir, name, spec]
          )

          Aidp.log_debug("strategy_repository", "registered", id: strategy_id, name: name)

          {id: strategy_id, name: name}
        end

        def load(id)
          row = query_one("SELECT * FROM strategies WHERE id = ? AND project_dir = ?", [id, project_dir])
          deserialize_strategy(row)
        end

        def find_by_name(name)
          row = query_one(
            "SELECT * FROM strategies WHERE project_dir = ? AND name = ? ORDER BY created_at DESC, rowid DESC",
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
