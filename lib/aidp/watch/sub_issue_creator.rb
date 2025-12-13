# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Creates sub-issues from a hierarchical plan during watch mode.
    # Links sub-issues to parent, adds them to projects, and sets custom fields.
    class SubIssueCreator
      include Aidp::MessageDisplay

      attr_reader :repository_client, :state_store, :project_id

      def initialize(repository_client:, state_store:, project_id: nil)
        @repository_client = repository_client
        @state_store = state_store
        @project_id = project_id
      end

      # Creates sub-issues from hierarchical plan data
      # @param parent_issue [Hash] The parent issue data
      # @param sub_issues_data [Array<Hash>] Array of sub-issue specifications
      # @return [Array<Hash>] Created sub-issue details
      def create_sub_issues(parent_issue, sub_issues_data)
        parent_number = parent_issue[:number]
        Aidp.log_debug("sub_issue_creator", "create_sub_issues", parent: parent_number, count: sub_issues_data.size)

        display_message("🔨 Creating #{sub_issues_data.size} sub-issues for ##{parent_number}", type: :info)

        created_issues = []

        sub_issues_data.each_with_index do |sub_data, index|
          issue = create_single_sub_issue(parent_issue, sub_data, index + 1)
          created_issues << issue
          display_message("  ✓ Created sub-issue ##{issue[:number]}: #{sub_data[:title]}", type: :success)
        rescue => e
          Aidp.log_error("sub_issue_creator", "Failed to create sub-issue", parent: parent_number, index: index, error: e.message)
          display_message("  ✗ Failed to create sub-issue #{index + 1}: #{e.message}", type: :error)
        end

        # Link all created issues to project if project_id is configured
        if @project_id && created_issues.any?
          link_issues_to_project(parent_number, created_issues.map { |i| i[:number] })
        end

        # Update state store with parent-child relationships
        @state_store.record_sub_issues(parent_number, created_issues.map { |i| i[:number] })

        # Post summary comment on parent issue
        post_sub_issues_summary(parent_issue, created_issues)

        Aidp.log_debug("sub_issue_creator", "create_sub_issues_complete", parent: parent_number, created: created_issues.size)
        created_issues
      end

      private

      def create_single_sub_issue(parent_issue, sub_data, sequence_number)
        parent_number = parent_issue[:number]
        Aidp.log_debug("sub_issue_creator", "create_single_sub_issue", parent: parent_number, sequence: sequence_number)

        # Build issue title
        title = sub_data[:title]
        title = "#{parent_issue[:title]} - Part #{sequence_number}" if title.to_s.strip.empty?

        # Build issue body with parent reference
        body = build_sub_issue_body(parent_issue, sub_data, sequence_number)

        # Determine labels
        labels = ["aidp-auto"]
        labels.concat(Array(sub_data[:labels])) if sub_data[:labels]

        # Create the issue
        result = @repository_client.create_issue(
          title: title,
          body: body,
          labels: labels,
          assignees: Array(sub_data[:assignees])
        )

        Aidp.log_debug("sub_issue_creator", "issue_created", parent: parent_number, number: result[:number], url: result[:url])

        {
          number: result[:number],
          url: result[:url],
          title: title,
          skills: sub_data[:skills],
          personas: sub_data[:personas],
          dependencies: sub_data[:dependencies]
        }
      end

      def build_sub_issue_body(parent_issue, sub_data, sequence_number)
        parts = []

        # Parent reference
        parts << "## 🔗 Parent Issue"
        parts << ""
        parts << "This is sub-issue #{sequence_number} of #{parent_issue[:url]}"
        parts << ""

        # Description
        if sub_data[:description] && !sub_data[:description].to_s.strip.empty?
          parts << "## 📋 Description"
          parts << ""
          parts << sub_data[:description]
          parts << ""
        end

        # Tasks
        if sub_data[:tasks]&.any?
          parts << "## ✅ Tasks"
          parts << ""
          sub_data[:tasks].each do |task|
            parts << "- [ ] #{task}"
          end
          parts << ""
        end

        # Skills required
        if sub_data[:skills]&.any?
          parts << "## 🛠️ Skills Required"
          parts << ""
          parts << sub_data[:skills].map { |s| "- #{s}" }.join("\n")
          parts << ""
        end

        # Personas
        if sub_data[:personas]&.any?
          parts << "## 👤 Suggested Personas"
          parts << ""
          parts << sub_data[:personas].map { |p| "- #{p}" }.join("\n")
          parts << ""
        end

        # Dependencies
        if sub_data[:dependencies]&.any?
          parts << "## ⚠️ Dependencies"
          parts << ""
          parts << "This issue depends on:"
          parts << sub_data[:dependencies].map { |d| "- #{d}" }.join("\n")
          parts << ""
        end

        # Footer
        parts << "---"
        parts << "_This issue was automatically created by AIDP as part of hierarchical project planning._"

        parts.join("\n")
      end

      def link_issues_to_project(parent_number, sub_issue_numbers)
        Aidp.log_debug("sub_issue_creator", "link_issues_to_project", parent: parent_number, project_id: @project_id, count: sub_issue_numbers.size + 1)

        display_message("📊 Linking issues to project #{@project_id}", type: :info)

        # Link parent issue
        begin
          parent_item_id = @repository_client.link_issue_to_project(@project_id, parent_number)
          @state_store.record_project_item_id(parent_number, parent_item_id)
          display_message("  ✓ Linked parent issue ##{parent_number}", type: :success)
        rescue => e
          Aidp.log_error("sub_issue_creator", "Failed to link parent to project", parent: parent_number, error: e.message)
          display_message("  ✗ Failed to link parent issue: #{e.message}", type: :warn)
        end

        # Link sub-issues
        sub_issue_numbers.each do |number|
          item_id = @repository_client.link_issue_to_project(@project_id, number)
          @state_store.record_project_item_id(number, item_id)
          display_message("  ✓ Linked sub-issue ##{number}", type: :success)
        rescue => e
          Aidp.log_error("sub_issue_creator", "Failed to link sub-issue to project", issue: number, error: e.message)
          display_message("  ✗ Failed to link sub-issue ##{number}: #{e.message}", type: :warn)
        end
      end

      def post_sub_issues_summary(parent_issue, created_issues)
        parent_number = parent_issue[:number]
        Aidp.log_debug("sub_issue_creator", "post_sub_issues_summary", parent: parent_number, count: created_issues.size)

        return if created_issues.empty?

        parts = []
        parts << "## 🔀 Sub-Issues Created"
        parts << ""
        parts << "AIDP has broken down this issue into #{created_issues.size} sub-issues:"
        parts << ""

        created_issues.each_with_index do |issue, index|
          parts << "#{index + 1}. ##{issue[:number]} - #{issue[:title]}"

          metadata = []
          metadata << "**Skills**: #{issue[:skills].join(", ")}" if issue[:skills]&.any?
          metadata << "**Personas**: #{issue[:personas].join(", ")}" if issue[:personas]&.any?
          metadata << "**Depends on**: #{issue[:dependencies].join(", ")}" if issue[:dependencies]&.any?

          if metadata.any?
            parts << "   - #{metadata.join(" | ")}"
          end
        end

        parts << ""
        parts << "Each sub-issue has been labeled with `aidp-auto` and will be automatically picked up for implementation."
        parts << ""
        parts << "---"
        parts << "_This breakdown was automatically generated by AIDP._"

        body = parts.join("\n")

        begin
          @repository_client.post_comment(parent_number, body)
          display_message("💬 Posted sub-issues summary to parent issue ##{parent_number}", type: :success)
        rescue => e
          Aidp.log_error("sub_issue_creator", "Failed to post summary comment", parent: parent_number, error: e.message)
          display_message("⚠️  Failed to post summary comment: #{e.message}", type: :warn)
        end
      end
    end
  end
end
