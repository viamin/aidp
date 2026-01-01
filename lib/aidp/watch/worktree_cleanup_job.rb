# frozen_string_literal: true

require "open3"
require "time"

module Aidp
  module Watch
    # Handles automatic cleanup of worktrees whose branches have been merged into main.
    # Runs periodically during watch mode according to configured frequency.
    #
    # Requirements (from issue #367):
    # - Skip worktrees that are not "clean" (have uncommitted changes)
    # - Run silently with log entries
    # - Skip failed worktrees and retry later
    # - Default to weekly cleanup frequency
    class WorktreeCleanupJob
      SECONDS_PER_DAY = 86_400
      SECONDS_PER_WEEK = 604_800

      # @param project_dir [String] Project root directory
      # @param config [Hash] Cleanup configuration from aidp.yml
      def initialize(project_dir:, config: {})
        @project_dir = project_dir
        @config = normalize_config(config)
        Aidp.log_debug("worktree_cleanup_job", "initialized",
          project_dir: project_dir,
          config: @config)
      end

      # Check if cleanup is due based on last cleanup time and configured frequency
      #
      # @param last_cleanup_at [Time, nil] Time of last cleanup run
      # @return [Boolean] True if cleanup should run
      def cleanup_due?(last_cleanup_at)
        return true unless enabled?
        return true if last_cleanup_at.nil?

        elapsed = Time.now - last_cleanup_at
        elapsed >= cleanup_interval_seconds
      end

      # Execute cleanup of merged worktrees
      #
      # @return [Hash] Result containing cleaned count, skipped count, and errors
      def execute
        Aidp.log_info("worktree_cleanup_job", "cleanup_started",
          base_branch: base_branch,
          delete_branch: delete_branch?)

        return {cleaned: 0, skipped: 0, errors: []} unless enabled?

        worktrees = list_worktrees
        Aidp.log_debug("worktree_cleanup_job", "worktrees_found", count: worktrees.size)

        cleaned = 0
        skipped = 0
        errors = []

        worktrees.each do |worktree|
          result = process_worktree(worktree)
          case result[:status]
          when :cleaned
            cleaned += 1
          when :skipped
            skipped += 1
          when :error
            errors << {slug: worktree[:slug], error: result[:error]}
          end
        end

        Aidp.log_info("worktree_cleanup_job", "cleanup_completed",
          cleaned: cleaned,
          skipped: skipped,
          errors_count: errors.size)

        {cleaned: cleaned, skipped: skipped, errors: errors}
      end

      # Check if cleanup is enabled in configuration
      #
      # @return [Boolean]
      def enabled?
        @config[:enabled]
      end

      # Get the configured cleanup interval in seconds
      #
      # @return [Integer]
      def cleanup_interval_seconds
        case @config[:frequency]
        when "daily"
          SECONDS_PER_DAY
        when "weekly"
          SECONDS_PER_WEEK
        else
          SECONDS_PER_WEEK
        end
      end

      private

      def normalize_config(config)
        {
          enabled: config.fetch(:enabled, config.fetch("enabled", true)),
          frequency: config.fetch(:frequency, config.fetch("frequency", "weekly")),
          base_branch: config.fetch(:base_branch, config.fetch("base_branch", "main")),
          delete_branch: config.fetch(:delete_branch, config.fetch("delete_branch", true))
        }
      end

      def base_branch
        @config[:base_branch]
      end

      def delete_branch?
        @config[:delete_branch]
      end

      def list_worktrees
        Aidp::Worktree.list(project_dir: @project_dir)
      rescue => e
        Aidp.log_error("worktree_cleanup_job", "list_worktrees_failed", error: e.message)
        []
      end

      def process_worktree(worktree)
        slug = worktree[:slug]
        branch = worktree[:branch]
        path = worktree[:path]

        Aidp.log_debug("worktree_cleanup_job", "processing_worktree",
          slug: slug,
          branch: branch,
          active: worktree[:active])

        # Skip inactive worktrees (directory doesn't exist)
        unless worktree[:active]
          Aidp.log_debug("worktree_cleanup_job", "skipping_inactive", slug: slug)
          return {status: :skipped, reason: "inactive"}
        end

        # Check if worktree is clean (no uncommitted changes)
        unless worktree_clean?(path)
          Aidp.log_debug("worktree_cleanup_job", "skipping_dirty", slug: slug)
          return {status: :skipped, reason: "uncommitted_changes"}
        end

        # Check if branch is merged into base branch
        unless branch_merged?(branch)
          Aidp.log_debug("worktree_cleanup_job", "skipping_unmerged",
            slug: slug,
            branch: branch,
            base_branch: base_branch)
          return {status: :skipped, reason: "not_merged"}
        end

        # Remove the worktree
        remove_worktree(slug)
      rescue => e
        Aidp.log_error("worktree_cleanup_job", "process_worktree_error",
          slug: slug,
          error: e.message)
        {status: :error, error: e.message}
      end

      def worktree_clean?(path)
        return false unless Dir.exist?(path)

        stdout, _stderr, status = Open3.capture3(
          "git", "status", "--porcelain",
          chdir: path
        )

        status.success? && stdout.strip.empty?
      rescue => e
        Aidp.log_error("worktree_cleanup_job", "check_clean_failed",
          path: path,
          error: e.message)
        false
      end

      def branch_merged?(branch)
        stdout, _stderr, status = Open3.capture3(
          "git", "branch", "--merged", base_branch,
          chdir: @project_dir
        )

        return false unless status.success?

        # Parse branches that are merged (one per line, with possible leading whitespace or *)
        merged_branches = stdout.lines.map { |line| line.strip.sub(/^\*\s*/, "") }
        merged_branches.include?(branch)
      rescue => e
        Aidp.log_error("worktree_cleanup_job", "check_merged_failed",
          branch: branch,
          error: e.message)
        false
      end

      def remove_worktree(slug)
        Aidp.log_info("worktree_cleanup_job", "removing_worktree",
          slug: slug,
          delete_branch: delete_branch?)

        Aidp::Worktree.remove(
          slug: slug,
          project_dir: @project_dir,
          delete_branch: delete_branch?
        )

        Aidp.log_info("worktree_cleanup_job", "worktree_removed", slug: slug)
        {status: :cleaned}
      rescue Aidp::Worktree::WorktreeNotFound => e
        Aidp.log_warn("worktree_cleanup_job", "worktree_not_found",
          slug: slug,
          error: e.message)
        {status: :skipped, reason: "not_found"}
      rescue => e
        Aidp.log_error("worktree_cleanup_job", "remove_failed",
          slug: slug,
          error: e.message)
        {status: :error, error: e.message}
      end
    end
  end
end
