# frozen_string_literal: true

require "fileutils"
require "shellwords"

module Aidp
  module Execute
    # Creates and refreshes concise feature/tool notes under docs/
    class ProjectKnowledgeManager
      MAX_TOOL_NOTES = 5

      def initialize(project_dir)
        @project_dir = project_dir
      end

      def sync!(step_name:, task_description:, affected_files:, tool_commands:, feature_identifier: nil)
        sync_feature_note(
          feature_identifier: feature_identifier,
          task_description: task_description,
          affected_files: affected_files
        )
        sync_tool_notes(step_name: step_name, affected_files: affected_files, tool_commands: tool_commands)
      end

      private

      def sync_feature_note(feature_identifier:, task_description:, affected_files:)
        return if affected_files.empty?

        feature_id = resolve_feature_id(
          feature_identifier: feature_identifier,
          affected_files: affected_files
        )
        return if feature_id.empty?

        path = File.join(@project_dir, "docs", "features", "#{feature_id}.md")
        markers = affected_files.map { |file| "<#{feature_id}:#{file}>" }
        learning = bullet_line("#{Time.now.utc.iso8601}: #{learning_summary(task_description)}")

        content = if File.exist?(path)
          update_existing_note(File.read(path, encoding: "UTF-8"), markers: markers, learning: learning)
        else
          build_feature_note(feature_id: feature_id, markers: markers, learning: learning)
        end

        write_note(path, content)
      end

      def sync_tool_notes(step_name:, affected_files:, tool_commands:)
        tool_commands.first(MAX_TOOL_NOTES).each do |command|
          tool_id = tool_identifier(command)
          next if tool_id.empty?

          path = File.join(@project_dir, "docs", "tools", "#{tool_id}.md")
          commands = [bullet_line("`#{command}`")]
          markers = affected_files.map { |file| "<#{tool_id}:#{file}>" }
          learning = bullet_line("#{Time.now.utc.iso8601}: Used `#{command}` during `#{step_name}`.")

          content = if File.exist?(path)
            update_existing_note(File.read(path, encoding: "UTF-8"), markers: markers, learning: learning, commands: commands)
          else
            build_tool_note(commands: commands, tool_id: tool_id, markers: markers, learning: learning)
          end

          write_note(path, content)
        end
      end

      def build_feature_note(feature_id:, markers:, learning:)
        <<~MARKDOWN
          # #{humanize(feature_id)}

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

      def build_tool_note(commands:, tool_id:, markers:, learning:)
        paths_section = markers.empty? ? "- Add affected paths as they become known." : markers.join("\n")

        <<~MARKDOWN
          # #{humanize(tool_id)}

          ## Commands
          #{commands.join("\n")}

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

      def update_existing_note(content, markers:, learning:, commands: [])
        updated = ensure_section_entries(content, "Commands", commands)
        updated = ensure_section_entries(updated, "Paths", markers)
        ensure_section_entries(updated, "Recent Learnings", [learning], normalizer: method(:normalize_learning_entry))
      end

      def ensure_section_entries(content, section_name, entries, normalizer: nil)
        return content if entries.empty?

        existing_section = content.match(/(## #{Regexp.escape(section_name)}\n)(.*?)(?=\n## |\z)/m)
        return append_new_section(content, section_name, entries) unless existing_section

        body = existing_section[2].to_s
        existing_entries = body.lines.map(&:strip).reject(&:empty?)
        normalized_existing = normalize_section_entries(existing_entries, normalizer)
        missing = entries.reject do |entry|
          normalized_existing.include?(normalize_section_entry(entry, normalizer))
        end
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

      def resolve_feature_id(feature_identifier:, affected_files:)
        explicit_id = normalize_id(feature_identifier)
        return explicit_id unless explicit_id.empty?

        derived_id = normalize_id(feature_path_identifier(affected_files))
        return derived_id unless derived_id.empty?

        ""
      end

      def feature_path_identifier(affected_files)
        feature_files = affected_files.select { |file| feature_path?(file) }
        segments = feature_files.map { |file| file.to_s.split("/") }
        return "" if segments.empty?

        shared_segments = meaningful_segments(common_path_segments(segments))
        return shared_segments.join("_") unless shared_segments.empty?

        meaningful_segments(segments.first).join("_")
      end

      def feature_path?(file)
        first_segment = file.to_s.split("/").first
        !%w[docs spec test].include?(first_segment)
      end

      def common_path_segments(all_segments)
        shared = []
        max_length = all_segments.map(&:length).min

        max_length.times do |index|
          segment = all_segments.first[index]
          break unless all_segments.all? { |segments| segments[index] == segment }

          shared << segment
        end

        shared
      end

      def meaningful_segments(path_segments)
        path_segments.map { |segment| segment.sub(/\.[^.]+\z/, "") }
          .reject { |segment| generic_path_segment?(segment) }
          .reject(&:empty?)
      end

      def generic_path_segment?(segment)
        %w[app lib spec test docs].include?(segment)
      end

      def normalize_id(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
      end

      def learning_summary(task_description)
        single_line = task_description.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
          .lines
          .map(&:strip)
          .reject(&:empty?)
          .join(" ")
          .gsub(/\s+/, " ")

        return "Updated feature context." if single_line.empty?
        return single_line if single_line.length <= 200

        "#{single_line[0, 197].rstrip}..."
      end

      def normalize_section_entries(entries, normalizer)
        entries.map { |entry| normalize_section_entry(entry, normalizer) }
      end

      def normalize_section_entry(entry, normalizer)
        return entry unless normalizer

        normalizer.call(entry)
      end

      def normalize_learning_entry(entry)
        entry.to_s.sub(/\A-\s*/, "").sub(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z:\s*/, "")
      end

      def tool_identifier(command)
        raw_command = command.to_s.strip
        tokens = Shellwords.split(raw_command)
        executable = unwrap_tool_command(tokens)
        normalize_id(executable)
      rescue ArgumentError
        normalize_id(raw_command.split(/\s+/).first)
      end

      def unwrap_tool_command(tokens)
        normalized = tokens.drop_while { |token| token.include?("=") && !token.start_with?("/", "./", "../") }
        return "" if normalized.empty?

        return File.basename(normalized[2]) if normalized[0] == "bundle" && normalized[1] == "exec" && normalized[2]
        return File.basename(normalized[1], ".rb") if normalized[0] == "ruby" && normalized[1]

        File.basename(normalized.first, ".rb")
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
