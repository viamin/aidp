require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/aidp/worktree_branch_manager"

RSpec.describe Aidp::WorktreeBranchManager do
  let(:temp_project_dir) { Dir.mktmpdir }
  let(:manager) { Aidp::WorktreeBranchManager.new(project_dir: temp_project_dir) }
  let(:pr_number) { 42 }
  let(:head_branch) { "pr-#{pr_number}-feature" }
  let(:base_branch) { "main" }

  before do
    Dir.chdir(temp_project_dir) do
      system("git", "init", "-b", "main", out: File::NULL, err: File::NULL)
      system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL, err: File::NULL)
      system("git", "config", "commit.gpgsign", "false", out: File::NULL, err: File::NULL)
      system("touch", "README.md")
      system("git", "add", "README.md", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", out: File::NULL, err: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(temp_project_dir)
  end

  describe "#find_worktree" do
    context "when a worktree exists" do
      before do
        Dir.chdir(temp_project_dir) do
          system("git worktree add -b feature/test-branch .worktrees/test-branch", out: File::NULL, err: File::NULL)
        end
      end

      it "returns the worktree path when a worktree for the branch exists" do
        result = manager.find_worktree(branch: "feature/test-branch")
        expect(result).to match(%r{/\.worktrees/test-branch$})
        expect(File.directory?(result)).to be true
      end
    end
  end

  describe "#create_worktree" do
    context "when creating a new worktree" do
      it "creates a worktree for the specified branch" do
        worktree_path = manager.create_worktree(branch: "feature/new-branch")

        expect(worktree_path).to match(%r{/\.worktrees/feature_new-branch$})
        expect(File.directory?(worktree_path)).to be true

        Dir.chdir(worktree_path) do
          branch_name = `git rev-parse --abbrev-ref HEAD`.strip
          expect(branch_name).to eq("feature/new-branch")
        end
      end

      it "returns existing worktree when one already exists" do
        first_worktree = manager.create_worktree(branch: "feature/existing-branch")
        second_worktree = manager.create_worktree(branch: "feature/existing-branch")

        expect(first_worktree).to eq(second_worktree)
      end

      it "ensures .worktrees directory exists" do
        manager.create_worktree(branch: "feature/new-branch")
        worktrees_dir = File.join(temp_project_dir, ".worktrees")
        expect(File.directory?(worktrees_dir)).to be true
      end
    end
  end

  describe "registry operations" do
    let(:registry_path) { File.join(temp_project_dir, ".aidp", "worktrees.json") }
    let(:pr_registry_path) { File.join(temp_project_dir, ".aidp", "pr_worktrees.json") }

    before do
      allow(Aidp).to receive(:log_warn)
    end

    it "creates a registry file when creating a worktree" do
      manager.create_worktree(branch: "feature/registry-test")

      expect(File.exist?(registry_path)).to be true

      registry_data = JSON.parse(File.read(registry_path))
      expect(registry_data).to be_a(Array)

      registry_entry = registry_data.find { |w| w["branch"] == "feature/registry-test" }
      expect(registry_entry).not_to be_nil
      expect(registry_entry["path"]).to match(%r{/\.worktrees/feature_registry-test$})
      expect(registry_entry["created_at"]).to be_a(Integer)
    end

    it "tracks multiple worktrees in registry" do
      manager.create_worktree(branch: "feature/first-branch")
      manager.create_worktree(branch: "feature/second-branch")

      registry_data = JSON.parse(File.read(registry_path))
      expect(registry_data.length).to eq(2)

      branch_names = registry_data.map { |w| w["branch"] }
      expect(branch_names).to include("feature/first-branch", "feature/second-branch")
    end

    it "falls back gracefully on invalid registry JSON" do
      FileUtils.mkdir_p(File.dirname(registry_path))
      File.write(registry_path, "{not_json")

      expect(manager.send(:read_registry)).to eq([])
      expect(Aidp).to have_received(:log_warn)
    end

    it "reads pr registry entry and returns existing worktree" do
      FileUtils.mkdir_p(File.join(temp_project_dir, ".worktrees"))
      existing_path = File.join(temp_project_dir, ".worktrees", "pr_123")
      FileUtils.mkdir_p(existing_path)
      FileUtils.mkdir_p(File.dirname(pr_registry_path))
      File.write(pr_registry_path, JSON.dump([{"pr_number" => 123, "path" => existing_path}]))

      result = manager.find_or_create_pr_worktree(pr_number: 123, head_branch: "feature/pr-123")
      expect(result).to eq(existing_path)
    end

    it "handles invalid pr registry JSON" do
      FileUtils.mkdir_p(File.dirname(pr_registry_path))
      File.write(pr_registry_path, "{oops")

      expect(manager.send(:read_pr_registry)).to eq([])
      expect(Aidp).to have_received(:log_warn)
    end
  end

  describe "#find_or_create_pr_worktree" do
    context "when no existing worktree" do
      it "creates a new worktree" do
        result = manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch)

        expect(result).to match(%r{/\.worktrees/#{head_branch}-pr-#{pr_number}$})
        expect(File.directory?(result)).to be true

        # Verify git branch is correct (should be the unique PR branch)
        Dir.chdir(result) do
          branch_name = `git rev-parse --abbrev-ref HEAD`.strip
          expect(branch_name).to eq("#{head_branch}-pr-#{pr_number}")
        end
      end

      it "creates worktree with specified base branch" do
        custom_base_branch = "development"

        # First create the base branch
        Dir.chdir(temp_project_dir) do
          system("git checkout -b #{custom_base_branch}", out: File::NULL, err: File::NULL)
          system("touch BASE_README.md")
          system("git add BASE_README.md", out: File::NULL, err: File::NULL)
          system("git commit -m 'Base branch commit'", out: File::NULL, err: File::NULL)
          system("git checkout main", out: File::NULL, err: File::NULL)
        end

        result = manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch, base_branch: custom_base_branch)

        expect(result).to match(%r{/\.worktrees/#{head_branch}-pr-#{pr_number}$})
        expect(File.directory?(result)).to be true

        # Verify base branch contents are present
        Dir.chdir(result) do
          expect(File.exist?("BASE_README.md")).to be true
          branch_name = `git rev-parse --abbrev-ref HEAD`.strip
          expect(branch_name).to eq("#{head_branch}-pr-#{pr_number}")
        end
      end
    end

    context "when existing worktree" do
      before do
        # Create a worktree first
        @first_worktree = manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch)
      end

      it "returns existing worktree path" do
        second_worktree = manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch)

        expect(second_worktree).to eq(@first_worktree)
      end

      it "creates new worktree for different PR with same branch name" do
        different_pr_number = 99
        different_worktree = manager.find_or_create_pr_worktree(pr_number: different_pr_number, head_branch: head_branch)

        expect(different_worktree).not_to eq(@first_worktree)
      end
    end

    context "error cases" do
      it "raises error for invalid branch name" do
        expect {
          manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: "../invalid/branch")
        }.to raise_error(Aidp::WorktreeBranchManager::WorktreeCreationError)
      end

      it "raises error when no PR number is provided" do
        expect {
          manager.find_or_create_pr_worktree(head_branch: head_branch)
        }.to raise_error(ArgumentError)
      end
    end

    context "PR-specific registry" do
      it "updates PR-specific registry during worktree creation" do
        worktree_path = manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch)

        pr_registry_path = File.join(temp_project_dir, ".aidp", "pr_worktrees.json")
        expect(File.exist?(pr_registry_path)).to be true

        pr_registry_content = JSON.parse(File.read(pr_registry_path))
        pr_entry = pr_registry_content.find { |entry| entry["pr_number"] == pr_number }

        expect(pr_entry).not_to be_nil
        expect(pr_entry["path"]).to eq(worktree_path)
        expect(pr_entry["head_branch"]).to eq(head_branch)
        expect(pr_entry["base_branch"]).to eq("main")
        expect(pr_entry["created_at"]).to be_a(Integer)
      end
    end

    context "logging" do
      before do
        allow(Aidp).to receive(:log_debug)
      end

      it "logs worktree creation and lookup" do
        manager.find_or_create_pr_worktree(pr_number: pr_number, head_branch: head_branch)

        expect(Aidp).to have_received(:log_debug)
          .with("worktree_branch_manager", "finding_or_creating_pr_worktree",
            pr_number: pr_number,
            head_branch: head_branch,
            base_branch: "main")
      end
    end
  end
end
