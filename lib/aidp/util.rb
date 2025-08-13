# frozen_string_literal: true

require 'fileutils'

module Aidp
  module Util
    module_function

    def which(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable?(exe) && !File.directory?(exe)
        end
      end
      nil
    end

    def macos?
      (/darwin/ =~ RUBY_PLATFORM) != nil
    end

    def ensure_dirs(paths, root = Dir.pwd)
      paths.each do |p|
        dir = File.dirname(File.join(root, p))
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end
    end
  end
end
