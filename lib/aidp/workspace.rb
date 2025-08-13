# frozen_string_literal: true

require 'fileutils'
require 'digest'

module Aidp
  class Workspace
    def self.for(project_dir = Dir.pwd)
      h = Digest::SHA256.hexdigest(File.expand_path(project_dir))[0, 12]
      File.expand_path(File.join('~/.aidp/workspaces', h))
    end

    def self.prepare(project_dir = Dir.pwd)
      ws = self.for(project_dir)
      FileUtils.mkdir_p(ws)
      ws
    end
  end
end
