# frozen_string_literal: true

module Aidp
  # Skills subsystem for managing agent personas and capabilities
  #
  # Skills define WHO the agent is (persona) and WHAT capabilities they have.
  # This is separate from templates/procedures which define WHEN and HOW
  # to execute specific tasks.
  #
  # @example Loading and using skills
  #   registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
  #   registry.load_skills
  #
  #   skill = registry.find("repository_analyst")
  #   composer = Aidp::Skills::Composer.new
  #   prompt = composer.compose(skill: skill, template: "Analyze the repo...")
  #
  # @example Creating a custom skill
  #   # Create .aidp/skills/my_skill/SKILL.md with YAML frontmatter
  #   # It will automatically override built-in skills with matching ID
  module Skills
    # Error raised when a skill is not found
    class SkillNotFoundError < StandardError; end
  end
end
