# frozen_string_literal: true

require "fileutils"

module Aidp
  # Centralized path management for all AIDP internal files
  # Ensures consistent file locations and prevents path-related bugs
  module ConfigPaths
    def self.aidp_dir(project_dir = Dir.pwd) = File.join(project_dir, ".aidp")
    def self.config_file(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "aidp.yml")
    def self.config_dir(project_dir = Dir.pwd) = aidp_dir(project_dir)
    def self.progress_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "progress")
    def self.execute_progress_file(project_dir = Dir.pwd) = File.join(progress_dir(project_dir), "execute.yml")
    def self.analyze_progress_file(project_dir = Dir.pwd) = File.join(progress_dir(project_dir), "analyze.yml")
    def self.harness_state_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "harness")
    def self.harness_state_file(mode, project_dir = Dir.pwd) = File.join(harness_state_dir(project_dir), "#{mode}_state.json")
    def self.providers_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "providers")
    def self.provider_info_file(provider_name, project_dir = Dir.pwd) = File.join(providers_dir(project_dir), "#{provider_name}_info.yml")
    def self.jobs_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "jobs")
    def self.checkpoint_file(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "checkpoint.yml")
    def self.checkpoint_history_file(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "checkpoint_history.jsonl")
    def self.json_storage_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "json")
    def self.model_cache_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "model_cache")
    def self.work_loop_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "work_loop")
    def self.logs_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "logs")
    def self.evaluations_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "evaluations")
    def self.evaluations_index_file(project_dir = Dir.pwd) = File.join(evaluations_dir(project_dir), "index.json")

    # Security module paths
    def self.security_dir(project_dir = Dir.pwd) = File.join(aidp_dir(project_dir), "security")
    def self.secrets_registry_file(project_dir = Dir.pwd) = File.join(security_dir(project_dir), "secrets_registry.json")
    def self.security_audit_log_file(project_dir = Dir.pwd) = File.join(security_dir(project_dir), "audit.jsonl")
    def self.mcp_risk_profile_file(project_dir = Dir.pwd) = File.join(security_dir(project_dir), "mcp_risk_profile.yml")

    def self.config_exists?(project_dir = Dir.pwd)
      File.exist?(config_file(project_dir))
    end

    def self.ensure_aidp_dir(project_dir = Dir.pwd)
      dir = aidp_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_config_dir(project_dir = Dir.pwd)
      ensure_aidp_dir(project_dir)
    end

    def self.ensure_progress_dir(project_dir = Dir.pwd)
      dir = progress_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_harness_state_dir(project_dir = Dir.pwd)
      dir = harness_state_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_providers_dir(project_dir = Dir.pwd)
      dir = providers_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_jobs_dir(project_dir = Dir.pwd)
      dir = jobs_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_json_storage_dir(project_dir = Dir.pwd)
      dir = json_storage_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_evaluations_dir(project_dir = Dir.pwd)
      dir = evaluations_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.ensure_security_dir(project_dir = Dir.pwd)
      dir = security_dir(project_dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end
  end
end
