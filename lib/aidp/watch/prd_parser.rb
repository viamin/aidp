# frozen_string_literal: true

require "csv"
require "date"
require "rexml/document"

module Aidp
  module Watch
    # Parses Gantt-oriented planning documents into a normalized task graph.
    class PrdParser
      class ParseError < StandardError; end

      SUPPORTED_FORMATS = %i[mermaid ms_project_xml csv].freeze

      def initialize(file_path:, format: nil)
        @file_path = file_path
        @format = normalize_format(format) || detect_format
      end

      def parse
        raise ParseError, "File not found: #{@file_path}" unless File.exist?(@file_path)

        tasks = case @format
        when :mermaid then parse_mermaid(File.read(@file_path))
        when :ms_project_xml then parse_ms_project_xml(File.read(@file_path))
        when :csv then parse_csv
        else
          raise ParseError, "Unsupported format: #{@format}"
        end

        normalized_tasks = normalize_tasks(tasks)

        {
          format: @format,
          source_file: @file_path,
          tasks: normalized_tasks,
          metadata: build_metadata(normalized_tasks)
        }
      rescue REXML::ParseException => e
        raise ParseError, "Invalid XML: #{e.message}"
      rescue CSV::MalformedCSVError => e
        raise ParseError, "Invalid CSV: #{e.message}"
      end

      private

      def normalize_format(format)
        return nil if format.nil?

        normalized = format.to_s.strip.downcase.tr("-", "_")
        {
          "auto" => nil,
          "mermaid" => :mermaid,
          "ms_project_xml" => :ms_project_xml,
          "msp_xml" => :ms_project_xml,
          "xml" => :ms_project_xml,
          "csv" => :csv
        }.fetch(normalized) { raise ParseError, "Unknown format override: #{format}" }
      end

      def detect_format
        ext = File.extname(@file_path).downcase
        content = File.read(@file_path)

        return :csv if ext == ".csv"
        return :ms_project_xml if ext == ".xml"
        return :mermaid if mermaid_gantt_format?(ext, content)

        raise ParseError, "Unable to detect Gantt format for #{@file_path}"
      end

      def mermaid_gantt_format?(ext, content)
        return false unless [".md", ".markdown", ".mmd"].include?(ext) || content.match?(/^\s*gantt\s*$/)

        content.match?(/```mermaid\b.*?^\s*gantt\s*$/m) || content.match?(/^\s*gantt\s*$/)
      end

      def parse_mermaid(content)
        chart = extract_mermaid_chart(content)
        lines = chart.each_line.map(&:rstrip)
        chart_start_date = extract_mermaid_start_date(lines)
        section = nil
        tasks = []

        lines.each_with_index do |line, index|
          stripped = line.strip
          next if stripped.empty? || stripped == "gantt" || stripped.start_with?("%%", "title ", "dateFormat ", "axisFormat ", "todayMarker ")

          if stripped.start_with?("section ")
            section = stripped.delete_prefix("section ").strip
            next
          end

          next unless stripped.include?(":")

          name_part, definition = stripped.split(":", 2)
          tasks << build_mermaid_task(name_part, definition, section, index + 1, chart_start_date)
        end

        tasks
      end

      def extract_mermaid_chart(content)
        match = content.match(/```mermaid\s*\n(?<chart>.*?^\s*```)/m)
        return match[:chart].sub(/\n?\s*```\s*\z/m, "") if match

        content
      end

      def build_mermaid_task(name_part, definition, section, line_number, chart_start_date)
        tokens = definition.split(",").map(&:strip).reject(&:empty?)
        dependency_ids = []
        milestone = false
        critical = false
        status = nil
        task_id = nil
        explicit_dates = []
        duration_days = nil

        tokens.each do |token|
          case token
          when "crit"
            critical = true
          when "milestone", "milestone?"
            milestone = true
          when "done", "active"
            status = token
          when /\Aafter\s+(.+)\z/i
            dependency_ids.concat(Regexp.last_match(1).split)
          when /\A\d{4}-\d{2}-\d{2}\z/
            explicit_dates << Date.parse(token)
          when /\A(\d+)d\z/i
            duration_days = Regexp.last_match(1).to_i
          else
            task_id ||= token
          end
        end

        start_date = explicit_dates.first
        end_date = explicit_dates[1]
        duration_days ||= 0 if milestone
        duration_days ||= 1 unless end_date

        {
          id: task_id || slugify(name_part),
          name: name_part.strip,
          section: section,
          start_date: start_date,
          end_date: end_date || ((start_date && duration_days) ? start_date + duration_days - 1 : nil),
          duration_days: duration_days,
          dependency_ids: dependency_ids,
          milestone: milestone,
          critical: critical,
          status: status,
          issue_number: extract_issue_number("#{name_part} #{task_id}"),
          line_number: line_number,
          chart_start_date: chart_start_date
        }
      end

      def parse_ms_project_xml(content)
        document = REXML::Document.new(content)
        uid_to_task = {}

        REXML::XPath.each(document, "//Task") do |node|
          name = text_at(node, "Name")
          next if name.to_s.strip.empty?
          next if text_at(node, "Null") == "1"

          uid = text_at(node, "UID")
          task = {
            id: uid.to_s.empty? ? slugify(name) : uid.to_s,
            name: name.strip,
            section: nil,
            start_date: parse_date(text_at(node, "Start")),
            end_date: parse_date(text_at(node, "Finish")),
            duration_days: parse_duration(text_at(node, "Duration")),
            dependency_ids: [],
            milestone: text_at(node, "Milestone") == "1",
            critical: text_at(node, "Critical") == "1",
            status: nil,
            issue_number: extract_issue_number(name)
          }

          REXML::XPath.each(node, "PredecessorLink") do |link|
            predecessor_uid = text_at(link, "PredecessorUID")
            task[:dependency_ids] << predecessor_uid if predecessor_uid
          end

          uid_to_task[uid] = task
        end

        uid_to_task.values
      end

      def parse_csv
        rows = CSV.read(@file_path, headers: true)
        rows.map do |row|
          name = first_value(row, "name", "task", "title", "summary")
          id = first_value(row, "id", "task_id", "uid") || slugify(name)
          dependencies = first_value(row, "dependencies", "depends_on", "predecessors", "dependency_ids")

          {
            id: id.to_s,
            name: name.to_s.strip,
            section: first_value(row, "section", "phase", "group"),
            start_date: parse_date(first_value(row, "start_date", "start")),
            end_date: parse_date(first_value(row, "end_date", "finish", "due_date")),
            duration_days: parse_numeric(first_value(row, "duration_days", "duration", "days")),
            dependency_ids: split_dependencies(dependencies),
            milestone: truthy?(first_value(row, "milestone", "is_milestone")),
            critical: truthy?(first_value(row, "critical", "critical_path")),
            status: first_value(row, "status", "state"),
            issue_number: parse_numeric(first_value(row, "issue_number")) || extract_issue_number("#{name} #{id}")
          }
        end.reject { |task| task[:name].empty? }
      end

      def normalize_tasks(tasks)
        task_ids = tasks.each_with_object({}) { |task, memo| memo[task[:id].to_s] = task[:id].to_s }

        normalized_tasks = tasks.map do |task|
          dependency_ids = Array(task[:dependency_ids]).filter_map do |dependency|
            resolve_dependency_id(dependency, tasks, task_ids)
          end

          duration_days = task[:duration_days]
          duration_days = calculate_duration(task[:start_date], task[:end_date]) if duration_days.nil?
          duration_days ||= task[:milestone] ? 0 : 1

          task.merge(
            id: task[:id].to_s,
            dependency_ids: dependency_ids.uniq,
            duration_days: duration_days,
            end_date: task[:end_date] || infer_end_date(task[:start_date], duration_days)
          )
        end

        infer_dependency_dates(infer_chart_order_dates(normalized_tasks))
      end

      def infer_chart_order_dates(tasks)
        root_tasks = tasks.select { |task| task[:dependency_ids].empty? }
        return tasks if root_tasks.empty?

        cursor = root_tasks.filter_map { |task| task[:start_date] }.min ||
          tasks.filter_map { |task| task[:chart_start_date] }.min ||
          Date.today
        root_tasks_by_id = root_tasks.each_with_object({}) do |task, memo|
          start_date = task[:start_date] || cursor
          end_date = task[:end_date] || infer_end_date(start_date, task[:duration_days])
          memo[task[:id]] = task.merge(start_date: start_date, end_date: end_date, chart_start_date: nil)
          cursor = end_date + 1 if end_date
        end

        tasks.map do |task|
          root_tasks_by_id.fetch(task[:id]) { task.merge(chart_start_date: nil) }
        end
      end

      def resolve_dependency_id(dependency, tasks, task_ids)
        key = dependency.to_s.strip
        return if key.empty?
        return task_ids[key] if task_ids[key]

        task = tasks.find { |candidate| candidate[:name].casecmp?(key) }
        task&.dig(:id)&.to_s
      end

      def build_metadata(tasks)
        {
          task_count: tasks.size,
          milestone_count: tasks.count { |task| task[:milestone] },
          dependency_count: tasks.sum { |task| task[:dependency_ids].size },
          issues_mapped: tasks.count { |task| task[:issue_number] }
        }
      end

      def calculate_duration(start_date, end_date)
        return unless start_date && end_date

        [(end_date - start_date).to_i + 1, 0].max
      end

      def infer_end_date(start_date, duration_days)
        return unless start_date && duration_days
        return start_date if duration_days.zero?

        start_date + duration_days - 1
      end

      def infer_dependency_dates(tasks)
        tasks_by_id = tasks.each_with_object({}) { |task, memo| memo[task[:id]] = task }

        tasks.map do |task|
          resolved_task = resolve_dependency_dates(task, tasks_by_id, {})
          tasks_by_id[task[:id]] = resolved_task
        end
      end

      def resolve_dependency_dates(task, tasks_by_id, visiting)
        return task if task[:start_date] && task[:end_date]
        return task if task[:dependency_ids].empty?
        return task if visiting[task[:id]]

        visiting[task[:id]] = true
        dependency_end_dates = task[:dependency_ids].filter_map do |dependency_id|
          dependency = tasks_by_id[dependency_id]
          next unless dependency

          resolved_dependency = resolve_dependency_dates(dependency, tasks_by_id, visiting)
          tasks_by_id[dependency_id] = resolved_dependency
          resolved_dependency[:end_date]
        end
        visiting.delete(task[:id])

        return task if dependency_end_dates.empty?

        start_date = task[:start_date] || dependency_end_dates.max + 1
        task.merge(
          start_date: start_date,
          end_date: task[:end_date] || infer_end_date(start_date, task[:duration_days])
        )
      end

      def text_at(node, path)
        child = node.elements[path]
        child&.text
      end

      def parse_date(value)
        return if value.to_s.strip.empty?

        Date.parse(value.to_s)
      end

      def extract_mermaid_start_date(lines)
        value = lines.filter_map do |line|
          line.strip.match(/\A%%\s*start_date:\s*(\d{4}-\d{2}-\d{2})\s*\z/i)&.captures&.first
        end.first
        parse_date(value)
      end

      def parse_duration(value)
        return if value.to_s.strip.empty?

        return value.to_i if value.to_s.match?(/\A\d+\z/)

        hours = value.to_s.scan(/(\d+)H/i).flatten.first.to_i
        minutes = value.to_s.scan(/(\d+)M/i).flatten.first.to_i
        days = (hours / 8.0) + (minutes.positive? ? 1.0 / 8 : 0)
        days.ceil
      end

      def parse_numeric(value)
        return if value.to_s.strip.empty?

        value.to_s[/\d+/]&.to_i
      end

      def first_value(row, *keys)
        keys.each do |key|
          value = row[key] || row[key.to_s] || row[key.to_sym]
          return value unless value.nil?
        end

        nil
      end

      def split_dependencies(value)
        value.to_s.split(/[,;|]/).map(&:strip).reject(&:empty?)
      end

      def truthy?(value)
        %w[true yes y 1].include?(value.to_s.strip.downcase)
      end

      def extract_issue_number(value)
        value.to_s.match(/#(\d+)|\bissue[-\s]?(\d+)\b|\(#(\d+)\)/i)&.captures&.compact&.first&.to_i
      end

      def slugify(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
      end
    end
  end
end
