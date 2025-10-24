# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Worktree Fast Test Adapter" do
  let(:project_dir) { Dir.mktmpdir("aidp_worktree_fast") }

  before do
    # Use fast worktree adapter
    stub_worktree_for_fast_tests

    # Create minimal .aidp directory for registry
    FileUtils.mkdir_p(File.join(project_dir, ".aidp"))
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "create" do
    it "creates worktree directory structure without real git operations" do
      result = Aidp::Worktree.create(
        slug: "test-feature",
        project_dir: project_dir,
        task: "Test task"
      )

      expect(result[:slug]).to eq("test-feature")
      expect(result[:branch]).to eq("aidp/test-feature")
      expect(Dir.exist?(result[:path])).to be true

      # Verify .git file was created (simulates worktree)
      git_file = File.join(result[:path], ".git")
      expect(File.exist?(git_file)).to be true
      expect(File.read(git_file)).to include("gitdir:")

      # Verify .aidp directory exists
      aidp_dir = File.join(result[:path], ".aidp")
      expect(Dir.exist?(aidp_dir)).to be true
    end

    it "registers the worktree in the registry" do
      Aidp::Worktree.create(
        slug: "test-feature",
        project_dir: project_dir
      )

      info = Aidp::Worktree.info(slug: "test-feature", project_dir: project_dir)
      expect(info).not_to be_nil
      expect(info[:slug]).to eq("test-feature")
      expect(info[:branch]).to eq("aidp/test-feature")
    end

    it "raises error for duplicate slug" do
      Aidp::Worktree.create(slug: "duplicate", project_dir: project_dir)

      expect {
        Aidp::Worktree.create(slug: "duplicate", project_dir: project_dir)
      }.to raise_error(Aidp::Worktree::WorktreeExists)
    end
  end

  describe "remove" do
    it "removes worktree directory and registry entry" do
      Aidp::Worktree.create(slug: "remove-me", project_dir: project_dir)
      worktree_path = File.join(project_dir, ".worktrees", "remove-me")

      expect(Dir.exist?(worktree_path)).to be true

      Aidp::Worktree.remove(slug: "remove-me", project_dir: project_dir)

      expect(Dir.exist?(worktree_path)).to be false
      expect(Aidp::Worktree.info(slug: "remove-me", project_dir: project_dir)).to be_nil
    end

    it "does not attempt to delete git branch in fast mode" do
      # This spec verifies delete_branch flag is safely ignored in fast mode
      Aidp::Worktree.create(slug: "branch-test", project_dir: project_dir)

      expect {
        Aidp::Worktree.remove(
          slug: "branch-test",
          project_dir: project_dir,
          delete_branch: true
        )
      }.not_to raise_error
    end
  end

  describe "list" do
    it "lists all registered worktrees" do
      Aidp::Worktree.create(slug: "feature-a", project_dir: project_dir)
      Aidp::Worktree.create(slug: "feature-b", project_dir: project_dir)

      list = Aidp::Worktree.list(project_dir: project_dir)

      expect(list.size).to eq(2)
      slugs = list.map { |ws| ws[:slug] }
      expect(slugs).to include("feature-a", "feature-b")
    end
  end

  describe "exists?" do
    it "returns true for existing worktree" do
      Aidp::Worktree.create(slug: "exists", project_dir: project_dir)

      expect(Aidp::Worktree.exists?(slug: "exists", project_dir: project_dir)).to be true
    end

    it "returns false for non-existent worktree" do
      expect(Aidp::Worktree.exists?(slug: "nope", project_dir: project_dir)).to be false
    end
  end

  describe "no git dependency" do
    it "works without a git repository" do
      # This would normally fail because project_dir is not a git repo
      # But with the fast adapter, it should succeed
      expect {
        Aidp::Worktree.create(slug: "no-git-check", project_dir: project_dir)
      }.not_to raise_error
    end
  end
end
