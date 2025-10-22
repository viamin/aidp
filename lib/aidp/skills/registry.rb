# frozen_string_literal: true

module Aidp
  module Skills
    # Registry for managing available skills
    #
    # The Registry loads skills from multiple search paths and provides
    # lookup, filtering, and management capabilities.
    #
    # Skills are loaded from:
    # 1. Template skills directory (gem templates/skills/) - built-in templates
    # 2. Project skills directory (.aidp/skills/) - project-specific skills
    #
    # Project skills with matching IDs override template skills.
    #
    # @example Basic usage
    #   registry = Registry.new(project_dir: "/path/to/project")
    #   registry.load_skills
    #   skill = registry.find("repository_analyst")
    #
    # @example With provider filtering
    #   registry = Registry.new(project_dir: "/path/to/project", provider: "anthropic")
    #   registry.load_skills
    #   skills = registry.all # Only anthropic-compatible skills
    class Registry
      attr_reader :project_dir, :provider

      # Initialize a new skills registry
      #
      # @param project_dir [String] Root directory of the project
      # @param provider [String, nil] Optional provider name for filtering
      def initialize(project_dir:, provider: nil)
        @project_dir = project_dir
        @provider = provider
        @skills = {}
        @loaded = false
      end

      # Load skills from all search paths
      #
      # Skills are loaded in order:
      # 1. Template skills (gem templates/skills/) - built-in templates
      # 2. Project skills (.aidp/skills/) - override templates
      #
      # @return [Integer] Number of skills loaded
      def load_skills
        Aidp.log_debug("skills", "Loading skills", project_dir: project_dir, provider: provider)

        @skills = {}

        # Load template skills first
        template_skills = load_from_path(template_skills_path)
        template_skills.each { |skill| register_skill(skill, source: :template) }

        # Load project skills (override templates if IDs match)
        project_skills = load_from_path(project_skills_path)
        project_skills.each { |skill| register_skill(skill, source: :project) }

        @loaded = true

        Aidp.log_info("skills", "Loaded skills", count: @skills.size, provider: provider)
        @skills.size
      end

      # Find a skill by ID
      #
      # @param skill_id [String] Skill identifier
      # @return [Skill, nil] Skill if found, nil otherwise
      def find(skill_id)
        load_skills unless loaded?
        @skills[skill_id.to_s]
      end

      # Get all registered skills
      #
      # @return [Array<Skill>] Array of all skills
      def all
        load_skills unless loaded?
        @skills.values
      end

      # Get skills matching a search query
      #
      # @param query [String] Search query (searches id, name, description, keywords, expertise)
      # @return [Array<Skill>] Matching skills
      def search(query)
        load_skills unless loaded?
        all.select { |skill| skill.matches?(query) }
      end

      # Get skills by keyword
      #
      # @param keyword [String] Keyword to match
      # @return [Array<Skill>] Skills with matching keyword
      def by_keyword(keyword)
        load_skills unless loaded?
        all.select { |skill| skill.keywords.include?(keyword) }
      end

      # Get skills compatible with a specific provider
      #
      # @param provider_name [String] Provider name
      # @return [Array<Skill>] Compatible skills
      def compatible_with(provider_name)
        load_skills unless loaded?
        all.select { |skill| skill.compatible_with?(provider_name) }
      end

      # Check if a skill exists
      #
      # @param skill_id [String] Skill identifier
      # @return [Boolean] True if skill exists
      def exists?(skill_id)
        find(skill_id) != nil
      end

      # Check if skills have been loaded
      #
      # @return [Boolean] True if loaded
      def loaded?
        @loaded
      end

      # Get count of registered skills
      #
      # @return [Integer] Number of skills
      def count
        load_skills unless loaded?
        @skills.size
      end

      # Reload skills from disk
      #
      # @return [Integer] Number of skills loaded
      def reload
        @loaded = false
        load_skills
      end

      # Get skill IDs grouped by source
      #
      # @return [Hash] Hash with :template and :project arrays
      def by_source
        load_skills unless loaded?

        {
          template: @skills.values.select { |s| template_skill?(s) }.map(&:id),
          project: @skills.values.select { |s| project_skill?(s) }.map(&:id)
        }
      end

      private

      # Register a skill in the registry
      #
      # @param skill [Skill] Skill to register
      # @param source [Symbol] Source type (:builtin or :custom)
      def register_skill(skill, source:)
        if @skills.key?(skill.id)
          Aidp.log_debug(
            "skills",
            "Overriding skill",
            skill_id: skill.id,
            old_source: @skills[skill.id].source_path,
            new_source: skill.source_path
          )
        end

        @skills[skill.id] = skill

        Aidp.log_debug(
          "skills",
          "Registered skill",
          skill_id: skill.id,
          source: source,
          version: skill.version
        )
      end

      # Load skills from a directory path
      #
      # @param path [String] Directory path
      # @return [Array<Skill>] Loaded skills
      def load_from_path(path)
        return [] unless Dir.exist?(path)
        Loader.load_from_directory(path, provider: provider)
      end

      # Get template skills path (from gem)
      #
      # @return [String] Path to template skills directory
      def template_skills_path
        # Get the gem root directory (go up from lib/aidp/skills/registry.rb)
        gem_root = File.expand_path("../../../..", __FILE__)
        File.join(gem_root, "templates", "skills")
      end

      # Get project skills path
      #
      # @return [String] Path to project-specific skills directory
      def project_skills_path
        File.join(project_dir, ".aidp", "skills")
      end

      # Check if skill is from template directory
      #
      # @param skill [Skill] Skill to check
      # @return [Boolean] True if template
      def template_skill?(skill)
        skill.source_path.start_with?(template_skills_path)
      end

      # Check if skill is from project directory
      #
      # @param skill [Skill] Skill to check
      # @return [Boolean] True if project
      def project_skill?(skill)
        skill.source_path.start_with?(project_skills_path)
      end
    end
  end
end
