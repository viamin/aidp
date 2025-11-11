# frozen_string_literal: true

require_relative "auto_update/errors"
require_relative "auto_update/update_policy"
require_relative "auto_update/update_check"
require_relative "auto_update/checkpoint"
require_relative "auto_update/bundler_adapter"
require_relative "auto_update/rubygems_api_adapter"
require_relative "auto_update/version_detector"
require_relative "auto_update/checkpoint_store"
require_relative "auto_update/update_logger"
require_relative "auto_update/failure_tracker"
require_relative "auto_update/coordinator"

module Aidp
  # Auto-update functionality for Aidp in devcontainers
  module AutoUpdate
    # Exit code used to signal supervisor to perform update
    UPDATE_EXIT_CODE = 75

    # Create coordinator from project configuration
    # @param project_dir [String] Project root directory
    # @return [Coordinator]
    def self.coordinator(project_dir: Dir.pwd)
      config = Aidp::Config.load_harness_config(project_dir)
      auto_update_config = config[:auto_update] || config["auto_update"] || {}

      Coordinator.from_config(auto_update_config, project_dir: project_dir)
    end

    # Check if auto-update is enabled in configuration
    # @param project_dir [String] Project root directory
    # @return [Boolean]
    def self.enabled?(project_dir: Dir.pwd)
      config = Aidp::Config.load_harness_config(project_dir)
      auto_update_config = config[:auto_update] || config["auto_update"] || {}

      policy = UpdatePolicy.from_config(auto_update_config)
      !policy.disabled?
    end

    # Get auto-update policy from configuration
    # @param project_dir [String] Project root directory
    # @return [UpdatePolicy]
    def self.policy(project_dir: Dir.pwd)
      config = Aidp::Config.load_harness_config(project_dir)
      auto_update_config = config[:auto_update] || config["auto_update"] || {}

      UpdatePolicy.from_config(auto_update_config)
    end
  end
end
