# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Creates sub-issues from a hierarchical plan during watch mode.
    # Links sub-issues to parent, adds them to projects, and sets custom fields.
    class SubIssueCreator
      include Aidp::MessageDisplay

      UnresolvedDependenciesError = Class.new(StandardError)

      attr_reader :repository_client, :state_store, :project_id

      def initialize(repository_client:, state_store:, project_id: nil, build_label: "aidp-build", blocked_label: "aidp-blocked")
        @repository_client = repository_client
        @state_store = state_store
        @project_id = project_id
        @build_label = build_label
        @blocked_label = blocked_label
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
        creation_failed = false

        sub_issues_data.each_with_index do |sub_data, index|
          issue = create_single_sub_issue(parent_issue, sub_data, index + 1)
          created_issues << issue
          display_message("  ✓ Created sub-issue ##{issue[:number]}: #{sub_data[:title]}", type: :success)
        rescue => e
          creation_failed = true
          Aidp.log_error("sub_issue_creator", "Failed to create sub-issue", parent: parent_number, index: index, error: e.message)
          display_message("  ✗ Failed to create sub-issue #{index + 1}: #{e.message}", type: :error)
          break
        end

        return handle_partial_creation_failure(parent_number, created_issues) if creation_failed

        record_dependencies(created_issues)

        # Link all created issues to project if project_id is configured
        if @project_id && created_issues.any?
          link_issues_to_project(parent_number, created_issues.map { |i| i[:number] })
        end

        # Persist the hierarchy only after creation and dependency resolution succeed.
        @state_store.record_sub_issues(parent_number, created_issues.map { |i| i[:number] })

        # Post summary comment on parent issue
        post_sub_issues_summary(parent_issue, created_issues)

        Aidp.log_debug("sub_issue_creator", "create_sub_issues_complete", parent: parent_number, created: created_issues.size)
        created_issues
      rescue UnresolvedDependenciesError
        cleanup_created_issues(parent_number, created_issues)
        raise
      end

      def planned_sub_issue_attributes(parent_issue, sub_data, sequence_number)
        dependencies = sub_issue_dependencies(sub_data)
        title = sub_data[:title]
        title = "#{parent_issue[:title]} - Part #{sequence_number}" if title.to_s.strip.empty?

        {
          title: title,
          body: build_sub_issue_body(parent_issue, sub_data, sequence_number),
          labels: sub_issue_labels(sub_data, dependencies),
          assignees: Array(sub_data[:assignees]),
          dependencies: dependencies
        }
      end

      private

      def create_single_sub_issue(parent_issue, sub_data, sequence_number)
        parent_number = parent_issue[:number]
        Aidp.log_debug("sub_issue_creator", "create_single_sub_issue", parent: parent_number, sequence: sequence_number)

        attributes = planned_sub_issue_attributes(parent_issue, sub_data, sequence_number)

        # Create the issue
        result = @repository_client.create_issue(
          title: attributes[:title],
          body: attributes[:body],
          labels: attributes[:labels],
          assignees: attributes[:assignees]
        )

        Aidp.log_debug("sub_issue_creator", "issue_created", parent: parent_number, number: result[:number], url: result[:url])

        {
          number: result[:number],
          url: result[:url],
          title: attributes[:title],
          skills: sub_data[:skills],
          personas: sub_data[:personas],
          dependencies: attributes[:dependencies]
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
        parts << "Dependency-ready sub-issues have been labeled with `#{@build_label}`."
        parts << "Sub-issues waiting on prerequisites have been labeled with `#{@blocked_label}` until their dependencies are complete."
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

      def record_dependencies(created_issues)
        title_map = build_title_map(created_issues)

        created_issues.each do |issue|
          dependency_numbers, unresolved_dependencies = resolve_dependency_numbers(issue[:dependencies], title_map)
          raise_unresolved_dependencies!(issue, unresolved_dependencies) if unresolved_dependencies.any?

          @state_store.record_issue_dependencies(issue[:number], dependency_numbers)
          issue[:dependencies] = dependency_numbers
        end
      end

      def resolve_dependency_numbers(dependencies, title_map)
        Array(dependencies).each_with_object([[], []]) do |dependency, (resolved, unresolved)|
          dependency_number = resolve_dependency_number(dependency, title_map)
          dependency_number ? resolved << dependency_number : unresolved << dependency
        end
      end

      def raise_unresolved_dependencies!(issue, unresolved_dependencies)
        dependency_list = unresolved_dependencies.join(", ")
        raise UnresolvedDependenciesError,
          "Unable to resolve dependencies for sub-issue ##{issue[:number]} (#{issue[:title]}): #{dependency_list}"
      end

      def build_title_map(created_issues)
        duplicate_titles = duplicate_normalized_titles(created_issues)
        if duplicate_titles.empty?
          return created_issues.each_with_object({}) do |issue, memo|
            memo[normalize_title(issue[:title])] = issue[:number]
          end
        end

        raise UnresolvedDependenciesError,
          "Duplicate sub-issue titles after normalization are not allowed: #{duplicate_titles.join(", ")}"
      end

      def duplicate_normalized_titles(created_issues)
        grouped_titles = created_issues.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |issue, memo|
          normalized_title = normalize_title(issue[:title])
          next if normalized_title.empty?

          memo[normalized_title] << issue[:title].to_s.strip
        end

        grouped_titles.filter_map do |_normalized_title, titles|
          next unless titles.size > 1

          titles.uniq.join(" / ")
        end
      end

      def normalize_title(title)
        title.to_s.strip.downcase
      end

      def resolve_dependency_number(dependency, title_map)
        text = dependency.to_s.strip
        match = text.match(/\A#(\d+)\z/)
        return match[1].to_i if match

        title_map[normalize_title(text)]
      end

      def sub_issue_dependencies(sub_data)
        Array(sub_data[:dependencies]).map(&:to_s).reject(&:empty?)
      end

      def sub_issue_labels(sub_data, dependencies)
        [dependencies.any? ? @blocked_label : @build_label].concat(Array(sub_data[:labels]))
      end

      def handle_partial_creation_failure(parent_number, created_issues)
        cleanup_created_issues(parent_number, created_issues)
        []
      end

      def cleanup_created_issues(parent_number, created_issues)
        return if created_issues.empty?

        Aidp.log_warn("sub_issue_creator", "cleanup_created_sub_issues",
          parent: parent_number,
          sub_issue_numbers: created_issues.map { |issue| issue[:number] })
        display_message("🧹 Cleaning up #{created_issues.size} partially created sub-issues for ##{parent_number}", type: :warn)

        created_issues.each do |issue|
          @repository_client.close_issue(issue[:number])
          display_message("  ✓ Closed sub-issue ##{issue[:number]}", type: :success)
        rescue => e
          Aidp.log_error("sub_issue_creator", "Failed to clean up sub-issue", issue: issue[:number], error: e.message)
          display_message("  ✗ Failed to close sub-issue ##{issue[:number]}: #{e.message}", type: :warn)
        end
      end
    end
  end
end
