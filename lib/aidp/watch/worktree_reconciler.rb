# frozen_string_literal: true

require "open3"
require "time"

module Aidp
  module Watch
    # Handles reconciliation of dirty worktrees (those with uncommitted changes).
    # Determines appropriate action based on linked issue/PR state:
    # - Open issue/PR: Resume work by triggering build processor
    # - Merged PR: Reconcile changes and create follow-up PR if meaningful diff remains
    # - Closed without merge: Log and optionally clean up
    #
    # This runs as part of the watch mode poll cycle, after cleanup but before sleep.
    class WorktreeReconciler
      # Pattern to extract issue number from worktree slug
      # e.g., "issue-375-thinking-tiers-escalate" -> 375
      ISSUE_SLUG_PATTERN = /^issue-(\d+)-/

      # Pattern to extract PR number from worktree slug
      # e.g., "pr-456-ci-fix" -> 456
      PR_SLUG_PATTERN = /^pr-(\d+)-/

      # @param project_dir [String] Project root directory
      # @param repository_client [RepositoryClient] GitHub API client
      # @param build_processor [BuildProcessor] Processor for resuming builds
      # @param state_store [StateStore] For tracking build state
      # @param config [Hash] Configuration options
      def initialize(project_dir:, repository_client:, build_processor:, state_store:, config: {})
        @project_dir = project_dir
        @repository_client = repository_client
        @build_processor = build_processor
        @state_store = state_store
        @config = normalize_config(config)

        Aidp.log_debug("worktree_reconciler", "initialized",
          project_dir: project_dir,
          config: @config)
      end

      # Check if reconciliation is due based on last run time
      #
      # @param last_reconcile_at [Time, nil] Time of last reconciliation run
      # @return [Boolean] True if reconciliation should run
      def reconciliation_due?(last_reconcile_at)
        return false unless enabled?
        return true if last_reconcile_at.nil?

        elapsed = Time.now - last_reconcile_at
        elapsed >= reconciliation_interval_seconds
      end

      # Execute reconciliation of dirty worktrees
      #
      # @return [Hash] Result containing resumed, reconciled, skipped counts and errors
      def execute
        Aidp.log_info("worktree_reconciler", "reconciliation_started")

        return {resumed: 0, reconciled: 0, cleaned: 0, skipped: 0, errors: []} unless enabled?

        worktrees = list_dirty_worktrees
        Aidp.log_debug("worktree_reconciler", "dirty_worktrees_found", count: worktrees.size)

        results = {resumed: 0, reconciled: 0, cleaned: 0, skipped: 0, errors: []}

        worktrees.each do |worktree|
          result = process_dirty_worktree(worktree)
          case result[:action]
          when :resumed
            results[:resumed] += 1
          when :reconciled
            results[:reconciled] += 1
          when :cleaned
            results[:cleaned] += 1
          when :skipped
            results[:skipped] += 1
          when :error
            results[:errors] << {slug: worktree[:slug], error: result[:error]}
          end
        end

        Aidp.log_info("worktree_reconciler", "reconciliation_completed",
          resumed: results[:resumed],
          reconciled: results[:reconciled],
          cleaned: results[:cleaned],
          skipped: results[:skipped],
          errors_count: results[:errors].size)

        results
      end

      # Check if reconciliation is enabled
      #
      # @return [Boolean]
      def enabled?
        @config[:enabled]
      end

      # Get the configured reconciliation interval in seconds
      #
      # @return [Integer]
      def reconciliation_interval_seconds
        @config[:interval_seconds]
      end

      private

      def normalize_config(config)
        {
          enabled: config.fetch(:enabled, config.fetch("enabled", true)),
          # Default to checking every 5 minutes
          interval_seconds: config.fetch(:interval_seconds, config.fetch("interval_seconds", 300)),
          base_branch: config.fetch(:base_branch, config.fetch("base_branch", "main")),
          # Auto-resume open issues by default
          auto_resume: config.fetch(:auto_resume, config.fetch("auto_resume", true)),
          # Auto-reconcile merged PRs by default
          auto_reconcile: config.fetch(:auto_reconcile, config.fetch("auto_reconcile", true))
        }
      end

      def base_branch
        @config[:base_branch]
      end

      # List all worktrees that have uncommitted changes
      #
      # @return [Array<Hash>] Worktrees with uncommitted changes
      def list_dirty_worktrees
        all_worktrees = Aidp::Worktree.list(project_dir: @project_dir)

        all_worktrees.select do |worktree|
          next false unless worktree[:active]
          next false unless Dir.exist?(worktree[:path])

          !worktree_clean?(worktree[:path])
        end
      rescue => e
        Aidp.log_error("worktree_reconciler", "list_worktrees_failed", error: e.message)
        []
      end

      def worktree_clean?(path)
        stdout, _stderr, status = Open3.capture3(
          "git", "status", "--porcelain",
          chdir: path
        )

        status.success? && stdout.strip.empty?
      rescue => e
        Aidp.log_error("worktree_reconciler", "check_clean_failed",
          path: path,
          error: e.message)
        true # Assume clean on error to avoid false positives
      end

      # Process a single dirty worktree
      #
      # @param worktree [Hash] Worktree info from registry
      # @return [Hash] Result with :action and optional :error
      def process_dirty_worktree(worktree)
        slug = worktree[:slug]
        branch = worktree[:branch]

        Aidp.log_debug("worktree_reconciler", "processing_dirty_worktree",
          slug: slug,
          branch: branch)

        # Determine what this worktree is for
        issue_number = extract_issue_number(slug)
        pr_number = extract_pr_number(slug) || find_pr_for_branch(branch)

        if pr_number
          process_pr_worktree(worktree, pr_number, issue_number)
        elsif issue_number
          process_issue_worktree(worktree, issue_number)
        else
          Aidp.log_debug("worktree_reconciler", "orphan_worktree",
            slug: slug,
            reason: "no_linked_issue_or_pr")
          {action: :skipped, reason: "orphan_worktree"}
        end
      rescue => e
        Aidp.log_error("worktree_reconciler", "process_worktree_error",
          slug: slug,
          error: e.message)
        {action: :error, error: e.message}
      end

      # Process a worktree linked to a PR
      #
      # @param worktree [Hash] Worktree info
      # @param pr_number [Integer] PR number
      # @param issue_number [Integer, nil] Linked issue number if known
      # @return [Hash] Result
      def process_pr_worktree(worktree, pr_number, issue_number)
        pr = fetch_pr_state(pr_number)

        unless pr
          Aidp.log_debug("worktree_reconciler", "pr_not_found",
            pr_number: pr_number,
            slug: worktree[:slug])
          return {action: :skipped, reason: "pr_not_found"}
        end

        case pr[:state]
        when "MERGED"
          reconcile_merged_pr(worktree, pr, issue_number)
        when "OPEN"
          resume_open_pr(worktree, pr, issue_number)
        when "CLOSED"
          handle_closed_pr(worktree, pr)
        else
          {action: :skipped, reason: "unknown_pr_state"}
        end
      end

      # Process a worktree linked to an issue (no PR yet)
      #
      # @param worktree [Hash] Worktree info
      # @param issue_number [Integer] Issue number
      # @return [Hash] Result
      def process_issue_worktree(worktree, issue_number)
        issue = fetch_issue_state(issue_number)

        unless issue
          Aidp.log_debug("worktree_reconciler", "issue_not_found",
            issue_number: issue_number,
            slug: worktree[:slug])
          return {action: :skipped, reason: "issue_not_found"}
        end

        if issue[:state] == "OPEN"
          resume_open_issue(worktree, issue)
        else
          Aidp.log_debug("worktree_reconciler", "issue_closed",
            issue_number: issue_number,
            slug: worktree[:slug])
          # Issue is closed but we have uncommitted changes
          # This could be work that was done but never pushed
          {action: :skipped, reason: "issue_closed_with_uncommitted_changes"}
        end
      end

      # Reconcile a worktree whose PR has been merged
      #
      # @param worktree [Hash] Worktree info
      # @param pr [Hash] PR data
      # @param issue_number [Integer, nil] Linked issue number
      # @return [Hash] Result
      def reconcile_merged_pr(worktree, pr, issue_number)
        return {action: :skipped, reason: "auto_reconcile_disabled"} unless @config[:auto_reconcile]

        slug = worktree[:slug]
        path = worktree[:path]

        Aidp.log_info("worktree_reconciler", "reconciling_merged_pr",
          slug: slug,
          pr_number: pr[:number])

        # Fetch latest base branch to compare against
        fetch_base_branch(path)

        # Get diff between worktree and merged base branch
        remaining_changes = get_remaining_diff(path, pr[:base_branch] || base_branch)

        if remaining_changes.empty?
          # No meaningful changes remain - clean up
          Aidp.log_info("worktree_reconciler", "no_remaining_changes",
            slug: slug,
            pr_number: pr[:number])
          cleanup_worktree(slug)
          {action: :cleaned, reason: "no_remaining_changes_after_merge"}
        else
          # There are changes that weren't in the merged PR
          Aidp.log_info("worktree_reconciler", "remaining_changes_found",
            slug: slug,
            pr_number: pr[:number],
            files_changed: remaining_changes.size)
          create_followup_pr(worktree, pr, remaining_changes, issue_number)
          {action: :reconciled, reason: "followup_pr_created"}
        end
      rescue => e
        Aidp.log_error("worktree_reconciler", "reconcile_merged_pr_failed",
          slug: slug,
          error: e.message)
        {action: :error, error: e.message}
      end

      # Resume work on an open PR
      #
      # @param worktree [Hash] Worktree info
      # @param pr [Hash] PR data
      # @param issue_number [Integer, nil] Linked issue number
      # @return [Hash] Result
      def resume_open_pr(worktree, pr, issue_number)
        return {action: :skipped, reason: "auto_resume_disabled"} unless @config[:auto_resume]

        # For open PRs with uncommitted changes, we just log it
        # The change-request processor should handle this if there are pending changes
        Aidp.log_info("worktree_reconciler", "open_pr_with_uncommitted_changes",
          slug: worktree[:slug],
          pr_number: pr[:number])

        # If we have a linked issue, try to resume via build processor
        if issue_number
          resume_via_build_processor(worktree, issue_number)
        else
          {action: :skipped, reason: "open_pr_needs_manual_attention"}
        end
      end

      # Resume work on an open issue
      #
      # @param worktree [Hash] Worktree info
      # @param issue [Hash] Issue data
      # @return [Hash] Result
      def resume_open_issue(worktree, issue)
        return {action: :skipped, reason: "auto_resume_disabled"} unless @config[:auto_resume]

        # Check if issue has the build label
        has_build_label = issue[:labels]&.any? { |l| l["name"] == @build_processor.build_label }

        if has_build_label
          resume_via_build_processor(worktree, issue[:number])
        else
          Aidp.log_debug("worktree_reconciler", "issue_missing_build_label",
            issue_number: issue[:number],
            slug: worktree[:slug])
          {action: :skipped, reason: "issue_missing_build_label"}
        end
      end

      # Handle a closed (not merged) PR
      #
      # @param worktree [Hash] Worktree info
      # @param pr [Hash] PR data
      # @return [Hash] Result
      def handle_closed_pr(worktree, pr)
        Aidp.log_info("worktree_reconciler", "closed_pr_with_uncommitted_changes",
          slug: worktree[:slug],
          pr_number: pr[:number])

        # Don't automatically delete - user might want to review the work
        {action: :skipped, reason: "pr_closed_without_merge"}
      end

      # Resume work via the build processor
      #
      # @param worktree [Hash] Worktree info
      # @param issue_number [Integer] Issue number
      # @return [Hash] Result
      def resume_via_build_processor(worktree, issue_number)
        Aidp.log_info("worktree_reconciler", "resuming_work",
          slug: worktree[:slug],
          issue_number: issue_number)

        # Fetch the full issue details
        issue = @repository_client.fetch_issue(issue_number)

        unless issue
          return {action: :error, error: "failed_to_fetch_issue"}
        end

        # Trigger the build processor
        @build_processor.process(issue)

        {action: :resumed, reason: "build_processor_triggered"}
      rescue => e
        Aidp.log_error("worktree_reconciler", "resume_failed",
          slug: worktree[:slug],
          issue_number: issue_number,
          error: e.message)
        {action: :error, error: e.message}
      end

      # Extract issue number from worktree slug
      #
      # @param slug [String] Worktree slug
      # @return [Integer, nil] Issue number or nil
      def extract_issue_number(slug)
        match = slug.match(ISSUE_SLUG_PATTERN)
        match ? match[1].to_i : nil
      end

      # Extract PR number from worktree slug
      #
      # @param slug [String] Worktree slug
      # @return [Integer, nil] PR number or nil
      def extract_pr_number(slug)
        match = slug.match(PR_SLUG_PATTERN)
        match ? match[1].to_i : nil
      end

      # Find PR number for a given branch
      #
      # @param branch [String] Branch name
      # @return [Integer, nil] PR number or nil
      def find_pr_for_branch(branch)
        # Use gh CLI to find PR for this branch
        stdout, _stderr, status = Open3.capture3(
          "gh", "pr", "list",
          "--repo", @repository_client.full_repo,
          "--head", branch,
          "--state", "all",
          "--json", "number",
          "--limit", "1"
        )

        return nil unless status.success?

        prs = JSON.parse(stdout)
        prs.first&.dig("number")
      rescue => e
        Aidp.log_debug("worktree_reconciler", "find_pr_for_branch_failed",
          branch: branch,
          error: e.message)
        nil
      end

      # Fetch PR state from GitHub
      #
      # @param pr_number [Integer] PR number
      # @return [Hash, nil] PR data or nil
      def fetch_pr_state(pr_number)
        stdout, _stderr, status = Open3.capture3(
          "gh", "pr", "view", pr_number.to_s,
          "--repo", @repository_client.full_repo,
          "--json", "number,state,mergedAt,baseRefName,headRefName,title"
        )

        return nil unless status.success?

        data = JSON.parse(stdout)
        {
          number: data["number"],
          state: data["state"],
          merged_at: data["mergedAt"],
          base_branch: data["baseRefName"],
          head_branch: data["headRefName"],
          title: data["title"]
        }
      rescue => e
        Aidp.log_debug("worktree_reconciler", "fetch_pr_state_failed",
          pr_number: pr_number,
          error: e.message)
        nil
      end

      # Fetch issue state from GitHub
      #
      # @param issue_number [Integer] Issue number
      # @return [Hash, nil] Issue data or nil
      def fetch_issue_state(issue_number)
        stdout, _stderr, status = Open3.capture3(
          "gh", "issue", "view", issue_number.to_s,
          "--repo", @repository_client.full_repo,
          "--json", "number,state,title,labels"
        )

        return nil unless status.success?

        data = JSON.parse(stdout)
        {
          number: data["number"],
          state: data["state"],
          title: data["title"],
          labels: data["labels"]
        }
      rescue => e
        Aidp.log_debug("worktree_reconciler", "fetch_issue_state_failed",
          issue_number: issue_number,
          error: e.message)
        nil
      end

      # Fetch the latest base branch in the worktree
      #
      # @param path [String] Worktree path
      def fetch_base_branch(path)
        Open3.capture3("git", "fetch", "origin", base_branch, chdir: path)
      end

      # Get list of files with remaining changes after merge
      #
      # @param path [String] Worktree path
      # @param target_branch [String] Branch to compare against
      # @return [Array<String>] List of changed files
      def get_remaining_diff(path, target_branch)
        # First, get list of modified/untracked files in worktree
        stdout, _stderr, status = Open3.capture3(
          "git", "status", "--porcelain",
          chdir: path
        )

        return [] unless status.success?

        changed_files = stdout.lines.map { |line| line[3..].strip }.reject(&:empty?)
        return [] if changed_files.empty?

        # For each changed file, check if it differs from the target branch
        remaining = []
        changed_files.each do |file|
          # Check if file content differs from target branch
          diff_out, _diff_err, diff_status = Open3.capture3(
            "git", "diff", "origin/#{target_branch}", "--", file,
            chdir: path
          )

          # If diff is non-empty, this file has changes not in target branch
          remaining << file if diff_status.success? && !diff_out.strip.empty?
        end

        remaining
      rescue => e
        Aidp.log_error("worktree_reconciler", "get_remaining_diff_failed",
          path: path,
          error: e.message)
        []
      end

      # Create a follow-up PR for remaining changes
      #
      # @param worktree [Hash] Worktree info
      # @param original_pr [Hash] Original merged PR data
      # @param changed_files [Array<String>] Files with changes
      # @param issue_number [Integer, nil] Linked issue number
      def create_followup_pr(worktree, original_pr, changed_files, issue_number)
        path = worktree[:path]
        slug = worktree[:slug]

        Aidp.log_info("worktree_reconciler", "creating_followup_pr",
          slug: slug,
          original_pr: original_pr[:number],
          changed_files: changed_files.size)

        # Create a new branch for the follow-up
        followup_branch = "#{worktree[:branch]}-followup-#{Time.now.to_i}"

        Dir.chdir(path) do
          # Checkout a new branch from current state
          Open3.capture3("git", "checkout", "-b", followup_branch)

          # Stage all changes
          Open3.capture3("git", "add", "-A")

          # Build commit message parts
          issue_ref = issue_number ? "Related issue: ##{issue_number}\n" : ""
          files_list = changed_files.map { |f| "- #{f}" }.join("\n")

          commit_message = <<~MSG
            Follow-up changes from PR ##{original_pr[:number]}

            These changes were found in a local worktree after PR ##{original_pr[:number]}
            was merged from another machine. This follow-up PR captures the remaining
            uncommitted work.

            Original PR: ##{original_pr[:number]} - #{original_pr[:title]}
            #{issue_ref}
            Changed files:
            #{files_list}

            🤖 Generated with [Claude Code](https://claude.com/claude-code)

            Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
          MSG

          Open3.capture3("git", "commit", "-m", commit_message)

          # Push the branch
          Open3.capture3("git", "push", "-u", "origin", followup_branch)

          # Build PR body parts
          issue_context = issue_number ? "- Related issue: ##{issue_number}\n" : ""
          files_md = changed_files.map { |f| "- `#{f}`" }.join("\n")

          pr_body = <<~BODY
            ## Summary

            This PR captures follow-up changes that were found in a local worktree after
            PR ##{original_pr[:number]} was merged from another machine.

            ## Context

            - Original PR: ##{original_pr[:number]}
            #{issue_context}
            ## Changed Files

            #{files_md}

            ## Review Notes

            Please review these changes carefully - they represent uncommitted work that
            was not included in the original PR merge.

            🤖 Generated with [Claude Code](https://claude.com/claude-code)
          BODY

          pr_title = "Follow-up: Additional changes from PR ##{original_pr[:number]}"

          stdout, stderr, status = Open3.capture3(
            "gh", "pr", "create",
            "--repo", @repository_client.full_repo,
            "--title", pr_title,
            "--body", pr_body,
            "--base", original_pr[:base_branch] || base_branch,
            "--head", followup_branch
          )

          if status.success?
            Aidp.log_info("worktree_reconciler", "followup_pr_created",
              slug: slug,
              pr_url: stdout.strip)
          else
            Aidp.log_error("worktree_reconciler", "followup_pr_creation_failed",
              slug: slug,
              error: stderr)
          end
        end
      rescue => e
        Aidp.log_error("worktree_reconciler", "create_followup_pr_failed",
          slug: slug,
          error: e.message)
      end

      # Clean up a worktree
      #
      # @param slug [String] Worktree slug
      def cleanup_worktree(slug)
        Aidp.log_info("worktree_reconciler", "cleaning_up_worktree", slug: slug)

        Aidp::Worktree.remove(
          slug: slug,
          project_dir: @project_dir,
          delete_branch: true
        )
      rescue => e
        Aidp.log_error("worktree_reconciler", "cleanup_failed",
          slug: slug,
          error: e.message)
      end
    end
  end
end
