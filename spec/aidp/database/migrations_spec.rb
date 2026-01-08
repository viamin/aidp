# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Migrations do
  let(:temp_dir) { Dir.mktmpdir("aidp_migrations_test")}
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db")}

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe ".run!" do
    it "applies initial migration" do
      applied = described_class.run!(temp_dir)

      expect(applied).to include(1)
    end

    it "creates schema_migrations table" do
      described_class.run!(temp_dir)

      db = Aidp::Database.connection(temp_dir)
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r["name"]}

      expect(tables).to include("schema_migrations")
    end

    it "creates all expected tables" do
      described_class.run!(temp_dir)

      db = Aidp::Database.connection(temp_dir)
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r["name"]}

      expected_tables = %w[
        schema_migrations
        checkpoints
        checkpoint_history
        tasks
        progress
        harness_state
        worktrees
        workstreams
        workstream_events
        watch_state
        evaluations
        provider_metrics
        provider_rate_limits
        secrets_registry
        prompt_archive
        provider_info_cache
        model_cache
        deprecated_models
        background_jobs
        auto_update_checkpoints
      ]

      expected_tables.each do |table|
        expect(tables).to include(table), "Expected table #{table} to exist"
      end
    end

    it "records migration in schema_migrations" do
      described_class.run!(temp_dir)

      db = Aidp::Database.connection(temp_dir)
      version = db.get_first_value("SELECT MAX(version) FROM schema_migrations")

      expect(version).to eq(1)
    end

    it "returns empty array if already migrated" do
      described_class.run!(temp_dir)

      applied = described_class.run!(temp_dir)

      expect(applied).to be_empty
    end

    it "is idempotent" do
      3.times { described_class.run!(temp_dir)}

      db = Aidp::Database.connection(temp_dir)
      count = db.get_first_value("SELECT COUNT(*) FROM schema_migrations")

      expect(count).to eq(1)
    end
  end

  describe ".pending?" do
    it "returns true before migrations run" do
      Aidp::Database.connection(temp_dir)

      expect(described_class.pending?(temp_dir)).to be true
    end

    it "returns false after migrations run" do
      described_class.run!(temp_dir)

      expect(described_class.pending?(temp_dir)).to be false
    end
  end

  describe ".pending_versions" do
    it "returns all versions before migration" do
      Aidp::Database.connection(temp_dir)

      pending = described_class.pending_versions(temp_dir)

      expect(pending).to include(1)
    end

    it "returns empty array after migration" do
      described_class.run!(temp_dir)

      pending = described_class.pending_versions(temp_dir)

      expect(pending).to be_empty
    end
  end

  describe "indexes" do
    before do
      described_class.run!(temp_dir)
    end

    it "creates checkpoints index" do
      db = Aidp::Database.connection(temp_dir)
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index'").map { |r| r["name"]}

      expect(indexes).to include("idx_checkpoints_project")
    end

    it "creates tasks indexes" do
      db = Aidp::Database.connection(temp_dir)
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index'").map { |r| r["name"]}

      expect(indexes).to include("idx_tasks_project")
      expect(indexes).to include("idx_tasks_status")
    end

    it "creates unique indexes" do
      db = Aidp::Database.connection(temp_dir)
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index'").map { |r| r["name"]}

      expect(indexes).to include("idx_progress_project_mode")
      expect(indexes).to include("idx_workstreams_project_slug")
    end
  end
end
