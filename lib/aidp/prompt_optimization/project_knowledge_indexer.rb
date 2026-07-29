# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Indexes concise feature and tool notes stored under docs/
    #
    # These notes use inline path markers like <feature_id:lib/file.rb> so
    # they can be found quickly by ripgrep and loaded for matching files.
    class ProjectKnowledgeIndexer
      KNOWLEDGE_DIRS = {
        feature: File.join("docs", "features"),
        tool: File.join("docs", "tools")
      }.freeze

      MARKER_PATTERN = /<([a-z0-9_]+):([^>\n]+)>/

      attr_reader :fragments, :project_dir

      def initialize(project_dir:)
        @project_dir = project_dir
        @fragments = []
      end

      def index!
        @fragments = []

        KNOWLEDGE_DIRS.each do |note_type, relative_dir|
          index_directory(note_type, File.join(project_dir, relative_dir))
        end

        @fragments
      end

      private

      def index_directory(note_type, directory)
        return unless Dir.exist?(directory)

        Dir.glob(File.join(directory, "**", "*.md")).sort.each do |file_path|
          @fragments << parse_file(file_path, note_type)
        end
      end

      def parse_file(file_path, note_type)
        content = File.read(file_path, encoding: "UTF-8")
        title = extract_title(content, file_path)
        markers = content.scan(MARKER_PATTERN)
        note_id = markers.first&.first || File.basename(file_path, ".md")

        ProjectKnowledgeFragment.new(
          id: note_id,
          title: title,
          note_type: note_type,
          file_path: file_path,
          content: content,
          linked_paths: markers.map { |(_, path)| path.strip }.uniq,
          tags: extract_tags(note_type, content)
        )
      end

      def extract_title(content, file_path)
        heading = content.lines.find { |line| line.start_with?("# ") }
        return heading.sub(/^#\s+/, "").strip if heading

        File.basename(file_path, ".md").split("_").map(&:capitalize).join(" ")
      end

      def extract_tags(note_type, content)
        text = content.downcase
        tags = [note_type.to_s, "project_knowledge"]
        tags << "testing" if text.match?(/rspec|rubocop|test|lint|spec/)
        tags << "documentation" if text.match?(/doc|guide|markdown/)
        tags << "implementation" if text.match?(/implement|feature|behavior/)
        tags << "filesystem" if text.match?(/file|path|directory|workspace/)
        tags << "external_service" if text.match?(/api|provider|service|github|slack/)
        tags.uniq
      end
    end

    class ProjectKnowledgeFragment
      attr_reader :id, :title, :note_type, :file_path, :content, :linked_paths, :tags

      def initialize(id:, title:, note_type:, file_path:, content:, linked_paths:, tags:)
        @id = id
        @title = title
        @note_type = note_type
        @file_path = file_path
        @content = content
        @linked_paths = linked_paths
        @tags = tags
      end

      def estimated_tokens
        (content.length / 4.0).ceil
      end
    end
  end
end
