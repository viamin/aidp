# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for worktrees table
      # Replaces worktrees.json and pr_worktrees.json
      # Handles both standard and PR worktrees
      class WorktreeRepository < Repository
        TYPES = %w[standard pr].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "worktrees")
        end

        # Register a standard worktree
        #
        # @param slug [String] Worktree slug
        # @param path [String] Filesystem path
        # @param branch [String] Branch name
        # @return [Hash] Worktree info
        def register(slug:, path:, branch:)
          now = current_timestamp

          execute(
            insert_sql([
              :project_dir, :worktree_type, :path, :branch, :slug,
              :status, :created_at, :updated_at
            ]),
            [project_dir, "standard", path, branch, slug, "active", now, now]
          )

          Aidp.log_debug("worktree_repository", "registered",
            slug: slug, type: "standard")

          find_by_slug(slug)
        end

        # Register a PR worktree
        #
        # @param pr_number [Integer] PR number
        # @param path [String] Filesystem path
        # @param base_branch [String] Base branch
        # @param head_branch [String] Head branch
        # @param metadata [Hash] Additional metadata
        # @return [Hash] Worktree info
        def register_pr(pr_number:, path:, base_branch:, head_branch:, metadata: {})
          now = current_timestamp
          slug = "pr-#{pr_number}-#{Time.now.to_i}"

          full_metadata = metadata.merge(
            base_branch: base_branch,
            head_branch: head_branch,
            created_at: Time.now.to_i
          )

          execute(
            insert_sql([
              :project_dir, :worktree_type, :path, :branch, :slug, :pr_number,
              :status, :metadata, :created_at, :updated_at
            ]),
            [
              project_dir, "pr", path, head_branch, slug, pr_number,
              "active", serialize_json(full_metadata), now, now
            ]
          )

          Aidp.log_debug("worktree_repository", "registered_pr",
            pr_number: pr_number, slug: slug)

          find_by_pr(pr_number)
        end

        # Find worktree by slug
        #
        # @param slug [String] Worktree slug
        # @return [Hash, nil] Worktree info or nil
        def find_by_slug(slug)
          row = query_one(
            "SELECT * FROM worktrees WHERE project_dir = ? AND slug = ?",
            [project_dir, slug]
          )
          deserialize_worktree(row)
        end

        # Find worktree by PR number
        #
        # @param pr_number [Integer] PR number
        # @return [Hash, nil] Worktree info or nil
        def find_by_pr(pr_number)
          row = query_one(
            "SELECT * FROM worktrees WHERE project_dir = ? AND pr_number = ?",
            [project_dir, pr_number]
          )
          deserialize_worktree(row)
        end

        # Find worktree by branch
        #
        # @param branch [String] Branch name
        # @return [Hash, nil] Worktree info or nil
        def find_by_branch(branch)
          row = query_one(
            "SELECT * FROM worktrees WHERE project_dir = ? AND branch = ?",
            [project_dir, branch]
          )
          deserialize_worktree(row)
        end

        # Check if worktree exists
        #
        # @param slug [String] Worktree slug
        # @return [Boolean]
        def exists?(slug)
          !find_by_slug(slug).nil?
        end

        # List all worktrees
        #
        # @param type [String, nil] Filter by type (standard, pr)
        # @return [Array<Hash>] Worktrees
        def list(type: nil)
          if type
            rows = query(
              "SELECT * FROM worktrees WHERE project_dir = ? AND worktree_type = ? ORDER BY created_at DESC",
              [project_dir, type]
            )
          else
            rows = query(
              "SELECT * FROM worktrees WHERE project_dir = ? ORDER BY created_at DESC",
              [project_dir]
            )
          end

          rows.map { |row| deserialize_worktree(row) }
        end

        # List standard worktrees (for Worktree module)
        #
        # @return [Array<Hash>]
        def list_standard
          list(type: "standard")
        end

        # List PR worktrees (for PRWorktreeManager)
        #
        # @return [Hash] Map of pr_number => worktree info
        def list_pr_worktrees
          rows = query(
            "SELECT * FROM worktrees WHERE project_dir = ? AND worktree_type = 'pr'",
            [project_dir]
          )

          rows.each_with_object({}) do |row, hash|
            wt = deserialize_worktree(row)
            hash[wt[:pr_number].to_s] = wt if wt[:pr_number]
          end
        end

        # Unregister a worktree by slug
        #
        # @param slug [String] Worktree slug
        def unregister(slug)
          execute(
            "DELETE FROM worktrees WHERE project_dir = ? AND slug = ?",
            [project_dir, slug]
          )
          Aidp.log_debug("worktree_repository", "unregistered", slug: slug)
        end

        # Unregister a PR worktree
        #
        # @param pr_number [Integer] PR number
        def unregister_pr(pr_number)
          execute(
            "DELETE FROM worktrees WHERE project_dir = ? AND pr_number = ?",
            [project_dir, pr_number]
          )
          Aidp.log_debug("worktree_repository", "unregistered_pr", pr_number: pr_number)
        end

        # Update worktree status
        #
        # @param slug [String] Worktree slug
        # @param status [String] New status
        def update_status(slug, status)
          execute(
            "UPDATE worktrees SET status = ?, updated_at = ? WHERE project_dir = ? AND slug = ?",
            [status, current_timestamp, project_dir, slug]
          )
        end

        # Cleanup stale PR worktrees
        #
        # @param days_threshold [Integer] Days after which to consider stale
        # @return [Array<Hash>] Removed worktrees
        def cleanup_stale_pr(days_threshold: 30)
          threshold_time = (Time.now - (days_threshold * 24 * 60 * 60)).strftime("%Y-%m-%d %H:%M:%S")

          stale = query(
            "SELECT * FROM worktrees WHERE project_dir = ? AND worktree_type = 'pr' AND created_at < ?",
            [project_dir, threshold_time]
          )

          stale.each do |row|
            execute("DELETE FROM worktrees WHERE id = ?", [row["id"]])
          end

          stale.map { |row| deserialize_worktree(row) }
        end

        private

        def deserialize_worktree(row)
          return nil unless row

          metadata = deserialize_json(row["metadata"]) || {}

          {
            id: row["id"],
            slug: row["slug"],
            path: row["path"],
            branch: row["branch"],
            worktree_type: row["worktree_type"],
            pr_number: row["pr_number"],
            status: row["status"],
            metadata: metadata,
            base_branch: metadata[:base_branch],
            head_branch: metadata[:head_branch] || row["branch"],
            created_at: row["created_at"],
            updated_at: row["updated_at"],
            active: row["path"] && Dir.exist?(row["path"])
          }
        end
      end
    end
  end
end
