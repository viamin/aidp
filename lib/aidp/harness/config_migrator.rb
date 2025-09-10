# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "config_schema"
require_relative "config_validator"

module Aidp
  module Harness
    # Configuration migration utilities
    class ConfigMigrator
      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @config_file = File.join(project_dir, "aidp.yml")
        @legacy_config_file = File.join(project_dir, ".aidp.yml")
        @backup_dir = File.join(project_dir, ".aidp", "backups")
      end

      # Migrate from legacy configuration format
      def migrate_from_legacy(options = {})
        return { success: false, message: "No legacy configuration found" } unless legacy_config_exists?

        # Create backup
        backup_result = create_backup(options[:backup] != false)
        return backup_result unless backup_result[:success]

        # Load legacy configuration
        legacy_config = load_legacy_config
        return { success: false, message: "Failed to load legacy configuration" } unless legacy_config

        # Convert to new format
        new_config = convert_legacy_to_new(legacy_config)
        return { success: false, message: "Failed to convert legacy configuration" } unless new_config

        # Validate new configuration
        validator = ConfigValidator.new(@project_dir)
        validation_result = validator.validate_config(new_config)

        if validation_result[:valid]
          # Write new configuration
          write_result = write_config(new_config, options)
          if write_result[:success]
            {
              success: true,
              message: "Successfully migrated configuration",
              backup_file: backup_result[:backup_file],
              warnings: validation_result[:warnings]
            }
          else
            write_result
          end
        else
          {
            success: false,
            message: "Converted configuration is invalid: #{validation_result[:errors].join(', ')}",
            errors: validation_result[:errors]
          }
        end
      end

      # Migrate from old harness configuration format
      def migrate_harness_format(options = {})
        return { success: false, message: "No configuration found" } unless config_exists?

        # Create backup
        backup_result = create_backup(options[:backup] != false)
        return backup_result unless backup_result[:success]

        # Load current configuration
        current_config = load_current_config
        return { success: false, message: "Failed to load current configuration" } unless current_config

        # Convert to new harness format
        new_config = convert_to_new_harness_format(current_config)
        return { success: false, message: "Failed to convert configuration" } unless new_config

        # Validate new configuration
        validator = ConfigValidator.new(@project_dir)
        validation_result = validator.validate_config(new_config)

        if validation_result[:valid]
          # Write new configuration
          write_result = write_config(new_config, options)
          if write_result[:success]
            {
              success: true,
              message: "Successfully migrated harness configuration",
              backup_file: backup_result[:backup_file],
              warnings: validation_result[:warnings]
            }
          else
            write_result
          end
        else
          {
            success: false,
            message: "Converted configuration is invalid: #{validation_result[:errors].join(', ')}",
            errors: validation_result[:errors]
          }
        end
      end

      # Migrate provider configurations
      def migrate_provider_configs(options = {})
        return { success: false, message: "No configuration found" } unless config_exists?

        # Create backup
        backup_result = create_backup(options[:backup] != false)
        return backup_result unless backup_result[:success]

        # Load current configuration
        current_config = load_current_config
        return { success: false, message: "Failed to load current configuration" } unless current_config

        # Convert provider configurations
        new_config = convert_provider_configs(current_config)
        return { success: false, message: "Failed to convert provider configurations" } unless new_config

        # Validate new configuration
        validator = ConfigValidator.new(@project_dir)
        validation_result = validator.validate_config(new_config)

        if validation_result[:valid]
          # Write new configuration
          write_result = write_config(new_config, options)
          if write_result[:success]
            {
              success: true,
              message: "Successfully migrated provider configurations",
              backup_file: backup_result[:backup_file],
              warnings: validation_result[:warnings]
            }
          else
            write_result
          end
        else
          {
            success: false,
            message: "Converted configuration is invalid: #{validation_result[:errors].join(', ')}",
            errors: validation_result[:errors]
          }
        end
      end

      # Migrate from specific version
      def migrate_from_version(version, options = {})
        case version.to_s
        when "1.0", "1.x"
          migrate_from_legacy(options)
        when "2.0", "2.x"
          migrate_harness_format(options)
        else
          { success: false, message: "Unknown version: #{version}" }
        end
      end

      # Auto-detect and migrate configuration
      def auto_migrate(options = {})
        if legacy_config_exists?
          migrate_from_legacy(options)
        elsif config_exists?
          # Check if current config needs migration
          current_config = load_current_config
          if needs_migration?(current_config)
            migrate_harness_format(options)
          else
            { success: true, message: "Configuration is already up to date" }
          end
        else
          { success: false, message: "No configuration found to migrate" }
        end
      end

      # Check if configuration needs migration
      def needs_migration?(config = nil)
        config ||= load_current_config
        return false unless config

        # Check for old format indicators
        old_format_indicators = [
          config.key?("provider") && !config.key?("providers"),
          config.key?("harness") && config["harness"].is_a?(String),
          config.key?("retry_count") && !config.dig("harness", "retry"),
          config.key?("timeout") && !config.dig("harness", "request_timeout")
        ]

        old_format_indicators.any?
      end

      # Create backup of current configuration
      def create_backup(create_backup = true)
        return { success: true, backup_file: nil } unless create_backup

        # Ensure backup directory exists
        FileUtils.mkdir_p(@backup_dir) unless Dir.exist?(@backup_dir)

        # Find existing config file
        source_file = nil
        if File.exist?(@config_file)
          source_file = @config_file
        elsif File.exist?(@legacy_config_file)
          source_file = @legacy_config_file
        else
          return { success: false, message: "No configuration file to backup" }
        end

        # Create backup filename with timestamp
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        backup_filename = "aidp_config_backup_#{timestamp}.yml"
        backup_file = File.join(@backup_dir, backup_filename)

        # Copy file to backup
        begin
          FileUtils.cp(source_file, backup_file)
          { success: true, backup_file: backup_file }
        rescue => e
          { success: false, message: "Failed to create backup: #{e.message}" }
        end
      end

      # Restore from backup
      def restore_from_backup(backup_file, _options = {})
        return { success: false, message: "Backup file not found" } unless File.exist?(backup_file)

        # Create backup of current config if it exists
        current_backup = nil
        if File.exist?(@config_file)
          current_backup = create_backup(true)
          return current_backup unless current_backup[:success]
        end

        # Copy backup to config file
        begin
          FileUtils.cp(backup_file, @config_file)
          {
            success: true,
            message: "Successfully restored configuration from backup",
            current_backup: current_backup&.dig(:backup_file)
          }
        rescue => e
          { success: false, message: "Failed to restore backup: #{e.message}" }
        end
      end

      # List available backups
      def list_backups
        return [] unless Dir.exist?(@backup_dir)

        backup_files = Dir.glob(File.join(@backup_dir, "aidp_config_backup_*.yml"))
        backup_files.map do |file|
          {
            file: file,
            filename: File.basename(file),
            created: File.mtime(file),
            size: File.size(file)
          }
        end.sort_by { |backup| backup[:created] }.reverse
      end

      # Clean old backups
      def clean_backups(keep_count = 10)
        backups = list_backups
        return { success: true, message: "No backups to clean" } if backups.length <= keep_count

        backups_to_delete = backups[keep_count..-1]
        deleted_count = 0

        backups_to_delete.each do |backup|
          begin
            File.delete(backup[:file])
            deleted_count += 1
          rescue
            # Continue with other deletions
          end
        end

        {
          success: true,
          message: "Cleaned #{deleted_count} old backups",
          deleted_count: deleted_count
        }
      end

      # Get migration status
      def get_migration_status
        status = {
          has_config: config_exists?,
          has_legacy_config: legacy_config_exists?,
          needs_migration: false,
          config_version: "unknown",
          last_modified: nil
        }

        if status[:has_config]
          config = load_current_config
          status[:needs_migration] = needs_migration?(config)
          status[:config_version] = detect_config_version(config)
          status[:last_modified] = File.mtime(@config_file)
        elsif status[:has_legacy_config]
          status[:needs_migration] = true
          status[:config_version] = "legacy"
          status[:last_modified] = File.mtime(@legacy_config_file)
        end

        status
      end

      private

      def config_exists?
        File.exist?(@config_file)
      end

      def legacy_config_exists?
        File.exist?(@legacy_config_file)
      end

      def load_legacy_config
        return nil unless legacy_config_exists?

        begin
          YAML.load_file(@legacy_config_file)
        rescue
          nil
        end
      end

      def load_current_config
        return nil unless config_exists?

        begin
          YAML.load_file(@config_file)
        rescue
          nil
        end
      end

      def write_config(config, options = {})
        begin
          # Apply defaults if requested
          if options[:apply_defaults] != false
            config = ConfigSchema.apply_defaults(config)
          end

          # Write configuration
          File.write(@config_file, YAML.dump(config))
          { success: true, message: "Configuration written successfully" }
        rescue => e
          { success: false, message: "Failed to write configuration: #{e.message}" }
        end
      end

      def convert_legacy_to_new(legacy_config)
        new_config = {}

        # Convert basic provider configuration
        if legacy_config["provider"]
          new_config["harness"] = {
            "default_provider" => legacy_config["provider"]
          }

          new_config["providers"] = {
            legacy_config["provider"] => {
              "type" => "package",
              "priority" => 1,
              "models" => ["default"],
              "features" => {
                "file_upload" => true,
                "code_generation" => true,
                "analysis" => true
              }
            }
          }
        end

        # Convert retry configuration
        if legacy_config["retry_count"]
          new_config["harness"] ||= {}
          new_config["harness"]["max_retries"] = legacy_config["retry_count"]
        end

        # Convert timeout configuration
        if legacy_config["timeout"]
          new_config["harness"] ||= {}
          new_config["harness"]["request_timeout"] = legacy_config["timeout"]
        end

        # Convert other legacy settings
        if legacy_config["max_tokens"]
          provider_name = legacy_config["provider"] || "default"
          new_config["providers"] ||= {}
          new_config["providers"][provider_name] ||= {}
          new_config["providers"][provider_name]["max_tokens"] = legacy_config["max_tokens"]
        end

        # Apply defaults to ensure completeness
        ConfigSchema.apply_defaults(new_config)
      end

      def convert_to_new_harness_format(current_config)
        new_config = current_config.dup

        # Convert old harness format to new format
        if new_config["harness"].is_a?(String)
          # Old format: harness: "provider_name"
          provider_name = new_config["harness"]
          new_config["harness"] = {
            "default_provider" => provider_name
          }
        end

        # Convert old retry format
        if new_config["retry_count"]
          new_config["harness"] ||= {}
          new_config["harness"]["max_retries"] = new_config["retry_count"]
          new_config.delete("retry_count")
        end

        # Convert old timeout format
        if new_config["timeout"] && !new_config.dig("harness", "request_timeout")
          new_config["harness"] ||= {}
          new_config["harness"]["request_timeout"] = new_config["timeout"]
        end

        # Convert old provider format
        if new_config["provider"] && !new_config["providers"]
          provider_name = new_config["provider"]
          new_config["providers"] = {
            provider_name => {
              "type" => "package",
              "priority" => 1,
              "models" => ["default"],
              "features" => {
                "file_upload" => true,
                "code_generation" => true,
                "analysis" => true
              }
            }
          }
          new_config.delete("provider")
        end

        # Apply defaults to ensure completeness
        ConfigSchema.apply_defaults(new_config)
      end

      def convert_provider_configs(current_config)
        new_config = current_config.dup

        # Ensure providers section exists
        new_config["providers"] ||= {}

        # Convert each provider configuration
        new_config["providers"].each do |provider_name, provider_config|
          # Convert string-based provider config to object
          if provider_config.is_a?(String)
            new_config["providers"][provider_name] = {
              "type" => "package",
              "priority" => 1,
              "models" => [provider_config],
              "features" => {
                "file_upload" => true,
                "code_generation" => true,
                "analysis" => true
              }
            }
          end

          # Ensure required fields exist
          provider_config = new_config["providers"][provider_name]
          provider_config["type"] ||= "package"
          provider_config["priority"] ||= 1
          provider_config["models"] ||= ["default"]
          provider_config["features"] ||= {
            "file_upload" => true,
            "code_generation" => true,
            "analysis" => true
          }
        end

        # Apply defaults to ensure completeness
        ConfigSchema.apply_defaults(new_config)
      end

      def detect_config_version(config)
        return "legacy" if config.key?("provider") && !config.key?("providers")
        return "2.0" if config.key?("harness") && config["harness"].is_a?(Hash)
        return "1.0" if config.key?("harness") && config["harness"].is_a?(String)
        "unknown"
      end
    end
  end
end
