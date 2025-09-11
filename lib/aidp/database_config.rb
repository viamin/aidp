# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "output_helper"

module Aidp
  class DatabaseConfig
    extend Aidp::OutputHelper
    DEFAULT_CONFIG = {
      "database" => {
        "adapter" => "postgresql",
        "host" => "localhost",
        "port" => 5432,
        "database" => "aidp",
        "username" => ENV["USER"],
        "password" => nil,
        "pool" => 5,
        "timeout" => 5000
      }
    }.freeze

    def self.load(project_dir = Dir.pwd)
      new(project_dir).load
    end

    def initialize(project_dir)
      @project_dir = project_dir
      @config_file = File.join(project_dir, ".aidp-config.yml")
    end

    def load
      ensure_config_exists
      config = YAML.load_file(@config_file)
      validate_config(config)
      config["database"]
    end

    private

    def ensure_config_exists
      return if File.exist?(@config_file)

      # Create config directory if it doesn't exist
      FileUtils.mkdir_p(File.dirname(@config_file))

      # Write default config
      File.write(@config_file, YAML.dump(DEFAULT_CONFIG))

      puts "Created default database configuration at #{@config_file}"
      puts "Please update the configuration with your database settings"
    end

    def validate_config(config)
      unless config.is_a?(Hash) && config["database"].is_a?(Hash)
        raise "Invalid configuration format in #{@config_file}"
      end

      required_keys = %w[adapter host port database username]
      missing_keys = required_keys - config["database"].keys

      unless missing_keys.empty?
        raise "Missing required configuration keys: #{missing_keys.join(", ")}"
      end

      unless config["database"]["adapter"] == "postgresql"
        raise "Only PostgreSQL is supported as a database adapter"
      end
    end
  end
end
