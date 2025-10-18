# frozen_string_literal: true

module Aidp
  module Skills
    # Composes skills with templates to create complete prompts
    #
    # The Composer combines skill content (WHO the agent is and WHAT capabilities
    # they have) with template content (WHEN/HOW to execute a specific task).
    #
    # Composition structure:
    #   1. Skill content (persona, expertise, philosophy)
    #   2. Separator
    #   3. Template content (task-specific instructions)
    #
    # @example Basic composition
    #   composer = Composer.new
    #   prompt = composer.compose(
    #     skill: repository_analyst_skill,
    #     template: "Analyze the repository..."
    #   )
    #
    # @example Template-only (no skill)
    #   prompt = composer.compose(template: "Do this task...")
    class Composer
      # Separator between skill and template content
      SKILL_TEMPLATE_SEPARATOR = "\n\n---\n\n"

      # Compose a skill and template into a complete prompt
      #
      # @param skill [Skill, nil] Skill to include (optional)
      # @param template [String] Template content
      # @param options [Hash] Optional parameters for template variable replacement
      # @return [String] Composed prompt
      def compose(template:, skill: nil, options: {})
        Aidp.log_debug(
          "skills",
          "Composing prompt",
          skill_id: skill&.id,
          template_length: template.length,
          options_count: options.size
        )

        # Replace template variables
        rendered_template = render_template(template, options: options)

        # If no skill, return template only
        unless skill
          Aidp.log_debug("skills", "Template-only composition", template_length: rendered_template.length)
          return rendered_template
        end

        # Compose skill + template
        composed = [
          skill.content,
          SKILL_TEMPLATE_SEPARATOR,
          "# Current Task",
          "",
          rendered_template
        ].join("\n")

        Aidp.log_debug(
          "skills",
          "Composed prompt with skill",
          skill_id: skill.id,
          total_length: composed.length,
          skill_length: skill.content.length,
          template_length: rendered_template.length
        )

        composed
      end

      # Render a template with variable substitution
      #
      # Replaces {{variable}} placeholders with values from options hash
      #
      # @param template [String] Template content
      # @param options [Hash] Variable values for substitution
      # @return [String] Rendered template
      def render_template(template, options: {})
        return template if options.empty?

        rendered = template.dup

        options.each do |key, value|
          placeholder = "{{#{key}}}"
          rendered = rendered.gsub(placeholder, value.to_s)
        end

        # Log if there are unreplaced placeholders
        remaining_placeholders = rendered.scan(/\{\{([^}]+)\}\}/).flatten
        if remaining_placeholders.any?
          Aidp.log_warn(
            "skills",
            "Unreplaced template variables",
            placeholders: remaining_placeholders
          )
        end

        rendered
      end

      # Compose multiple skills with a template
      #
      # Note: This is for future use when skill composition is supported.
      # Currently raises an error as it's not implemented in v1.
      #
      # @param skills [Array<Skill>] Skills to compose
      # @param template [String] Template content
      # @param options [Hash] Template variables
      # @return [String] Composed prompt
      # @raise [NotImplementedError] Skill composition not yet supported
      def compose_multiple(skills:, template:, options: {})
        raise NotImplementedError, "Multiple skill composition not yet supported in v1"
      end

      # Preview what a composed prompt would look like
      #
      # Returns a hash with skill content, template content, and full composition
      # for inspection without executing.
      #
      # @param skill [Skill, nil] Skill to include
      # @param template [String] Template content
      # @param options [Hash] Template variables
      # @return [Hash] Preview with :skill, :template, :composed, :metadata
      def preview(template:, skill: nil, options: {})
        rendered_template = render_template(template, options: options)
        composed = compose(skill: skill, template: template, options: options)

        {
          skill: skill ? {
            id: skill.id,
            name: skill.name,
            content: skill.content,
            length: skill.content.length
          } : nil,
          template: {
            content: rendered_template,
            length: rendered_template.length,
            variables: options.keys
          },
          composed: {
            content: composed,
            length: composed.length
          },
          metadata: {
            has_skill: !skill.nil?,
            separator_used: !skill.nil?,
            unreplaced_vars: composed.scan(/\{\{([^}]+)\}\}/).flatten
          }
        }
      end
    end
  end
end
