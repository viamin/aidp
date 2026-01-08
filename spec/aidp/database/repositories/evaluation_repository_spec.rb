# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::EvaluationRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_eval_repo_test")}
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

  describe "#store" do
    it "stores an evaluation" do
      result = repository.store(
        id: "eval_001",
        rating: "good",
        target_type: "plan",
        target_id: "issue_123",
        feedback: "Great work!"
      )

      expect(result[:success]).to be true
      expect(result[:id]).to eq("eval_001")
    end
  end

  describe "#load" do
    it "loads an evaluation" do
      repository.store(id: "eval_002", rating: "bad", target_type: "review", target_id: "pr_456")

      eval = repository.load("eval_002")

      expect(eval[:id]).to eq("eval_002")
      expect(eval[:rating]).to eq("bad")
    end
  end

  describe "#list" do
    before do
      repository.store(id: "e1", rating: "good", target_type: "plan", target_id: "1")
      repository.store(id: "e2", rating: "bad", target_type: "review", target_id: "2")
      repository.store(id: "e3", rating: "good", target_type: "plan", target_id: "3")
    end

    it "lists all evaluations" do
      expect(repository.list.size).to eq(3)
    end

    it "filters by rating" do
      expect(repository.list(rating: "good").size).to eq(2)
    end

    it "filters by target_type" do
      expect(repository.list(target_type: "plan").size).to eq(2)
    end
  end

  describe "#stats" do
    before do
      repository.store(id: "s1", rating: "good", target_type: "x", target_id: "1")
      repository.store(id: "s2", rating: "good", target_type: "x", target_id: "2")
      repository.store(id: "s3", rating: "bad", target_type: "y", target_id: "3")
    end

    it "returns statistics" do
      stats = repository.stats

      expect(stats[:total]).to eq(3)
      expect(stats[:by_rating][:good]).to eq(2)
      expect(stats[:by_rating][:bad]).to eq(1)
    end
  end

  describe "#delete" do
    it "deletes an evaluation" do
      repository.store(id: "to_delete", rating: "neutral", target_type: "x", target_id: "1")

      repository.delete("to_delete")

      expect(repository.load("to_delete")).to be_nil
    end
  end

  describe "#any?" do
    it "returns false when empty" do
      expect(repository.any?).to be false
    end

    it "returns true when has evaluations" do
      repository.store(id: "e1", rating: "good", target_type: "x", target_id: "1")

      expect(repository.any?).to be true
    end
  end
end
