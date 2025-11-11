# frozen_string_literal: true

require "yaml"
require_relative "../errors"

module Aidp
  module Skills
    # Loads skills from SKILL.md files with YAML frontmatter
    #
    # Parses skill files in the format:
    #   ---
    #   id: skill_id
    #   name: Skill Name
    #   ...
    #   ---
    #   # Skill content in markdown
    #
    # @example Loading a skill
    #   skill = Loader.load_from_file("/path/to/SKILL.md")
    #
    # @example Loading a skill with provider filtering
    #   skill = Loader.load_from_file("/path/to/SKILL.md", provider: "anthropic")
    class Loader
      # Load a skill from a file path
      #
      # @param file_path [String] Path to SKILL.md file
      # @param provider [String, nil] Optional provider name for compatibility check
      # @return [Skill, nil] Loaded skill or nil if incompatible with provider
      # @raise [Aidp::Errors::ValidationError] if file format is invalid
      def self.load_from_file(file_path, provider: nil)
        Aidp.log_debug("skills", "Loading skill from file", file: file_path, provider: provider)

        unless File.exist?(file_path)
          raise Aidp::Errors::ValidationError, "Skill file not found: #{file_path}"
        end

        content = File.read(file_path, encoding: "UTF-8")
        load_from_string(content, source_path: file_path, provider: provider)
      end

      # Load a skill from a string
      #
      # @param content [String] SKILL.md file content
      # @param source_path [String] Source file path for reference
      # @param provider [String, nil] Optional provider name for compatibility check
      # @return [Skill, nil] Loaded skill or nil if incompatible with provider
      # @raise [Aidp::Errors::ValidationError] if format is invalid
      def self.load_from_string(content, source_path:, provider: nil)
        metadata, markdown = parse_frontmatter(content, source_path: source_path)

        skill = Skill.new(
          id: metadata["id"],
          name: metadata["name"],
          description: metadata["description"],
          version: metadata["version"],
          expertise: metadata["expertise"] || [],
          keywords: metadata["keywords"] || [],
          when_to_use: metadata["when_to_use"] || [],
          when_not_to_use: metadata["when_not_to_use"] || [],
          compatible_providers: metadata["compatible_providers"] || [],
          content: markdown,
          source_path: source_path
        )

        # Filter by provider compatibility if specified
        if provider && !skill.compatible_with?(provider)
          Aidp.log_debug(
            "skills",
            "Skipping incompatible skill",
            skill_id: skill.id,
            provider: provider,
            compatible: skill.compatible_providers
          )
          return nil
        end

        Aidp.log_debug(
          "skills",
          "Loaded skill",
          skill_id: skill.id,
          version: skill.version,
          source: source_path
        )

        skill
      rescue Aidp::Errors::ValidationError => e
        Aidp.log_error("skills", "Skill validation failed", error: e.message, file: source_path)
        raise
      end

      # Load all skills from a directory
      #
      # @param directory [String] Path to directory containing skill subdirectories
      # @param provider [String, nil] Optional provider name for compatibility check
      # @return [Array<Skill>] Array of loaded skills (excludes incompatible)
      def self.load_from_directory(directory, provider: nil)
        Aidp.log_debug("skills", "Loading skills from directory", directory: directory, provider: provider)

        unless Dir.exist?(directory)
          Aidp.log_warn("skills", "Skills directory not found", directory: directory)
          return []
        end

        skills = []
        skill_dirs = Dir.glob(File.join(directory, "*")).select { |path| File.directory?(path) }

        skill_dirs.each do |skill_dir|
          skill_file = File.join(skill_dir, "SKILL.md")
          next unless File.exist?(skill_file)

          begin
            skill = load_from_file(skill_file, provider: provider)
            skills << skill if skill # nil if incompatible with provider
          rescue Aidp::Errors::ValidationError => e
            Aidp.log_warn(
              "skills",
              "Failed to load skill",
              file: skill_file,
              error: e.message
            )
            # Continue loading other skills even if one fails
          end
        end

        Aidp.log_info(
          "skills",
          "Loaded skills from directory",
          directory: directory,
          count: skills.size
        )

        skills
      end

      # Parse YAML frontmatter from content
      #
      # @param content [String] File content with frontmatter
      # @param source_path [String] Source path for error messages
      # @return [Array(Hash, String)] Tuple of [metadata, markdown_content]
      # @raise [Aidp::Errors::ValidationError] if frontmatter is missing or invalid
      def self.parse_frontmatter(content, source_path:)
        # Ensure content is UTF-8 encoded
        content = content.encode("UTF-8", invalid: :replace, undef: :replace) unless content.encoding == Encoding::UTF_8
        lines = content.lines

        unless lines.first&.strip == "---"
          raise Aidp::Errors::ValidationError,
            "Invalid SKILL.md format: missing YAML frontmatter in #{source_path}"
        end

        frontmatter_lines = []
        body_start_index = nil

        lines[1..].each_with_index do |line, index|
          if line.strip == "---"
            body_start_index = index + 2
            break
          end

          frontmatter_lines << line
        end

        unless body_start_index
          raise Aidp::Errors::ValidationError,
            "Invalid SKILL.md format: missing closing frontmatter delimiter in #{source_path}"
        end

        markdown_content = lines[body_start_index..]&.join.to_s.strip
        frontmatter_yaml = frontmatter_lines.join

        begin
          metadata = YAML.safe_load(frontmatter_yaml, permitted_classes: [Symbol])
        rescue Psych::SyntaxError => e
          raise Aidp::Errors::ValidationError,
            "Invalid YAML frontmatter in #{source_path}: #{e.message}"
        end

        unless metadata.is_a?(Hash)
          raise Aidp::Errors::ValidationError,
            "YAML frontmatter must be a hash in #{source_path}"
        end

        validate_required_fields(metadata, source_path: source_path)

        [metadata, markdown_content]
      end

      # Validate required frontmatter fields
      #
      # @param metadata [Hash] Parsed YAML metadata
      # @param source_path [String] Source path for error messages
      # @raise [Aidp::Errors::ValidationError] if required fields are missing
      def self.validate_required_fields(metadata, source_path:)
        required_fields = %w[id name description version]

        required_fields.each do |field|
          next if metadata[field] && !metadata[field].to_s.strip.empty?

          raise Aidp::Errors::ValidationError,
            "Missing required field '#{field}' in #{source_path}"
        end
      end

      private_class_method :parse_frontmatter, :validate_required_fields
    end
  end
end
