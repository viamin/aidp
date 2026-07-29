# frozen_string_literal: true

require "date"

module Aidp
  module Watch
    # Synchronizes parsed Gantt task data with GitHub Projects and Mermaid docs.
    class GanttSynchronizer
      CRITICAL_PATH_VALUES = %w[Yes No].freeze

      def initialize(repository_client:, state_store:, project_id:, field_mappings:, auto_create_fields: true, parser_class: PrdParser)
        @repository_client = repository_client
        @state_store = state_store
        @project_id = project_id
        @field_mappings = field_mappings
        @auto_create_fields = auto_create_fields
        @parser_class = parser_class
        @project_fields_cache = nil
      end

      def sync_from_prd(prd_path:, format: nil)
        parsed = @parser_class.new(file_path: prd_path, format: format).parse
        tasks = parsed[:tasks]
        critical_path = calculate_critical_path(tasks)
        tasks_by_id = tasks.each_with_object({}) { |task, memo| memo[task[:id]] = task }

        synced = 0
        skipped = 0

        tasks.each do |task|
          if task[:issue_number].nil?
            skipped += 1
            next
          end

          item_id = ensure_project_item(task[:issue_number])
          update_date_fields(item_id, task)
          update_dependencies_field(item_id, task, tasks_by_id)
          update_critical_path_field(item_id, critical_path.include?(task[:id]))

          @state_store.record_project_sync(task[:issue_number], {
            gantt_task_id: task[:id],
            gantt_path: prd_path,
            gantt_format: parsed[:format].to_s,
            critical_path: critical_path.include?(task[:id])
          })
          synced += 1
        end

        {synced: synced, skipped: skipped, critical_path: critical_path}
      end

      def sync_issue_status_to_gantt(prd_path:, issue_number:, status:, format: nil)
        parser = @parser_class.new(file_path: prd_path, format: format)
        parsed = parser.parse
        return false unless parsed[:format] == :mermaid

        content = File.read(prd_path)
        lines = content.lines
        line_index = lines.index { |line| line.include?("##{issue_number}") || line.include?("(##{issue_number})") }
        return false unless line_index

        lines[line_index] = rewrite_mermaid_status(lines[line_index], status)
        File.write(prd_path, lines.join)
        true
      end

      private

      def calculate_critical_path(tasks)
        explicit = tasks.select { |task| task[:critical] }.map { |task| task[:id] }
        return explicit if explicit.any?

        durations = tasks.each_with_object({}) { |task, memo| memo[task[:id]] = task[:duration_days].to_i }
        predecessors = tasks.each_with_object({}) { |task, memo| memo[task[:id]] = task[:dependency_ids] }
        longest = {}
        previous = {}

        ordered_ids(tasks, predecessors).each do |task_id|
          best_predecessor = predecessors[task_id].max_by { |candidate| longest[candidate].to_i }
          longest[task_id] = durations[task_id] + longest[best_predecessor].to_i
          previous[task_id] = best_predecessor
        end

        endpoint = longest.max_by { |_task_id, distance| distance }&.first
        unwind_path(endpoint, previous)
      end

      def ordered_ids(tasks, predecessors)
        task_ids = tasks.map { |task| task[:id] }
        ordered = []
        remaining = task_ids.dup

        until remaining.empty?
          progressed = false
          remaining.dup.each do |task_id|
            unmet = predecessors[task_id].reject { |dependency| ordered.include?(dependency) }
            next if unmet.any?

            ordered << task_id
            remaining.delete(task_id)
            progressed = true
          end

          break unless progressed
        end

        ordered + remaining
      end

      def unwind_path(endpoint, previous)
        path = []
        current = endpoint

        while current
          path.unshift(current)
          current = previous[current]
        end

        path
      end

      def ensure_project_item(issue_number)
        item_id = @state_store.project_item_id(issue_number)
        return item_id if item_id

        item_id = @repository_client.link_issue_to_project(@project_id, issue_number)
        @state_store.record_project_item_id(issue_number, item_id)
        item_id
      end

      def update_date_fields(item_id, task)
        update_date_field(item_id, @field_mappings[:start_date], task[:start_date])
        update_date_field(item_id, @field_mappings[:target_date], task[:end_date] || task[:start_date])
      end

      def update_date_field(item_id, field_name, date)
        return unless field_name && date

        field = find_or_create_field(field_name, "DATE")
        return unless field

        @repository_client.update_project_item_field(
          item_id,
          field[:id],
          {project_id: @project_id, date: date.iso8601}
        )
      end

      def update_dependencies_field(item_id, task, tasks_by_id)
        field_name = @field_mappings[:dependencies]
        return unless field_name

        dependency_issue_numbers = task[:dependency_ids].filter_map do |dependency_id|
          tasks_by_id[dependency_id]&.dig(:issue_number)
        end
        field = find_or_create_field(field_name, "TEXT")
        return unless field

        text = dependency_issue_numbers.map { |issue_number| "##{issue_number}" }.join(", ")
        @repository_client.update_project_item_field(
          item_id,
          field[:id],
          {project_id: @project_id, text: text}
        )
      end

      def update_critical_path_field(item_id, critical)
        field_name = @field_mappings[:critical_path]
        return unless field_name

        field = find_or_create_field(field_name, "SINGLE_SELECT", CRITICAL_PATH_VALUES)
        return unless field

        option_id = field[:options]&.find { |option| option[:name].casecmp?(critical ? "Yes" : "No") }&.dig(:id)
        return unless option_id

        @repository_client.update_project_item_field(
          item_id,
          field[:id],
          {project_id: @project_id, option_id: option_id}
        )
      end

      def rewrite_mermaid_status(line, status)
        name_part, definition = line.split(/\s+:/, 2)
        tokens = definition.to_s.split(",").map(&:strip).reject(&:empty?)
        tokens.reject! { |token| %w[done active].include?(token) }

        mapped_status = case status.to_s.downcase
        when "done", "closed", "completed" then "done"
        when "in progress", "in_progress", "active" then "active"
        end
        tokens.unshift(mapped_status) if mapped_status

        "#{name_part} :#{tokens.join(", ")}\n"
      end

      def project_fields
        @project_fields_cache ||= @repository_client.fetch_project_fields(@project_id)
      end

      def invalidate_fields_cache
        @project_fields_cache = nil
      end

      def find_or_create_field(name, field_type, options = nil)
        field = project_fields.find { |entry| entry[:name].casecmp?(name) }
        return field if field
        return nil unless @auto_create_fields

        formatted_options = options&.map { |option| {name: option} } if field_type == "SINGLE_SELECT"
        field = @repository_client.create_project_field(@project_id, name, field_type, options: formatted_options)
        invalidate_fields_cache
        field
      end
    end
  end
end
