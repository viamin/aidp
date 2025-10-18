# frozen_string_literal: true

require_relative "../errors"

module Aidp
  module Skills
    # Represents a skill/persona with metadata and content
    #
    # A Skill encapsulates an agent's persona, expertise, and capabilities.
    # Skills are loaded from SKILL.md files with YAML frontmatter.
    #
    # @example Creating a skill
    #   skill = Skill.new(
    #     id: "repository_analyst",
    #     name: "Repository Analyst",
    #     description: "Expert in version control analysis",
    #     version: "1.0.0",
    #     expertise: ["git analysis", "code metrics"],
    #     keywords: ["git", "metrics"],
    #     when_to_use: ["Analyzing repository history"],
    #     when_not_to_use: ["Writing new code"],
    #     compatible_providers: ["anthropic", "openai"],
    #     content: "You are a Repository Analyst...",
    #     source_path: "/path/to/SKILL.md"
    #   )
    class Skill
      attr_reader :id, :name, :description, :version, :expertise, :keywords,
        :when_to_use, :when_not_to_use, :compatible_providers,
        :content, :source_path

      # Initialize a new Skill
      #
      # @param id [String] Unique identifier for the skill
      # @param name [String] Human-readable name
      # @param description [String] Brief one-line description
      # @param version [String] Semantic version (e.g., "1.0.0")
      # @param expertise [Array<String>] List of expertise areas
      # @param keywords [Array<String>] Search/filter keywords
      # @param when_to_use [Array<String>] Guidance for when to use this skill
      # @param when_not_to_use [Array<String>] Guidance for when NOT to use
      # @param compatible_providers [Array<String>] Compatible provider names
      # @param content [String] The skill content (markdown)
      # @param source_path [String] Path to source SKILL.md file
      def initialize(
        id:,
        name:,
        description:,
        version:,
        content:, source_path:, expertise: [],
        keywords: [],
        when_to_use: [],
        when_not_to_use: [],
        compatible_providers: []
      )
        @id = id
        @name = name
        @description = description
        @version = version
        @expertise = Array(expertise)
        @keywords = Array(keywords)
        @when_to_use = Array(when_to_use)
        @when_not_to_use = Array(when_not_to_use)
        @compatible_providers = Array(compatible_providers)
        @content = content
        @source_path = source_path

        validate!
      end

      # Check if this skill is compatible with a given provider
      #
      # @param provider_name [String] Provider name (e.g., "anthropic")
      # @return [Boolean] True if compatible or no restrictions defined
      def compatible_with?(provider_name)
        return true if compatible_providers.empty?
        compatible_providers.include?(provider_name.to_s.downcase)
      end

      # Check if this skill matches a search query
      #
      # Searches across: id, name, description, expertise, keywords
      #
      # @param query [String] Search query (case-insensitive)
      # @return [Boolean] True if skill matches the query
      def matches?(query)
        return true if query.nil? || query.strip.empty?

        query_lower = query.downcase
        searchable_text = [
          id,
          name,
          description,
          expertise,
          keywords
        ].flatten.join(" ").downcase

        searchable_text.include?(query_lower)
      end

      # Get a summary of this skill for display
      #
      # @return [Hash] Summary with key skill metadata
      def summary
        {
          id: id,
          name: name,
          description: description,
          version: version,
          expertise_areas: expertise.size,
          keywords: keywords,
          providers: compatible_providers.empty? ? "all" : compatible_providers.join(", ")
        }
      end

      # Get full details of this skill for display
      #
      # @return [Hash] Detailed skill information
      def details
        {
          id: id,
          name: name,
          description: description,
          version: version,
          expertise: expertise,
          keywords: keywords,
          when_to_use: when_to_use,
          when_not_to_use: when_not_to_use,
          compatible_providers: compatible_providers,
          source: source_path,
          content_length: content.length
        }
      end

      # Return string representation
      #
      # @return [String] Skill representation
      def to_s
        "Skill[#{id}](#{name} v#{version})"
      end

      # Return inspection string
      #
      # @return [String] Detailed inspection
      def inspect
        "#<Aidp::Skills::Skill id=#{id} name=\"#{name}\" version=#{version} " \
          "source=#{source_path}>"
      end

      private

      # Validate required fields
      #
      # @raise [Aidp::Errors::ValidationError] if validation fails
      def validate!
        raise Aidp::Errors::ValidationError, "Skill id is required" if id.nil? || id.strip.empty?
        raise Aidp::Errors::ValidationError, "Skill name is required" if name.nil? || name.strip.empty?
        raise Aidp::Errors::ValidationError, "Skill description is required" if description.nil? || description.strip.empty?
        raise Aidp::Errors::ValidationError, "Skill version is required" if version.nil? || version.strip.empty?
        raise Aidp::Errors::ValidationError, "Skill content is required" if content.nil? || content.strip.empty?
        raise Aidp::Errors::ValidationError, "Skill source_path is required" if source_path.nil? || source_path.strip.empty?

        # Validate version format (simple semantic version check)
        unless version.match?(/^\d+\.\d+\.\d+/)
          raise Aidp::Errors::ValidationError, "Skill version must be in format X.Y.Z (e.g., 1.0.0)"
        end

        # Validate id format (lowercase, alphanumeric, underscores only)
        unless id.match?(/^[a-z0-9_]+$/)
          raise Aidp::Errors::ValidationError, "Skill id must be lowercase alphanumeric with underscores only"
        end
      end
    end
  end
end
