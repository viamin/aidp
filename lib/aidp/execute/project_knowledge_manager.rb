# frozen_string_literal: true

require "fileutils"

module Aidp
  module Execute
    # Creates and refreshes concise feature/tool notes under docs/
    class ProjectKnowledgeManager
      MAX_TOOL_NOTES = 5

      def initialize(project_dir)
        @project_dir = project_dir
      end

      def sync!(step_name:, task_description:, affected_files:, tool_commands:)
        sync_feature_note(step_name: step_name, task_description: task_description, affected_files: affected_files)
        sync_tool_notes(step_name: step_name, affected_files: affected_files, tool_commands: tool_commands)
      end

      private

      def sync_feature_note(step_name:, task_description:, affected_files:)
        return if affected_files.empty?

        feature_id = normalize_id(step_name)
        path = File.join(@project_dir, "docs", "features", "#{feature_id}.md")
        markers = affected_files.map { |file| "<#{feature_id}:#{file}>" }
        learning = bullet_line("#{Time.now.utc.iso8601}: #{task_description}")

        content = if File.exist?(path)
          update_existing_note(File.read(path, encoding: "UTF-8"), markers: markers, learning: learning)
        else
          build_feature_note(step_name: step_name, markers: markers, learning: learning)
        end

        write_note(path, content)
      end

      def sync_tool_notes(step_name:, affected_files:, tool_commands:)
        tool_commands.first(MAX_TOOL_NOTES).each do |command|
          tool_id = normalize_id(command)
          path = File.join(@project_dir, "docs", "tools", "#{tool_id}.md")
          markers = affected_files.map { |file| "<#{tool_id}:#{file}>" }
          learning = bullet_line("#{Time.now.utc.iso8601}: Used `#{command}` during `#{step_name}`.")

          content = if File.exist?(path)
            update_existing_note(File.read(path, encoding: "UTF-8"), markers: markers, learning: learning)
          else
            build_tool_note(command: command, tool_id: tool_id, markers: markers, learning: learning)
          end

          write_note(path, content)
        end
      end

      def build_feature_note(step_name:, markers:, learning:)
        <<~MARKDOWN
          # #{humanize(step_name)}

          ## Paths
          #{markers.join("\n")}

          ## Purpose
          - Concise feature context for work touching these paths.

          ## Users
          - Developers maintaining this feature.

          ## Known Gaps
          - Add concrete gaps when discovered.

          ## Key Decisions
          - Add behavior-affecting decisions when they become clear.

          ## Recent Learnings
          #{learning}
        MARKDOWN
      end

      def build_tool_note(command:, tool_id:, markers:, learning:)
        paths_section = markers.empty? ? "- Add affected paths as they become known." : markers.join("\n")

        <<~MARKDOWN
          # #{humanize(tool_id)}

          ## Command
          - `#{command}`

          ## Paths
          #{paths_section}

          ## Intended Use
          - Run this tool while validating or updating related paths.

          ## Known Gaps
          - Add environment quirks or failure modes when discovered.

          ## Recent Learnings
          #{learning}
        MARKDOWN
      end

      def update_existing_note(content, markers:, learning:)
        updated = ensure_section_entries(content, "Paths", markers)
        ensure_section_entries(updated, "Recent Learnings", [learning])
      end

      def ensure_section_entries(content, section_name, entries)
        return content if entries.empty?

        existing_section = content.match(/(## #{Regexp.escape(section_name)}\n)(.*?)(?=\n## |\z)/m)
        return append_new_section(content, section_name, entries) unless existing_section

        body = existing_section[2].to_s
        missing = entries.reject { |entry| body.include?(entry) }
        return content if missing.empty?

        replacement = "#{existing_section[1]}#{body.rstrip}\n#{missing.join("\n")}\n"
        content.sub(existing_section[0], replacement)
      end

      def append_new_section(content, section_name, entries)
        [content.rstrip, "", "## #{section_name}", entries.join("\n"), ""].join("\n")
      end

      def write_note(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def normalize_id(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
      end

      def humanize(value)
        value.to_s.split(/[_\s]+/).map(&:capitalize).join(" ")
      end

      def bullet_line(value)
        "- #{value}"
      end
    end
  end
end
