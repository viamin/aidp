# frozen_string_literal: true

require_relative "../loader"

module Aidp
  module Skills
    module Wizard
      # Manages skill templates for the wizard
      #
      # Loads and provides access to template skills from the gem's templates/skills/ directory
      # and existing project skills from .aidp/skills/ for cloning.
      #
      # @example Loading templates
      #   library = TemplateLibrary.new(project_dir: "/path/to/project")
      #   templates = library.templates
      #   template = library.find("base_developer")
      class TemplateLibrary
        attr_reader :project_dir

        # Initialize template library
        #
        # @param project_dir [String] Root directory of the project
        def initialize(project_dir:)
          @project_dir = project_dir
          @templates = nil
          @project_skills = nil
        end

        # Get all available templates
        #
        # @return [Array<Skill>] Array of template skills
        def templates
          load_templates unless loaded?
          @templates
        end

        # Get all project skills (for cloning)
        #
        # @return [Array<Skill>] Array of project-specific skills
        def project_skills
          load_project_skills unless project_skills_loaded?
          @project_skills
        end

        # Get all skills (templates + project skills)
        #
        # @return [Array<Skill>] Combined array of all skills
        def all
          templates + project_skills
        end

        # Find a template or project skill by ID
        #
        # @param skill_id [String] Skill identifier
        # @return [Skill, nil] Found skill or nil
        def find(skill_id)
          all.find { |skill| skill.id == skill_id.to_s }
        end

        # Check if a skill ID exists
        #
        # @param skill_id [String] Skill identifier
        # @return [Boolean] True if skill exists
        def exists?(skill_id)
          !find(skill_id).nil?
        end

        # Get template names for display
        #
        # @return [Array<Hash>] Array of {id, name, description} hashes
        def template_list
          templates.map do |skill|
            {
              id: skill.id,
              name: skill.name,
              description: skill.description,
              source: :template
            }
          end
        end

        # Get project skill names for display
        #
        # @return [Array<Hash>] Array of {id, name, description} hashes
        def project_skill_list
          project_skills.map do |skill|
            {
              id: skill.id,
              name: skill.name,
              description: skill.description,
              source: :project
            }
          end
        end

        # Get combined list for selection
        #
        # @return [Array<Hash>] Array of {id, name, description, source} hashes
        def skill_list
          template_list + project_skill_list
        end

        private

        # Load templates from gem directory
        def load_templates
          @templates = Loader.load_from_directory(templates_path)
          Aidp.log_debug(
            "wizard",
            "Loaded templates",
            count: @templates.size,
            path: templates_path
          )
        end

        # Load project skills
        def load_project_skills
          @project_skills = if Dir.exist?(project_skills_path)
            Loader.load_from_directory(project_skills_path)
          else
            []
          end

          Aidp.log_debug(
            "wizard",
            "Loaded project skills",
            count: @project_skills.size,
            path: project_skills_path
          )
        end

        # Check if templates are loaded
        #
        # @return [Boolean] True if loaded
        def loaded?
          !@templates.nil?
        end

        # Check if project skills are loaded
        #
        # @return [Boolean] True if loaded
        def project_skills_loaded?
          !@project_skills.nil?
        end

        # Get path to templates directory
        #
        # @return [String] Path to templates/skills directory
        def templates_path
          # Get the gem root directory (go up 4 levels from lib/aidp/skills/wizard/template_library.rb)
          gem_root = File.expand_path("../../../..", __dir__)
          File.join(gem_root, "templates", "skills")
        end

        # Get path to project skills directory
        #
        # @return [String] Path to .aidp/skills directory
        def project_skills_path
          File.join(project_dir, ".aidp", "skills")
        end
      end
    end
  end
end
