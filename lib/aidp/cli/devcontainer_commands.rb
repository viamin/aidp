# frozen_string_literal: true

require_relative "../setup/devcontainer/parser"
require_relative "../setup/devcontainer/generator"
require_relative "../setup/devcontainer/port_manager"
require_relative "../setup/devcontainer/backup_manager"
require_relative "../message_display"
require "json"
require "yaml"

module Aidp
  class CLI
    # Commands for managing devcontainer configuration
    class DevcontainerCommands
      COMPONENT = "devcontainer_commands"
      include Aidp::MessageDisplay

      def initialize(project_dir: Dir.pwd, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @prompt = prompt
        Aidp.log_debug(COMPONENT, "initialized", project_dir: project_dir)
      end

      # Show diff between current and proposed devcontainer configuration
      def diff(options = {})
        Aidp.log_debug(COMPONENT, "diff.start", options: options)
        parser = Aidp::Setup::Devcontainer::Parser.new(@project_dir)

        unless parser.devcontainer_exists?
          Aidp.log_debug(COMPONENT, "diff.no_devcontainer")
          display_message("No existing devcontainer.json found", type: :warning)
          display_message("Run 'aidp config --interactive' to create one", type: :muted)
          return false
        end

        devcontainer_path = parser.detect
        current_config = parser.parse

        # Load proposed config from aidp.yml or generate from config
        proposed_config = load_proposed_config(options)

        unless proposed_config
          Aidp.log_debug(COMPONENT, "diff.no_proposed_config")
          display_message("No proposed configuration found", type: :warning)
          display_message("Update your aidp.yml or use --generate", type: :muted)
          return false
        end

        display_diff(current_config, proposed_config, devcontainer_path)
        Aidp.log_debug(COMPONENT, "diff.complete", devcontainer_path: devcontainer_path)
        true
      end

      # Apply devcontainer configuration from aidp.yml
      def apply(options = {})
        dry_run = options[:dry_run] || false
        force = options[:force] || false
        create_backup = options[:backup] != false  # Default true
        Aidp.log_debug(COMPONENT, "apply.start",
          dry_run: dry_run,
          force: force,
          create_backup: create_backup)

        parser = Aidp::Setup::Devcontainer::Parser.new(@project_dir)
        existing_config = parser.devcontainer_exists? ? parser.parse : nil
        devcontainer_path = parser.detect || default_devcontainer_path

        # Load configuration
        proposed_config = load_proposed_config(options)

        unless proposed_config
          Aidp.log_debug(COMPONENT, "apply.no_configuration")
          display_message("❌ No configuration found in aidp.yml", type: :error)
          display_message("Run 'aidp config --interactive' first", type: :muted)
          return false
        end

        # Merge with existing if present
        generator = Aidp::Setup::Devcontainer::Generator.new(@project_dir)
        final_config = if existing_config
          generator.merge_with_existing(proposed_config, existing_config)
        else
          proposed_config
        end

        # Show preview
        if dry_run
          display_message("🔍 Dry Run - Changes Preview", type: :highlight)
          display_diff(existing_config || {}, final_config, devcontainer_path)
          display_message("\nNo changes made (dry run)", type: :muted)
          Aidp.log_debug(COMPONENT, "apply.dry_run_preview",
            has_existing: !existing_config.nil?,
            devcontainer_path: devcontainer_path)
          return true
        end

        # Confirm unless forced
        unless force
          display_diff(existing_config || {}, final_config, devcontainer_path)
          display_message("")

          unless @prompt.yes?("Apply these changes?")
            display_message("Cancelled", type: :warning)
            return false
          end
        end

        # Create backup if existing file
        if create_backup && File.exist?(devcontainer_path)
          backup_manager = Aidp::Setup::Devcontainer::BackupManager.new(@project_dir)
          backup_path = backup_manager.create_backup(devcontainer_path, {
            reason: "cli_apply",
            timestamp: Time.now.utc.iso8601
          })
          display_message("✅ Backup created: #{File.basename(backup_path)}", type: :success)
          Aidp.log_debug(COMPONENT, "apply.backup_created", backup_path: backup_path)
        end

        # Write devcontainer.json
        write_devcontainer(devcontainer_path, final_config)

        display_message("✅ Devcontainer configuration applied", type: :success)
        display_message("   #{devcontainer_path}", type: :muted)
        Aidp.log_debug(COMPONENT, "apply.completed",
          devcontainer_path: devcontainer_path,
          forward_ports: final_config["forwardPorts"]&.length)
        true
      end

      # List available backups
      def list_backups
        Aidp.log_debug(COMPONENT, "list_backups.start")
        backup_manager = Aidp::Setup::Devcontainer::BackupManager.new(@project_dir)
        backups = backup_manager.list_backups

        if backups.empty?
          display_message("No backups found", type: :muted)
          Aidp.log_debug(COMPONENT, "list_backups.none_found")
          return true
        end

        display_message("📦 Available Backups", type: :highlight)
        display_message("")

        backups.each_with_index do |backup, index|
          display_message("#{index + 1}. #{backup[:filename]}", type: :info)
          display_message("   Created: #{backup[:created_at].strftime("%Y-%m-%d %H:%M:%S")}", type: :muted)
          display_message("   Size: #{format_size(backup[:size])}", type: :muted)
          if backup[:metadata]
            display_message("   Reason: #{backup[:metadata]["reason"]}", type: :muted)
          end
          display_message("")
        end

        total_size = backup_manager.total_backup_size
        display_message("Total: #{backups.size} backups (#{format_size(total_size)})", type: :muted)
        Aidp.log_debug(COMPONENT, "list_backups.complete",
          count: backups.size,
          total_size: total_size)
        true
      end

      # Restore from a backup
      def restore(backup_index_or_path, options = {})
        Aidp.log_debug(COMPONENT, "restore.start",
          selector: backup_index_or_path,
          options: options)
        backup_manager = Aidp::Setup::Devcontainer::BackupManager.new(@project_dir)

        backup_path = if backup_index_or_path.to_i.positive?
          # Index-based selection
          backups = backup_manager.list_backups
          index = backup_index_or_path.to_i - 1

          unless backups[index]
            Aidp.log_debug(COMPONENT, "restore.invalid_index",
              selector: backup_index_or_path)
            display_message("❌ Invalid backup index: #{backup_index_or_path}", type: :error)
            return false
          end

          backups[index][:path]
        else
          # Direct path
          backup_index_or_path
        end
        Aidp.log_debug(COMPONENT, "restore.resolved_backup", backup_path: backup_path)

        unless File.exist?(backup_path)
          Aidp.log_debug(COMPONENT, "restore.missing_backup", backup_path: backup_path)
          display_message("❌ Backup not found: #{backup_path}", type: :error)
          return false
        end

        parser = Aidp::Setup::Devcontainer::Parser.new(@project_dir)
        target_path = parser.detect || default_devcontainer_path

        # Show what will be restored
        JSON.parse(File.read(backup_path))
        display_message("📦 Restoring Backup", type: :highlight)
        display_message("   From: #{File.basename(backup_path)}", type: :muted)
        display_message("   To: #{target_path}", type: :muted)
        display_message("")

        unless options[:force] || @prompt.yes?("Restore this backup?")
          Aidp.log_debug(COMPONENT, "restore.cancelled_by_user", target_path: target_path)
          display_message("Cancelled", type: :warning)
          return false
        end

        # Restore
        backup_manager.restore_backup(backup_path, target_path, create_backup: !options[:no_backup])
        Aidp.log_debug(COMPONENT, "restore.completed", target_path: target_path)

        display_message("✅ Backup restored successfully", type: :success)
        true
      end

      private

      def load_proposed_config(options)
        if options[:config_file]
          # Load from specific file
          config_file = options[:config_file]
          unless File.exist?(config_file)
            Aidp.log_debug(COMPONENT, "load_proposed_config.file_missing", path: config_file)
            return nil
          end
          Aidp.log_debug(COMPONENT, "load_proposed_config.from_file", path: config_file)
          JSON.parse(File.read(config_file))
        elsif options[:generate]
          # Generate from wizard config in aidp.yml
          aidp_config = load_aidp_config
          return nil unless aidp_config

          generator = Aidp::Setup::Devcontainer::Generator.new(@project_dir, aidp_config)
          wizard_config = extract_wizard_config(aidp_config)
          Aidp.log_debug(COMPONENT, "load_proposed_config.generate_from_wizard",
            wizard_keys: wizard_config.keys)
          generator.generate(wizard_config)
        else
          # Load from aidp.yml and generate using wizard config
          aidp_config = load_aidp_config
          return nil unless aidp_config&.dig("devcontainer", "manage")

          # Use Generator to create proper devcontainer config
          generator = Aidp::Setup::Devcontainer::Generator.new(@project_dir, aidp_config)
          wizard_config = extract_wizard_config_for_generation(aidp_config)
          Aidp.log_debug(COMPONENT, "load_proposed_config.from_managed_config",
            wizard_keys: wizard_config.keys)
          generator.generate(wizard_config)
        end
      end

      def load_aidp_config
        config_path = File.join(@project_dir, ".aidp", "aidp.yml")
        return nil unless File.exist?(config_path)

        config = YAML.load_file(config_path)
        Aidp.log_debug(COMPONENT, "load_aidp_config.loaded",
          config_path: config_path,
          manages_devcontainer: config.dig("devcontainer", "manage"))
        config
      rescue => e
        Aidp.log_error("devcontainer_commands", "failed to load aidp.yml", error: e.message)
        nil
      end

      def extract_wizard_config(aidp_config)
        # Extract wizard-compatible config from aidp.yml
        {
          project_name: aidp_config.dig("project", "name"),
          language: aidp_config.dig("project", "language"),
          test_framework: aidp_config.dig("testing", "framework"),
          linters: aidp_config.dig("linting", "tools"),
          providers: aidp_config.dig("providers")&.keys,
          watch_mode: aidp_config.dig("watch", "enabled"),
          app_type: aidp_config.dig("project", "type"),
          app_port: aidp_config.dig("devcontainer", "ports", 0, "number")
        }.compact
      end

      def extract_wizard_config_for_generation(aidp_config)
        # Extract wizard-compatible config including custom_ports
        {
          providers: aidp_config.dig("providers")&.keys,
          test_framework: aidp_config.dig("work_loop", "test_commands", 0, "framework"),
          linters: aidp_config.dig("work_loop", "linting", "tools"),
          watch_mode: aidp_config.dig("work_loop", "watch", "enabled"),
          custom_ports: aidp_config.dig("devcontainer", "custom_ports")
        }.compact
      end

      def build_config_from_aidp_yml(devcontainer_config)
        config = {}

        # Basic info
        config["name"] = devcontainer_config["name"] if devcontainer_config["name"]

        # Features
        if devcontainer_config["features"]
          config["features"] = devcontainer_config["features"].each_with_object({}) do |feature, h|
            h[feature] = {}
          end
        end

        # Ports
        if devcontainer_config["ports"]
          config["forwardPorts"] = devcontainer_config["ports"].map { |p| p["number"] }
          config["portsAttributes"] = devcontainer_config["ports"].each_with_object({}) do |port, attrs|
            attrs[port["number"].to_s] = {
              "label" => port["label"],
              "protocol" => port["protocol"] || "http"
            }
          end
        end

        # Environment
        config["containerEnv"] = devcontainer_config["env"] if devcontainer_config["env"]

        # Custom settings
        config.merge!(devcontainer_config["custom_settings"] || {})

        # AIDP metadata
        config["_aidp"] = {
          "managed" => true,
          "version" => Aidp::VERSION,
          "generated_at" => Time.now.utc.iso8601
        }

        config
      end

      def display_diff(current, proposed, path)
        display_message("📄 Devcontainer Changes Preview", type: :highlight)
        display_message("━" * 60, type: :muted)
        display_message("File: #{path}", type: :muted)
        display_message("")

        # Features diff
        display_features_diff(current["features"], proposed["features"])

        # Ports diff
        display_ports_diff(current["forwardPorts"], proposed["forwardPorts"])

        # Port attributes diff
        display_port_attributes_diff(
          current["portsAttributes"],
          proposed["portsAttributes"]
        )

        # Environment diff
        display_env_diff(current["containerEnv"], proposed["containerEnv"])

        # Other changes
        display_other_changes(current, proposed)
      end

      def display_features_diff(current, proposed)
        current_features = normalize_features(current)
        proposed_features = normalize_features(proposed)

        added = proposed_features.keys - current_features.keys
        removed = current_features.keys - proposed_features.keys

        if added.any? || removed.any?
          display_message("Features:", type: :info)
          added.each do |feature|
            display_message("  + #{feature}", type: :success)
          end
          removed.each do |feature|
            display_message("  - #{feature}", type: :error)
          end
          display_message("")
        end
      end

      def display_ports_diff(current, proposed)
        current_ports = Array(current).sort
        proposed_ports = Array(proposed).sort

        added = proposed_ports - current_ports
        removed = current_ports - proposed_ports

        if added.any? || removed.any?
          display_message("Ports:", type: :info)
          added.each do |port|
            display_message("  + #{port}", type: :success)
          end
          removed.each do |port|
            display_message("  - #{port}", type: :error)
          end
          display_message("")
        end
      end

      def display_port_attributes_diff(current, proposed)
        current_attrs = current || {}
        proposed_attrs = proposed || {}

        all_ports = (current_attrs.keys + proposed_attrs.keys).uniq

        changes = all_ports.select do |port|
          current_attrs[port] != proposed_attrs[port]
        end

        if changes.any?
          display_message("Port Attributes:", type: :info)
          changes.each do |port|
            if current_attrs[port] && proposed_attrs[port]
              display_message("  ~ #{port}: #{proposed_attrs[port]["label"]}", type: :warning)
            elsif proposed_attrs[port]
              display_message("  + #{port}: #{proposed_attrs[port]["label"]}", type: :success)
            else
              display_message("  - #{port}", type: :error)
            end
          end
          display_message("")
        end
      end

      def display_env_diff(current, proposed)
        current_env = current || {}
        proposed_env = proposed || {}

        added = proposed_env.keys - current_env.keys
        removed = current_env.keys - proposed_env.keys
        modified = (current_env.keys & proposed_env.keys).select do |key|
          current_env[key] != proposed_env[key]
        end

        if added.any? || removed.any? || modified.any?
          display_message("Environment:", type: :info)
          added.each do |key|
            display_message("  + #{key}=#{proposed_env[key]}", type: :success)
          end
          modified.each do |key|
            display_message("  ~ #{key}: #{current_env[key]} → #{proposed_env[key]}", type: :warning)
          end
          removed.each do |key|
            display_message("  - #{key}", type: :error)
          end
          display_message("")
        end
      end

      def display_other_changes(current, proposed)
        # Check for other significant changes
        changes = []

        if current["name"] != proposed["name"] && proposed["name"]
          changes << "  ~ name: #{current["name"]} → #{proposed["name"]}"
        end

        if current["image"] != proposed["image"] && proposed["image"]
          changes << "  ~ image: #{current["image"]} → #{proposed["image"]}"
        end

        if current["postCreateCommand"] != proposed["postCreateCommand"] && proposed["postCreateCommand"]
          changes << "  ~ postCreateCommand"
        end

        if changes.any?
          display_message("Other Changes:", type: :info)
          changes.each { |change| display_message(change, type: :warning) }
          display_message("")
        end
      end

      def normalize_features(features)
        case features
        when Hash
          features
        when Array
          features.each_with_object({}) { |f, h| h[f] = {} }
        else
          {}
        end
      end

      def write_devcontainer(path, config)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(config))
      end

      def default_devcontainer_path
        File.join(@project_dir, ".devcontainer", "devcontainer.json")
      end

      def format_size(bytes)
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.length - 1].min

        "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
      end
    end
  end
end
