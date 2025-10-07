# frozen_string_literal: true

require "fileutils"

module Aidp
  module Execute
    # Manages the PROMPT.md file lifecycle for work loops
    # Responsibilities:
    # - Read/write PROMPT.md
    # - Check existence
    # - Archive completed prompts
    class PromptManager
      PROMPT_FILENAME = "PROMPT.md"
      ARCHIVE_DIR = ".aidp/prompt_archive"

      def initialize(project_dir)
        @project_dir = project_dir
        @prompt_path = File.join(project_dir, PROMPT_FILENAME)
        @archive_dir = File.join(project_dir, ARCHIVE_DIR)
      end

      # Write content to PROMPT.md
      def write(content)
        File.write(@prompt_path, content)
      end

      # Read content from PROMPT.md
      def read
        return nil unless exists?
        File.read(@prompt_path)
      end

      # Check if PROMPT.md exists
      def exists?
        File.exist?(@prompt_path)
      end

      # Archive PROMPT.md with timestamp and step name
      def archive(step_name)
        return unless exists?

        FileUtils.mkdir_p(@archive_dir)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        archive_filename = "#{timestamp}_#{step_name}_PROMPT.md"
        archive_path = File.join(@archive_dir, archive_filename)

        FileUtils.cp(@prompt_path, archive_path)
        archive_path
      end

      # Delete PROMPT.md (typically after archiving)
      def delete
        File.delete(@prompt_path) if exists?
      end

      # Get the full path to PROMPT.md
      def path
        @prompt_path
      end
    end
  end
end
