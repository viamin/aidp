# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for prompt_feedback table
      # Tracks prompt template effectiveness for AGD evolution
      class PromptFeedbackRepository < Repository
        VALID_OUTCOMES = %w[success failure abandoned timeout].freeze
        VALID_REACTIONS = %w[positive negative neutral].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "prompt_feedback")
        end

        # Record feedback for a prompt template
        #
        # @param record [Hash] Feedback data with keys:
        #   - template_id [String] Template identifier
        #   - outcome [String] success/failure/abandoned/timeout
        #   - iterations [Integer, nil] Number of iterations to completion
        #   - user_reaction [String, nil] positive/negative/neutral
        #   - suggestions [Array<String>, nil] Improvement suggestions
        #   - context [Hash, nil] Additional context
        # @return [Hash] Result with :success and :id
        def record(record)
          execute(
            insert_sql([
              :project_dir, :template_id, :outcome, :iterations,
              :user_reaction, :suggestions, :context, :aidp_version
            ]),
            [
              project_dir,
              record[:template_id],
              record[:outcome].to_s,
              record[:iterations],
              record[:user_reaction]&.to_s,
              serialize_json(record[:suggestions]),
              serialize_json(record[:context] || {}),
              Aidp::VERSION
            ]
          )

          Aidp.log_debug("prompt_feedback_repository", "recorded",
            template_id: record[:template_id], outcome: record[:outcome])

          {success: true, id: last_insert_row_id}
        rescue => e
          Aidp.log_debug("prompt_feedback_repository", "record_failed",
            template_id: record[:template_id], error: e.message)
          {success: false, error: e.message}
        end

        # Get summary statistics for a template
        #
        # @param template_id [String] Template identifier
        # @return [Hash] Summary statistics
        def summary(template_id:)
          total = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ? AND template_id = ?",
            [project_dir, template_id]
          ) || 0

          return empty_summary(template_id) if total.zero?

          success_count = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND outcome = 'success'",
            [project_dir, template_id]
          ) || 0

          failure_count = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND outcome = 'failure'",
            [project_dir, template_id]
          ) || 0

          avg_iterations = query_value(
            "SELECT AVG(iterations) FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND iterations IS NOT NULL",
            [project_dir, template_id]
          )

          positive_reactions = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND user_reaction = 'positive'",
            [project_dir, template_id]
          ) || 0

          negative_reactions = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND user_reaction = 'negative'",
            [project_dir, template_id]
          ) || 0

          # Get suggestions
          suggestion_rows = query(
            "SELECT suggestions FROM prompt_feedback WHERE project_dir = ? AND template_id = ? AND suggestions IS NOT NULL",
            [project_dir, template_id]
          )
          all_suggestions = suggestion_rows.flat_map { |r| deserialize_json(r["suggestions"]) || [] }.compact.uniq

          first_row = query_one(
            "SELECT created_at FROM prompt_feedback WHERE project_dir = ? AND template_id = ? ORDER BY created_at ASC LIMIT 1",
            [project_dir, template_id]
          )
          last_row = query_one(
            "SELECT created_at FROM prompt_feedback WHERE project_dir = ? AND template_id = ? ORDER BY created_at DESC LIMIT 1",
            [project_dir, template_id]
          )

          {
            template_id: template_id,
            total_uses: total,
            success_rate: (total > 0) ? (success_count.to_f / total * 100).round(1) : 0,
            success_count: success_count,
            failure_count: failure_count,
            avg_iterations: avg_iterations&.round(1),
            positive_reactions: positive_reactions,
            negative_reactions: negative_reactions,
            common_suggestions: all_suggestions.take(5),
            first_use: first_row&.dig("created_at"),
            last_use: last_row&.dig("created_at")
          }
        end

        # List feedback entries with filtering
        #
        # @param template_id [String, nil] Filter by template
        # @param outcome [String, nil] Filter by outcome
        # @param limit [Integer] Maximum entries
        # @return [Array<Hash>] Feedback entries
        def list(template_id: nil, outcome: nil, limit: 100)
          conditions = ["project_dir = ?"]
          params = [project_dir]

          if template_id
            conditions << "template_id = ?"
            params << template_id
          end

          if outcome
            conditions << "outcome = ?"
            params << outcome.to_s
          end

          params << limit

          rows = query(
            <<~SQL,
              SELECT * FROM prompt_feedback
              WHERE #{conditions.join(" AND ")}
              ORDER BY created_at DESC, id DESC
              LIMIT ?
            SQL
            params
          )

          rows.map { |row| deserialize_feedback(row) }
        end

        # Find templates that need improvement
        #
        # @param min_uses [Integer] Minimum uses to consider
        # @param max_success_rate [Float] Success rate threshold
        # @return [Array<Hash>] Templates needing improvement
        def templates_needing_improvement(min_uses: 5, max_success_rate: 70.0)
          # Get unique template IDs
          template_rows = query(
            "SELECT DISTINCT template_id FROM prompt_feedback WHERE project_dir = ?",
            [project_dir]
          )

          template_rows.filter_map do |row|
            template_id = row["template_id"]
            stats = summary(template_id: template_id)

            next if stats[:total_uses] < min_uses
            next if stats[:success_rate] > max_success_rate

            stats
          end.sort_by { |s| s[:success_rate] }
        end

        # Clear all feedback
        #
        # @return [Hash] Result with count
        def clear
          count = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ?",
            [project_dir]
          ) || 0

          execute("DELETE FROM prompt_feedback WHERE project_dir = ?", [project_dir])

          Aidp.log_debug("prompt_feedback_repository", "cleared", count: count)
          {success: true, count: count}
        end

        # Check if any feedback exists
        #
        # @return [Boolean]
        def any?
          count = query_value(
            "SELECT COUNT(*) FROM prompt_feedback WHERE project_dir = ?",
            [project_dir]
          ) || 0
          count.positive?
        end

        private

        def deserialize_feedback(row)
          return nil unless row

          {
            id: row["id"],
            template_id: row["template_id"],
            outcome: row["outcome"],
            iterations: row["iterations"],
            user_reaction: row["user_reaction"],
            suggestions: deserialize_json(row["suggestions"]),
            context: deserialize_json(row["context"]) || {},
            aidp_version: row["aidp_version"],
            created_at: row["created_at"]
          }
        end

        def empty_summary(template_id)
          {
            template_id: template_id,
            total_uses: 0,
            success_rate: 0,
            success_count: 0,
            failure_count: 0,
            avg_iterations: nil,
            positive_reactions: 0,
            negative_reactions: 0,
            common_suggestions: [],
            first_use: nil,
            last_use: nil
          }
        end
      end
    end
  end
end
