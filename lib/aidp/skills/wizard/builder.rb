# frozen_string_literal: true

require_relative "../skill"

module Aidp
  module Skills
    module Wizard
      # Builds Skill objects from wizard responses
      #
      # Takes user input from the wizard and constructs a valid Skill object.
      # Handles template inheritance by merging metadata and content.
      #
      # @example Building a new skill
      #   builder = Builder.new
      #   responses = { id: "my_skill", name: "My Skill", ... }
      #   skill = builder.build(responses)
      #
      # @example Building from a template
      #   builder = Builder.new(base_skill: template)
      #   responses = { id: "my_skill", ... }
      #   skill = builder.build(responses)  # Inherits from template
      class Builder
        attr_reader :base_skill

        # Initialize builder
        #
        # @param base_skill [Skill, nil] Optional base skill for inheritance
        def initialize(base_skill: nil)
          @base_skill = base_skill
        end

        # Build a Skill from wizard responses
        #
        # @param responses [Hash] Wizard responses
        # @option responses [String] :id Skill ID
        # @option responses [String] :name Skill name
        # @option responses [String] :description Description
        # @option responses [String] :version Version (default: "1.0.0")
        # @option responses [Array<String>] :expertise Expertise areas
        # @option responses [Array<String>] :keywords Keywords
        # @option responses [Array<String>] :when_to_use When to use
        # @option responses [Array<String>] :when_not_to_use When not to use
        # @option responses [Array<String>] :compatible_providers Compatible providers
        # @option responses [String] :content Markdown content
        # @return [Skill] Built skill
        def build(responses)
          # Merge with base skill if provided
          merged = if base_skill
            merge_with_base(responses)
          else
            responses
          end

          # Create skill with merged attributes
          # Note: source_path will be set by Writer when saved
          Skill.new(
            id: merged[:id],
            name: merged[:name],
            description: merged[:description],
            version: merged[:version] || "1.0.0",
            expertise: Array(merged[:expertise]),
            keywords: Array(merged[:keywords]),
            when_to_use: Array(merged[:when_to_use]),
            when_not_to_use: Array(merged[:when_not_to_use]),
            compatible_providers: Array(merged[:compatible_providers]),
            content: merged[:content],
            source_path: merged[:source_path] || "<pending>"
          )
        end

        # Generate YAML frontmatter + content for writing
        #
        # @param skill [Skill] Skill to serialize
        # @return [String] Complete SKILL.md content
        def to_skill_md(skill)
          frontmatter = build_frontmatter(skill)
          "#{frontmatter}\n#{skill.content}"
        end

        private

        # Merge responses with base skill
        #
        # @param responses [Hash] User responses
        # @return [Hash] Merged attributes
        def merge_with_base(responses)
          {
            id: responses[:id],
            name: responses[:name] || base_skill.name,
            description: responses[:description] || base_skill.description,
            version: responses[:version] || "1.0.0",
            expertise: merge_arrays(base_skill.expertise, responses[:expertise]),
            keywords: merge_arrays(base_skill.keywords, responses[:keywords]),
            when_to_use: merge_arrays(base_skill.when_to_use, responses[:when_to_use]),
            when_not_to_use: merge_arrays(base_skill.when_not_to_use, responses[:when_not_to_use]),
            compatible_providers: responses[:compatible_providers] || base_skill.compatible_providers,
            content: responses[:content] || base_skill.content,
            source_path: responses[:source_path]
          }
        end

        # Merge arrays (base + new, deduplicated)
        #
        # @param base [Array] Base array
        # @param new_items [Array, nil] New items
        # @return [Array] Merged and deduplicated array
        def merge_arrays(base, new_items)
          return base if new_items.nil? || new_items.empty?
          (base + Array(new_items)).uniq
        end

        # Build YAML frontmatter
        #
        # @param skill [Skill] Skill object
        # @return [String] YAML frontmatter block
        def build_frontmatter(skill)
          data = {
            "id" => skill.id,
            "name" => skill.name,
            "description" => skill.description,
            "version" => skill.version
          }

          # Add optional arrays if not empty
          data["expertise"] = skill.expertise unless skill.expertise.empty?
          data["keywords"] = skill.keywords unless skill.keywords.empty?
          data["when_to_use"] = skill.when_to_use unless skill.when_to_use.empty?
          data["when_not_to_use"] = skill.when_not_to_use unless skill.when_not_to_use.empty?
          data["compatible_providers"] = skill.compatible_providers unless skill.compatible_providers.empty?

          # Generate YAML
          yaml_content = data.to_yaml
          # Remove the leading "---\n" that to_yaml adds, we'll add our own delimiters
          yaml_content = yaml_content.sub(/\A---\n/, "")

          "---\n#{yaml_content}---"
        end
      end
    end
  end
end
