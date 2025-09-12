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
      config_command.run(["unknown"])
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

      expect(migrator).to receive(:migrate_from_legacy).with({from: "legacy"})
      config_command.run_migrate(["--from", "legacy"])
    end

    it "migrates from harness format successfully" do
      allow(migrator).to receive(:migrate_harness_format).and_return({
        success: true,
        message: "Successfully migrated harness configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect(migrator).to receive(:migrate_harness_format).with({from: "2.0"})
      config_command.run_migrate(["--from", "2.0"])
    end

    it "performs auto migration successfully" do
      allow(migrator).to receive(:auto_migrate).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      expect(migrator).to receive(:auto_migrate).with({from: "auto"})
      config_command.run_migrate(["--from", "auto"])
    end

    it "handles migration failure" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: false,
        message: "Migration failed",
        errors: ["Error 1", "Error 2"]
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_migrate(["--from", "legacy"])
      end
      expect(output).to match(/❌ Migration failed/)
        .and raise_error(SystemExit)
    end

    it "displays warnings when present" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: ["Warning 1", "Warning 2"]
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_migrate(["--from", "legacy"])
      end
      expect(output).to match(/⚠️  Warnings:/)
    end

    it "displays backup file information" do
      allow(migrator).to receive(:migrate_from_legacy).and_return({
        success: true,
        message: "Successfully migrated configuration",
        backup_file: "/tmp/backup.yml",
        warnings: []
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_migrate(["--from", "legacy"])
      end
      expect(output).to match(/📁 Backup created: \/tmp\/backup\.yml/)
    end
  end

  describe "#run_validate" do
    it "validates configuration successfully" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        warnings: []
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_validate([])
      end
      expect(output).to match(/✅ Configuration is valid/)
    end

    it "displays warnings when present" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: true,
        warnings: ["Warning 1", "Warning 2"]
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_validate([])
      end
      expect(output).to match(/⚠️  Warnings:/)
    end

    it "handles invalid configuration" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(validator).to receive(:validate_existing).and_return({
        valid: false,
        errors: ["Error 1", "Error 2"]
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_validate([])
      end
      expect(output).to match(/❌ Configuration is invalid/)
        .and raise_error(SystemExit)
    end

    it "handles missing configuration file" do
      allow(validator).to receive(:config_exists?).and_return(false)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_validate([])
      end
      expect(output).to match(/❌ No configuration file found/)
        .and raise_error(SystemExit)
    end
  end

  describe "#run_backup" do
    it "creates backup successfully" do
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: "/tmp/backup.yml"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_backup([])
      end
      expect(output).to match(/✅ Backup created: \/tmp\/backup\.yml/)
    end

    it "handles backup creation failure" do
      allow(migrator).to receive(:create_backup).and_return({
        success: false,
        message: "Backup failed"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_backup([])
      end
      expect(output).to match(/❌ Backup failed/)
        .and raise_error(SystemExit)
    end

    it "handles no configuration file to backup" do
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: nil
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_backup([])
      end
      expect(output).to match(/✅ No backup needed/)
    end
  end

  describe "#run_restore" do
    it "restores from backup successfully" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: true,
        message: "Successfully restored configuration from backup",
        current_backup: "/tmp/current_backup.yml"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_restore(["--backup-file", "/tmp/backup.yml"])
      end
      expect(output).to match(/✅ Successfully restored configuration from backup/)
    end

    it "displays current backup information" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: true,
        message: "Successfully restored configuration from backup",
        current_backup: "/tmp/current_backup.yml"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_restore(["--backup-file", "/tmp/backup.yml"])
      end
      expect(output).to match(/📁 Current config backed up to: \/tmp\/current_backup\.yml/)
    end

    it "handles restore failure" do
      allow(migrator).to receive(:restore_from_backup).and_return({
        success: false,
        message: "Restore failed"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_restore(["--backup-file", "/tmp/backup.yml"])
      end
      expect(output).to match(/❌ Restore failed/)
        .and raise_error(SystemExit)
    end

    it "requires backup file path" do
      output = Aidp::OutputLogger.capture_output do
        config_command.run_restore([])
      end
      expect(output).to match(/❌ Backup file path required/)
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

      output = Aidp::OutputLogger.capture_output do
        config_command.run_status([])
      end
      expect(output).to match(/Configuration Status:/)
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

      output = Aidp::OutputLogger.capture_output do
        config_command.run_status([])
      end
      expect(output).to match(/Has configuration: ✅/)
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

      output = Aidp::OutputLogger.capture_output do
        config_command.run_status([])
      end
      expect(output).to match(/Valid: ✅/)
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

      output = Aidp::OutputLogger.capture_output do
        config_command.run_status([])
      end
      expect(output).to match(/Available Backups:/)
    end
  end

  describe "#run_clean" do
    it "cleans old backups successfully" do
      allow(migrator).to receive(:clean_backups).and_return({
        success: true,
        message: "Cleaned 5 old backups",
        deleted_count: 5
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_clean(["--keep", "10"])
      end
      expect(output).to match(/✅ Cleaned 5 old backups/)
    end

    it "uses default keep count when not specified" do
      allow(migrator).to receive(:clean_backups).with(10).and_return({
        success: true,
        message: "Cleaned 0 old backups",
        deleted_count: 0
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_clean([])
      end
      expect(output).to match(/✅ Cleaned 0 old backups/)
    end

    it "handles clean failure" do
      allow(migrator).to receive(:clean_backups).and_return({
        success: false,
        message: "Clean failed"
      })

      output = Aidp::OutputLogger.capture_output do
        config_command.run_clean([])
      end
      expect(output).to match(/❌ Clean failed/)
        .and raise_error(SystemExit)
    end
  end

  describe "#run_init" do
    it "initializes configuration with minimal template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "minimal"])
      end
      expect(output).to match(/✅ Configuration initialized/)
    end

    it "initializes configuration with production template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "production"])
      end
      expect(output).to match(/✅ Configuration initialized/)
    end

    it "initializes configuration with development template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "development"])
      end
      expect(output).to match(/✅ Configuration initialized/)
    end

    it "creates backup before overwriting existing configuration" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(migrator).to receive(:create_backup).and_return({
        success: true,
        backup_file: "/tmp/backup.yml"
      })
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "minimal", "--force"])
      end
      expect(output).to match(/📁 Existing config backed up to: \/tmp\/backup\.yml/)
    end

    it "refuses to overwrite existing configuration without force" do
      allow(validator).to receive(:config_exists?).and_return(true)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "minimal"])
      end
      expect(output).to match(/❌ Configuration file already exists/)
        .and raise_error(SystemExit)
    end

    it "handles missing template" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(false)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "nonexistent"])
      end
      expect(output).to match(/❌ Template not found: nonexistent/)
        .and raise_error(SystemExit)
    end

    it "handles initialization failure" do
      allow(validator).to receive(:config_exists?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp).and_raise(StandardError.new("Copy failed"))

      output = Aidp::OutputLogger.capture_output do
        config_command.run_init(["--template", "minimal"])
      end
      expect(output).to match(/❌ Failed to initialize configuration: Copy failed/)
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

      output = Aidp::OutputLogger.capture_output do
        config_command.run_show([])
      end
      expect(output).to match(/Configuration Summary:/)
    end

    it "shows configuration in YAML format" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_return({test: "value"})

      output = Aidp::OutputLogger.capture_output do
        config_command.run_show(["--format", "yaml"])
      end
      expect(output).to match(/test: value/)
    end

    it "shows configuration in JSON format" do
      allow(validator).to receive(:config_exists?).and_return(true)
      allow(loader).to receive(:load_config).and_return({test: "value"})

      output = Aidp::OutputLogger.capture_output do
        config_command.run_show(["--format", "json"])
      end
      expect(output).to match(/"test": "value"/)
    end

    it "handles missing configuration file" do
      allow(validator).to receive(:config_exists?).and_return(false)

      output = Aidp::OutputLogger.capture_output do
        config_command.run_show([])
      end
      expect(output).to match(/❌ No configuration file found/)
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
      output = Aidp::OutputLogger.capture_output do
        config_command.show_help
      end
      expect(output).to match(/AIDP Configuration Management/)
    end

    it "displays usage information" do
      output = Aidp::OutputLogger.capture_output do
        config_command.show_help
      end
      expect(output).to match(/Usage: aidp config <command>/)
    end

    it "displays available commands" do
      output = Aidp::OutputLogger.capture_output do
        config_command.show_help
      end
      expect(output).to match(/migrate.*validate.*backup.*restore.*status.*clean.*init.*show.*help/m)
    end

    it "displays examples" do
      output = Aidp::OutputLogger.capture_output do
        config_command.show_help
      end
      expect(output).to match(/Examples:/)
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
      output = Aidp::OutputLogger.capture_output do
        config_command.run([])
      end
      expect(output).to match(/Unknown command: /)
    end

    it "handles nil command arguments" do
      output = Aidp::OutputLogger.capture_output do
        config_command.run([nil])
      end
      expect(output).to match(/Unknown command: /)
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
