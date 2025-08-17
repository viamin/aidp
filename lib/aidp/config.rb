# frozen_string_literal: true

require "yaml"

module Aidp
  # Configuration management for both execute and analyze modes
  class Config
    def self.load(project_dir = Dir.pwd)
      config_file = File.join(project_dir, ".aidp.yml")
      if File.exist?(config_file)
        YAML.load_file(config_file) || {}
      else
        {}
      end
    end

    def self.templates_root
      File.join(Dir.pwd, "templates")
    end

    def self.analyze_templates_root
      File.join(Dir.pwd, "templates", "ANALYZE")
    end

    def self.execute_templates_root
      File.join(Dir.pwd, "templates", "EXECUTE")
    end

    def self.common_templates_root
      File.join(Dir.pwd, "templates", "COMMON")
    end
  end
end
