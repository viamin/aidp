# frozen_string_literal: true

require "yaml"
require "fileutils"

module Aidp
  module Execute
    # Manages a backlog of future work items discovered during work loops
    # Captures style violations, technical debt, and refactoring opportunities
    # that are not directly related to the current feature being implemented
    class FutureWorkBacklog
      attr_reader :project_dir, :entries, :current_context

      # Entry types
      ENTRY_TYPES = {
        style_violation: "Style Violation",
        refactor_opportunity: "Refactor Opportunity",
        technical_debt: "Technical Debt",
        todo: "TODO",
        performance: "Performance Issue",
        security: "Security Concern",
        documentation: "Documentation Needed"
      }.freeze

      # Priority levels
      PRIORITIES = {
        low: 1,
        medium: 2,
        high: 3,
        critical: 4
      }.freeze

      def initialize(project_dir, options = {})
        @project_dir = project_dir
        @backlog_dir = File.join(project_dir, ".aidp")
        @backlog_file = options[:backlog_file] || File.join(@backlog_dir, "future_work.yml")
        @markdown_file = File.join(@backlog_dir, "future_work.md")
        @entries = []
        @current_context = {}
        @options = options

        ensure_backlog_directory
        load_existing_backlog
      end

      # Add a new future work entry
      # @param entry_hash [Hash] Entry details
      # @option entry_hash [Symbol] :type Entry type (see ENTRY_TYPES)
      # @option entry_hash [String] :file File path
      # @option entry_hash [Integer,Range,String] :lines Line number(s)
      # @option entry_hash [String] :reason Description of the issue
      # @option entry_hash [String] :recommendation Recommended fix
      # @option entry_hash [Symbol] :priority Priority level (see PRIORITIES)
      # @option entry_hash [Hash] :metadata Additional metadata
      def add_entry(entry_hash)
        entry = normalize_entry(entry_hash)

        # Avoid duplicates
        return if duplicate?(entry)

        entry[:id] = generate_entry_id
        entry[:created_at] = Time.now.utc.iso8601
        entry[:context] = @current_context.dup

        @entries << entry
        entry
      end

      # Set context for subsequent entries (e.g., current work loop, step)
      def set_context(context_hash)
        @current_context.merge!(context_hash)
      end

      # Clear context
      def clear_context
        @current_context.clear
      end

      # Save backlog to disk (both YAML and Markdown)
      def save
        save_yaml
        save_markdown
      end

      # Get entries filtered by criteria
      def filter(criteria = {})
        filtered = @entries

        filtered = filtered.select { |e| e[:type] == criteria[:type] } if criteria[:type]
        filtered = filtered.select { |e| e[:file] == criteria[:file] } if criteria[:file]
        filtered = filtered.select { |e| e[:priority] == criteria[:priority] } if criteria[:priority]
        filtered = filtered.select { |e| e[:context][:work_loop] == criteria[:work_loop] } if criteria[:work_loop]

        filtered
      end

      # Get entries grouped by type
      def by_type
        @entries.group_by { |e| e[:type] }
      end

      # Get entries grouped by file
      def by_file
        @entries.group_by { |e| e[:file] }
      end

      # Get entries grouped by priority
      def by_priority
        @entries.group_by { |e| e[:priority] }.sort_by { |priority, _| -PRIORITIES[priority] }.to_h
      end

      # Get summary statistics
      def summary
        {
          total: @entries.size,
          by_type: by_type.transform_values(&:size),
          by_priority: by_priority.transform_values(&:size),
          files_affected: @entries.map { |e| e[:file] }.uniq.size
        }
      end

      # Mark entry as resolved
      def resolve_entry(entry_id, resolution_note = nil)
        entry = @entries.find { |e| e[:id] == entry_id }
        return unless entry

        entry[:resolved] = true
        entry[:resolved_at] = Time.now.utc.iso8601
        entry[:resolution_note] = resolution_note if resolution_note
      end

      # Remove resolved entries
      def clear_resolved
        @entries.reject! { |e| e[:resolved] }
      end

      # Convert entry to work loop PROMPT.md content
      def entry_to_prompt(entry_id)
        entry = @entries.find { |e| e[:id] == entry_id }
        return unless entry

        <<~PROMPT
          # Work Loop: #{entry_type_display(entry[:type])}

          ## Task Description

          **File**: #{entry[:file]}
          **Lines**: #{entry[:lines]}
          **Priority**: #{entry[:priority].to_s.upcase}

          ## Issue

          #{entry[:reason]}

          ## Recommended Fix

          #{entry[:recommendation]}

          ## Acceptance Criteria

          - [ ] #{entry[:reason]} is resolved
          - [ ] Code follows LLM_STYLE_GUIDE
          - [ ] Tests pass
          - [ ] No new style violations introduced

          ## Original Context

          - Work Loop: #{entry[:context][:work_loop] || "N/A"}
          - Step: #{entry[:context][:step] || "N/A"}
          - Created: #{entry[:created_at]}

          ## Completion

          Mark this complete by adding: STATUS: COMPLETE
        PROMPT
      end

      # Display summary of backlog
      def display_summary(output = $stdout)
        return if @entries.empty?

        output.puts "\n" + "=" * 80
        output.puts "📝 Future Work Backlog Summary"
        output.puts "=" * 80

        sum = summary
        output.puts "\nTotal Items: #{sum[:total]}"
        output.puts "Files Affected: #{sum[:files_affected]}"

        if sum[:by_type].any?
          output.puts "\nBy Type:"
          sum[:by_type].each do |type, count|
            output.puts "  #{entry_type_display(type)}: #{count}"
          end
        end

        if sum[:by_priority].any?
          output.puts "\nBy Priority:"
          sum[:by_priority].each do |priority, count|
            output.puts "  #{priority.to_s.upcase}: #{count}"
          end
        end

        output.puts "\n" + "-" * 80
        output.puts "Review backlog: .aidp/future_work.md"
        output.puts "Convert to work loop: aidp backlog convert <entry-id>"
        output.puts "=" * 80 + "\n"
      end

      private

      # Ensure backlog directory exists
      def ensure_backlog_directory
        FileUtils.mkdir_p(@backlog_dir) unless Dir.exist?(@backlog_dir)
      end

      # Load existing backlog from disk
      def load_existing_backlog
        return unless File.exist?(@backlog_file)

        data = YAML.load_file(@backlog_file)
        @entries = data["entries"] || [] if data.is_a?(Hash)
        @entries = symbolize_keys_deep(@entries)
      rescue => e
        warn "Warning: Could not load existing backlog: #{e.message}"
        @entries = []
      end

      # Save backlog to YAML
      def save_yaml
        data = {
          "version" => "1.0",
          "generated_at" => Time.now.utc.iso8601,
          "project" => @project_dir,
          "entries" => @entries.map { |e| stringify_keys_deep(e) }
        }

        File.write(@backlog_file, YAML.dump(data))
      end

      # Save backlog to Markdown (human-readable)
      def save_markdown
        content = generate_markdown

        File.write(@markdown_file, content)
      end

      # Generate Markdown representation
      def generate_markdown
        lines = []
        lines << "# Future Work Backlog"
        lines << ""
        lines << "Generated: #{Time.now.utc.iso8601}"
        lines << "Project: #{@project_dir}"
        lines << ""

        sum = summary
        lines << "## Summary"
        lines << ""
        lines << "- **Total Items**: #{sum[:total]}"
        lines << "- **Files Affected**: #{sum[:files_affected]}"
        lines << ""

        # Group by priority
        by_priority.each do |priority, entries|
          lines << "## #{priority.to_s.upcase} Priority (#{entries.size})"
          lines << ""

          # Group by type within priority
          entries.group_by { |e| e[:type] }.each do |type, type_entries|
            lines << "### #{entry_type_display(type)}"
            lines << ""

            type_entries.each do |entry|
              lines << format_entry_markdown(entry)
              lines << ""
            end
          end
        end

        lines << "---"
        lines << ""
        lines << "## Usage"
        lines << ""
        lines << "Convert an entry to a work loop:"
        lines << "```bash"
        lines << "aidp backlog convert <entry-id>"
        lines << "```"
        lines << ""

        lines.join("\n")
      end

      # Format single entry as Markdown
      def format_entry_markdown(entry)
        lines = []
        lines << "#### #{entry[:id]} - #{entry[:file]}"
        lines << ""
        lines << "**Lines**: #{entry[:lines]}"
        lines << ""
        lines << "**Issue**: #{entry[:reason]}"
        lines << ""
        lines << "**Recommendation**: #{entry[:recommendation]}"
        lines << ""

        if entry[:context].any?
          lines << "**Context**: Work Loop: #{entry[:context][:work_loop] || "N/A"}, Step: #{entry[:context][:step] || "N/A"}"
          lines << ""
        end

        lines << "*Created: #{entry[:created_at]}*"

        lines.join("\n")
      end

      # Normalize entry hash
      def normalize_entry(entry_hash)
        {
          type: entry_hash[:type] || :technical_debt,
          file: normalize_path(entry_hash[:file]),
          lines: normalize_lines(entry_hash[:lines]),
          reason: entry_hash[:reason] || "No reason provided",
          recommendation: entry_hash[:recommendation] || "No recommendation provided",
          priority: entry_hash[:priority] || :medium,
          metadata: entry_hash[:metadata] || {},
          resolved: false
        }
      end

      # Check if entry is duplicate
      def duplicate?(entry)
        @entries.any? do |existing|
          existing[:file] == entry[:file] &&
            existing[:lines] == entry[:lines] &&
            existing[:reason] == entry[:reason] &&
            !existing[:resolved]
        end
      end

      # Generate unique entry ID
      def generate_entry_id
        timestamp = Time.now.to_i
        random = SecureRandom.hex(4)
        "fw-#{timestamp}-#{random}"
      end

      # Normalize file path (relative to project)
      def normalize_path(file_path)
        return file_path unless file_path

        path = Pathname.new(file_path)
        project = Pathname.new(@project_dir)

        if path.absolute?
          path.relative_path_from(project).to_s
        else
          path.to_s
        end
      rescue ArgumentError
        file_path
      end

      # Normalize line numbers
      def normalize_lines(lines)
        case lines
        when Integer
          lines.to_s
        when Range
          "#{lines.begin}-#{lines.end}"
        when String
          lines
        else
          "unknown"
        end
      end

      # Get display name for entry type
      def entry_type_display(type)
        ENTRY_TYPES[type] || type.to_s.split("_").map(&:capitalize).join(" ")
      end

      # Recursively symbolize keys
      def symbolize_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = symbolize_keys_deep(value)
          end
        when Array
          obj.map { |item| symbolize_keys_deep(item) }
        else
          obj
        end
      end

      # Recursively stringify keys
      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_s] = stringify_keys_deep(value)
          end
        when Array
          obj.map { |item| stringify_keys_deep(item) }
        else
          obj
        end
      end
    end
  end
end
