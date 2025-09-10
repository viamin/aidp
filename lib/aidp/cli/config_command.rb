# frozen_string_literal: true

require_relative "../harness/config_migrator"
require_relative "../harness/config_validator"
require_relative "../harness/config_loader"

module Aidp
  # Configuration management command
  class ConfigCommand
      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @migrator = Aidp::Harness::ConfigMigrator.new(project_dir)
        @validator = Aidp::Harness::ConfigValidator.new(project_dir)
        @loader = Aidp::Harness::ConfigLoader.new(project_dir)
      end

      # Main command entry point
      def run(args)
        command = args[0]
        case command
        when "migrate"
          run_migrate(args[1..-1])
        when "validate"
          run_validate(args[1..-1])
        when "backup"
          run_backup(args[1..-1])
        when "restore"
          run_restore(args[1..-1])
        when "status"
          run_status(args[1..-1])
        when "clean"
          run_clean(args[1..-1])
        when "init"
          run_init(args[1..-1])
        when "show"
          run_show(args[1..-1])
        when "help"
          show_help
        else
          puts "Unknown command: #{command}"
          show_help
        end
      end

      public

      def run_migrate(args)
        options = parse_options(args)

        puts "Starting configuration migration..."

        result = case options[:from]
                 when "legacy"
                   @migrator.migrate_from_legacy(options)
                 when "2.0", "2.x"
                   @migrator.migrate_harness_format(options)
                 when "auto"
                   @migrator.auto_migrate(options)
                 else
                   @migrator.auto_migrate(options)
        end

        if result[:success]
          puts "✅ #{result[:message]}"
          if result[:backup_file]
            puts "📁 Backup created: #{result[:backup_file]}"
          end
          if result[:warnings] && !result[:warnings].empty?
            puts "⚠️  Warnings:"
            result[:warnings].each { |warning| puts "   - #{warning}" }
          end
        else
          puts "❌ #{result[:message]}"
          if result[:errors]
            puts "Errors:"
            result[:errors].each { |error| puts "   - #{error}" }
          end
          exit 1
        end
      end

      def run_validate(args)
        _options = parse_options(args)

        puts "Validating configuration..."

        if @validator.config_exists?
          validation_result = @validator.validate_existing

          if validation_result[:valid]
            puts "✅ Configuration is valid"
            if validation_result[:warnings] && !validation_result[:warnings].empty?
              puts "⚠️  Warnings:"
              validation_result[:warnings].each { |warning| puts "   - #{warning}" }
            end
          else
            puts "❌ Configuration is invalid"
            puts "Errors:"
            validation_result[:errors].each { |error| puts "   - #{error}" }
            exit 1
          end
        else
          puts "❌ No configuration file found"
          exit 1
        end
      end

      def run_backup(args)
        options = parse_options(args)

        puts "Creating configuration backup..."

        result = @migrator.create_backup(options[:backup] != false)

        if result[:success]
          if result[:backup_file]
            puts "✅ Backup created: #{result[:backup_file]}"
          else
            puts "✅ No backup needed (no configuration file found)"
          end
        else
          puts "❌ #{result[:message]}"
          exit 1
        end
      end

      def run_restore(args)
        options = parse_options(args)

        if options[:backup_file]
          puts "Restoring configuration from: #{options[:backup_file]}"

          result = @migrator.restore_from_backup(options[:backup_file], options)

          if result[:success]
            puts "✅ #{result[:message]}"
            if result[:current_backup]
              puts "📁 Current config backed up to: #{result[:current_backup]}"
            end
          else
            puts "❌ #{result[:message]}"
            exit 1
          end
        else
          puts "❌ Backup file path required"
          puts "Usage: aidp config restore --backup-file <path>"
          exit 1
        end
      end

      def run_status(args)
        _options = parse_options(args)

        puts "Configuration Status:"
        puts "=" * 50

        status = @migrator.get_migration_status

        puts "Has configuration: #{status[:has_config] ? '✅' : '❌'}"
        puts "Has legacy configuration: #{status[:has_legacy_config] ? '✅' : '❌'}"
        puts "Needs migration: #{status[:needs_migration] ? '⚠️  Yes' : '✅ No'}"
        puts "Config version: #{status[:config_version]}"

        if status[:last_modified]
          puts "Last modified: #{status[:last_modified].strftime('%Y-%m-%d %H:%M:%S')}"
        end

        if status[:has_config] || status[:has_legacy_config]
          puts "\nValidation Status:"
          puts "-" * 30

          if @validator.config_exists?
            validation_result = @validator.validate_existing
            puts "Valid: #{validation_result[:valid] ? '✅' : '❌'}"

            if validation_result[:errors] && !validation_result[:errors].empty?
              puts "Errors: #{validation_result[:errors].length}"
            end

            if validation_result[:warnings] && !validation_result[:warnings].empty?
              puts "Warnings: #{validation_result[:warnings].length}"
            end
          else
            puts "Valid: ❌ (no config file)"
          end
        end

        # Show available backups
        backups = @migrator.list_backups
        if backups.any?
          puts "\nAvailable Backups:"
          puts "-" * 30
          backups.first(5).each do |backup|
            puts "#{backup[:filename]} (#{backup[:created].strftime('%Y-%m-%d %H:%M:%S')})"
          end
          puts "..." if backups.length > 5
        end
      end

      def run_clean(args)
        options = parse_options(args)
        keep_count = options[:keep] || 10

        puts "Cleaning old backups (keeping #{keep_count})..."

        result = @migrator.clean_backups(keep_count)

        if result[:success]
          puts "✅ #{result[:message]}"
        else
          puts "❌ #{result[:message]}"
          exit 1
        end
      end

      def run_init(args)
        options = parse_options(args)
        template = options[:template] || "minimal"

        puts "Initializing configuration with #{template} template..."

        # Check if config already exists
        if @validator.config_exists?
          unless options[:force]
            puts "❌ Configuration file already exists. Use --force to overwrite."
            exit 1
          end
        end

        # Create backup if config exists
        if @validator.config_exists?
          backup_result = @migrator.create_backup(true)
          if backup_result[:success] && backup_result[:backup_file]
            puts "📁 Existing config backed up to: #{backup_result[:backup_file]}"
          end
        end

        # Copy template
        template_file = File.join(File.dirname(__FILE__), "..", "..", "..", "templates", "aidp-#{template}.yml.example")
        config_file = File.join(@project_dir, "aidp.yml")

        unless File.exist?(template_file)
          puts "❌ Template not found: #{template}"
          puts "Available templates: minimal, production, development"
          exit 1
        end

        begin
          FileUtils.cp(template_file, config_file)
          puts "✅ Configuration initialized: #{config_file}"
          puts "📝 Edit the configuration file to customize your settings"
        rescue => e
          puts "❌ Failed to initialize configuration: #{e.message}"
          exit 1
        end
      end

      def run_show(args)
        options = parse_options(args)

        if @validator.config_exists?
          config = @loader.load_config

          if options[:format] == "yaml"
            puts YAML.dump(config)
          elsif options[:format] == "json"
            require "json"
            puts JSON.pretty_generate(config)
          else
            # Show summary
            puts "Configuration Summary:"
            puts "=" * 50

            if config[:harness]
              puts "Harness Configuration:"
              puts "  Default Provider: #{config[:harness][:default_provider] || 'Not set'}"
              puts "  Max Retries: #{config[:harness][:max_retries] || 'Not set'}"
              puts "  Fallback Providers: #{config[:harness][:fallback_providers]&.join(', ') || 'None'}"
            end

            if config[:providers]
              puts "\nProviders:"
              config[:providers].each do |name, provider_config|
                puts "  #{name}:"
                puts "    Type: #{provider_config[:type] || 'Not set'}"
                puts "    Priority: #{provider_config[:priority] || 'Not set'}"
                puts "    Models: #{provider_config[:models]&.join(', ') || 'None'}"
              end
            end
          end
        else
          puts "❌ No configuration file found"
          exit 1
        end
      end

      def parse_options(args)
        options = {}

        i = 0
        while i < args.length
          arg = args[i]

          case arg
          when "--from"
            options[:from] = args[i + 1]
            i += 1
          when "--backup"
            options[:backup] = args[i + 1] != "false"
            i += 1
          when "--backup-file"
            options[:backup_file] = args[i + 1]
            i += 1
          when "--keep"
            options[:keep] = args[i + 1].to_i
            i += 1
          when "--template"
            options[:template] = args[i + 1]
            i += 1
          when "--force"
            options[:force] = true
          when "--format"
            options[:format] = args[i + 1]
            i += 1
          when "--apply-defaults"
            options[:apply_defaults] = args[i + 1] != "false"
            i += 1
          end

          i += 1
        end

        options
      end

      def show_help
        puts <<~HELP
          AIDP Configuration Management

          Usage: aidp config <command> [options]

          Commands:
            migrate     Migrate configuration to new format
            validate    Validate current configuration
            backup      Create backup of current configuration
            restore     Restore configuration from backup
            status      Show configuration status
            clean       Clean old backups
            init        Initialize new configuration
            show        Show configuration summary
            help        Show this help message

          Migration Options:
            --from <version>    Migrate from specific version (legacy, 2.0, auto)
            --backup <bool>     Create backup before migration (default: true)

          Backup Options:
            --backup <bool>     Create backup (default: true)

          Restore Options:
            --backup-file <path>  Path to backup file to restore

          Clean Options:
            --keep <count>      Number of backups to keep (default: 10)

          Init Options:
            --template <name>   Template to use (minimal, production, development)
            --force            Overwrite existing configuration

          Show Options:
            --format <format>   Output format (yaml, json, summary)

          Examples:
            aidp config migrate --from legacy
            aidp config validate
            aidp config backup
            aidp config restore --backup-file .aidp/backups/aidp_config_backup_20240101_120000.yml
            aidp config status
            aidp config clean --keep 5
            aidp config init --template minimal
            aidp config show --format yaml
        HELP
      end
    end
end
