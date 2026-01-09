# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for prompt_archive table
      # Replaces prompt_archive/*.md files
      # Write-only audit trail of prompts
      class PromptArchiveRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "prompt_archive")
        end

        # Archive a prompt
        #
        # @param step_name [String, nil] Step name
        # @param content [String] Prompt content
        # @return [Integer] Archive entry ID
        def archive(step_name:, content:)
          now = current_timestamp

          execute(
            insert_sql([:project_dir, :step_name, :content, :archived_at]),
            [project_dir, step_name, content, now]
          )

          id = last_insert_row_id

          Aidp.log_debug("prompt_archive_repository", "archived",
            id: id, step: step_name, size: content.length)

          id
        end

        # Get recent archived prompts
        #
        # @param limit [Integer] Maximum entries
        # @param step_name [String, nil] Filter by step
        # @return [Array<Hash>] Archive entries
        def recent(limit: 50, step_name: nil)
          rows = if step_name
            query(
              <<~SQL,
                SELECT * FROM prompt_archive
                WHERE project_dir = ? AND step_name = ?
                ORDER BY archived_at DESC
                LIMIT ?
              SQL
              [project_dir, step_name, limit]
            )
          else
            query(
              <<~SQL,
                SELECT * FROM prompt_archive
                WHERE project_dir = ?
                ORDER BY archived_at DESC
                LIMIT ?
              SQL
              [project_dir, limit]
            )
          end

          rows.map { |row| deserialize_entry(row) }
        end

        # Get archive entry by ID
        #
        # @param id [Integer] Entry ID
        # @return [Hash, nil] Entry or nil
        def find(id)
          row = query_one(
            "SELECT * FROM prompt_archive WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )
          deserialize_entry(row)
        end

        # Get latest archived prompt for a step
        #
        # @param step_name [String] Step name
        # @return [Hash, nil] Latest entry or nil
        def latest_for_step(step_name)
          row = query_one(
            <<~SQL,
              SELECT * FROM prompt_archive
              WHERE project_dir = ? AND step_name = ?
              ORDER BY archived_at DESC, id DESC
              LIMIT 1
            SQL
            [project_dir, step_name]
          )
          deserialize_entry(row)
        end

        # Get archive stats
        #
        # @return [Hash] Statistics
        def stats
          total = query_value(
            "SELECT COUNT(*) FROM prompt_archive WHERE project_dir = ?",
            [project_dir]
          ) || 0

          by_step_rows = query(
            <<~SQL,
              SELECT step_name, COUNT(*) as count
              FROM prompt_archive
              WHERE project_dir = ?
              GROUP BY step_name
            SQL
            [project_dir]
          )

          by_step = by_step_rows.each_with_object({}) do |row, h|
            h[row["step_name"] || "unknown"] = row["count"]
          end

          first = query_one(
            "SELECT archived_at FROM prompt_archive WHERE project_dir = ? ORDER BY archived_at ASC LIMIT 1",
            [project_dir]
          )

          last = query_one(
            "SELECT archived_at FROM prompt_archive WHERE project_dir = ? ORDER BY archived_at DESC LIMIT 1",
            [project_dir]
          )

          {
            total: total,
            by_step: by_step,
            first_archived_at: first&.dig("archived_at"),
            last_archived_at: last&.dig("archived_at")
          }
        end

        # Search archived prompts
        #
        # @param query_text [String] Search text
        # @param limit [Integer] Maximum results
        # @return [Array<Hash>] Matching entries
        def search(query_text, limit: 20)
          rows = query(
            <<~SQL,
              SELECT * FROM prompt_archive
              WHERE project_dir = ? AND content LIKE ?
              ORDER BY archived_at DESC
              LIMIT ?
            SQL
            [project_dir, "%#{query_text}%", limit]
          )

          rows.map { |row| deserialize_entry(row) }
        end

        # Clear old archives (keep recent N days)
        #
        # @param days_to_keep [Integer] Days of history to retain
        # @return [Integer] Number of entries deleted
        def cleanup(days_to_keep: 30)
          threshold = (Time.now - (days_to_keep * 24 * 60 * 60)).strftime("%Y-%m-%d %H:%M:%S")

          count = query_value(
            "SELECT COUNT(*) FROM prompt_archive WHERE project_dir = ? AND archived_at < ?",
            [project_dir, threshold]
          ) || 0

          execute(
            "DELETE FROM prompt_archive WHERE project_dir = ? AND archived_at < ?",
            [project_dir, threshold]
          )

          Aidp.log_debug("prompt_archive_repository", "cleanup",
            deleted: count, threshold: threshold)

          count
        end

        private

        def deserialize_entry(row)
          return nil unless row

          {
            id: row["id"],
            step_name: row["step_name"],
            content: row["content"],
            archived_at: row["archived_at"]
          }
        end
      end
    end
  end
end
