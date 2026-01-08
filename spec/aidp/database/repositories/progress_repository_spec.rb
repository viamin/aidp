# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::ProgressRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_progress_repo_test")}
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db")}
  let(:repository) { described_class.new(project_dir: temp_dir)}

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#get" do
    it "returns empty progress when none exists" do
      progress = repository.get(:execute)

      expect(progress[:mode]).to eq("execute")
      expect(progress[:current_step]).to be_nil
      expect(progress[:steps_completed]).to eq([])
    end

    it "returns stored progress" do
      repository.mark_step_completed(:execute, "01_SETUP")

      progress = repository.get(:execute)

      expect(progress[:steps_completed]).to eq(["01_SETUP"])
    end
  end

  describe "#completed_steps" do
    it "returns empty array initially" do
      expect(repository.completed_steps(:execute)).to eq([])
    end

    it "returns completed steps" do
      repository.mark_step_completed(:execute, "01_SETUP")
      repository.mark_step_completed(:execute, "02_BUILD")

      expect(repository.completed_steps(:execute)).to eq(["01_SETUP", "02_BUILD"])
    end
  end

  describe "#current_step" do
    it "returns nil initially" do
      expect(repository.current_step(:execute)).to be_nil
    end

    it "returns current step" do
      repository.mark_step_in_progress(:execute, "01_SETUP")

      expect(repository.current_step(:execute)).to eq("01_SETUP")
    end
  end

  describe "#step_completed?" do
    it "returns false for incomplete step" do
      expect(repository.step_completed?(:execute, "01_SETUP")).to be false
    end

    it "returns true for completed step" do
      repository.mark_step_completed(:execute, "01_SETUP")

      expect(repository.step_completed?(:execute, "01_SETUP")).to be true
    end
  end

  describe "#mark_step_completed" do
    it "marks step as completed" do
      repository.mark_step_completed(:execute, "01_SETUP")

      expect(repository.step_completed?(:execute, "01_SETUP")).to be true
    end

    it "clears current step" do
      repository.mark_step_in_progress(:execute, "01_SETUP")
      repository.mark_step_completed(:execute, "01_SETUP")

      expect(repository.current_step(:execute)).to be_nil
    end

    it "does not duplicate steps" do
      repository.mark_step_completed(:execute, "01_SETUP")
      repository.mark_step_completed(:execute, "01_SETUP")

      expect(repository.completed_steps(:execute)).to eq(["01_SETUP"])
    end

    it "sets started_at on first completion" do
      repository.mark_step_completed(:execute, "01_SETUP")

      expect(repository.started_at(:execute)).not_to be_nil
    end
  end

  describe "#mark_step_in_progress" do
    it "sets current step" do
      repository.mark_step_in_progress(:execute, "01_SETUP")

      expect(repository.current_step(:execute)).to eq("01_SETUP")
    end

    it "sets started_at" do
      repository.mark_step_in_progress(:execute, "01_SETUP")

      expect(repository.started_at(:execute)).not_to be_nil
    end
  end

  describe "#reset" do
    it "clears all progress" do
      repository.mark_step_completed(:execute, "01_SETUP")
      repository.mark_step_in_progress(:execute, "02_BUILD")

      repository.reset(:execute)

      expect(repository.completed_steps(:execute)).to eq([])
      expect(repository.current_step(:execute)).to be_nil
    end
  end

  describe "mode isolation" do
    it "keeps execute and analyze progress separate" do
      repository.mark_step_completed(:execute, "01_EXECUTE_STEP")
      repository.mark_step_completed(:analyze, "01_ANALYZE_STEP")

      expect(repository.completed_steps(:execute)).to eq(["01_EXECUTE_STEP"])
      expect(repository.completed_steps(:analyze)).to eq(["01_ANALYZE_STEP"])
    end
  end
end
