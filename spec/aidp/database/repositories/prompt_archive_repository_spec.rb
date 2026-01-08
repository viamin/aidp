# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::PromptArchiveRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_archive_repo_test")}
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

  describe "#archive" do
    it "archives a prompt" do
      id = repository.archive(step_name: "01_SETUP", content: "# Prompt Content")

      expect(id).to be_a(Integer)
    end
  end

  describe "#recent" do
    before do
      repository.archive(step_name: "step1", content: "content 1")
      repository.archive(step_name: "step2", content: "content 2")
      repository.archive(step_name: "step1", content: "content 3")
    end

    it "returns recent prompts" do
      entries = repository.recent

      expect(entries.size).to eq(3)
    end

    it "filters by step_name" do
      entries = repository.recent(step_name: "step1")

      expect(entries.size).to eq(2)
    end

    it "respects limit" do
      entries = repository.recent(limit: 2)

      expect(entries.size).to eq(2)
    end
  end

  describe "#find" do
    it "finds entry by ID" do
      id = repository.archive(step_name: "test", content: "test content")

      entry = repository.find(id)

      expect(entry[:content]).to eq("test content")
    end
  end

  describe "#latest_for_step" do
    it "returns latest entry for step" do
      repository.archive(step_name: "mystep", content: "old")
      repository.archive(step_name: "mystep", content: "new")

      entry = repository.latest_for_step("mystep")

      expect(entry[:content]).to eq("new")
    end
  end

  describe "#stats" do
    before do
      repository.archive(step_name: "a", content: "x")
      repository.archive(step_name: "a", content: "y")
      repository.archive(step_name: "b", content: "z")
    end

    it "returns statistics" do
      stats = repository.stats

      expect(stats[:total]).to eq(3)
      expect(stats[:by_step]["a"]).to eq(2)
      expect(stats[:by_step]["b"]).to eq(1)
    end
  end

  describe "#search" do
    before do
      repository.archive(step_name: "s", content: "hello world")
      repository.archive(step_name: "s", content: "goodbye world")
      repository.archive(step_name: "s", content: "hello there")
    end

    it "searches content" do
      results = repository.search("hello")

      expect(results.size).to eq(2)
    end
  end
end
