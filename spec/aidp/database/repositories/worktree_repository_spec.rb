# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::WorktreeRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_worktree_repo_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#register" do
    it "registers a standard worktree" do
      wt = repository.register(slug: "feature-123", path: "/tmp/wt", branch: "feature/123")

      expect(wt[:slug]).to eq("feature-123")
      expect(wt[:path]).to eq("/tmp/wt")
      expect(wt[:branch]).to eq("feature/123")
      expect(wt[:worktree_type]).to eq("standard")
    end
  end

  describe "#register_pr" do
    it "registers a PR worktree" do
      wt = repository.register_pr(
        pr_number: 456,
        path: "/tmp/pr-456",
        base_branch: "main",
        head_branch: "feature/pr-456"
      )

      expect(wt[:pr_number]).to eq(456)
      expect(wt[:worktree_type]).to eq("pr")
      expect(wt[:base_branch]).to eq("main")
    end
  end

  describe "#find_by_slug" do
    it "finds worktree by slug" do
      repository.register(slug: "test-wt", path: "/tmp/test", branch: "test")

      wt = repository.find_by_slug("test-wt")

      expect(wt[:slug]).to eq("test-wt")
    end

    it "returns nil for non-existent slug" do
      expect(repository.find_by_slug("nonexistent")).to be_nil
    end
  end

  describe "#find_by_pr" do
    it "finds worktree by PR number" do
      repository.register_pr(pr_number: 789, path: "/tmp/pr", base_branch: "main", head_branch: "fix")

      wt = repository.find_by_pr(789)

      expect(wt[:pr_number]).to eq(789)
    end
  end

  describe "#list" do
    before do
      repository.register(slug: "std-1", path: "/tmp/std1", branch: "std1")
      repository.register_pr(pr_number: 100, path: "/tmp/pr100", base_branch: "main", head_branch: "pr100")
    end

    it "lists all worktrees" do
      expect(repository.list.size).to eq(2)
    end

    it "filters by type" do
      expect(repository.list(type: "standard").size).to eq(1)
      expect(repository.list(type: "pr").size).to eq(1)
    end
  end

  describe "#unregister" do
    it "removes worktree" do
      repository.register(slug: "to-remove", path: "/tmp/x", branch: "x")

      repository.unregister("to-remove")

      expect(repository.find_by_slug("to-remove")).to be_nil
    end
  end
end
