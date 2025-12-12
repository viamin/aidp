# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Handles hierarchical PR creation strategy for parent and sub-issues.
    # Parent issues get draft PRs targeting main. Sub-issues get PRs targeting
    # the parent's branch.
    class HierarchicalPrStrategy
      include Aidp::MessageDisplay

      # Labels for hierarchical PR identification
      PARENT_PR_LABEL = "aidp-parent-pr"
      SUB_PR_LABEL = "aidp-sub-pr"

      attr_reader :repository_client, :state_store

      def initialize(repository_client:, state_store:)
        @repository_client = repository_client
        @state_store = state_store
      end

      # Determine if an issue is a parent issue (has sub-issues)
      # @param issue_number [Integer] The issue number
      # @return [Boolean] True if this is a parent issue
      def parent_issue?(issue_number)
        sub_issues = @state_store.sub_issues(issue_number)
        sub_issues.any?
      end

      # Determine if an issue is a sub-issue (has a parent)
      # @param issue_number [Integer] The issue number
      # @return [Boolean] True if this is a sub-issue
      def sub_issue?(issue_number)
        parent = @state_store.parent_issue(issue_number)
        !parent.nil?
      end

      # Get PR creation options for an issue based on its hierarchy position
      # @param issue [Hash] The issue data
      # @param default_base_branch [String] The default base branch (e.g., "main")
      # @return [Hash] PR options including :base_branch, :draft, :labels
      def pr_options_for_issue(issue, default_base_branch:)
        issue_number = issue[:number]
        Aidp.log_debug("hierarchical_pr_strategy", "determining_pr_options",
          issue_number: issue_number, default_base: default_base_branch)

        if parent_issue?(issue_number)
          parent_pr_options(issue, default_base_branch)
        elsif sub_issue?(issue_number)
          sub_issue_pr_options(issue, default_base_branch)
        else
          # Regular issue - use default behavior
          regular_pr_options(issue, default_base_branch)
        end
      end

      # Generate branch name for hierarchical issues
      # @param issue [Hash] The issue data
      # @return [String] The branch name
      def branch_name_for(issue)
        issue_number = issue[:number]
        slug = issue_slug(issue)

        if parent_issue?(issue_number)
          # Parent branch: aidp/parent-{number}-{slug}
          "aidp/parent-#{issue_number}-#{slug}"
        elsif sub_issue?(issue_number)
          parent_number = @state_store.parent_issue(issue_number)
          # Sub-issue branch: aidp/sub-{parent}-{number}-{slug}
          "aidp/sub-#{parent_number}-#{issue_number}-#{slug}"
        else
          # Regular branch: aidp/issue-{number}-{slug}
          "aidp/issue-#{issue_number}-#{slug}"
        end
      end

      # Build PR description with hierarchy context
      # @param issue [Hash] The issue data
      # @param plan_summary [String] The plan summary
      # @return [String] The PR description
      def pr_description_for(issue, plan_summary:)
        issue_number = issue[:number]

        if parent_issue?(issue_number)
          build_parent_pr_description(issue, plan_summary)
        elsif sub_issue?(issue_number)
          build_sub_issue_pr_description(issue, plan_summary)
        else
          build_regular_pr_description(issue, plan_summary)
        end
      end

      # Get the base branch for a sub-issue PR (the parent's branch)
      # @param issue_number [Integer] The sub-issue number
      # @return [String, nil] The parent's branch name, or nil if not found
      def parent_branch_for_sub_issue(issue_number)
        parent_number = @state_store.parent_issue(issue_number)
        return nil unless parent_number

        parent_build = @state_store.workstream_for_issue(parent_number)
        return nil unless parent_build

        parent_build[:branch]
      end

      private

      def issue_slug(issue)
        issue[:title].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")[0, 32]
      end

      def parent_pr_options(issue, default_base_branch)
        Aidp.log_debug("hierarchical_pr_strategy", "parent_pr_options",
          issue_number: issue[:number])

        {
          base_branch: default_base_branch,
          draft: true, # Parent PRs always start as draft
          labels: [PARENT_PR_LABEL],
          additional_context: build_parent_context(issue)
        }
      end

      def sub_issue_pr_options(issue, default_base_branch)
        issue_number = issue[:number]
        parent_branch = parent_branch_for_sub_issue(issue_number)

        Aidp.log_debug("hierarchical_pr_strategy", "sub_issue_pr_options",
          issue_number: issue_number, parent_branch: parent_branch)

        # If parent branch exists, target it; otherwise fall back to default
        base = parent_branch || default_base_branch

        {
          base_branch: base,
          draft: false, # Sub-PRs can be non-draft (will be auto-merged)
          labels: [SUB_PR_LABEL],
          additional_context: build_sub_issue_context(issue)
        }
      end

      def regular_pr_options(issue, default_base_branch)
        {
          base_branch: default_base_branch,
          draft: true,
          labels: [],
          additional_context: nil
        }
      end

      def build_parent_context(issue)
        issue_number = issue[:number]
        sub_issues = @state_store.sub_issues(issue_number)

        return nil if sub_issues.empty?

        lines = []
        lines << "### Sub-Issues"
        lines << ""
        lines << "This parent PR aggregates the following sub-issues:"
        lines << ""

        sub_issues.each do |sub_number|
          sub_build = @state_store.workstream_for_issue(sub_number)
          pr_link = sub_build&.dig(:pr_url) ? sub_build[:pr_url] : "_(PR pending)_"
          lines << "- ##{sub_number}: #{pr_link}"
        end

        lines << ""
        lines << "**Note:** This PR will be ready for review once all sub-issue PRs are merged."
        lines.join("\n")
      end

      def build_sub_issue_context(issue)
        issue_number = issue[:number]
        parent_number = @state_store.parent_issue(issue_number)

        return nil unless parent_number

        parent_build = @state_store.workstream_for_issue(parent_number)

        lines = []
        lines << "### Parent Issue"
        lines << ""
        lines << "This PR implements a sub-issue of ##{parent_number}."
        lines << ""

        pr_link = parent_build&.dig(:pr_url) || "_(pending)_"
        lines << "**Parent PR:** #{pr_link}"

        lines << ""
        lines << "This sub-issue PR will be automatically merged when CI passes."
        lines.join("\n")
      end

      def build_parent_pr_description(issue, plan_summary)
        issue_number = issue[:number]
        sub_context = build_parent_context(issue)

        parts = []
        parts << "Implements ##{issue_number}"
        parts << ""
        parts << "## Summary"
        parts << plan_summary
        parts << ""

        if sub_context
          parts << sub_context
          parts << ""
        end

        parts << "---"
        parts << "_This is a parent PR that aggregates changes from sub-issue PRs._"
        parts << "_It requires human review before merging to the main branch._"

        parts.join("\n")
      end

      def build_sub_issue_pr_description(issue, plan_summary)
        issue_number = issue[:number]
        sub_context = build_sub_issue_context(issue)

        parts = []
        parts << "Fixes ##{issue_number}"
        parts << ""
        parts << "## Summary"
        parts << plan_summary
        parts << ""

        if sub_context
          parts << sub_context
          parts << ""
        end

        parts << "---"
        parts << "_This is a sub-issue PR that will be auto-merged when CI passes._"

        parts.join("\n")
      end

      def build_regular_pr_description(issue, plan_summary)
        <<~DESCRIPTION
          Fixes ##{issue[:number]}

          ## Summary
          #{plan_summary}

          ---
          _Automated implementation by AIDP._
        DESCRIPTION
      end
    end
  end
end
