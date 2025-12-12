# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Synchronizes GitHub issues with GitHub Projects V2.
    # Updates project fields based on issue state and handles blocking relationships.
    class ProjectsProcessor
      include Aidp::MessageDisplay

      # Default field mapping configuration
      DEFAULT_FIELD_MAPPINGS = {
        status: "Status",
        priority: "Priority",
        skills: "Skills",
        personas: "Personas",
        blocking: "Blocking"
      }.freeze

      # Status values for different issue states
      STATUS_VALUES = {
        backlog: "Backlog",
        todo: "Todo",
        in_progress: "In Progress",
        in_review: "In Review",
        done: "Done",
        blocked: "Blocked"
      }.freeze

      attr_reader :repository_client, :state_store, :project_id

      def initialize(repository_client:, state_store:, project_id:, config: {})
        @repository_client = repository_client
        @state_store = state_store
        @project_id = project_id
        @config = config
        @field_mappings = config[:field_mappings] || DEFAULT_FIELD_MAPPINGS
        @auto_create_fields = config[:auto_create_fields] != false
        @project_fields_cache = nil
      end

      # Sync a single issue to the project
      # @param issue_number [Integer] The issue number
      # @param status [String, nil] Optional status to set
      # @return [Boolean] True if sync was successful
      def sync_issue_to_project(issue_number, status: nil)
        Aidp.log_debug("projects_processor", "sync_issue_to_project", issue_number: issue_number, status: status)

        # Check if issue is already linked to project
        item_id = @state_store.project_item_id(issue_number)

        unless item_id
          # Link issue to project
          begin
            item_id = @repository_client.link_issue_to_project(@project_id, issue_number)
            @state_store.record_project_item_id(issue_number, item_id)
            display_message("📊 Linked issue ##{issue_number} to project", type: :success)
          rescue => e
            Aidp.log_error("projects_processor", "Failed to link issue to project",
              issue_number: issue_number, error: e.message)
            display_message("⚠️  Failed to link issue ##{issue_number} to project: #{e.message}", type: :warn)
            return false
          end
        end

        # Update status if provided
        if status
          update_issue_status(issue_number, status)
        end

        # Check and update blocking status
        check_blocking_dependencies(issue_number)

        @state_store.record_project_sync(issue_number, {
          last_sync: Time.now.utc.iso8601,
          status: status
        })

        true
      rescue => e
        Aidp.log_error("projects_processor", "Failed to sync issue to project",
          issue_number: issue_number, error: e.message)
        false
      end

      # Update the status field for an issue in the project
      # @param issue_number [Integer] The issue number
      # @param status [String] The status value (e.g., "In Progress", "Done")
      # @return [Boolean] True if update was successful
      def update_issue_status(issue_number, status)
        Aidp.log_debug("projects_processor", "update_issue_status",
          issue_number: issue_number, status: status)

        item_id = @state_store.project_item_id(issue_number)
        return false unless item_id

        status_field = find_or_create_field(@field_mappings[:status], "SINGLE_SELECT", STATUS_VALUES.values)
        return false unless status_field

        option_id = find_option_id(status_field, status)
        return false unless option_id

        begin
          @repository_client.update_project_item_field(
            item_id,
            status_field[:id],
            {project_id: @project_id, option_id: option_id}
          )
          display_message("✓ Updated status for ##{issue_number} to '#{status}'", type: :success)
          true
        rescue => e
          Aidp.log_error("projects_processor", "Failed to update status",
            issue_number: issue_number, status: status, error: e.message)
          display_message("⚠️  Failed to update status: #{e.message}", type: :warn)
          false
        end
      end

      # Check if an issue is blocked by any of its sub-issues
      # @param issue_number [Integer] The parent issue number
      # @return [Hash] Blocking status with :blocked flag and :blockers list
      def check_blocking_dependencies(issue_number)
        Aidp.log_debug("projects_processor", "check_blocking_dependencies", issue_number: issue_number)

        status = @state_store.blocking_status(issue_number)

        if status[:blocked]
          # Fetch current status of sub-issues
          open_blockers = []
          status[:blockers].each do |sub_number|
            issue = @repository_client.fetch_issue(sub_number)
            open_blockers << sub_number if issue[:state] == "open"
          rescue => e
            Aidp.log_warn("projects_processor", "Failed to fetch sub-issue",
              sub_issue: sub_number, error: e.message)
            # Assume still blocking if we can't check
            open_blockers << sub_number
          end

          if open_blockers.any?
            update_blocking_field(issue_number, open_blockers)
            display_message("⚠️  Issue ##{issue_number} is blocked by #{open_blockers.size} open sub-issues",
              type: :warn)
            {blocked: true, blockers: open_blockers}
          else
            # All sub-issues are closed - unblock parent
            clear_blocking_field(issue_number)
            update_issue_status(issue_number, STATUS_VALUES[:todo])
            display_message("✓ Issue ##{issue_number} is no longer blocked", type: :success)
            {blocked: false, blockers: []}
          end
        else
          {blocked: false, blockers: []}
        end
      end

      # Sync all active issues in a project
      # @param issues [Array<Hash>] Array of issue data with :number keys
      def sync_all_issues(issues)
        Aidp.log_debug("projects_processor", "sync_all_issues", count: issues.size)

        display_message("📊 Syncing #{issues.size} issues to project...", type: :info)

        synced = 0
        failed = 0

        issues.each do |issue|
          success = sync_issue_to_project(issue[:number])
          if success
            synced += 1
          else
            failed += 1
          end
        end

        display_message("📊 Sync complete: #{synced} synced, #{failed} failed", type: :info)
        {synced: synced, failed: failed}
      end

      # Initialize required project fields if they don't exist
      # @return [Boolean] True if all fields are ready
      def ensure_project_fields
        return true unless @auto_create_fields

        Aidp.log_debug("projects_processor", "ensure_project_fields", project_id: @project_id)

        required_fields = [
          {name: @field_mappings[:status], type: "SINGLE_SELECT", options: STATUS_VALUES.values},
          {name: @field_mappings[:blocking], type: "TEXT"}
        ]

        all_ready = true
        required_fields.each do |field_spec|
          field = find_or_create_field(field_spec[:name], field_spec[:type], field_spec[:options])
          all_ready = false unless field
        end

        all_ready
      end

      private

      def project_fields
        @project_fields_cache ||= begin
          @repository_client.fetch_project_fields(@project_id)
        rescue => e
          Aidp.log_error("projects_processor", "Failed to fetch project fields", error: e.message)
          []
        end
      end

      def invalidate_fields_cache
        @project_fields_cache = nil
      end

      def find_or_create_field(name, field_type, options = nil)
        # Search existing fields
        field = project_fields.find { |f| f[:name].downcase == name.downcase }
        return field if field

        # Create if auto-create is enabled
        return nil unless @auto_create_fields

        Aidp.log_debug("projects_processor", "creating_project_field",
          name: name, field_type: field_type, project_id: @project_id)

        begin
          formatted_options = if options && field_type == "SINGLE_SELECT"
            options.map { |opt| {name: opt} }
          end

          field = @repository_client.create_project_field(
            @project_id,
            name,
            field_type,
            options: formatted_options
          )

          invalidate_fields_cache
          display_message("✓ Created project field '#{name}'", type: :success)
          field
        rescue => e
          Aidp.log_error("projects_processor", "Failed to create project field",
            name: name, error: e.message)
          display_message("⚠️  Failed to create project field '#{name}': #{e.message}", type: :warn)
          nil
        end
      end

      def find_option_id(field, value)
        return nil unless field[:options]

        option = field[:options].find { |opt| opt[:name].downcase == value.downcase }
        option&.dig(:id)
      end

      def update_blocking_field(issue_number, blockers)
        item_id = @state_store.project_item_id(issue_number)
        return false unless item_id

        blocking_field = find_or_create_field(@field_mappings[:blocking], "TEXT")
        return false unless blocking_field

        blocker_text = blockers.map { |n| "##{n}" }.join(", ")

        begin
          @repository_client.update_project_item_field(
            item_id,
            blocking_field[:id],
            {project_id: @project_id, text: blocker_text}
          )
          true
        rescue => e
          Aidp.log_warn("projects_processor", "Failed to update blocking field",
            issue_number: issue_number, error: e.message)
          false
        end
      end

      def clear_blocking_field(issue_number)
        update_blocking_field(issue_number, [])
      end
    end
  end
end
