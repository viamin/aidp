# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Indexes LLM_STYLE_GUIDE.md into retrievable fragments
    #
    # Parses the style guide markdown and creates searchable fragments
    # based on headings and sections. Each fragment can be independently
    # included or excluded from prompts based on relevance.
    #
    # @example Basic usage
    #   indexer = StyleGuideIndexer.new(project_dir: "/path/to/project")
    #   indexer.index!
    #   fragments = indexer.find_fragments(tags: ["testing", "naming"])
    class StyleGuideIndexer
      attr_reader :fragments, :project_dir

      def initialize(project_dir:)
        @project_dir = project_dir
        @fragments = []
      end

      # Index the style guide file
      #
      # Parses the LLM_STYLE_GUIDE.md and extracts fragments
      # organized by sections and headings
      #
      # @return [Array<Fragment>] List of indexed fragments
      def index!
        @fragments = []
        content = read_style_guide

        return @fragments if content.nil? || content.empty?

        parse_fragments(content)
        @fragments
      end

      # Find fragments matching given criteria
      #
      # @param tags [Array<String>] Tags to match (e.g., ["testing", "naming"])
      # @param heading [String] Heading pattern to match
      # @param min_level [Integer] Minimum heading level (1-6)
      # @param max_level [Integer] Maximum heading level (1-6)
      # @return [Array<Fragment>] Matching fragments
      def find_fragments(tags: nil, heading: nil, min_level: 1, max_level: 6)
        results = @fragments

        if tags && !tags.empty?
          results = results.select { |f| f.matches_any_tag?(tags) }
        end

        if heading
          pattern = Regexp.new(heading, Regexp::IGNORECASE)
          results = results.select { |f| f.heading =~ pattern }
        end

        results.select { |f| f.level.between?(min_level, max_level) }
      end

      # Get all unique tags from indexed fragments
      #
      # @return [Array<String>] List of all tags
      def all_tags
        @fragments.flat_map(&:tags).uniq.sort
      end

      # Get fragment by ID
      #
      # @param id [String] Fragment ID (e.g., "naming-structure")
      # @return [Fragment, nil] The fragment or nil if not found
      def find_by_id(id)
        @fragments.find { |f| f.id == id }
      end

      private

      # Read the LLM_STYLE_GUIDE.md file
      #
      # @return [String, nil] File content or nil if not found
      def read_style_guide
        guide_path = File.join(@project_dir, "docs", "LLM_STYLE_GUIDE.md")
        return nil unless File.exist?(guide_path)

        File.read(guide_path)
      end

      # Parse markdown content into fragments
      #
      # @param content [String] Markdown content
      # @return [Array<Fragment>] Parsed fragments
      def parse_fragments(content)
        lines = content.lines
        current_content = []
        current_heading = nil
        current_level = 0

        lines.each_with_index do |line, idx|
          if line.match?(/^#+\s+/)
            # Save previous section if exists
            save_fragment(current_heading, current_level, current_content) if current_heading

            # Start new section
            current_level = line.match(/^(#+)/)[1].length
            current_heading = line.sub(/^#+\s+/, "").strip
            current_content = [line]
          elsif current_heading
            current_content << line
          end
        end

        # Save last section
        save_fragment(current_heading, current_level, current_content) if current_heading
      end

      # Save a fragment from heading and content
      #
      # @param heading [String] Section heading
      # @param level [Integer] Heading level (1-6)
      # @param content [Array<String>] Section content lines
      def save_fragment(heading, level, content)
        return if heading.nil? || content.empty?

        fragment = Fragment.new(
          id: generate_id(heading),
          heading: heading,
          level: level,
          content: content.join,
          tags: extract_tags(heading, content.join)
        )

        @fragments << fragment
      end

      # Generate a unique ID from heading
      #
      # @param heading [String] Section heading
      # @return [String] Fragment ID (e.g., "zero-framework-cognition-zfc")
      def generate_id(heading)
        heading
          .downcase
          .gsub(/[^a-z0-9\s-]/, "")
          .gsub(/\s+/, "-").squeeze("-")
          .gsub(/\A-|-\z/, "")
      end

      # Extract relevant tags from heading and content
      #
      # @param heading [String] Section heading
      # @param content [String] Section content
      # @return [Array<String>] List of tags
      def extract_tags(heading, content)
        tags = []

        # Extract from heading
        tags << "naming" if /naming|structure/i.match?(heading)
        tags << "testing" if /test/i.match?(heading)
        tags << "logging" if /log/i.match?(heading)
        tags << "error" if /error|exception/i.match?(heading)
        tags << "security" if /security|auth/i.match?(heading)
        tags << "performance" if /performance|optim/i.match?(heading)
        tags << "zfc" if /zero framework|zfc/i.match?(heading)
        tags << "tty" if /tty|tui|ui/i.match?(heading)
        tags << "git" if /git|version|commit/i.match?(heading)
        tags << "style" if /style|format|convention/i.match?(heading)
        tags << "refactor" if /refactor/i.match?(heading)
        tags << "architecture" if /architect|design|pattern/i.match?(heading)

        # Extract from content keywords
        tags << "testing" if /rspec|test.*spec|describe.*it/i.match?(content)
        tags << "async" if /async|thread|concurrent/i.match?(content)
        tags << "api" if /api|endpoint|rest/i.match?(content)
        tags << "database" if /database|sql|query/i.match?(content)

        tags.uniq
      end
    end

    # Represents a fragment of the style guide
    #
    # Each fragment corresponds to a section or subsection
    # and can be independently selected for inclusion in prompts
    class Fragment
      attr_reader :id, :heading, :level, :content, :tags

      def initialize(id:, heading:, level:, content:, tags: [])
        @id = id
        @heading = heading
        @level = level
        @content = content
        @tags = tags
      end

      # Check if fragment matches any of the given tags
      #
      # @param query_tags [Array<String>] Tags to match against
      # @return [Boolean] True if any tag matches
      def matches_any_tag?(query_tags)
        query_tags = query_tags.map(&:downcase)
        @tags.any? { |tag| query_tags.include?(tag.downcase) }
      end

      # Get the size of the fragment in characters
      #
      # @return [Integer] Character count
      def size
        @content.length
      end

      # Estimate token count (rough approximation: 1 token ≈ 4 chars)
      #
      # @return [Integer] Estimated token count
      def estimated_tokens
        (size / 4.0).ceil
      end

      # Get a summary of the fragment
      #
      # @return [Hash] Fragment summary
      def summary
        {
          id: @id,
          heading: @heading,
          level: @level,
          tags: @tags,
          size: size,
          estimated_tokens: estimated_tokens
        }
      end

      def to_s
        "Fragment<#{@id}>"
      end

      def inspect
        "#<Fragment id=#{@id} heading=\"#{@heading}\" level=#{@level} tags=#{@tags}>"
      end
    end
  end
end
