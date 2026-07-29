# frozen_string_literal: true

require_relative "../message_display"
require_relative "plan_generator"
require_relative "state_store"
require_relative "feedback_collector"
require_relative "projects_processor"
require_relative "sub_issue_creator"

module Aidp
  module Watch
    # Handles the aidp-plan label trigger by generating an implementation plan
    # and posting it back to the originating GitHub issue.
    class PlanProcessor
      include Aidp::MessageDisplay

      TrackedSubIssuesRetirementError = Class.new(StandardError)

      # Default label names
      DEFAULT_PLAN_LABEL = "aidp-plan"
      DEFAULT_PROJECT_LABEL = "aidp-project"
      DEFAULT_NEEDS_INPUT_LABEL = "aidp-needs-input"
      DEFAULT_READY_LABEL = "aidp-ready"
      DEFAULT_BUILD_LABEL = "aidp-build"
      DEFAULT_BLOCKED_LABEL = "aidp-blocked"

      COMMENT_HEADER = "## 🤖 AIDP Plan Proposal"

      attr_reader :plan_label, :project_label, :needs_input_label, :ready_label, :build_label, :blocked_label

      def initialize(repository_client:, state_store:, plan_generator:, label_config: {}, project_config: {})
        @repository_client = repository_client
        @state_store = state_store
        @plan_generator = plan_generator
        @project_config = project_config

        # Load label configuration with defaults
        @plan_label = label_config[:plan_trigger] || label_config["plan_trigger"] || DEFAULT_PLAN_LABEL
        @project_label = label_config[:project_trigger] || label_config["project_trigger"] || DEFAULT_PROJECT_LABEL
        @needs_input_label = label_config[:needs_input] || label_config["needs_input"] || DEFAULT_NEEDS_INPUT_LABEL
        @ready_label = label_config[:ready_to_build] || label_config["ready_to_build"] || DEFAULT_READY_LABEL
        @build_label = label_config[:build_trigger] || label_config["build_trigger"] || DEFAULT_BUILD_LABEL
        @blocked_label = label_config[:blocked_trigger] || label_config["blocked_trigger"] || DEFAULT_BLOCKED_LABEL
      end

      def process(issue, trigger_label: @plan_label)
        number = issue[:number]
        existing_plan = @state_store.plan_data(number)
        project_mode = trigger_label.to_s.casecmp(@project_label).zero?

        if existing_plan
          display_message("🔄 Re-planning for issue ##{number} (iteration #{@state_store.plan_iteration_count(number) + 1})", type: :info)
        else
          prefix = project_mode ? "🗂️  Generating project plan" : "🧠 Generating plan"
          display_message("#{prefix} for issue ##{number} (#{issue[:title]})", type: :info)
        end

        plan_data = @plan_generator.generate(issue, hierarchical: project_mode)

        # If plan generation failed (all providers unavailable), silently skip
        unless plan_data
          Aidp.log_warn("plan_processor", "plan_generation_failed", issue: number, reason: "no plan data returned")
          display_message("⚠️  Unable to generate plan for issue ##{number} - all providers failed", type: :warn)
          return
        end

        # Fetch the user who added the most recent label
        label_actor = @repository_client.most_recent_label_actor(number)

        # If updating existing plan, archive the previous content
        archived_content = existing_plan ? archive_previous_plan(number, existing_plan) : nil

        comment_body = build_comment(
          issue: issue,
          plan: plan_data,
          project_mode: project_mode,
          label_actor: label_actor,
          archived_content: archived_content
        )
        comment_body_with_feedback = FeedbackCollector.append_feedback_prompt(comment_body)
        comment_id = nil

        if existing_plan && existing_plan["comment_id"]
          # Update existing comment
          @repository_client.update_comment(existing_plan["comment_id"], comment_body_with_feedback)
          comment_id = existing_plan["comment_id"]
          display_message("📝 Updated plan comment for issue ##{number}", type: :success)
        elsif existing_plan
          # Try to find existing comment by header
          existing_comment = @repository_client.find_comment(number, COMMENT_HEADER)
          if existing_comment
            @repository_client.update_comment(existing_comment[:id], comment_body_with_feedback)
            comment_id = existing_comment[:id]
            display_message("📝 Updated plan comment for issue ##{number}", type: :success)
          else
            # Fallback to posting new comment if we can't find the old one
            result = @repository_client.post_comment(number, comment_body_with_feedback)
            comment_id = result[:id] if result.is_a?(Hash)
            display_message("💬 Posted new plan comment for issue ##{number}", type: :success)
          end
        else
          # First time planning - post new comment
          result = @repository_client.post_comment(number, comment_body_with_feedback)
          comment_id = result[:id] if result.is_a?(Hash)
          display_message("💬 Posted plan comment for issue ##{number}", type: :success)
        end

        plan_data = plan_data.merge(comment_id: comment_id) if comment_id
        @state_store.record_plan(number, plan_data.merge(comment_body: comment_body, comment_hint: COMMENT_HEADER))

        project_setup = project_mode ? process_project_plan(issue, plan_data) : {status: :not_applicable}

        # Update labels: remove plan trigger, add appropriate status label
        update_labels_after_plan(
          number,
          plan_data,
          trigger_label: trigger_label,
          project_mode: project_mode,
          project_setup: project_setup
        )
      end

      private

      def archive_previous_plan(number, existing_plan)
        iteration = @state_store.plan_iteration_count(number)
        timestamp = existing_plan["posted_at"] || "unknown"

        archived_parts = []
        archived_parts << "<!-- ARCHIVED_PLAN_START iteration=#{iteration} timestamp=#{timestamp} -->"
        archived_parts << "<details>"
        archived_parts << "<summary>📋 Previous Plan (Iteration #{iteration}) - #{timestamp}</summary>"
        archived_parts << ""
        archived_parts << "<!-- ARCHIVED_PLAN_SUMMARY_START -->"
        archived_parts << "### Plan Summary"
        archived_parts << existing_plan["summary"].to_s
        archived_parts << "<!-- ARCHIVED_PLAN_SUMMARY_END -->"
        archived_parts << ""
        archived_parts << "<!-- ARCHIVED_PLAN_TASKS_START -->"
        archived_parts << "### Proposed Tasks"
        archived_parts << format_bullets(Array(existing_plan["tasks"]), placeholder: "_No tasks_")
        archived_parts << "<!-- ARCHIVED_PLAN_TASKS_END -->"
        archived_parts << ""
        archived_parts << "</details>"
        archived_parts << "<!-- ARCHIVED_PLAN_END -->"

        archived_parts.join("\n")
      end

      def update_labels_after_plan(number, plan_data, trigger_label:, project_mode:, project_setup:)
        new_label, status_text = next_label_for(
          plan_data,
          trigger_label: trigger_label,
          project_mode: project_mode,
          project_setup: project_setup
        )
        old_labels = labels_to_replace(trigger_label, project_mode: project_mode)

        if old_labels == [new_label]
          display_message("🏷️  Left label '#{trigger_label}' in place (#{status_text})", type: :info)
          return
        end

        begin
          @repository_client.replace_labels(
            number,
            old_labels: old_labels,
            new_labels: [new_label]
          )
          display_message("🏷️  Updated labels: removed '#{trigger_label}', added '#{new_label}' (#{status_text})", type: :info)
        rescue => e
          display_message("⚠️  Failed to update labels for issue ##{number}: #{e.message}", type: :warn)
          # Don't fail the whole process if label update fails
        end
      end

      def build_comment(issue:, plan:, project_mode:, label_actor: nil, archived_content: nil)
        summary = plan[:summary].to_s.strip
        tasks = Array(plan[:tasks])
        questions = Array(plan[:questions])
        has_questions = questions.any? && !questions.all? { |q| q.to_s.strip.empty? }

        parts = []
        parts << COMMENT_HEADER
        parts << ""

        # Tag the label actor if available
        if label_actor
          parts << "cc @#{label_actor}"
          parts << ""
        end

        parts << "**Issue**: [##{issue[:number]}](#{issue[:url]})"
        parts << "**Title**: #{issue[:title]}"
        parts << ""

        # Add archived content if this is a plan update
        if archived_content
          parts << archived_content
          parts << ""
        end

        parts << "<!-- PLAN_SUMMARY_START -->"
        parts << "### Plan Summary"
        parts << (summary.empty? ? "_No summary generated_" : summary)
        parts << "<!-- PLAN_SUMMARY_END -->"
        parts << ""
        parts << "<!-- PLAN_TASKS_START -->"
        parts << "### Proposed Tasks"
        parts << format_bullets(tasks, placeholder: "_Pending task breakdown_")
        parts << "<!-- PLAN_TASKS_END -->"
        parts << ""
        parts << "<!-- CLARIFYING_QUESTIONS_START -->"
        parts << "### Clarifying Questions"
        parts << format_numbered(questions, placeholder: "_No questions identified_")
        parts << "<!-- CLARIFYING_QUESTIONS_END -->"
        parts << ""

        # Add instructions based on whether there are questions
        parts << if has_questions
          resume_label = project_mode ? @project_label : @build_label
          "**Next Steps**: Please reply with answers to the questions above. Once resolved, remove the `#{@needs_input_label}` label and add the `#{resume_label}` label to continue."
        elsif plan[:should_create_sub_issues]
          "**Next Steps**: AIDP will create project sub-issues, place them on the active GitHub Project, and dispatch dependency-ready work with `#{@build_label}` while blocked work is held under `#{@blocked_label}`."
        else
          "**Next Steps**: This plan is ready for implementation. Add the `#{@build_label}` label to begin."
        end

        parts.join("\n")
      end

      def process_project_plan(issue, plan_data)
        return {status: :not_required} unless plan_data[:should_create_sub_issues]

        sub_issues = Array(plan_data[:sub_issues])
        if sub_issues.empty?
          return record_project_setup_failure(issue[:number], "no sub-issues were generated for project planning")
        end

        project_id = resolve_project_id(issue)
        return record_project_setup_failure(issue[:number], "unable to resolve a GitHub Project") unless project_id

        projects_processor = ProjectsProcessor.new(
          repository_client: @repository_client,
          state_store: @state_store,
          project_id: project_id,
          config: @project_config
        )
        unless projects_processor.ensure_project_fields
          return record_project_setup_failure(issue[:number], "unable to configure required GitHub Project fields")
        end

        creator = SubIssueCreator.new(
          repository_client: @repository_client,
          state_store: @state_store,
          project_id: project_id,
          build_label: @build_label,
          blocked_label: @blocked_label
        )
        created_issues = existing_sub_issues_for(issue, sub_issues: sub_issues, creator: creator)
        created_issues = creator.create_sub_issues(issue, sub_issues) if created_issues.empty?
        if created_issues.empty?
          return record_project_setup_failure(issue[:number], "unable to create project sub-issues")
        end

        if prd_path_configured? && !sync_project_gantt_data(projects_processor, issue[:number])
          return record_project_setup_failure(issue[:number], "unable to sync GitHub Project data from the PRD Gantt chart")
        end

        unless sync_project_issue_statuses(issue[:number], created_issues, projects_processor)
          return record_project_setup_failure(issue[:number], "unable to sync project issues to the GitHub Project")
        end

        @state_store.record_project_sync(issue[:number], setup_status: "ready", setup_error: nil, setup_failed_at: nil)
        {status: :ready}
      rescue SubIssueCreator::UnresolvedDependenciesError => e
        Aidp.log_error("plan_processor", "project_sub_issue_dependency_resolution_failed",
          issue: issue[:number], error: e.message)
        record_project_setup_failure(issue[:number], e.message)
      rescue TrackedSubIssuesRetirementError => e
        Aidp.log_error("plan_processor", "project_sub_issue_retirement_failed",
          issue: issue[:number], error: e.message)
        record_project_setup_failure(issue[:number], e.message)
      end

      def resolve_project_id(issue)
        configured_project_id = @project_config[:default_project_id] || @project_config["default_project_id"]
        return configured_project_id if configured_project_id

        saved_project_id = @state_store.project_sync_data(issue[:number])["project_id"]
        return saved_project_id if saved_project_id

        active_project = @repository_client.find_active_project
        if active_project
          @state_store.record_project_sync(
            issue[:number],
            project_id: active_project[:id],
            project_url: active_project[:url],
            project_title: active_project[:title]
          )
          display_message("📊 Reusing active GitHub Project '#{active_project[:title]}'", type: :info)
          return active_project[:id]
        end

        title = "AIDP Project ##{issue[:number]}: #{issue[:title]}".slice(0, 100)
        project = @repository_client.create_project(title: title)
        @state_store.record_project_sync(issue[:number], project_id: project[:id], project_url: project[:url], project_title: project[:title])
        display_message("📊 Created GitHub Project '#{project[:title]}'", type: :success)
        project[:id]
      rescue => e
        Aidp.log_error("plan_processor", "project_resolution_failed", issue: issue[:number], error: e.message)
        display_message("⚠️  Failed to resolve GitHub Project for issue ##{issue[:number]}: #{e.message}", type: :warn)
        nil
      end

      def sync_project_issue_statuses(parent_number, created_issues, projects_processor)
        return false unless projects_processor.sync_issue_to_project(parent_number, status: ProjectsProcessor::STATUS_VALUES[:blocked])

        created_issues.each do |created_issue|
          status = project_issue_status_for(created_issue)
          return false unless projects_processor.sync_issue_to_project(created_issue[:number], status: status)
        end

        true
      end

      def sync_project_gantt_data(projects_processor, issue_number)
        projects_processor.sync_from_gantt
        true
      rescue => e
        Aidp.log_error("plan_processor", "project_gantt_sync_failed",
          issue: issue_number, error: e.message)
        false
      end

      def prd_path_configured?
        value = @project_config[:prd_path] || @project_config["prd_path"]
        !value.to_s.empty?
      end

      def existing_sub_issues_for(parent_issue, sub_issues:, creator:)
        parent_number = parent_issue[:number]
        existing_numbers = @state_store.sub_issues(parent_number)
        return [] if existing_numbers.empty?

        tracked_issues = existing_numbers.map { |number| fetch_tracked_sub_issue(number) }
        preserved_issues, remaining_numbers, remaining_sub_issues = preserve_closed_tracked_sub_issues(tracked_issues, sub_issues)
        preserved_numbers_by_title = issue_numbers_by_title(preserved_issues)

        remaining_issues = if remaining_numbers.empty? && remaining_sub_issues.empty?
          []
        elsif reconciliable_sub_issues?(remaining_numbers, remaining_sub_issues)
          display_message("🔁 Reusing #{existing_numbers.size} tracked sub-issues for ##{parent_number}", type: :info)
          reconcile_existing_sub_issues(
            parent_issue,
            remaining_numbers,
            remaining_sub_issues,
            creator,
            issue_numbers_by_title: preserved_numbers_by_title
          )
        else
          regenerate_open_tracked_sub_issues(
            parent_issue,
            parent_number,
            remaining_numbers,
            remaining_sub_issues,
            creator,
            preserved_numbers_by_title: preserved_numbers_by_title
          )
        end

        ordered_issues = order_tracked_sub_issues(sub_issues, preserved_issues + remaining_issues)
        record_tracked_sub_issue_dependencies(ordered_issues, sub_issues)
        @state_store.record_sub_issues(parent_number, ordered_issues.map { |tracked_issue| tracked_issue[:number] })
        ordered_issues
      end

      def next_label_for(plan_data, trigger_label:, project_mode:, project_setup:)
        questions = Array(plan_data[:questions])
        has_questions = questions.any? && !questions.all? { |q| q.to_s.strip.empty? }

        return [@needs_input_label, "needs input"] if has_questions
        if project_mode && plan_data[:should_create_sub_issues]
          return [@blocked_label, "project initialized"] if project_setup[:status] == :ready

          return [@needs_input_label, "project setup failed: #{project_setup[:reason]}"]
        end

        [@ready_label, "ready to build"]
      end

      def labels_to_replace(trigger_label, project_mode:)
        return [trigger_label] unless project_mode

        [trigger_label, @plan_label, @build_label].uniq
      end

      def record_project_setup_failure(issue_number, reason)
        @state_store.record_project_sync(
          issue_number,
          setup_status: "failed",
          setup_error: reason,
          setup_failed_at: Time.now.utc.iso8601
        )
        {status: :failed, reason: reason}
      end

      def project_issue_status_for(created_issue)
        return ProjectsProcessor::STATUS_VALUES[:done] if created_issue[:state].to_s.casecmp("closed").zero?

        created_issue[:dependencies].any? ? ProjectsProcessor::STATUS_VALUES[:blocked] : ProjectsProcessor::STATUS_VALUES[:todo]
      end

      def format_bullets(items, placeholder:)
        if items.empty?
          placeholder
        else
          items.map { |item| "- #{item}" }.join("\n")
        end
      end

      def format_numbered(items, placeholder:)
        if items.empty?
          placeholder
        else
          items.each_with_index.map { |item, index| "#{index + 1}. #{item}" }.join("\n")
        end
      end

      def reconciliable_sub_issues?(existing_numbers, sub_issues)
        return false unless sub_issue_count_matches?(existing_numbers, sub_issues)
        return true if tracked_sub_issues_match_plan?(existing_numbers, sub_issues)

        display_message(
          "⚠️  Tracked sub-issues no longer match the regenerated plan; regenerating them",
          type: :warn
        )
        false
      end

      def sub_issue_count_matches?(existing_numbers, sub_issues)
        return true if existing_numbers.size == sub_issues.size

        display_message(
          "⚠️  Tracked sub-issues no longer match the regenerated plan (#{existing_numbers.size} tracked, #{sub_issues.size} planned); regenerating them",
          type: :warn
        )
        false
      end

      def tracked_sub_issues_match_plan?(existing_numbers, sub_issues)
        tracked_issues = existing_numbers.map { |number| fetch_tracked_sub_issue(number) }

        tracked_titles = tracked_issues.map { |tracked_issue| normalize_sub_issue_title(tracked_issue[:title]) }
        planned_titles = sub_issues.map { |sub_issue| normalize_sub_issue_title(sub_issue[:title]) }

        tracked_titles == planned_titles
      rescue => e
        Aidp.log_warn("plan_processor", "tracked_sub_issue_validation_failed",
          error: e.message,
          tracked_issue_numbers: existing_numbers)
        false
      end

      def fetch_tracked_sub_issue(number)
        @repository_client.fetch_issue(number)
      end

      def normalize_sub_issue_title(title)
        title.to_s.strip.downcase
      end

      def preserve_closed_tracked_sub_issues(tracked_issues, sub_issues)
        remaining_tracked_issues = tracked_issues.dup
        remaining_sub_issues = sub_issues.dup
        preserved_issues = []

        tracked_issues.each do |tracked_issue|
          next unless tracked_issue[:state].to_s.casecmp("closed").zero?

          match_index = remaining_sub_issues.index do |sub_issue|
            normalize_sub_issue_title(sub_issue[:title]) == normalize_sub_issue_title(tracked_issue[:title])
          end
          next unless match_index

          preserved_issues << tracked_issue
          remaining_tracked_issues.delete(tracked_issue)
          remaining_sub_issues.delete_at(match_index)
        end

        return [preserved_issues, remaining_tracked_issues.map { |tracked_issue| tracked_issue[:number] }, remaining_sub_issues] if preserved_issues.empty?

        suffix = if preserved_issues.one?
          ""
        else
          "s"
        end
        display_message(
          "🔒 Preserving #{preserved_issues.size} completed tracked sub-issue#{suffix} during re-plan",
          type: :info
        )
        [preserved_issues, remaining_tracked_issues.map { |tracked_issue| tracked_issue[:number] }, remaining_sub_issues]
      end

      def reconcile_existing_sub_issues(parent_issue, existing_numbers, sub_issues, creator, issue_numbers_by_title: {})
        tracked_issues = sub_issues.each_with_index.map do |sub_issue, index|
          number = existing_numbers.fetch(index)
          tracked_issue = @repository_client.fetch_issue(number)
          planned_issue = creator.planned_sub_issue_attributes(parent_issue, sub_issue, index + 1)
          update_tracked_sub_issue(number, tracked_issue, planned_issue) unless tracked_sub_issue_contract_matches?(tracked_issue, planned_issue)

          {
            number: number,
            title: planned_issue[:title].to_s.strip,
            dependencies: Array(sub_issue[:dependencies]),
            state: tracked_issue[:state]
          }
        end

        issue_numbers_by_title = build_issue_numbers_by_title(tracked_issues, issue_numbers_by_title)
        tracked_issues.each do |tracked_issue|
          dependencies, unresolved_dependencies = resolve_tracked_dependencies(
            tracked_issue[:dependencies],
            issue_numbers_by_title
          )
          if unresolved_dependencies.any?
            raise SubIssueCreator::UnresolvedDependenciesError,
              "Unable to resolve dependencies for sub-issue ##{tracked_issue[:number]} (#{tracked_issue[:title]}): #{unresolved_dependencies.join(", ")}"
          end

          @state_store.record_issue_dependencies(tracked_issue[:number], dependencies)
          tracked_issue[:dependencies] = dependencies
        end

        tracked_issues
      end

      def regenerate_open_tracked_sub_issues(parent_issue, parent_number, existing_numbers, sub_issues, creator, preserved_numbers_by_title:)
        retire_tracked_sub_issues(parent_number, existing_numbers)
        return [] if sub_issues.empty?

        creator.create_sub_issues(
          parent_issue,
          sub_issues_with_resolved_dependencies(sub_issues, preserved_numbers_by_title)
        )
      end

      def order_tracked_sub_issues(sub_issues, tracked_issues)
        tracked_issue_groups = tracked_issues.group_by { |tracked_issue| normalize_sub_issue_title(tracked_issue[:title]) }

        sub_issues.map do |sub_issue|
          normalized_title = normalize_sub_issue_title(sub_issue[:title])
          issue_group = tracked_issue_groups[normalized_title]
          next issue_group.shift if issue_group&.any?

          raise SubIssueCreator::UnresolvedDependenciesError,
            "Unable to match tracked sub-issue for planned item '#{sub_issue[:title]}'"
        end
      end

      def record_tracked_sub_issue_dependencies(tracked_issues, sub_issues)
        issue_numbers_by_title = build_issue_numbers_by_title(tracked_issues)

        tracked_issues.zip(sub_issues).each do |tracked_issue, sub_issue|
          dependencies, unresolved_dependencies = resolve_tracked_dependencies(
            sub_issue[:dependencies],
            issue_numbers_by_title
          )
          if unresolved_dependencies.any?
            raise SubIssueCreator::UnresolvedDependenciesError,
              "Unable to resolve dependencies for sub-issue ##{tracked_issue[:number]} (#{tracked_issue[:title]}): #{unresolved_dependencies.join(", ")}"
          end

          @state_store.record_issue_dependencies(tracked_issue[:number], dependencies)
          tracked_issue[:dependencies] = dependencies
        end
      end

      def sub_issues_with_resolved_dependencies(sub_issues, issue_numbers_by_title)
        sub_issues.map do |sub_issue|
          dependencies = Array(sub_issue[:dependencies]).map do |dependency|
            issue_number = issue_numbers_by_title[normalize_sub_issue_title(dependency)]
            issue_number ? "##{issue_number}" : dependency
          end

          sub_issue.merge(dependencies: dependencies)
        end
      end

      def build_issue_numbers_by_title(tracked_issues, seed = {})
        issue_numbers_by_title = seed.dup
        duplicate_titles = duplicate_normalized_tracked_titles(tracked_issues)
        if duplicate_titles.empty?
          tracked_issues.each do |tracked_issue|
            normalized_title = normalize_sub_issue_title(tracked_issue[:title])
            next if normalized_title.empty?
            next unless issue_numbers_by_title.key?(normalized_title) && issue_numbers_by_title[normalized_title] != tracked_issue[:number]

            duplicate_titles << tracked_issue[:title].to_s.strip
          end
          if duplicate_titles.empty?
            return tracked_issues.each_with_object(issue_numbers_by_title) do |tracked_issue, memo|
              normalized_title = normalize_sub_issue_title(tracked_issue[:title])
              memo[normalized_title] = tracked_issue[:number] unless normalized_title.empty?
            end
          end
        end

        raise SubIssueCreator::UnresolvedDependenciesError,
          "Duplicate sub-issue titles after normalization are not allowed: #{duplicate_titles.join(", ")}"
      end

      def duplicate_normalized_tracked_titles(tracked_issues)
        grouped_titles = tracked_issues.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |tracked_issue, memo|
          normalized_title = normalize_sub_issue_title(tracked_issue[:title])
          next if normalized_title.empty?

          memo[normalized_title] << tracked_issue[:title].to_s.strip
        end

        grouped_titles.filter_map do |_normalized_title, titles|
          next unless titles.size > 1

          titles.uniq.join(" / ")
        end
      end

      def issue_numbers_by_title(tracked_issues)
        tracked_issues.each_with_object({}) do |tracked_issue, memo|
          normalized_title = normalize_sub_issue_title(tracked_issue[:title])
          memo[normalized_title] = tracked_issue[:number] unless normalized_title.empty?
        end
      end

      def resolve_tracked_dependencies(dependencies, issue_numbers_by_title)
        Array(dependencies).each_with_object([[], []]) do |dependency, (resolved, unresolved)|
          text = dependency.to_s.strip
          match = text.match(/\A#(\d+)\z/)
          resolved_dependency = match ? match[1].to_i : issue_numbers_by_title[normalize_sub_issue_title(text)]
          resolved_dependency ? resolved << resolved_dependency : unresolved << dependency
        end
      end

      def tracked_sub_issue_contract_matches?(tracked_issue, planned_issue)
        normalize_sub_issue_title(tracked_issue[:title]) == normalize_sub_issue_title(planned_issue[:title]) &&
          tracked_issue[:body].to_s == planned_issue[:body] &&
          normalized_list(tracked_issue[:labels]) == normalized_list(planned_issue[:labels]) &&
          normalized_list(tracked_issue[:assignees]) == normalized_list(planned_issue[:assignees])
      end

      def update_tracked_sub_issue(number, tracked_issue, planned_issue)
        Aidp.log_info("plan_processor", "tracked_sub_issue_updated",
          issue: number,
          title_changed: normalize_sub_issue_title(tracked_issue[:title]) != normalize_sub_issue_title(planned_issue[:title]),
          body_changed: tracked_issue[:body].to_s != planned_issue[:body],
          labels_changed: normalized_list(tracked_issue[:labels]) != normalized_list(planned_issue[:labels]),
          assignees_changed: normalized_list(tracked_issue[:assignees]) != normalized_list(planned_issue[:assignees]))

        @repository_client.update_issue(
          number,
          title: planned_issue[:title],
          body: planned_issue[:body],
          labels: planned_issue[:labels],
          assignees: planned_issue[:assignees]
        )
      end

      def normalized_list(values)
        Array(values).map { |value| value.to_s.strip }.reject(&:empty?).sort
      end

      def retire_tracked_sub_issues(parent_number, existing_numbers)
        display_message("🧹 Retiring #{existing_numbers.size} stale tracked sub-issues for ##{parent_number}", type: :warn)

        existing_numbers.each do |number|
          @repository_client.close_issue(number)
        rescue => e
          raise TrackedSubIssuesRetirementError,
            "unable to retire stale tracked sub-issue ##{number}: #{e.message}"
        end

        @state_store.clear_sub_issues(parent_number)
        []
      end
    end
  end
end
