# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "aidp/evaluations"

RSpec.describe Aidp::Evaluations::EvaluationStorage do
  let(:temp_dir) { Dir.mktmpdir }
  let(:storage) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#store" do
    it "stores an evaluation record" do
      record = Aidp::Evaluations::EvaluationRecord.new(rating: "good")
      result = storage.store(record)

      expect(result[:success]).to be true
      expect(result[:id]).to eq(record.id)
      expect(File.exist?(result[:file_path])).to be true
    end

    it "creates evaluations directory" do
      record = Aidp::Evaluations::EvaluationRecord.new(rating: "good")
      storage.store(record)

      expect(Dir.exist?(File.join(temp_dir, ".aidp", "evaluations"))).to be true
    end

    it "updates the index file" do
      record = Aidp::Evaluations::EvaluationRecord.new(rating: "good")
      storage.store(record)

      index_file = File.join(temp_dir, ".aidp", "evaluations", "index.json")
      expect(File.exist?(index_file)).to be true

      index = JSON.parse(File.read(index_file))
      expect(index["entries"].size).to eq(1)
      expect(index["entries"][0]["id"]).to eq(record.id)
    end
  end

  describe "#load" do
    it "loads an evaluation by id" do
      record = Aidp::Evaluations::EvaluationRecord.new(
        rating: "good",
        comment: "Test comment"
      )
      storage.store(record)

      loaded = storage.load(record.id)

      expect(loaded).to be_a(Aidp::Evaluations::EvaluationRecord)
      expect(loaded.id).to eq(record.id)
      expect(loaded.rating).to eq("good")
      expect(loaded.comment).to eq("Test comment")
    end

    it "returns nil for non-existent id" do
      expect(storage.load("non_existent")).to be_nil
    end
  end

  describe "#list" do
    before do
      # Create several records with different ratings
      @records = [
        Aidp::Evaluations::EvaluationRecord.new(rating: "good", target_type: "prompt"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "bad", target_type: "work_unit"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "good", target_type: "work_loop"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "neutral", target_type: "prompt")
      ]
      @records.each { |r| storage.store(r) }
    end

    it "returns all evaluations" do
      list = storage.list
      expect(list.size).to eq(4)
    end

    it "limits results" do
      list = storage.list(limit: 2)
      expect(list.size).to eq(2)
    end

    it "filters by rating" do
      list = storage.list(rating: "good")
      expect(list.size).to eq(2)
      expect(list.all? { |r| r.rating == "good" }).to be true
    end

    it "filters by target_type" do
      list = storage.list(target_type: "prompt")
      expect(list.size).to eq(2)
      expect(list.all? { |r| r.target_type == "prompt" }).to be true
    end

    it "returns empty array when no evaluations exist" do
      empty_storage = described_class.new(project_dir: Dir.mktmpdir)
      expect(empty_storage.list).to eq([])
    end
  end

  describe "#stats" do
    before do
      [
        Aidp::Evaluations::EvaluationRecord.new(rating: "good", target_type: "prompt"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "good", target_type: "work_unit"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "bad", target_type: "work_loop"),
        Aidp::Evaluations::EvaluationRecord.new(rating: "neutral", target_type: "prompt")
      ].each { |r| storage.store(r) }
    end

    it "returns total count" do
      stats = storage.stats
      expect(stats[:total]).to eq(4)
    end

    it "returns counts by rating" do
      stats = storage.stats
      expect(stats[:by_rating][:good]).to eq(2)
      expect(stats[:by_rating][:bad]).to eq(1)
      expect(stats[:by_rating][:neutral]).to eq(1)
    end

    it "returns counts by target_type" do
      stats = storage.stats
      expect(stats[:by_target_type]["prompt"]).to eq(2)
      expect(stats[:by_target_type]["work_unit"]).to eq(1)
      expect(stats[:by_target_type]["work_loop"]).to eq(1)
    end

    it "returns empty stats when no evaluations exist" do
      empty_storage = described_class.new(project_dir: Dir.mktmpdir)
      stats = empty_storage.stats

      expect(stats[:total]).to eq(0)
      expect(stats[:by_rating][:good]).to eq(0)
    end
  end

  describe "#delete" do
    it "deletes an evaluation" do
      record = Aidp::Evaluations::EvaluationRecord.new(rating: "good")
      storage.store(record)

      result = storage.delete(record.id)

      expect(result[:success]).to be true
      expect(storage.load(record.id)).to be_nil
    end

    it "removes from index" do
      record = Aidp::Evaluations::EvaluationRecord.new(rating: "good")
      storage.store(record)
      storage.delete(record.id)

      stats = storage.stats
      expect(stats[:total]).to eq(0)
    end

    it "returns success for non-existent id" do
      result = storage.delete("non_existent")
      expect(result[:success]).to be true
    end
  end

  describe "#clear" do
    it "removes all evaluations" do
      3.times { storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good")) }

      result = storage.clear

      expect(result[:success]).to be true
      expect(result[:count]).to eq(3)
      expect(storage.any?).to be false
    end

    it "returns zero count when no evaluations exist" do
      result = storage.clear

      expect(result[:success]).to be true
      expect(result[:count]).to eq(0)
    end
  end

  describe "#any?" do
    it "returns false when no evaluations exist" do
      expect(storage.any?).to be false
    end

    it "returns true when evaluations exist" do
      storage.store(Aidp::Evaluations::EvaluationRecord.new(rating: "good"))
      expect(storage.any?).to be true
    end
  end
end
