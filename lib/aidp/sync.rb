# frozen_string_literal: true

require 'fileutils'

module Aidp
  class Sync
    def self.to_project(paths, project_dir = Dir.pwd, from_dir = project_dir)
      paths.each do |rel|
        src = File.join(from_dir, rel)
        dst = File.join(project_dir, rel)
        next unless File.exist?(src)

        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst)
      end
    end
  end
end
