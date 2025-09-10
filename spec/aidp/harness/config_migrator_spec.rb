# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/config_migrator"

RSpec.describe Aidp::Harness::ConfigMigrator do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, "aidp.yml") }
  let(:legacy_config_file) { File.join(project_dir, ".aidp.yml") }
  let(:backup_dir) { File.join(project_dir, ".aidp", "backups") }
  let(:migrator) { described_class.new(project_dir) }

  before do
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(backup_dir)
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "initialization" do
    it "creates migrator successfully" do
      expect(migrator).to be_a(described_class)
      expect(migrator.instance_variable_get(:@project_dir)).to eq(project_dir)
      expect(migrator.instance_variable_get(:@config_file)).to eq(config_file)
      expect(migrator.instance_variable_get(:@legacy_config_file)).to eq(legacy_config_file)
    end
  end

  describe "legacy migration" do
    let(:legacy_config) do
      {
        "provider" => "cursor",
        "retry_count" => 3,
        "timeout" => 300,
        "max_tokens" => 100000
      }
    end

    before do
      File.write(legacy_config_file, YAML.dump(legacy_config))
    end

    it "migrates from legacy configuration" do
      result = migrator.migrate_from_legacy

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
      expect(result[:backup_file]).to be_a(String)
      expect(File.exist?(config_file)).to be true
    end

    it "creates backup before migration" do
      result = migrator.migrate_from_legacy(backup: true)

      expect(result[:success]).to be true
      expect(result[:backup_file]).to be_a(String)
      expect(File.exist?(result[:backup_file])).to be true
    end

    it "skips backup when requested" do
      result = migrator.migrate_from_legacy(backup: false)

      expect(result[:success]).to be true
      expect(result[:backup_file]).to be_nil
    end

    it "converts legacy configuration correctly" do
      migrator.migrate_from_legacy

      new_config = YAML.load_file(config_file)

      expect(new_config["harness"]["default_provider"]).to eq("cursor")
      expect(new_config["harness"]["max_retries"]).to eq(3)
      expect(new_config["harness"]["request_timeout"]).to eq(300)
      expect(new_config["providers"]["cursor"]["max_tokens"]).to eq(100000)
    end

    it "handles missing legacy configuration" do
      File.delete(legacy_config_file)

      result = migrator.migrate_from_legacy

      expect(result[:success]).to be false
      expect(result[:message]).to include("No legacy configuration found")
    end
  end

  describe "harness format migration" do
    let(:old_harness_config) do
      {
        "harness" => "cursor",
        "retry_count" => 2,
        "timeout" => 180,
        "provider" => "claude"
      }
    end

    before do
      File.write(config_file, YAML.dump(old_harness_config))
    end

    it "migrates harness format" do
      result = migrator.migrate_harness_format

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "converts old harness format correctly" do
      migrator.migrate_harness_format

      new_config = YAML.load_file(config_file)

      expect(new_config["harness"]["default_provider"]).to eq("cursor")
      expect(new_config["harness"]["max_retries"]).to eq(2)
      expect(new_config["harness"]["request_timeout"]).to eq(180)
      expect(new_config["providers"]["claude"]).to be_a(Hash)
    end
  end

  describe "provider configuration migration" do
    let(:old_provider_config) do
      {
        "harness" => {
          "default_provider" => "cursor"
        },
        "providers" => {
          "cursor" => "cursor-default",
          "claude" => {
            "type" => "api",
            "models" => ["claude-3-5-sonnet-20241022"]
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(old_provider_config))
    end

    it "migrates provider configurations" do
      result = migrator.migrate_provider_configs

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "converts provider configurations correctly" do
      migrator.migrate_provider_configs

      new_config = YAML.load_file(config_file)

      expect(new_config["providers"]["cursor"]).to be_a(Hash)
      expect(new_config["providers"]["cursor"]["models"]).to eq(["cursor-default"])
      expect(new_config["providers"]["claude"]["type"]).to eq("api")
    end
  end

  describe "version-specific migration" do
    let(:legacy_config) do
      {
        "provider" => "cursor",
        "retry_count" => 3
      }
    end

    before do
      File.write(legacy_config_file, YAML.dump(legacy_config))
    end

    it "migrates from version 1.0" do
      result = migrator.migrate_from_version("1.0")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "migrates from version 1.x" do
      result = migrator.migrate_from_version("1.x")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "handles unknown version" do
      result = migrator.migrate_from_version("unknown")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Unknown version")
    end
  end

  describe "auto migration" do
    it "migrates from legacy when legacy config exists" do
      legacy_config = {"provider" => "cursor"}
      File.write(legacy_config_file, YAML.dump(legacy_config))

      result = migrator.auto_migrate

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "migrates harness format when needed" do
      old_config = {"harness" => "cursor"}
      File.write(config_file, YAML.dump(old_config))

      result = migrator.auto_migrate

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully migrated")
    end

    it "reports no migration needed when config is up to date" do
      new_config = {
        "harness" => {
          "default_provider" => "cursor"
        },
        "providers" => {
          "cursor" => {
            "type" => "package"
          }
        }
      }
      File.write(config_file, YAML.dump(new_config))

      result = migrator.auto_migrate

      expect(result[:success]).to be true
      expect(result[:message]).to include("already up to date")
    end

    it "handles no configuration found" do
      result = migrator.auto_migrate

      expect(result[:success]).to be false
      expect(result[:message]).to include("No configuration found")
    end
  end

  describe "migration detection" do
    it "detects legacy configuration needs migration" do
      legacy_config = {"provider" => "cursor"}
      File.write(config_file, YAML.dump(legacy_config))

      expect(migrator.needs_migration?).to be true
    end

    it "detects old harness format needs migration" do
      old_config = {"harness" => "cursor"}
      File.write(config_file, YAML.dump(old_config))

      expect(migrator.needs_migration?).to be true
    end

    it "detects new configuration does not need migration" do
      new_config = {
        "harness" => {
          "default_provider" => "cursor"
        },
        "providers" => {
          "cursor" => {
            "type" => "package"
          }
        }
      }
      File.write(config_file, YAML.dump(new_config))

      expect(migrator.needs_migration?).to be false
    end
  end

  describe "backup management" do
    let(:test_config) do
      {
        "harness" => {
          "default_provider" => "cursor"
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(test_config))
    end

    it "creates backup successfully" do
      result = migrator.create_backup

      expect(result[:success]).to be true
      expect(result[:backup_file]).to be_a(String)
      expect(File.exist?(result[:backup_file])).to be true
    end

    it "skips backup when requested" do
      result = migrator.create_backup(false)

      expect(result[:success]).to be true
      expect(result[:backup_file]).to be_nil
    end

    it "handles backup failure gracefully" do
      # Make backup directory read-only
      FileUtils.chmod(0o444, backup_dir)

      result = migrator.create_backup

      expect(result[:success]).to be false
      expect(result[:message]).to include("Failed to create backup")

      # Restore permissions
      FileUtils.chmod(0o755, backup_dir)
    end

    it "lists available backups" do
      # Create some backup files
      backup1 = File.join(backup_dir, "aidp_config_backup_20240101_120000.yml")
      backup2 = File.join(backup_dir, "aidp_config_backup_20240102_120000.yml")

      File.write(backup1, "test1")
      File.write(backup2, "test2")

      backups = migrator.list_backups

      expect(backups).to have(2).items
      expect(backups.first[:filename]).to include("20240102")
      expect(backups.last[:filename]).to include("20240101")
    end

    it "cleans old backups" do
      # Create more backups than keep limit
      (1..15).each do |i|
        backup_file = File.join(backup_dir, "aidp_config_backup_2024010#{i}_120000.yml")
        File.write(backup_file, "test#{i}")
      end

      result = migrator.clean_backups(10)

      expect(result[:success]).to be true
      expect(result[:deleted_count]).to eq(5)

      backups = migrator.list_backups
      expect(backups).to have(10).items
    end
  end

  describe "restore functionality" do
    let(:backup_config) do
      {
        "harness" => {
          "default_provider" => "claude"
        }
      }
    end

    it "restores from backup successfully" do
      # Create backup file
      backup_file = File.join(backup_dir, "test_backup.yml")
      File.write(backup_file, YAML.dump(backup_config))

      # Create current config
      current_config = {"harness" => {"default_provider" => "cursor"}}
      File.write(config_file, YAML.dump(current_config))

      result = migrator.restore_from_backup(backup_file)

      expect(result[:success]).to be true
      expect(result[:message]).to include("Successfully restored")

      # Verify config was restored
      restored_config = YAML.load_file(config_file)
      expect(restored_config["harness"]["default_provider"]).to eq("claude")
    end

    it "creates backup of current config before restore" do
      # Create backup file
      backup_file = File.join(backup_dir, "test_backup.yml")
      File.write(backup_file, YAML.dump(backup_config))

      # Create current config
      current_config = {"harness" => {"default_provider" => "cursor"}}
      File.write(config_file, YAML.dump(current_config))

      result = migrator.restore_from_backup(backup_file)

      expect(result[:success]).to be true
      expect(result[:current_backup]).to be_a(String)
      expect(File.exist?(result[:current_backup])).to be true
    end

    it "handles missing backup file" do
      result = migrator.restore_from_backup("/nonexistent/backup.yml")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Backup file not found")
    end
  end

  describe "migration status" do
    it "reports status for legacy configuration" do
      legacy_config = {"provider" => "cursor"}
      File.write(legacy_config_file, YAML.dump(legacy_config))

      status = migrator.get_migration_status

      expect(status[:has_config]).to be false
      expect(status[:has_legacy_config]).to be true
      expect(status[:needs_migration]).to be true
      expect(status[:config_version]).to eq("legacy")
    end

    it "reports status for current configuration" do
      current_config = {
        "harness" => {
          "default_provider" => "cursor"
        }
      }
      File.write(config_file, YAML.dump(current_config))

      status = migrator.get_migration_status

      expect(status[:has_config]).to be true
      expect(status[:has_legacy_config]).to be false
      expect(status[:needs_migration]).to be false
      expect(status[:config_version]).to eq("2.0")
    end

    it "reports status for no configuration" do
      status = migrator.get_migration_status

      expect(status[:has_config]).to be false
      expect(status[:has_legacy_config]).to be false
      expect(status[:needs_migration]).to be false
      expect(status[:config_version]).to eq("unknown")
    end
  end

  describe "configuration conversion" do
    it "converts legacy configuration correctly" do
      legacy_config = {
        "provider" => "cursor",
        "retry_count" => 3,
        "timeout" => 300,
        "max_tokens" => 100000
      }

      converted = migrator.send(:convert_legacy_to_new, legacy_config)

      expect(converted["harness"]["default_provider"]).to eq("cursor")
      expect(converted["harness"]["max_retries"]).to eq(3)
      expect(converted["harness"]["request_timeout"]).to eq(300)
      expect(converted["providers"]["cursor"]["max_tokens"]).to eq(100000)
    end

    it "converts old harness format correctly" do
      old_config = {
        "harness" => "cursor",
        "retry_count" => 2,
        "timeout" => 180,
        "provider" => "claude"
      }

      converted = migrator.send(:convert_to_new_harness_format, old_config)

      expect(converted["harness"]["default_provider"]).to eq("cursor")
      expect(converted["harness"]["max_retries"]).to eq(2)
      expect(converted["harness"]["request_timeout"]).to eq(180)
      expect(converted["providers"]["claude"]).to be_a(Hash)
    end

    it "converts provider configurations correctly" do
      old_config = {
        "providers" => {
          "cursor" => "cursor-default",
          "claude" => {
            "type" => "api",
            "models" => ["claude-3-5-sonnet-20241022"]
          }
        }
      }

      converted = migrator.send(:convert_provider_configs, old_config)

      expect(converted["providers"]["cursor"]).to be_a(Hash)
      expect(converted["providers"]["cursor"]["models"]).to eq(["cursor-default"])
      expect(converted["providers"]["claude"]["type"]).to eq("api")
    end
  end
end
