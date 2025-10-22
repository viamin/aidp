# frozen_string_literal: true

require_relative "template_library"
require_relative "prompter"
require_relative "builder"
require_relative "writer"

module Aidp
  module Skills
    module Wizard
      # Controller orchestrating the skill creation wizard
      #
      # Coordinates the wizard flow: template selection, prompting, building,
      # preview, and writing the skill.
      #
      # @example Creating a new skill
      #   controller = Controller.new(project_dir: "/path/to/project")
      #   controller.run
      #
      # @example With options
      #   controller = Controller.new(
      #     project_dir: "/path/to/project",
      #     options: { id: "my_skill", dry_run: true }
      #   )
      #   controller.run
      class Controller
        attr_reader :project_dir, :options, :template_library, :prompter, :writer

        # Initialize controller
        #
        # @param project_dir [String] Root directory of the project
        # @param options [Hash] Wizard options
        # @option options [String] :id Pre-filled skill ID
        # @option options [String] :name Pre-filled skill name
        # @option options [Boolean] :dry_run Don't write files
        # @option options [Boolean] :minimal Skip optional sections
        # @option options [Boolean] :open_editor Open in $EDITOR (future)
        def initialize(project_dir:, options: {})
          @project_dir = project_dir
          @options = options
          @template_library = TemplateLibrary.new(project_dir: project_dir)
          @prompter = Prompter.new
          @writer = Writer.new(project_dir: project_dir)
        end

        # Run the wizard
        #
        # @return [String, nil] Path to created skill file, or nil if cancelled/dry-run
        def run
          Aidp.log_info("wizard", "Starting skill creation wizard", options: options)

          # Gather user responses
          responses = prompter.gather_responses(template_library, options: options)

          # Build skill from responses
          base_skill = responses.delete(:base_skill)
          builder = Builder.new(base_skill: base_skill)
          skill = builder.build(responses)

          # Generate SKILL.md content
          skill_md_content = builder.to_skill_md(skill)

          # Preview
          show_preview(skill, skill_md_content) unless options[:minimal]

          # Confirm
          unless options[:dry_run] || options[:yes] || confirm_save(skill)
            prompter.prompt.warn("Cancelled")
            return nil
          end

          # Write to disk
          path = writer.write(
            skill,
            content: skill_md_content,
            dry_run: options[:dry_run],
            backup: true
          )

          # Show success message
          show_success(skill, path) unless options[:dry_run]

          path
        rescue Interrupt
          prompter.prompt.warn("\nWizard cancelled")
          nil
        rescue => e
          Aidp.log_error("wizard", "Wizard failed", error: e.message, backtrace: e.backtrace.first(5))
          prompter.prompt.error("Error: #{e.message}")
          nil
        end

        private

        # Show preview of the skill
        #
        # @param skill [Skill] Built skill
        # @param content [String] SKILL.md content
        def show_preview(skill, content)
          prompter.prompt.say("\n" + "=" * 60)
          prompter.prompt.say("Skill Preview: #{skill.id} v#{skill.version}")
          prompter.prompt.say("=" * 60 + "\n")

          # Show first 20 lines of content
          lines = content.lines
          preview_lines = lines.first(20)
          prompter.prompt.say(preview_lines.join)

          if lines.size > 20
            prompter.prompt.say("\n... (#{lines.size - 20} more lines)")
          end

          prompter.prompt.say("\n" + "=" * 60 + "\n")
        end

        # Confirm before saving
        #
        # @param skill [Skill] Skill to save
        # @return [Boolean] True if user confirms
        def confirm_save(skill)
          if writer.exists?(skill.id)
            prompter.prompt.warn("Warning: Skill '#{skill.id}' already exists and will be overwritten (backup will be created)")
          end

          prompter.prompt.yes?("Save this skill?")
        end

        # Show success message
        #
        # @param skill [Skill] Created skill
        # @param path [String] Path to file
        def show_success(skill, path)
          prompter.prompt.say("\n✅ Skill created successfully!\n")
          prompter.prompt.say("   ID:      #{skill.id}")
          prompter.prompt.say("   Version: #{skill.version}")
          prompter.prompt.say("   File:    #{path}")
          prompter.prompt.say("\nNext steps:")
          prompter.prompt.say("  • Review: aidp skill preview #{skill.id}")
          prompter.prompt.say("  • Edit:   aidp skill edit #{skill.id}")
          prompter.prompt.say("  • Use:    Reference in your workflow steps\n")
        end
      end
    end
  end
end
