# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Automatically merges sub-issue PRs when CI passes and conditions are met.
    # Never auto-merges parent PRs - those require human review.
    class AutoMerger
      include Aidp::MessageDisplay

      # Labels that indicate PR type
      PARENT_PR_LABEL = "aidp-parent-pr"
      SUB_PR_LABEL = "aidp-sub-pr"

      # Default configuration
      DEFAULT_CONFIG = {
        enabled: true,
        sub_issue_prs_only: true,
        require_ci_success: true,
        require_reviews: 0,
        merge_method: "squash",
        delete_branch: true
      }.freeze

      attr_reader :repository_client, :state_store

      def initialize(repository_client:, state_store:, config: {})
        @repository_client = repository_client
        @state_store = state_store
        @config = DEFAULT_CONFIG.merge(config)
      end

      # Check if a PR can be auto-merged
      # @param pr_number [Integer] The PR number
      # @return [Hash] Result with :can_merge flag and :reason
      def can_auto_merge?(pr_number)
        Aidp.log_debug("auto_merger", "checking_can_auto_merge", pr_number: pr_number)

        return {can_merge: false, reason: "Auto-merge is disabled"} unless @config[:enabled]

        # Fetch PR details
        pr = begin
          @repository_client.fetch_pull_request(pr_number)
        rescue => e
          Aidp.log_error("auto_merger", "Failed to fetch PR", pr_number: pr_number, error: e.message)
          return {can_merge: false, reason: "Failed to fetch PR: #{e.message}"}
        end

        # Check if it's a parent PR (never auto-merge)
        if pr[:labels].include?(PARENT_PR_LABEL)
          Aidp.log_debug("auto_merger", "skipping_parent_pr", pr_number: pr_number)
          return {can_merge: false, reason: "Parent PRs require human review"}
        end

        # Check if sub-PRs only mode requires the sub-PR label
        if @config[:sub_issue_prs_only] && !pr[:labels].include?(SUB_PR_LABEL)
          Aidp.log_debug("auto_merger", "not_a_sub_pr", pr_number: pr_number)
          return {can_merge: false, reason: "Not a sub-issue PR (missing #{SUB_PR_LABEL} label)"}
        end

        # Check PR state
        unless pr[:state] == "open" || pr[:state] == "OPEN"
          return {can_merge: false, reason: "PR is not open (state: #{pr[:state]})"}
        end

        # Check mergeability
        if pr[:mergeable] == false
          return {can_merge: false, reason: "PR has merge conflicts"}
        end

        # Check CI status
        if @config[:require_ci_success]
          ci_status = @repository_client.fetch_ci_status(pr_number)
          unless ci_status[:state] == "success"
            Aidp.log_debug("auto_merger", "ci_not_passed",
              pr_number: pr_number, ci_state: ci_status[:state])
            return {can_merge: false, reason: "CI has not passed (status: #{ci_status[:state]})"}
          end
        end

        # All checks passed
        Aidp.log_debug("auto_merger", "can_auto_merge", pr_number: pr_number)
        {can_merge: true, reason: "All merge conditions met"}
      end

      # Attempt to merge a PR
      # @param pr_number [Integer] The PR number
      # @return [Hash] Result with :success flag, :reason, and optional :merge_sha
      def merge_pr(pr_number)
        Aidp.log_debug("auto_merger", "attempting_merge", pr_number: pr_number)

        # Verify can merge
        eligibility = can_auto_merge?(pr_number)
        unless eligibility[:can_merge]
          return {success: false, reason: eligibility[:reason]}
        end

        begin
          result = @repository_client.merge_pull_request(
            pr_number,
            merge_method: @config[:merge_method]
          )

          Aidp.log_info("auto_merger", "pr_merged",
            pr_number: pr_number, merge_method: @config[:merge_method])
          display_message("✅ Auto-merged PR ##{pr_number}", type: :success)

          # Post comment about auto-merge
          post_merge_comment(pr_number)

          # Update parent issue/PR if this was a sub-issue PR
          update_parent_after_merge(pr_number)

          {success: true, reason: "Successfully merged", result: result}
        rescue => e
          Aidp.log_error("auto_merger", "merge_failed",
            pr_number: pr_number, error: e.message)
          display_message("❌ Failed to auto-merge PR ##{pr_number}: #{e.message}", type: :error)
          {success: false, reason: "Merge failed: #{e.message}"}
        end
      end

      # Process all eligible PRs for auto-merge
      # @param prs [Array<Hash>] Array of PR data with :number keys
      # @return [Hash] Summary with :merged, :skipped, :failed counts
      def process_auto_merge_candidates(prs)
        Aidp.log_debug("auto_merger", "processing_candidates", count: prs.size)

        merged = 0
        skipped = 0
        failed = 0

        prs.each do |pr|
          pr_number = pr[:number]

          eligibility = can_auto_merge?(pr_number)
          unless eligibility[:can_merge]
            Aidp.log_debug("auto_merger", "skipping_pr",
              pr_number: pr_number, reason: eligibility[:reason])
            skipped += 1
            next
          end

          result = merge_pr(pr_number)
          if result[:success]
            merged += 1
          else
            failed += 1
          end
        end

        summary = {merged: merged, skipped: skipped, failed: failed}
        Aidp.log_info("auto_merger", "processing_complete", **summary)
        display_message("🔀 Auto-merge: #{merged} merged, #{skipped} skipped, #{failed} failed",
          type: :info)
        summary
      end

      # List all PRs with the sub-PR label that are candidates for auto-merge
      # @return [Array<Hash>] PRs that might be eligible for auto-merge
      def list_sub_pr_candidates
        begin
          @repository_client.list_pull_requests(labels: [SUB_PR_LABEL], state: "open")
        rescue => e
          Aidp.log_error("auto_merger", "Failed to list sub-PR candidates", error: e.message)
          []
        end
      end

      private

      def post_merge_comment(pr_number)
        comment = <<~COMMENT
          ✅ This PR was automatically merged by AIDP after CI passed.

          Merge method: `#{@config[:merge_method]}`

          ---
          _Sub-issue PRs are automatically merged when CI passes. Parent PRs always require human review._
        COMMENT

        begin
          @repository_client.post_comment(pr_number, comment)
        rescue => e
          Aidp.log_warn("auto_merger", "Failed to post merge comment",
            pr_number: pr_number, error: e.message)
        end
      end

      def update_parent_after_merge(pr_number)
        # Find the parent issue for this sub-PR
        # The sub-PR should target the parent's branch, so we can identify it

        # First, check if we have hierarchy data
        build_data = @state_store.find_build_by_pr(pr_number)
        return unless build_data

        issue_number = build_data[:issue_number]
        parent_number = @state_store.parent_issue(issue_number)
        return unless parent_number

        Aidp.log_debug("auto_merger", "updating_parent_after_merge",
          sub_issue: issue_number, parent: parent_number)

        # Check if all sub-issues are now complete
        sub_issues = @state_store.sub_issues(parent_number)
        all_complete = sub_issues.all? do |sub_number|
          sub_build = @state_store.workstream_for_issue(sub_number)
          sub_build && sub_build[:status] == "completed"
        end

        if all_complete
          notify_parent_ready_for_review(parent_number)
        end
      rescue => e
        Aidp.log_warn("auto_merger", "Failed to update parent after merge",
          pr_number: pr_number, error: e.message)
      end

      def notify_parent_ready_for_review(parent_number)
        Aidp.log_info("auto_merger", "all_sub_issues_complete", parent: parent_number)

        comment = <<~COMMENT
          🎉 All sub-issue PRs have been merged!

          The parent PR is now ready for final review and merge to main.

          ### Sub-Issues Completed
          #{format_sub_issues_list(parent_number)}

          **Next Steps:**
          1. Review the combined changes in the parent PR
          2. Ensure all integration tests pass
          3. Merge the parent PR manually

          ---
          _Parent PRs are never auto-merged and require human review._
        COMMENT

        begin
          @repository_client.post_comment(parent_number, comment)
          display_message("📋 Notified parent issue ##{parent_number} that all sub-PRs are merged",
            type: :success)

          # Mark the parent PR as ready for review if it's still draft
          parent_build = @state_store.workstream_for_issue(parent_number)
          if parent_build && parent_build[:pr_url]
            pr_number = parent_build[:pr_url].split("/").last.to_i
            begin
              @repository_client.mark_pr_ready_for_review(pr_number)
              display_message("✅ Marked parent PR ##{pr_number} as ready for review", type: :success)
            rescue => e
              Aidp.log_warn("auto_merger", "Failed to mark parent PR ready",
                pr_number: pr_number, error: e.message)
            end
          end
        rescue => e
          Aidp.log_warn("auto_merger", "Failed to notify parent",
            parent: parent_number, error: e.message)
        end
      end

      def format_sub_issues_list(parent_number)
        sub_issues = @state_store.sub_issues(parent_number)
        return "_No sub-issues found_" if sub_issues.empty?

        sub_issues.map do |sub_number|
          build = @state_store.workstream_for_issue(sub_number)
          pr_link = build&.dig(:pr_url) || "No PR"
          "- ##{sub_number}: #{pr_link}"
        end.join("\n")
      end
    end
  end
end
