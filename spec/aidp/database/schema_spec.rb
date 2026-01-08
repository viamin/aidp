# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Database::Schema do
  describe ".versions" do
    it "returns array of migration versions" do
      versions = described_class.versions

      expect(versions).to be_an(Array)
      expect(versions).to include(1)
    end

    it "returns versions in order" do
      versions = described_class.versions

      expect(versions).to eq(versions.sort)
    end
  end

  describe ".latest_version" do
    it "returns highest migration version" do
      expect(described_class.latest_version).to be >= 1
    end
  end

  describe ".migration_sql" do
    it "returns SQL for valid version" do
      sql = described_class.migration_sql(1)

      expect(sql).to be_a(String)
      expect(sql).to include("CREATE TABLE")
    end

    it "returns nil for invalid version" do
      sql = described_class.migration_sql(9999)

      expect(sql).to be_nil
    end
  end

  describe "V1_INITIAL schema" do
    let(:sql) {described_class::V1_INITIAL}

    it "creates schema_migrations table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS schema_migrations")
    end

    it "creates checkpoints table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS checkpoints")
    end

    it "creates checkpoint_history table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS checkpoint_history")
    end

    it "creates tasks table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS tasks")
    end

    it "creates progress table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS progress")
    end

    it "creates harness_state table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS harness_state")
    end

    it "creates worktrees table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS worktrees")
    end

    it "creates workstreams table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS workstreams")
    end

    it "creates workstream_events table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS workstream_events")
    end

    it "creates watch_state table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS watch_state")
    end

    it "creates evaluations table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS evaluations")
    end

    it "creates provider_metrics table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS provider_metrics")
    end

    it "creates provider_rate_limits table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS provider_rate_limits")
    end

    it "creates secrets_registry table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS secrets_registry")
    end

    it "creates prompt_archive table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS prompt_archive")
    end

    it "creates provider_info_cache table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS provider_info_cache")
    end

    it "creates model_cache table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS model_cache")
    end

    it "creates deprecated_models table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS deprecated_models")
    end

    it "creates background_jobs table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS background_jobs")
    end

    it "creates auto_update_checkpoints table" do
      expect(sql).to include("CREATE TABLE IF NOT EXISTS auto_update_checkpoints")
    end

    it "includes proper indexes" do
      expect(sql).to include("CREATE INDEX IF NOT EXISTS idx_checkpoints_project")
      expect(sql).to include("CREATE INDEX IF NOT EXISTS idx_tasks_project")
      expect(sql).to include("CREATE INDEX IF NOT EXISTS idx_tasks_status")
      expect(sql).to include("CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_project_mode")
    end
  end

  describe "MIGRATIONS constant" do
    it "is frozen" do
      expect(described_class::MIGRATIONS).to be_frozen
    end

    it "contains version 1" do
      expect(described_class::MIGRATIONS).to have_key(1)
    end
  end
end
