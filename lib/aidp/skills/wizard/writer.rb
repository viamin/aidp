# frozen_string_literal: true

require "fileutils"

module Aidp
  module Skills
    module Wizard
      # Writes skills to the filesystem
      #
      # Handles creating directories, writing SKILL.md files, and creating backups.
      #
      # @example Writing a new skill
      #   writer = Writer.new(project_dir: "/path/to/project")
      #   writer.write(skill, content: "...", dry_run: false)
      #
      # @example Dry-run mode
      #   writer.write(skill, content: "...", dry_run: true)  # Returns path without writing
      class Writer
        attr_reader :project_dir

        # Initialize writer
        #
        # @param project_dir [String] Root directory of the project
        def initialize(project_dir:)
          @project_dir = project_dir
        end

        # Write a skill to disk
        #
        # @param skill [Skill] Skill object
        # @param content [String] Complete SKILL.md content
        # @param dry_run [Boolean] If true, don't actually write
        # @param backup [Boolean] If true, create backup of existing file
        # @return [String] Path to written file
        def write(skill, content:, dry_run: false, backup: true)
          skill_path = path_for_skill(skill.id)
          skill_dir = File.dirname(skill_path)

          if dry_run
            Aidp.log_debug("wizard", "Dry-run mode, would write to", path: skill_path)
            return skill_path
          end

          # Create backup if file exists and backup is requested
          create_backup(skill_path) if backup && File.exist?(skill_path)

          # Create directory if it doesn't exist
          FileUtils.mkdir_p(skill_dir) unless Dir.exist?(skill_dir)

          # Write file
          File.write(skill_path, content)

          Aidp.log_info(
            "wizard",
            "Wrote skill",
            skill_id: skill.id,
            path: skill_path,
            size: content.bytesize
          )

          skill_path
        end

        # Get the path where a skill would be written
        #
        # @param skill_id [String] Skill identifier
        # @return [String] Full path to SKILL.md file
        def path_for_skill(skill_id)
          File.join(project_dir, ".aidp", "skills", skill_id, "SKILL.md")
        end

        # Check if a skill already exists
        #
        # @param skill_id [String] Skill identifier
        # @return [Boolean] True if skill file exists
        def exists?(skill_id)
          File.exist?(path_for_skill(skill_id))
        end

        private

        # Create a backup of an existing file
        #
        # @param file_path [String] Path to file to backup
        def create_backup(file_path)
          backup_path = "#{file_path}.backup"
          timestamp_backup_path = "#{file_path}.#{Time.now.strftime("%Y%m%d_%H%M%S")}.backup"

          # Create timestamped backup
          FileUtils.cp(file_path, timestamp_backup_path)

          # Also create/update .backup for convenience
          FileUtils.cp(file_path, backup_path)

          Aidp.log_debug(
            "wizard",
            "Created backup",
            original: file_path,
            backup: timestamp_backup_path
          )
        end
      end
    end
  end
end
