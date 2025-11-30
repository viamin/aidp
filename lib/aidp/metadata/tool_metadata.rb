# frozen_string_literal: true

require_relative "../errors"

module Aidp
  module Metadata
    # Base class for tool metadata (skills, personas, templates)
    #
    # Represents metadata extracted from YAML frontmatter in .md files.
    # Provides validation and query capabilities for the tool directory.
    #
    # @example Creating tool metadata
    #   metadata = ToolMetadata.new(
    #     type: "skill",
    #     id: "ruby_rspec_tdd",
    #     title: "Ruby RSpec TDD Implementer",
    #     summary: "Expert in Test-Driven Development",
    #     version: "1.0.0",
    #     applies_to: ["ruby", "testing"],
    #     work_unit_types: ["implementation", "testing"],
    #     priority: 10,
    #     content: "You are a TDD expert...",
    #     source_path: "/path/to/SKILL.md"
    #   )
    class ToolMetadata
      attr_reader :type, :id, :title, :summary, :version,
        :applies_to, :work_unit_types, :priority,
        :capabilities, :dependencies, :experimental,
        :content, :source_path, :file_hash

      # Valid tool types
      VALID_TYPES = %w[skill persona template].freeze

      # Default priority (medium)
      DEFAULT_PRIORITY = 5

      # Initialize new tool metadata
      #
      # @param type [String] Tool type: "skill", "persona", or "template"
      # @param id [String] Unique identifier (lowercase, alphanumeric, underscores)
      # @param title [String] Human-readable title
      # @param summary [String] Brief one-line summary
      # @param version [String] Semantic version (e.g., "1.0.0")
      # @param applies_to [Array<String>] Tags indicating applicability
      # @param work_unit_types [Array<String>] Work unit types this tool supports
      # @param priority [Integer] Priority for ranking (1-10, default 5)
      # @param capabilities [Array<String>] Capabilities provided by this tool
      # @param dependencies [Array<String>] IDs of required tools
      # @param experimental [Boolean] Whether this is experimental
      # @param content [String] The tool content (markdown)
      # @param source_path [String] Path to source .md file
      # @param file_hash [String] SHA256 hash of source file for cache invalidation
      def initialize(
        type:,
        id:,
        title:,
        summary:,
        version:,
        content:,
        source_path:,
        file_hash:,
        applies_to: [],
        work_unit_types: [],
        priority: DEFAULT_PRIORITY,
        capabilities: [],
        dependencies: [],
        experimental: false
      )
        @type = type
        @id = id
        @title = title
        @summary = summary
        @version = version
        @applies_to = Array(applies_to)
        @work_unit_types = Array(work_unit_types)
        @priority = priority
        @capabilities = Array(capabilities)
        @dependencies = Array(dependencies)
        @experimental = experimental
        @content = content
        @source_path = source_path
        @file_hash = file_hash

        validate!
      end

      # Check if this tool applies to given tags
      #
      # @param tags [Array<String>] Tags to check against
      # @return [Boolean] True if any tag matches applies_to
      def applies_to?(tags)
        return true if applies_to.empty?
        tags = Array(tags).map(&:downcase)
        applies_to.map(&:downcase).any? { |tag| tags.include?(tag) }
      end

      # Check if this tool supports a given work unit type
      #
      # @param type [String] Work unit type (e.g., "implementation", "analysis")
      # @return [Boolean] True if type is supported
      def supports_work_unit?(type)
        return true if work_unit_types.empty?
        work_unit_types.map(&:downcase).include?(type.to_s.downcase)
      end

      # Get a summary of this tool for display
      #
      # @return [Hash] Summary with key metadata
      def summary_hash
        {
          type: type,
          id: id,
          title: title,
          summary: summary,
          version: version,
          priority: priority,
          tags: applies_to,
          experimental: experimental
        }
      end

      # Get full details of this tool for display
      #
      # @return [Hash] Detailed tool information
      def details
        {
          type: type,
          id: id,
          title: title,
          summary: summary,
          version: version,
          applies_to: applies_to,
          work_unit_types: work_unit_types,
          priority: priority,
          capabilities: capabilities,
          dependencies: dependencies,
          experimental: experimental,
          source: source_path,
          file_hash: file_hash,
          content_length: content.length
        }
      end

      # Convert to hash for serialization
      #
      # @return [Hash] Metadata as hash (for JSON)
      def to_h
        {
          "type" => type,
          "id" => id,
          "title" => title,
          "summary" => summary,
          "version" => version,
          "applies_to" => applies_to,
          "work_unit_types" => work_unit_types,
          "priority" => priority,
          "capabilities" => capabilities,
          "dependencies" => dependencies,
          "experimental" => experimental,
          "source_path" => source_path,
          "file_hash" => file_hash
        }
      end

      # Return string representation
      #
      # @return [String] Tool representation
      def to_s
        "#{type.capitalize}[#{id}](#{title} v#{version})"
      end

      # Return inspection string
      #
      # @return [String] Detailed inspection
      def inspect
        "#<Aidp::Metadata::ToolMetadata type=#{type} id=#{id} title=\"#{title}\" " \
          "version=#{version} source=#{source_path}>"
      end

      private

      # Validate required fields and types
      #
      # @raise [Aidp::Errors::ValidationError] if validation fails
      def validate!
        validate_required_fields!
        validate_types!
        validate_formats!
        validate_ranges!
      end

      # Validate required fields are present
      def validate_required_fields!
        raise Aidp::Errors::ValidationError, "type is required" if type.nil? || type.strip.empty?
        raise Aidp::Errors::ValidationError, "id is required" if id.nil? || id.strip.empty?
        raise Aidp::Errors::ValidationError, "title is required" if title.nil? || title.strip.empty?
        raise Aidp::Errors::ValidationError, "summary is required" if summary.nil? || summary.strip.empty?
        raise Aidp::Errors::ValidationError, "version is required" if version.nil? || version.strip.empty?
        raise Aidp::Errors::ValidationError, "content is required" if content.nil? || content.strip.empty?
        raise Aidp::Errors::ValidationError, "source_path is required" if source_path.nil? || source_path.strip.empty?
        raise Aidp::Errors::ValidationError, "file_hash is required" if file_hash.nil? || file_hash.strip.empty?
      end

      # Validate field types
      def validate_types!
        unless VALID_TYPES.include?(type)
          raise Aidp::Errors::ValidationError, "type must be one of: #{VALID_TYPES.join(", ")}"
        end

        unless priority.is_a?(Integer)
          raise Aidp::Errors::ValidationError, "priority must be an integer"
        end

        unless [true, false].include?(experimental)
          raise Aidp::Errors::ValidationError, "experimental must be boolean"
        end
      end

      # Validate field formats
      def validate_formats!
        # Validate version format (simple semantic version check)
        unless version.match?(/^\d+\.\d+\.\d+/)
          raise Aidp::Errors::ValidationError, "version must be in format X.Y.Z (e.g., 1.0.0)"
        end

        # Validate id format (lowercase, alphanumeric, underscores only)
        unless id.match?(/^[a-z0-9_]+$/)
          raise Aidp::Errors::ValidationError, "id must be lowercase alphanumeric with underscores only"
        end

        # Validate file_hash format (SHA256 hex)
        unless file_hash.match?(/^[a-f0-9]{64}$/)
          raise Aidp::Errors::ValidationError, "file_hash must be a valid SHA256 hex string"
        end
      end

      # Validate value ranges
      def validate_ranges!
        unless priority.between?(1, 10)
          raise Aidp::Errors::ValidationError, "priority must be between 1 and 10"
        end
      end
    end
  end
end
