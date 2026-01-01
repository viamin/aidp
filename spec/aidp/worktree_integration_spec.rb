# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Integration test for real Worktree module (no stubs)
# This ensures production code works with actual git operations
RSpec.describe Aidp::Worktree, "integration with real git", :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_worktree_integration") }

  before do
    # Initialize a real git repository
    Dir.chdir(project_dir) do
      system("git", "init", out: File::NULL, err: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL, err: File::NULL)
      system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "config", "commit.gpgsign", "false", out: File::NULL, err: File::NULL)

      # Create initial commit
      File.write("README.md", "# Test\n")
      system("git", "add", "README.md", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", out: File::NULL, err: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  it "creates a real git worktree" do
    result = described_class.create(
      slug: "real-worktree",
      project_dir: project_dir,
      task: "Real git test"
    )

    expect(result[:slug]).to eq("real-worktree")
    expect(result[:path]).to include(".worktrees/real-worktree")
    expect(Dir.exist?(result[:path])).to be true

    # Verify it's a real git worktree
    git_file = File.join(result[:path], ".git")
    expect(File.exist?(git_file)).to be true

    # Verify branch exists
    branch_exists = Dir.chdir(project_dir) do
      system("git", "show-ref", "--verify", "--quiet", "refs/heads/aidp/real-worktree")
    end
    expect(branch_exists).to be true
  end

  it "removes a real git worktree" do
    described_class.create(slug: "remove-real", project_dir: project_dir)
    worktree_path = File.join(project_dir, ".worktrees", "remove-real")

    expect(Dir.exist?(worktree_path)).to be true

    described_class.remove(slug: "remove-real", project_dir: project_dir)

    expect(Dir.exist?(worktree_path)).to be false
  end

  it "recovers from missing but registered worktree directories" do
    result = described_class.create(slug: "stale-entry", project_dir: project_dir)
    stale_path = result[:path]

    # Simulate manual deletion without deregistering
    FileUtils.rm_rf(stale_path)

    expect {
      described_class.create(slug: "stale-entry", project_dir: project_dir)
    }.not_to raise_error

    described_class.remove(slug: "stale-entry", project_dir: project_dir)
  end

  it "raises error when not in a git repository" do
    non_git_dir = Dir.mktmpdir("non_git")

    begin
      expect {
        described_class.create(slug: "should-fail", project_dir: non_git_dir)
      }.to raise_error(Aidp::Worktree::NotInGitRepo)
    ensure
      FileUtils.rm_rf(non_git_dir)
    end
  end

  describe "remote-only branches" do
    let(:remote_dir) { Dir.mktmpdir("aidp_worktree_remote") }

    before do
      # Create a "remote" bare repository
      Dir.chdir(remote_dir) do
        system("git", "init", "--bare", out: File::NULL, err: File::NULL)
      end

      # Add it as origin to our test repo
      Dir.chdir(project_dir) do
        system("git", "remote", "add", "origin", remote_dir, out: File::NULL, err: File::NULL)
        system("git", "push", "-u", "origin", "master", out: File::NULL, err: File::NULL)
      end
    end

    after do
      FileUtils.rm_rf(remote_dir)
    end

    it "creates worktree from remote branch when branch only exists on origin" do
      # Create a branch on the remote with different content
      clone_dir = Dir.mktmpdir("aidp_worktree_clone")
      begin
        Dir.chdir(clone_dir) do
          system("git", "clone", remote_dir, ".", out: File::NULL, err: File::NULL)
          system("git", "config", "user.name", "Remote User", out: File::NULL, err: File::NULL)
          system("git", "config", "user.email", "remote@example.com", out: File::NULL, err: File::NULL)
          system("git", "config", "commit.gpgsign", "false", out: File::NULL, err: File::NULL)
          system("git", "checkout", "-b", "claude/pr-feature", out: File::NULL, err: File::NULL)
          File.write("pr_changes.txt", "Changes from PR branch\n")
          system("git", "add", "pr_changes.txt", out: File::NULL, err: File::NULL)
          system("git", "commit", "-m", "PR changes", out: File::NULL, err: File::NULL)
          system("git", "push", "origin", "claude/pr-feature", out: File::NULL, err: File::NULL)
        end

        # Now in our main repo, fetch but DON'T checkout the branch
        Dir.chdir(project_dir) do
          system("git", "fetch", "origin", out: File::NULL, err: File::NULL)

          # Verify the local branch does NOT exist
          local_exists = system("git", "show-ref", "--verify", "--quiet", "refs/heads/claude/pr-feature")
          expect(local_exists).to be false

          # Verify the remote branch DOES exist
          remote_exists = system("git", "show-ref", "--verify", "--quiet", "refs/remotes/origin/claude/pr-feature")
          expect(remote_exists).to be true
        end

        # Create worktree with the remote-only branch
        result = described_class.create(
          slug: "pr-123-ci-fix",
          project_dir: project_dir,
          branch: "claude/pr-feature",
          base_branch: nil
        )

        expect(result[:path]).to include(".worktrees/pr-123-ci-fix")
        expect(Dir.exist?(result[:path])).to be true

        # Verify the worktree has the PR's content (not HEAD from master)
        pr_file = File.join(result[:path], "pr_changes.txt")
        expect(File.exist?(pr_file)).to be true
        expect(File.read(pr_file)).to eq("Changes from PR branch\n")

        # Verify the local branch was created
        Dir.chdir(project_dir) do
          local_exists = system("git", "show-ref", "--verify", "--quiet", "refs/heads/claude/pr-feature")
          expect(local_exists).to be true
        end
      ensure
        FileUtils.rm_rf(clone_dir)
        begin
          described_class.remove(slug: "pr-123-ci-fix", project_dir: project_dir)
        rescue Aidp::Worktree::WorktreeNotFound
          # Worktree may not exist if test failed before creation
        end
      end
    end

    it "falls back to HEAD when branch doesn't exist locally or on remote" do
      result = described_class.create(
        slug: "new-branch-test",
        project_dir: project_dir,
        branch: "brand-new-branch",
        base_branch: nil
      )

      expect(result[:path]).to include(".worktrees/new-branch-test")
      expect(Dir.exist?(result[:path])).to be true

      # Verify the branch was created from HEAD (has README but no pr_changes.txt)
      readme_file = File.join(result[:path], "README.md")
      expect(File.exist?(readme_file)).to be true

      described_class.remove(slug: "new-branch-test", project_dir: project_dir)
    end
  end

  describe ".find_by_branch" do
    it "finds worktree by branch name" do
      described_class.create(
        slug: "test-find",
        project_dir: project_dir,
        branch: "feature/test-branch"
      )

      result = described_class.find_by_branch(
        branch: "feature/test-branch",
        project_dir: project_dir
      )

      expect(result).not_to be_nil
      expect(result[:slug]).to eq("test-find")
      expect(result[:branch]).to eq("feature/test-branch")
      expect(result[:active]).to be true
    end

    it "returns nil when branch not found" do
      result = described_class.find_by_branch(
        branch: "nonexistent/branch",
        project_dir: project_dir
      )

      expect(result).to be_nil
    end

    it "returns inactive status when worktree directory is deleted" do
      described_class.create(
        slug: "inactive-test",
        project_dir: project_dir,
        branch: "test/inactive"
      )

      # Delete the worktree directory manually
      worktree_path = File.join(project_dir, ".worktrees", "inactive-test")
      FileUtils.rm_rf(worktree_path)

      result = described_class.find_by_branch(
        branch: "test/inactive",
        project_dir: project_dir
      )

      expect(result).not_to be_nil
      expect(result[:active]).to be false
    end
  end
end
