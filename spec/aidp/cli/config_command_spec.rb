# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/cli/config_command"

RSpec.describe Aidp::ConfigCommand do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_command) { described_class.new(project_dir) }
  let(:migrator) { instance_double("Aidp::Harness::ConfigMigrator") }
  let(:validator) { instance_double("Aidp::Harness::ConfigValidator") }
  let(:loader) { instance_double("Aidp::Harness::ConfigLoader") }

  before do
    # Mock the dependencies
    allow(Aidp::Harness::ConfigMigrator).to receive(:new).with(project_dir).and_return(migrator)
    allow(Aidp::Harness::ConfigValidator).to receive(:new).with(project_dir).and_return(validator)
    allow(Aidp::Harness::ConfigLoader).to receive(:new).with(project_dir).and_return(loader)
  end

  describe "initialization" do
    it "creates config command successfully" do
      expect(config_command).to be_a(described_class)
    end

    it "initializes with correct project directory" do
      expect(config_command.instance_variable_get(:@project_dir)).to eq(project_dir)
    end

    it "initializes migrator, validator, and loader" do
      expect(config_command.instance_variable_get(:@migrator)).to eq(migrator)
      expect(config_command.instance_variable_get(:@validator)).to eq(validator)
      expect(config_command.instance_variable_get(:@loader)).to eq(loader)
    end
  end

  describe "#run" do
    it "calls migrate command" do
      expect(config_command).to receive(:run_migrate).with(["legacy"])
      config_command.run(["migrate", "legacy"])
    end

    it "calls validate command" do
      expect(config_command).to receive(:run_validate).with([])
      config_command.run(["validate"])
    end

    it "calls backup command" do
      expect(config_command).to receive(:run_backup).with([])
      config_command.run(["backup"])
    end

    it "calls restore command" do
      expect(config_command).to receive(:run_restore).with(["--backup-file", "test.yml"])
      config_command.run(["restore", "--backup-file", "test.yml"])
    end

    it "calls status command" do
      expect(config_command).to receive(:run_status).with([])
      config_command.run(["status"])
    end

    it "calls clean command" do
      expect(config_command).to receive(:run_clean).with(["--keep", "5"])
      config_command.run(["clean", "--keep", "5"])
    end

    it "calls init command" do
      expect(config_command).to receive(:run_init).with(["--template", "minimal"])
      config_command.run(["init", "--template", "minimal"])
    end

    it "calls show command" do
      expect(config_command).to receive(:run_show).with(["--format", "yaml"])
      config_command.run(["show", "--format", "yaml"])
    end

    it "calls help command" do
      expect(config_command).to receive(:show_help)
      config_command.run(["help"])
    end

    it "shows help for unknown command" do
      expect(config_command).to receive(:show_help)
      expect { config_command.run(["unknown"]) }.to output(/Unknown command/).to_stdout
    end
  end

  describe "#run_migrate" do
    it "migrates from legacy configuration successfully" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect { config_command.run_migrate(["--from", "legacy"]) }
        .to output(/✅ Successfully migrated configuration/).to_stdout
    end

    it "migrates from harness format successfully" do
      allow(migrator).to receive(:migrate_harness_format).and_return({
        success: true,
        message: "Successfully migrated harness configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect { config_command.run_migrate(["--from", "2.0"]) }
        .to output(/✅ Successfully migrated harness configuration/).to_stdout
    end

    it "performs auto migration successfully" do
      allow(migrator).to receive(:auto_migrate).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect { config_command.run_migrate(["--from", "auto"]) }
        .to output(/✅ Successfully migrated configuration/).to_stdout
    end

    it "handles migration failure" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: false,
        message: "Migration failed",
        errors: ["Error 1", "Error 2"]
      })

      expect { config_command.run_migrate(["--from", "legacy"]) }
        .to output(/❌ Migration failed/).to_stdout
        .and raise_error(SystemExit)
    end

    it "displays warnings when present" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: ["Warning 1", "Warning 2"]
      })

      expect { config_command.run_migrate(["--from", "legacy"]) }
        .to output(/⚠️  Warnings:/).to_stdout
    end

    it "displays backup file information" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect { config_command.run_migrate(["--from", "legacy"]) }
        .to output(/📁 Backup created: \/tmp\/backup\.yml/).to_stdout
    end
  end

  describe "#run_validate" do
    it "validates configuration successfully" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        warnings: []
      })

      expect { config_command.run_validate([]) }
        .to output(/✅ Configuration is valid/).to_stdout
    end

    it "displays warnings when present" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        warnings: ["Warning 1", "Warning 2"]
      })

      expect { config_command.run_validate([]) }
        .to output(/⚠️  Warnings:/).to_stdout
    end

    it "handles invalid configuration" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: false,
        errors: ["Error 1", "Error 2"]
      })

      expect { config_command.run_validate([]) }
        .to output(/❌ Configuration is invalid/).to_stdout
        .and raise_error(SystemExit)
    end

    it "handles missing configuration file" do
      allow(validator).to receive(:config_exists?).and_return(false)

      expect { config_command.run_validate([]) }
        .to output(/❌ No configuration file found/).to_stdout
        .and raise_error(SystemExit)
    end
  end

  describe "#run_backup" do
    it "creates backup successfully" do
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: "/tmp/backup.yml"
      })

      expect { config_command.run_backup([]) }
        .to output(/✅ Backup created: \/tmp\/backup\.yml/).to_stdout
    end

    it "handles backup creation failure" do
      allow(migrator).to receive(:create_backup).and_return({
        success: false,
        message: "Backup failed"
      })

      expect { config_command.run_backup([]) }
        .to output(/❌ Backup failed/).to_stdout
        .and raise_error(SystemExit)
    end

    it "handles no configuration file to backup" do
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: nil
      })

      expect { config_command.run_backup([]) }
        .to output(/✅ No backup needed/).to_stdout
    end
  end

  describe "#run_restore" do
    it "restores from backup successfully" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: true,
        message: "Successfully restored configuration from backup",
        current_backup: "/tmp/current_backup.yml"
      })

      expect { config_command.run_restore(["--backup-file", "/tmp/backup.yml"]) }
        .to output(/✅ Successfully restored configuration from backup/).to_stdout
    end

    it "displays current backup information" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: true,
        message: "Successfully restored configuration from backup",
        current_backup: "/tmp/current_backup.yml"
      })

      expect { config_command.run_restore(["--backup-file", "/tmp/backup.yml"]) }
        .to output(/📁 Current config backed up to: \/tmp\/current_backup\.yml/).to_stdout
    end

    it "handles restore failure" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: false,
        message: "Restore failed"
      })

      expect { config_command.run_restore(["--backup-file", "/tmp/backup.yml"]) }
        .to output(/❌ Restore failed/).to_stdout
        .and raise_error(SystemExit)
    end

    it "requires backup file path" do
      expect { config_command.run_restore([]) }
        .to output(/❌ Backup file path required/).to_stdout
        .and raise_error(SystemExit)
    end
  end

  describe "#run_status" do
    it "displays configuration status" do
      allow(migrator).to receive(:get_migration_status).and_return({
        has_config: true,
        has_legacy_config: false,
        needs_migration: false,
        config_version: "2.0",
        last_modified: Time.now
      })
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        errors: [],
        warnings: []
      })
      allow(migrator).to receive(:list_backups).and_return([])

      expect { config_command.run_status([]) }
        .to output(/Configuration Status:/).to_stdout
    end

    it "displays migration status" do
      allow(migrator).to receive(:get_migration_status).and_return({
        has_config: true,
        has_legacy_config: false,
        needs_migration: false,
        config_version: "2.0",
        last_modified: Time.now
      })
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        errors: [],
        warnings: []
      })
      allow(migrator).to receive(:list_backups).and_return([])

      expect { config_command.run_status([]) }
        .to output(/Has configuration: ✅/).to_stdout
    end

    it "displays validation status" do
      allow(migrator).to receive(:get_migration_status).and_return({
        has_config: true,
        has_legacy_config: false,
        needs_migration: false,
        config_version: "2.0",
        last_modified: Time.now
      })
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        errors: [],
        warnings: []
      })
      allow(migrator).to receive(:list_backups).and_return([])

      expect { config_command.run_status([]) }
        .to output(/Valid: ✅/).to_stdout
    end

    it "displays available backups" do
      allow(migrator).to receive(:get_migration_status).and_return({
        has_config: true,
        has_legacy_config: false,
        needs_migration: false,
        config_version: "2.0",
        last_modified: Time.now
      })
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        errors: [],
        warnings: []
      })
      allow(migrator).to receive(:list_backups).and_return([
        {
          filename: "aidp_config_backup_20240101_120000.yml",
          created: Time.now
        }
      ])

      expect { config_command.run_status([]) }
        .to output(/Available Backups:/).to_stdout
    end
  end

  describe "#run_clean" do
    it "cleans old backups successfully" do
      allow(migrator).to receive(:clean_backups).and_return({
        success: true,
        message: "Cleaned 5 old backups",
        deleted_count: 5
      })

      expect { config_command.run_clean(["--keep", "10"]) }
        .to output(/✅ Cleaned 5 old backups/).to_stdout
    end

    it "uses default keep count when not specified" do
      allow(migrator).to receive(:clean_backups).with(10).and_return({
        success: true,
        message: "Cleaned 0 old backups",
        deleted_count: 0
      })

      expect { config_command.run_clean([]) }
        .to output(/✅ Cleaned 0 old backups/).to_stdout
    end

    it "handles clean failure" do
      allow(migrator).to receive(:clean_backups).and_return({
        success: false,
        message: "Clean failed"
      })

      expect { config_command.run_clean([]) }
        .to output(/❌ Clean failed/).to_stdout
        .and raise_error(SystemExit)
    end
  end

  describe "#run_init" do
    it "initializes configuration with minimal template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      expect { config_command.run_init(["--template", "minimal"]) }
        .to output(/✅ Configuration initialized/).to_stdout
    end

    it "initializes configuration with production template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      expect { config_command.run_init(["--template", "production"]) }
        .to output(/✅ Configuration initialized/).to_stdout
    end

    it "initializes configuration with development template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      expect { config_command.run_init(["--template", "development"]) }
        .to output(/✅ Configuration initialized/).to_stdout
    end

    it "creates backup before overwriting existing configuration" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: "/tmp/backup.yml"
      })
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      expect { config_command.run_init(["--template", "minimal", "--force"]) }
        .to output(/📁 Existing config backed up to: \/tmp\/backup\.yml/).to_stdout
    end

    it "refuses to overwrite existing configuration without force" do
      allow(validator).to receive(:config_exists?).and_return(true)

      expect { config_command.run_init(["--template", "minimal"]) }
        .to output(/❌ Configuration file already exists/).to_stdout
        .and raise_error(SystemExit)
    end

    it "handles missing template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(false)

      expect { config_command.run_init(["--template", "nonexistent"]) }
        .to output(/❌ Template not found: nonexistent/).to_stdout
        .and raise_error(SystemExit)
    end

    it "handles initialization failure" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp).and_raise(StandardError.new("Copy failed"))

      expect { config_command.run_init(["--template", "minimal"]) }
        .to output(/❌ Failed to initialize configuration: Copy failed/).to_stdout
        .and raise_error(SystemExit)
    end
  end

  describe "#run_show" do
    it "shows configuration summary" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_return({
        harness: {
          default_provider: "claude",
          max_retries: 3,
          fallback_providers: ["gemini"]
        },
        providers: {
          claude: {
            type: "api",
            priority: 1,
            models: ["claude-3-5-sonnet-20241022"]
          }
        }
      })

      expect { config_command.run_show([]) }
        .to output(/Configuration Summary:/).to_stdout
    end

    it "shows configuration in YAML format" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_return({ test: "value" })

      expect { config_command.run_show(["--format", "yaml"]) }
        .to output(/test: value/).to_stdout
    end

    it "shows configuration in JSON format" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_return({ test: "value" })

      expect { config_command.run_show(["--format", "json"]) }
        .to output(/"test": "value"/).to_stdout
    end

    it "handles missing configuration file" do
      allow(validator).to receive(:config_exists?).and_return(false)

      expect { config_command.run_show([]) }
        .to output(/❌ No configuration file found/).to_stdout
        .and raise_error(SystemExit)
    end
  end

  describe "#parse_options" do
    it "parses from option" do
      options = config_command.send(:parse_options, ["--from", "legacy"])
      expect(options[:from]).to eq("legacy")
    end

    it "parses backup option" do
      options = config_command.send(:parse_options, ["--backup", "false"])
      expect(options[:backup]).to be false
    end

    it "parses backup-file option" do
      options = config_command.send(:parse_options, ["--backup-file", "/tmp/backup.yml"])
      expect(options[:backup_file]).to eq("/tmp/backup.yml")
    end

    it "parses keep option" do
      options = config_command.send(:parse_options, ["--keep", "5"])
      expect(options[:keep]).to eq(5)
    end

    it "parses template option" do
      options = config_command.send(:parse_options, ["--template", "minimal"])
      expect(options[:template]).to eq("minimal")
    end

    it "parses force option" do
      options = config_command.send(:parse_options, ["--force"])
      expect(options[:force]).to be true
    end

    it "parses format option" do
      options = config_command.send(:parse_options, ["--format", "yaml"])
      expect(options[:format]).to eq("yaml")
    end

    it "parses apply-defaults option" do
      options = config_command.send(:parse_options, ["--apply-defaults", "false"])
      expect(options[:apply_defaults]).to be false
    end

    it "handles multiple options" do
      options = config_command.send(:parse_options, [
        "--from", "legacy",
        "--backup", "true",
        "--force"
      ])
      expect(options[:from]).to eq("legacy")
      expect(options[:backup]).to be true
      expect(options[:force]).to be true
    end

    it "handles empty arguments" do
      options = config_command.send(:parse_options, [])
      expect(options).to eq({})
    end
  end

  describe "#show_help" do
    it "displays help information" do
      expect { config_command.show_help }
        .to output(/AIDP Configuration Management/).to_stdout
    end

    it "displays usage information" do
      expect { config_command.show_help }
        .to output(/Usage: aidp config <command>/).to_stdout
    end

    it "displays available commands" do
      expect { config_command.show_help }
        .to output(/migrate.*validate.*backup.*restore.*status.*clean.*init.*show.*help/m).to_stdout
    end

    it "displays examples" do
      expect { config_command.show_help }
        .to output(/Examples:/).to_stdout
    end
  end

  describe "error handling" do
    it "handles missing migrator methods gracefully" do
      allow(migrator).to receive(:migrate_from_legacy).and_raise(NoMethodError)

      expect { config_command.run_migrate(["--from", "legacy"]) }
        .to raise_error(NoMethodError)
    end

    it "handles missing validator methods gracefully" do
      allow(validator).to receive(:config_exists?).and_raise(NoMethodError)

      expect { config_command.run_validate([]) }
        .to raise_error(NoMethodError)
    end

    it "handles missing loader methods gracefully" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_raise(NoMethodError)

      expect { config_command.run_show([]) }
        .to raise_error(NoMethodError)
    end
  end

  describe "edge cases" do
    it "handles empty command arguments" do
      expect { config_command.run([]) }
        .to output(/Unknown command: /).to_stdout
    end

    it "handles nil command arguments" do
      expect { config_command.run([nil]) }
        .to output(/Unknown command: /).to_stdout
    end

    it "handles malformed option arguments" do
      allow(migrator).to receive(:auto_migrate).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: nil,
        warnings: []
      })

      expect { config_command.run_migrate(["--from"]) }
        .not_to raise_error
    end

    it "handles invalid option values" do
      allow(migrator).to receive(:clean_backups).and_return({
        success: true,
        message: "Cleaned 0 old backups",
        deleted_count: 0
      })

      expect { config_command.run_clean(["--keep", "invalid"]) }
        .not_to raise_error
    end
  end
end
