# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Indexes step templates into retrievable fragments
    #
    # Parses template markdown files from the templates/ directory
    # and creates searchable fragments based on template category,
    # content, and keywords.
    #
    # @example Basic usage
    #   indexer = TemplateIndexer.new(project_dir: "/path/to/project")
    #   indexer.index!
    #   fragments = indexer.find_templates(category: "analysis", tags: ["testing"])
    class TemplateIndexer
      attr_reader :templates, :project_dir

      # Template categories based on directory structure
      CATEGORIES = %w[analysis planning implementation].freeze

      def initialize(project_dir:)
        @project_dir = project_dir
        @templates = []
      end

      # Index all template files
      #
      # Scans the templates/ directory and indexes all markdown templates
      #
      # @return [Array<TemplateFragment>] List of indexed templates
      def index!
        @templates = []

        CATEGORIES.each do |category|
          category_dir = File.join(@project_dir, "templates", category)
          next unless Dir.exist?(category_dir)

          index_category(category, category_dir)
        end

        @templates
      end

      # Find templates matching given criteria
      #
      # @param category [String, nil] Category to filter by (e.g., "analysis", "planning")
      # @param tags [Array<String>] Tags to match
      # @param name [String, nil] Template name pattern to match
      # @return [Array<TemplateFragment>] Matching templates
      def find_templates(category: nil, tags: nil, name: nil)
        results = @templates

        if category
          results = results.select { |t| t.category == category }
        end

        if tags && !tags.empty?
          results = results.select { |t| t.matches_any_tag?(tags) }
        end

        if name
          pattern = Regexp.new(name, Regexp::IGNORECASE)
          results = results.select { |t| t.name =~ pattern }
        end

        results
      end

      # Get all unique tags from indexed templates
      #
      # @return [Array<String>] List of all tags
      def all_tags
        @templates.flat_map(&:tags).uniq.sort
      end

      # Get all categories
      #
      # @return [Array<String>] List of categories
      def categories
        @templates.map(&:category).uniq.sort
      end

      # Get template by ID
      #
      # @param id [String] Template ID
      # @return [TemplateFragment, nil] The template or nil if not found
      def find_by_id(id)
        @templates.find { |t| t.id == id }
      end

      private

      # Index all templates in a category
      #
      # @param category [String] Category name
      # @param category_dir [String] Category directory path
      def index_category(category, category_dir)
        Dir.glob(File.join(category_dir, "*.md")).each do |file_path|
          template = parse_template(category, file_path)
          @templates << template if template
        end
      end

      # Parse a template file
      #
      # @param category [String] Template category
      # @param file_path [String] Path to template file
      # @return [TemplateFragment, nil] Parsed template or nil
      def parse_template(category, file_path)
        content = File.read(file_path)
        filename = File.basename(file_path, ".md")

        # Extract title from first heading
        title = extract_title(content) || titleize(filename)

        # Extract tags from content and filename
        tags = extract_tags(filename, content, category)

        TemplateFragment.new(
          id: "#{category}/#{filename}",
          name: title,
          category: category,
          file_path: file_path,
          content: content,
          tags: tags
        )
      rescue => e
        Aidp.log_error("template_indexer", "Failed to parse template",
          file: file_path, error: e.message)
        nil
      end

      # Extract title from markdown content
      #
      # @param content [String] Markdown content
      # @return [String, nil] Extracted title
      def extract_title(content)
        match = content.match(/^#\s+(.+)$/)
        match&.[](1)&.strip
      end

      # Convert filename to title case
      #
      # @param filename [String] Filename without extension
      # @return [String] Title-cased string
      def titleize(filename)
        filename.split("_").map(&:capitalize).join(" ")
      end

      # Extract tags from template
      #
      # @param filename [String] Template filename
      # @param content [String] Template content
      # @param category [String] Template category
      # @return [Array<String>] List of tags
      def extract_tags(filename, content, category)
        tags = [category]

        # Extract from filename
        tags << "testing" if /test/i.match?(filename)
        tags << "refactor" if /refactor/i.match?(filename)
        tags << "architecture" if /architect/i.match?(filename)
        tags << "documentation" if /doc/i.match?(filename)
        tags << "analysis" if /analy[sz]/i.match?(filename)
        tags << "planning" if /plan|design/i.match?(filename)
        tags << "implementation" if /implement/i.match?(filename)
        tags << "security" if /security|auth/i.match?(filename)
        tags << "performance" if /performance|optim/i.match?(filename)

        # Extract from content
        tags << "testing" if /test coverage|testing strategy/i.match?(content)
        tags << "refactor" if /refactor|complexity/i.match?(content)
        tags << "security" if /security|vulnerabilit/i.match?(content)
        tags << "performance" if /performance|scalability/i.match?(content)
        tags << "documentation" if /documentation|readme/i.match?(content)
        tags << "database" if /database|sql|schema/i.match?(content)
        tags << "api" if /\bapi\b|endpoint|rest/i.match?(content)

        # Extract role-based tags
        tags << "analyst" if /analyst/i.match?(content)
        tags << "architect" if /architect/i.match?(content)
        tags << "developer" if /developer|implementation/i.match?(content)

        tags.uniq
      end
    end

    # Represents a template fragment
    #
    # Each template is a complete markdown file that can be
    # included or excluded from prompts based on relevance
    class TemplateFragment
      attr_reader :id, :name, :category, :file_path, :content, :tags

      def initialize(id:, name:, category:, file_path:, content:, tags: [])
        @id = id
        @name = name
        @category = category
        @file_path = file_path
        @content = content
        @tags = tags
      end

      # Check if template matches any of the given tags
      #
      # @param query_tags [Array<String>] Tags to match against
      # @return [Boolean] True if any tag matches
      def matches_any_tag?(query_tags)
        query_tags = query_tags.map(&:downcase)
        @tags.any? { |tag| query_tags.include?(tag.downcase) }
      end

      # Get the size of the template in characters
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

      # Get a summary of the template
      #
      # @return [Hash] Template summary
      def summary
        {
          id: @id,
          name: @name,
          category: @category,
          tags: @tags,
          size: size,
          estimated_tokens: estimated_tokens
        }
      end

      def to_s
        "TemplateFragment<#{@id}>"
      end

      def inspect
        "#<TemplateFragment id=#{@id} name=\"#{@name}\" category=#{@category} tags=#{@tags}>"
      end
    end
  end
end
