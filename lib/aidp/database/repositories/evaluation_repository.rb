# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for evaluations table
      # Replaces evaluations/*.json and index.json
      class EvaluationRepository < Repository
        VALID_RATINGS = %w[good neutral bad].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "evaluations")
        end

        # Store a new evaluation
        #
        # @param record [Hash] Evaluation data with keys:
        #   - id [String] Evaluation ID
        #   - rating [String] good/neutral/bad
        #   - target_type [String] Type of item being evaluated
        #   - target_id [String] ID of item being evaluated
        #   - feedback [String, nil] User feedback text
        #   - context [Hash, nil] Additional context
        # @return [Hash] Result with :success and :id
        def store(record)
          now = current_timestamp

          execute(
            insert_sql([
              :id, :project_dir, :evaluation_type, :status, :result,
              :metadata, :created_at
            ]),
            [
              record[:id],
              project_dir,
              record[:target_type],
              record[:rating],
              serialize_json({
                rating: record[:rating],
                feedback: record[:feedback],
                target_id: record[:target_id]
              }),
              serialize_json(record[:context] || {}),
              record[:created_at] || now
            ]
          )

          Aidp.log_debug("evaluation_repository", "stored",
            id: record[:id], rating: record[:rating])

          { success: true, id: record[:id] }
        rescue => e
          Aidp.log_debug("evaluation_repository", "store_failed",
            id: record[:id], error: e.message)
          { success: false, error: e.message, id: record[:id] }
        end

        # Load an evaluation by ID
        #
        # @param id [String] Evaluation ID
        # @return [Hash, nil] Evaluation or nil
        def load(id)
          row = query_one(
            "SELECT * FROM evaluations WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )
          deserialize_evaluation(row)
        end

        # List evaluations with optional filtering
        #
        # @param limit [Integer] Maximum records
        # @param rating [String, nil] Filter by rating
        # @param target_type [String, nil] Filter by target type
        # @return [Array<Hash>] Evaluations
        def list(limit: 50, rating: nil, target_type: nil)
          conditions = ["project_dir = ?"]
          params = [project_dir]

          if rating
            conditions << "status = ?"
            params << rating
          end

          if target_type
            conditions << "evaluation_type = ?"
            params << target_type
          end

          params << limit

          rows = query(
            <<~SQL,
              SELECT * FROM evaluations
              WHERE #{conditions.join(" AND ")}
              ORDER BY created_at DESC
              LIMIT ?
            SQL
            params
          )

          rows.map { |row| deserialize_evaluation(row) }
        end

        # Get statistics
        #
        # @return [Hash] Statistics
        def stats
          total = query_value(
            "SELECT COUNT(*) FROM evaluations WHERE project_dir = ?",
            [project_dir]
          ) || 0

          by_rating = {}
          %w[good neutral bad].each do |r|
            by_rating[r.to_sym] = query_value(
              "SELECT COUNT(*) FROM evaluations WHERE project_dir = ? AND status = ?",
              [project_dir, r]
            ) || 0
          end

          by_type_rows = query(
            <<~SQL,
              SELECT evaluation_type, COUNT(*) as count
              FROM evaluations
              WHERE project_dir = ?
              GROUP BY evaluation_type
            SQL
            [project_dir]
          )
          by_target_type = by_type_rows.each_with_object({}) do |row, h|
            h[row["evaluation_type"]] = row["count"]
          end

          first_row = query_one(
            "SELECT created_at FROM evaluations WHERE project_dir = ? ORDER BY created_at ASC LIMIT 1",
            [project_dir]
          )
          last_row = query_one(
            "SELECT created_at FROM evaluations WHERE project_dir = ? ORDER BY created_at DESC LIMIT 1",
            [project_dir]
          )

          {
            total: total,
            by_rating: by_rating,
            by_target_type: by_target_type,
            first_evaluation: first_row&.dig("created_at"),
            last_evaluation: last_row&.dig("created_at")
          }
        end

        # Delete an evaluation
        #
        # @param id [String] Evaluation ID
        # @return [Hash] Result
        def delete(id)
          execute(
            "DELETE FROM evaluations WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )
          Aidp.log_debug("evaluation_repository", "deleted", id: id)
          { success: true, id: id }
        end

        # Clear all evaluations
        #
        # @return [Hash] Result with count
        def clear
          count = query_value(
            "SELECT COUNT(*) FROM evaluations WHERE project_dir = ?",
            [project_dir]
          ) || 0

          execute("DELETE FROM evaluations WHERE project_dir = ?", [project_dir])

          Aidp.log_debug("evaluation_repository", "cleared", count: count)
          { success: true, count: count }
        end

        # Check if any evaluations exist
        #
        # @return [Boolean]
        def any?
          count = query_value(
            "SELECT COUNT(*) FROM evaluations WHERE project_dir = ?",
            [project_dir]
          ) || 0
          count.positive?
        end

        private

        def deserialize_evaluation(row)
          return nil unless row

          result = deserialize_json(row["result"]) || {}
          metadata = deserialize_json(row["metadata"]) || {}

          {
            id: row["id"],
            rating: result[:rating] || row["status"],
            target_type: row["evaluation_type"],
            target_id: result[:target_id],
            feedback: result[:feedback],
            context: metadata,
            created_at: row["created_at"],
            started_at: row["started_at"],
            completed_at: row["completed_at"]
          }
        end
      end
    end
  end
end
