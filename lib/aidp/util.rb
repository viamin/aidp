# frozen_string_literal: true

require "fileutils"

module Aidp
  # Utility functions shared between execute and analyze modes
  class Util
    def self.which(cmd)
      exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable?(exe) && !File.directory?(exe)
        end
      end
      nil
    end

    def self.ensure_dirs(output_files, project_dir)
      output_files.each do |file|
        dir = File.dirname(File.join(project_dir, file))
        FileUtils.mkdir_p(dir) unless dir == "."
      end
    end

    def self.safe_file_write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def self.project_root?(dir = Dir.pwd)
      File.exist?(File.join(dir, ".git")) ||
        File.exist?(File.join(dir, "package.json")) ||
        File.exist?(File.join(dir, "Gemfile")) ||
        File.exist?(File.join(dir, "pom.xml")) ||
        File.exist?(File.join(dir, "build.gradle"))
    end
  end
end
