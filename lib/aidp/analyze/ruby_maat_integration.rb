# frozen_string_literal: true

module Aidp
  module Analyze
    class RubyMaatIntegration
      def initialize
        # TODO: Initialize RubyMaat integration
      end

      def check_prerequisites
        {
          git_repository: git_repository_available?,
          git_log_available: git_log_available?
        }
      end

      private

      def git_repository_available?
        Dir.exist?(".git") || system("git rev-parse --git-dir", out: File::NULL, err: File::NULL)
      end

      def git_log_available?
        return false unless git_repository_available?
        
        system("git log --oneline -1", out: File::NULL, err: File::NULL)
      end
    end
  end
end
