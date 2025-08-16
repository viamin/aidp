# frozen_string_literal: true

require "fileutils"
require "digest"

module Aidp
  module Shared
    # Workspace management utilities
    class Workspace
      def self.current
        Dir.pwd
      end

      def self.ensure_project_root
        unless Aidp::Shared::Util.project_root?
          raise "Not in a project root directory. Please run from a directory with .git, package.json, Gemfile, etc."
        end
      end
    end
  end
end
