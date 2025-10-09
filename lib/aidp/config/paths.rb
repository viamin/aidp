# frozen_string_literal: true

require "fileutils"

module Aidp
  # Centralized path management for all AIDP internal files
  # Ensures consistent file locations and prevents path-related bugs
  module ConfigPaths
    # Get the main AIDP directory for a project
    def self.aidp_dir(project_dir = Dir.pwd)
      File.join(project_dir, ".aidp")
    end

    # Get the main configuration file path
    def self.config_file(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "aidp.yml")
    end

    # Get the configuration directory path
    def self.config_dir(project_dir = Dir.pwd)
      aidp_dir(project_dir)
    end

    # Get the progress directory path
    def self.progress_dir(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "progress")
    end

    # Get the execute progress file path
    def self.execute_progress_file(project_dir = Dir.pwd)
      File.join(progress_dir(project_dir), "execute.yml")
    end

    # Get the analyze progress file path
    def self.analyze_progress_file(project_dir = Dir.pwd)
      File.join(progress_dir(project_dir), "analyze.yml")
    end

    # Get the harness state directory path
    def self.harness_state_dir(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "harness")
    end

    # Get the harness state file path for a specific mode
    def self.harness_state_file(mode, project_dir = Dir.pwd)
      File.join(harness_state_dir(project_dir), "#{mode}_state.json")
    end

    # Get the providers directory path
    def self.providers_dir(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "providers")
    end

    # Get the provider info file path
    def self.provider_info_file(provider_name, project_dir = Dir.pwd)
      File.join(providers_dir(project_dir), "#{provider_name}_info.yml")
    end

    # Get the jobs directory path
    def self.jobs_dir(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "jobs")
    end

    # Get the checkpoint file path
    def self.checkpoint_file(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "checkpoint.yml")
    end

    # Get the checkpoint history file path
    def self.checkpoint_history_file(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "checkpoint_history.jsonl")
    end

    # Get the JSON storage directory path
    def self.json_storage_dir(project_dir = Dir.pwd)
      File.join(aidp_dir(project_dir), "json")
    end

    # Check if the main configuration file exists
    def self.config_exists?(project_dir = Dir.pwd)
      File.exist?(config_file(project_dir))
    end

    # Ensure the main AIDP directory exists
    def self.ensure_aidp_dir(project_dir = Dir.pwd)
      dir = aidp_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Ensure the configuration directory exists
    def self.ensure_config_dir(project_dir = Dir.pwd)
      ensure_aidp_dir(project_dir)
    end

    # Ensure the progress directory exists
    def self.ensure_progress_dir(project_dir = Dir.pwd)
      dir = progress_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Ensure the harness state directory exists
    def self.ensure_harness_state_dir(project_dir = Dir.pwd)
      dir = harness_state_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Ensure the providers directory exists
    def self.ensure_providers_dir(project_dir = Dir.pwd)
      dir = providers_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Ensure the jobs directory exists
    def self.ensure_jobs_dir(project_dir = Dir.pwd)
      dir = jobs_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Ensure the JSON storage directory exists
    def self.ensure_json_storage_dir(project_dir = Dir.pwd)
      dir = json_storage_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end
  end
end
