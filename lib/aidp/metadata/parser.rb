# frozen_string_literal: true

require "yaml"
require "digest"
require_relative "../errors"
require_relative "tool_metadata"

module Aidp
  module Metadata
    # Parses tool metadata from markdown files with YAML frontmatter
    #
    # Extracts metadata headers from skill, persona, and template files.
    # Supports both new metadata format and legacy skill format.
    #
    # @example Parsing a file
    #   metadata = Parser.parse_file("/path/to/tool.md", type: "skill")
    #
    # @example Parsing with auto-detection
    #   metadata = Parser.parse_file("/path/to/SKILL.md")
    class Parser
      # Parse metadata from a file
      #
      # @param file_path [String] Path to .md file
      # @param type [String, nil] Tool type ("skill", "persona", "template") or nil to auto-detect
      # @return [ToolMetadata] Parsed metadata
      # @raise [Aidp::Errors::ValidationError] if file format is invalid
      def self.parse_file(file_path, type: nil)
        Aidp.log_debug("metadata", "Parsing file", file: file_path, type: type)

        unless File.exist?(file_path)
          raise Aidp::Errors::ValidationError, "File not found: #{file_path}"
        end

        content = File.read(file_path, encoding: "UTF-8")
        file_hash = compute_file_hash(content)

        # Auto-detect type from filename or path if not specified
        type ||= detect_type(file_path)

        parse_string(content, source_path: file_path, file_hash: file_hash, type: type)
      end

      # Parse metadata from a string
      #
      # @param content [String] File content with frontmatter
      # @param source_path [String] Source file path for reference
      # @param file_hash [String] SHA256 hash of content
      # @param type [String] Tool type ("skill", "persona", "template")
      # @return [ToolMetadata] Parsed metadata
      # @raise [Aidp::Errors::ValidationError] if format is invalid
      def self.parse_string(content, source_path:, file_hash:, type:)
        metadata_hash, markdown = parse_frontmatter(content, source_path: source_path)

        # Map legacy skill fields to new metadata schema
        normalized = normalize_metadata(metadata_hash, type: type)

        ToolMetadata.new(
          type: type,
          id: normalized["id"],
          title: normalized["title"],
          summary: normalized["summary"],
          version: normalized["version"],
          applies_to: normalized["applies_to"] || [],
          work_unit_types: normalized["work_unit_types"] || [],
          priority: normalized["priority"] || ToolMetadata::DEFAULT_PRIORITY,
          capabilities: normalized["capabilities"] || [],
          dependencies: normalized["dependencies"] || [],
          experimental: normalized["experimental"] || false,
          content: markdown,
          source_path: source_path,
          file_hash: file_hash
        )
      rescue Aidp::Errors::ValidationError => e
        Aidp.log_error("metadata", "Metadata validation failed", error: e.message, file: source_path)
        raise
      end

      # Compute SHA256 hash of file content
      #
      # @param content [String] File content
      # @return [String] SHA256 hex string
      def self.compute_file_hash(content)
        Digest::SHA256.hexdigest(content)
      end

      # Detect tool type from file path
      #
      # @param file_path [String] File path
      # @return [String] Detected type ("skill", "persona", or "template")
      def self.detect_type(file_path)
        case file_path
        when %r{/skills/}
          "skill"
        when %r{/personas/}
          "persona"
        when /SKILL\.md$/
          "skill"
        else
          "template"
        end
      end

      # Parse YAML frontmatter from content
      #
      # @param content [String] File content with frontmatter
      # @param source_path [String] Source path for error messages
      # @return [Array(Hash, String)] Tuple of [metadata, markdown_content]
      # @raise [Aidp::Errors::ValidationError] if frontmatter is invalid
      def self.parse_frontmatter(content, source_path:)
        # Ensure content is UTF-8 encoded
        content = content.encode("UTF-8", invalid: :replace, undef: :replace) unless content.encoding == Encoding::UTF_8
        lines = content.lines

        unless lines.first&.strip == "---"
          raise Aidp::Errors::ValidationError,
            "Invalid format: missing YAML frontmatter in #{source_path}"
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
            "Invalid format: missing closing frontmatter delimiter in #{source_path}"
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

        [metadata, markdown_content]
      end

      # Normalize metadata from various formats to unified schema
      #
      # Handles both legacy skill format and new metadata format.
      #
      # @param metadata [Hash] Raw metadata from frontmatter
      # @param type [String] Tool type
      # @return [Hash] Normalized metadata
      def self.normalize_metadata(metadata, type:)
        normalized = {}

        # Required fields (map from legacy names)
        normalized["id"] = metadata["id"]
        normalized["title"] = metadata["title"] || metadata["name"]
        normalized["summary"] = metadata["summary"] || metadata["description"]
        normalized["version"] = metadata["version"]

        # Optional fields (new schema)
        normalized["applies_to"] = extract_applies_to(metadata)
        normalized["work_unit_types"] = metadata["work_unit_types"] || []
        normalized["priority"] = metadata["priority"]&.to_i
        normalized["capabilities"] = metadata["capabilities"] || []
        normalized["dependencies"] = metadata["dependencies"] || []
        normalized["experimental"] = metadata["experimental"] || false

        normalized
      end

      # Extract applies_to tags from various metadata fields
      #
      # Combines keywords, tags, expertise areas, etc. into unified applies_to list
      #
      # @param metadata [Hash] Raw metadata
      # @return [Array<String>] Combined applies_to tags
      def self.extract_applies_to(metadata)
        applies_to = []

        # New schema
        applies_to.concat(metadata["applies_to"] || [])

        # Legacy skill schema
        applies_to.concat(metadata["keywords"] || [])
        applies_to.concat(metadata["tags"] || [])

        # Flatten and deduplicate
        applies_to.flatten.compact.uniq
      end

      private_class_method :parse_frontmatter, :normalize_metadata, :extract_applies_to
    end
  end
end
