# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../../../../lib/aidp/setup/devcontainer/backup_manager"

RSpec.describe Aidp::Setup::Devcontainer::BackupManager do
  let(:project_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(project_dir) }
  let(:source_file) { File.join(project_dir, ".devcontainer", "devcontainer.json") }
  let(:backup_dir) { File.join(project_dir, ".aidp", "backups", "devcontainer") }

  before do
    FileUtils.mkdir_p(File.dirname(source_file))
    File.write(source_file, '{"name": "test"}')
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#create_backup" do
    it "creates a backup of the source file" do
      backup_path = manager.create_backup(source_file)

      expect(File.exist?(backup_path)).to be true
      expect(File.read(backup_path)).to eq('{"name": "test"}')
    end

    it "creates backup in correct directory" do
      backup_path = manager.create_backup(source_file)

      expect(backup_path).to start_with(backup_dir)
    end

    it "creates backup with timestamp in filename" do
      backup_path = manager.create_backup(source_file)

      filename = File.basename(backup_path)
      expect(filename).to match(/devcontainer-\d{8}_\d{6}\.json/)
    end

    it "creates backup directory if it doesn't exist" do
      expect(File.directory?(backup_dir)).to be false

      manager.create_backup(source_file)

      expect(File.directory?(backup_dir)).to be true
    end

    it "raises error if source file doesn't exist" do
      expect {
        manager.create_backup("/nonexistent/file.json")
      }.to raise_error(Aidp::Setup::Devcontainer::BackupManager::BackupError, /does not exist/)
    end

    it "saves metadata when provided" do
      metadata = {reason: "wizard_update", version: "1.0"}

      backup_path = manager.create_backup(source_file, metadata)
      metadata_path = "#{backup_path}.meta"

      expect(File.exist?(metadata_path)).to be true
      saved_metadata = JSON.parse(File.read(metadata_path))
      expect(saved_metadata["reason"]).to eq("wizard_update")
      expect(saved_metadata["version"]).to eq("1.0")
    end

    it "does not create metadata file when no metadata provided" do
      backup_path = manager.create_backup(source_file)
      metadata_path = "#{backup_path}.meta"

      expect(File.exist?(metadata_path)).to be false
    end

    it "returns path to backup file" do
      backup_path = manager.create_backup(source_file)

      expect(backup_path).to be_a(String)
      expect(File.exist?(backup_path)).to be true
    end
  end

  describe "#list_backups" do
    it "returns empty array when no backups exist" do
      backups = manager.list_backups

      expect(backups).to be_empty
    end

    it "lists all backup files" do
      manager.create_backup(source_file)
      sleep 1.1  # Ensure different timestamps (1 second resolution)
      manager.create_backup(source_file)

      backups = manager.list_backups

      expect(backups.size).to eq(2)
    end

    it "returns backup info with path, filename, size" do
      manager.create_backup(source_file)

      backups = manager.list_backups
      backup = backups.first

      expect(backup).to have_key(:path)
      expect(backup).to have_key(:filename)
      expect(backup).to have_key(:size)
      expect(backup).to have_key(:created_at)
      expect(backup).to have_key(:timestamp)
    end

    it "includes metadata when available" do
      metadata = {reason: "test"}
      manager.create_backup(source_file, metadata)

      backups = manager.list_backups
      backup = backups.first

      expect(backup[:metadata]).to include("reason" => "test")
    end

    it "sorts backups by timestamp, newest first" do
      first_backup = manager.create_backup(source_file)
      sleep 1.1
      second_backup = manager.create_backup(source_file)

      backups = manager.list_backups

      expect(backups.first[:path]).to eq(second_backup)
      expect(backups.last[:path]).to eq(first_backup)
    end

    it "handles backups without metadata gracefully" do
      manager.create_backup(source_file)

      backups = manager.list_backups

      expect(backups.first).not_to have_key(:metadata)
    end

    it "handles invalid metadata JSON gracefully" do
      backup_path = manager.create_backup(source_file)
      File.write("#{backup_path}.meta", "invalid json {")

      backups = manager.list_backups

      expect(backups).not_to be_empty
      expect(backups.first).not_to have_key(:metadata)
    end
  end

  describe "#restore_backup" do
    let(:target_file) { File.join(project_dir, ".devcontainer", "devcontainer.json") }

    it "restores backup to target location" do
      backup_path = manager.create_backup(source_file)

      File.write(target_file, '{"name": "modified"}')
      manager.restore_backup(backup_path, target_file, create_backup: false)

      expect(File.read(target_file)).to eq('{"name": "test"}')
    end

    it "creates backup of target before restoring" do
      backup_path = manager.create_backup(source_file)
      sleep 1.1  # Ensure unique timestamp for next backup
      File.write(target_file, '{"name": "modified"}')

      initial_backup_count = manager.list_backups.size
      manager.restore_backup(backup_path, target_file, create_backup: true)

      expect(manager.list_backups.size).to eq(initial_backup_count + 1)
    end

    it "skips creating backup when create_backup is false" do
      backup_path = manager.create_backup(source_file)
      File.write(target_file, '{"name": "modified"}')

      initial_backup_count = manager.list_backups.size
      manager.restore_backup(backup_path, target_file, create_backup: false)

      expect(manager.list_backups.size).to eq(initial_backup_count)
    end

    it "creates target directory if it doesn't exist" do
      backup_path = manager.create_backup(source_file)
      new_target = File.join(project_dir, "new_dir", "devcontainer.json")

      manager.restore_backup(backup_path, new_target, create_backup: false)

      expect(File.exist?(new_target)).to be true
    end

    it "raises error if backup file doesn't exist" do
      expect {
        manager.restore_backup("/nonexistent/backup.json", target_file)
      }.to raise_error(Aidp::Setup::Devcontainer::BackupManager::BackupError, /does not exist/)
    end

    it "returns true on success" do
      backup_path = manager.create_backup(source_file)

      result = manager.restore_backup(backup_path, target_file, create_backup: false)

      expect(result).to be true
    end

    it "adds restore metadata to pre-restore backup" do
      backup_path = manager.create_backup(source_file)
      File.write(target_file, '{"name": "modified"}')

      manager.restore_backup(backup_path, target_file, create_backup: true)

      latest = manager.latest_backup
      expect(latest[:metadata]["reason"]).to eq("pre_restore")
      expect(latest[:metadata]["restoring_from"]).to eq(backup_path)
    end
  end

  describe "#cleanup_old_backups" do
    it "keeps specified number of backups" do
      5.times do |i|
        manager.create_backup(source_file, {index: i})
        sleep 1.1
      end

      manager.cleanup_old_backups(3)

      expect(manager.list_backups.size).to eq(3)
    end

    it "deletes oldest backups first" do
      backups = []
      3.times do |i|
        backups << manager.create_backup(source_file, {index: i})
        sleep 1.1
      end

      manager.cleanup_old_backups(1)

      remaining = manager.list_backups
      expect(remaining.size).to eq(1)
      expect(remaining.first[:path]).to eq(backups.last)
    end

    it "returns number of deleted backups" do
      5.times { manager.create_backup(source_file); sleep 1.1 }

      deleted_count = manager.cleanup_old_backups(2)

      expect(deleted_count).to eq(3)
    end

    it "returns 0 when no backups to delete" do
      3.times { manager.create_backup(source_file); sleep 1.1 }

      deleted_count = manager.cleanup_old_backups(10)

      expect(deleted_count).to eq(0)
    end

    it "deletes metadata files along with backups" do
      manager.create_backup(source_file, {reason: "test"})
      sleep 1.1
      manager.create_backup(source_file)

      manager.cleanup_old_backups(1)

      metadata_files = Dir.glob(File.join(backup_dir, "*.meta"))
      expect(metadata_files).to be_empty
    end

    it "handles missing metadata files gracefully" do
      manager.create_backup(source_file)
      sleep 1.1
      manager.create_backup(source_file)

      expect {
        manager.cleanup_old_backups(1)
      }.not_to raise_error
    end
  end

  describe "#latest_backup" do
    it "returns nil when no backups exist" do
      expect(manager.latest_backup).to be_nil
    end

    it "returns most recent backup" do
      first = manager.create_backup(source_file)
      sleep 1.1
      second = manager.create_backup(source_file)

      latest = manager.latest_backup

      expect(latest[:path]).to eq(second)
    end

    it "returns backup info hash" do
      manager.create_backup(source_file)

      latest = manager.latest_backup

      expect(latest).to have_key(:path)
      expect(latest).to have_key(:filename)
      expect(latest).to have_key(:size)
    end
  end

  describe "#total_backup_size" do
    it "returns 0 when no backups exist" do
      expect(manager.total_backup_size).to eq(0)
    end

    it "calculates total size of all backups" do
      manager.create_backup(source_file)
      sleep 1.1
      manager.create_backup(source_file)

      size = manager.total_backup_size

      expect(size).to be > 0
      expect(size).to eq(File.size(source_file) * 2)
    end

    it "includes metadata files in size calculation" do
      manager.create_backup(source_file, {reason: "test"})

      size = manager.total_backup_size

      expect(size).to be > File.size(source_file)
    end

    it "returns 0 when backup directory doesn't exist" do
      new_manager = described_class.new(Dir.mktmpdir)

      expect(new_manager.total_backup_size).to eq(0)
    end
  end

  describe "backup filename format" do
    it "uses consistent timestamp format" do
      backup_path = manager.create_backup(source_file)
      filename = File.basename(backup_path)

      # Format: devcontainer-YYYYMMDD_HHMMSS.json
      expect(filename).to match(/^devcontainer-\d{8}_\d{6}\.json$/)
    end

    it "creates unique filenames for sequential backups" do
      first = manager.create_backup(source_file)
      sleep 1  # Ensure different second
      second = manager.create_backup(source_file)

      expect(File.basename(first)).not_to eq(File.basename(second))
    end
  end

  describe "backup directory structure" do
    it "creates backups in .aidp/backups/devcontainer" do
      backup_path = manager.create_backup(source_file)

      expected_dir = File.join(project_dir, ".aidp", "backups", "devcontainer")
      expect(File.dirname(backup_path)).to eq(expected_dir)
    end
  end
end
