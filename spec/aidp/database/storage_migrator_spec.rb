# frozen_string_literal: true

require "spec_helper"
require "aidp/database/storage_migrator"
require "aidp/database"
require "aidp/config_paths"

RSpec.describe Aidp::Database::StorageMigrator do
  let(:temp_dir) { Dir.mktmpdir}
  let(:migrator) { described_class.new(project_dir: temp_dir)}
  let(:aidp_dir) { File.join(temp_dir, ".aidp")}

  before do
    FileUtils.mkdir_p(aidp_dir)
  end

  after do
    Aidp::Database.close(temp_dir) if Aidp::Database.connection?(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#migration_needed?" do
    context "when no file storage exists" do
      it "returns false" do
        expect(migrator.migration_needed?).to be false
      end
    end

    context "when checkpoint file exists" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), "step: test\n")
      end

      it "returns true" do
        expect(migrator.migration_needed?).to be true
      end
    end

    context "when tasks file exists" do
      before do
        File.write(File.join(aidp_dir, "tasks.json"), '{"tasks":[]}')
      end

      it "returns true" do
        expect(migrator.migration_needed?).to be true
      end
    end
  end

  describe "#already_migrated?" do
    context "when database is empty" do
      it "returns false" do
        expect(migrator.already_migrated?).to be false
      end
    end

    context "when database has data" do
      before do
        Aidp::Database.initialize!(temp_dir)
        db = Aidp::Database.connection(temp_dir)
        db.execute("INSERT INTO checkpoints (project_dir, step, status) VALUES (?, ?, ?)",
          [temp_dir, "test", "completed"])
      end

      it "returns true" do
        expect(migrator.already_migrated?).to be true
      end
    end
  end

  describe "#migrate!" do
    context "when no file storage exists" do
      it "returns skipped status" do
        result = migrator.migrate!

        expect(result[:status]).to eq(:skipped)
        expect(result[:reason]).to include("No file-based storage")
      end
    end

    context "with checkpoint file" do
      before do
        File.write(
          File.join(aidp_dir, "checkpoint.yml"),
          YAML.dump("step" => "analyze", "status" => "completed")
        )
      end

      it "migrates checkpoint data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:checkpoints_migrated]).to eq(1)
      end
    end

    context "with tasks file" do
      before do
        tasks = {
          tasks: [
            {title: "Task 1", status: "pending"},
            {title: "Task 2", status: "completed"}
          ]
       }
        File.write(File.join(aidp_dir, "tasks.json"), JSON.generate(tasks))
      end

      it "migrates task data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:tasks_migrated]).to eq(2)
      end
    end

    context "with progress files" do
      before do
        progress_dir = File.join(aidp_dir, "progress")
        FileUtils.mkdir_p(progress_dir)
        File.write(
          File.join(progress_dir, "execute.yml"),
          YAML.dump("current_step" => "step1", "status" => "running")
        )
      end

      it "migrates progress data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:progress_migrated]).to eq(1)
      end
    end

    context "with harness state files" do
      before do
        harness_dir = File.join(aidp_dir, "harness")
        FileUtils.mkdir_p(harness_dir)
        File.write(
          File.join(harness_dir, "execute_state.json"),
          JSON.generate(provider: "claude", status: "active")
        )
      end

      it "migrates harness state" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:harness_states_migrated]).to eq(1)
      end
    end

    context "with provider info files" do
      before do
        providers_dir = File.join(aidp_dir, "providers")
        FileUtils.mkdir_p(providers_dir)
        File.write(
          File.join(providers_dir, "claude_info.yml"),
          YAML.dump("provider" => "claude", "cli_available" => true)
        )
      end

      it "migrates provider info" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:provider_info_migrated]).to eq(1)
      end
    end

    context "in dry run mode" do
      let(:migrator) { described_class.new(project_dir: temp_dir, dry_run: true)}

      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), YAML.dump("step" => "test"))
      end

      it "does not modify database" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:dry_run]).to be true
        expect(migrator.already_migrated?).to be false
      end
    end
  end

  describe "#create_backup" do
    before do
      File.write(File.join(aidp_dir, "test.txt"), "test content")
    end

    it "creates backup directory with contents" do
      backup_dir = migrator.create_backup

      expect(File.exist?(backup_dir)).to be true
      expect(File.exist?(File.join(backup_dir, "test.txt"))).to be true
    end
  end

  describe "#cleanup_old_storage!" do
    before do
      # Create some files to clean up
      File.write(File.join(aidp_dir, "checkpoint.yml"), "test")
      File.write(File.join(aidp_dir, "tasks.json"), "{}")
      File.write(File.join(aidp_dir, "aidp.yml"), "config: true")

      # Initialize database with some data
      Aidp::Database.initialize!(temp_dir)
      db = Aidp::Database.connection(temp_dir)
      db.execute("INSERT INTO checkpoints (project_dir, step, status) VALUES (?, ?, ?)",
        [temp_dir, "test", "completed"])
    end

    it "removes old storage files" do
      migrator.cleanup_old_storage!

      expect(File.exist?(File.join(aidp_dir, "checkpoint.yml"))).to be false
      expect(File.exist?(File.join(aidp_dir, "tasks.json"))).to be false
    end

    it "keeps config file by default" do
      migrator.cleanup_old_storage!

      expect(File.exist?(File.join(aidp_dir, "aidp.yml"))).to be true
    end

    it "removes config file when requested" do
      migrator.cleanup_old_storage!(keep_config: false)

      expect(File.exist?(File.join(aidp_dir, "aidp.yml"))).to be false
    end
  end
end
