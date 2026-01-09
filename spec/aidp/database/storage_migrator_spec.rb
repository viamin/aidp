# frozen_string_literal: true

require "spec_helper"
require "aidp/database/storage_migrator"
require "aidp/database"
require "aidp/config_paths"

RSpec.describe Aidp::Database::StorageMigrator do
  let(:temp_dir) { Dir.mktmpdir }
  let(:migrator) { described_class.new(project_dir: temp_dir) }
  let(:aidp_dir) { File.join(temp_dir, ".aidp") }

  before do
    FileUtils.mkdir_p(aidp_dir)
  end

  after do
    Aidp::Database.close(temp_dir) if Aidp::Database.exists?(temp_dir)
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
        Aidp::Database::Migrations.run!(temp_dir)
        db = Aidp::Database.connection(temp_dir)
        db.execute("INSERT INTO checkpoints (project_dir, step_name, status) VALUES (?, ?, ?)",
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

    context "with workstream files" do
      before do
        workstreams_dir = File.join(aidp_dir, "workstreams", "feature-123")
        FileUtils.mkdir_p(workstreams_dir)
        File.write(
          File.join(workstreams_dir, "state.json"),
          JSON.generate(slug: "feature-123", status: "active", task: "Implement feature")
        )
      end

      it "migrates workstream data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:workstreams_migrated]).to eq(1)
      end
    end

    context "with worktree files" do
      before do
        File.write(
          File.join(aidp_dir, "worktrees.json"),
          JSON.generate([{path: "/tmp/worktree", branch: "feature", slug: "ws-1"}])
        )
      end

      it "migrates worktree data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:worktrees_migrated]).to eq(1)
      end
    end

    context "with evaluation files" do
      before do
        evaluations_dir = File.join(aidp_dir, "evaluations")
        FileUtils.mkdir_p(evaluations_dir)
        File.write(
          File.join(evaluations_dir, "eval_123.json"),
          JSON.generate(id: "eval_123", rating: "good", comment: "Nice work")
        )
      end

      it "migrates evaluation data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:evaluations_migrated]).to eq(1)
      end
    end

    context "with model cache files" do
      before do
        model_cache_dir = File.join(aidp_dir, "model_cache")
        FileUtils.mkdir_p(model_cache_dir)
        File.write(
          File.join(model_cache_dir, "models.json"),
          JSON.generate(claude: [{id: "claude-3", name: "Claude 3"}])
        )
      end

      it "migrates model cache data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:model_cache_migrated]).to be >= 1
      end
    end

    context "with secrets registry" do
      before do
        security_dir = File.join(aidp_dir, "security")
        FileUtils.mkdir_p(security_dir)
        File.write(
          File.join(security_dir, "secrets_registry.json"),
          JSON.generate(secrets: [{name: "API_KEY", env_var: "API_KEY", description: "API key"}])
        )
      end

      it "migrates secrets data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:secrets_migrated]).to eq(1)
      end
    end

    context "with prompt archive files" do
      before do
        prompt_archive_dir = File.join(aidp_dir, "prompt_archive")
        FileUtils.mkdir_p(prompt_archive_dir)
        File.write(
          File.join(prompt_archive_dir, "analyze_20240101_120000.md"),
          "# Prompt\nAnalyze this code"
        )
      end

      it "migrates prompt archive data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:prompts_migrated]).to eq(1)
      end
    end

    context "with job files" do
      before do
        jobs_dir = File.join(aidp_dir, "jobs")
        FileUtils.mkdir_p(jobs_dir)
        File.write(
          File.join(jobs_dir, "job_123_metadata.json"),
          JSON.generate(id: "job_123", job_type: "execute", status: "completed")
        )
      end

      it "migrates job data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:jobs_migrated]).to eq(1)
      end
    end

    context "with provider metrics files" do
      before do
        File.write(
          File.join(aidp_dir, "provider_metrics.yml"),
          YAML.dump("claude" => {"success_count" => 10, "error_count" => 1})
        )
      end

      it "migrates provider metrics data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:provider_metrics_migrated]).to eq(1)
      end
    end

    context "with watch state files" do
      before do
        watch_dir = File.join(aidp_dir, "watch")
        FileUtils.mkdir_p(watch_dir)
        File.write(
          File.join(watch_dir, "owner_repo.yml"),
          YAML.dump("repository" => "owner/repo", "plans" => {"1" => {summary: "Plan"}})
        )
      end

      it "migrates watch state data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:watch_states_migrated]).to eq(1)
      end
    end

    context "with deprecated models file" do
      before do
        File.write(
          File.join(aidp_dir, "deprecated_models.json"),
          JSON.generate([{provider: "openai", model: "gpt-3", replacement: "gpt-4"}])
        )
      end

      it "migrates deprecated models data" do
        result = migrator.migrate!(backup: false)

        expect(result[:status]).to eq(:success)
        expect(result[:stats][:deprecated_models_migrated]).to eq(1)
      end
    end

    context "in dry run mode" do
      let(:migrator) { described_class.new(project_dir: temp_dir, dry_run: true) }

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

  describe "#file_storage_exists?" do
    context "when no file storage exists" do
      it "returns false" do
        expect(migrator.file_storage_exists?).to be false
      end
    end

    context "when checkpoint file exists" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), "step: test")
      end

      it "returns true" do
        expect(migrator.file_storage_exists?).to be true
      end
    end

    context "when progress directory exists" do
      before do
        FileUtils.mkdir_p(File.join(aidp_dir, "progress"))
        File.write(File.join(aidp_dir, "progress", "execute.yml"), "step: test")
      end

      it "returns true" do
        expect(migrator.file_storage_exists?).to be true
      end
    end
  end

  describe "#migrated_files" do
    context "when files exist" do
      before do
        File.write(File.join(aidp_dir, "checkpoint.yml"), "test")
        File.write(File.join(aidp_dir, "tasks.json"), "{}")
        progress_dir = File.join(aidp_dir, "progress")
        FileUtils.mkdir_p(progress_dir)
        File.write(File.join(progress_dir, "execute.yml"), "test")
      end

      it "returns list of migratable files" do
        files = migrator.migrated_files

        expect(files).to include(File.join(aidp_dir, "checkpoint.yml"))
        expect(files).to include(File.join(aidp_dir, "tasks.json"))
      end
    end
  end

  describe "#cleanup_old_storage!" do
    before do
      # Create some files to clean up
      File.write(File.join(aidp_dir, "checkpoint.yml"), "test")
      File.write(File.join(aidp_dir, "tasks.json"), "{}")
      File.write(File.join(aidp_dir, "aidp.yml"), "config: true")

      # Initialize database with some data
      Aidp::Database::Migrations.run!(temp_dir)
      db = Aidp::Database.connection(temp_dir)
      db.execute("INSERT INTO checkpoints (project_dir, step_name, status) VALUES (?, ?, ?)",
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
