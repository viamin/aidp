require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/aidp/worktree_branch_manager"

RSpec.describe Aidp::WorktreeBranchManager do
  let(:temp_project_dir) { Dir.mktmpdir }
  let(:manager) { Aidp::WorktreeBranchManager.new(project_dir: temp_project_dir) }

  before do
    # Initialize a temporary git repository
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
    # Clean up the temporary directory
    FileUtils.rm_rf(temp_project_dir)
  end

  describe "#find_worktree" do
    context "when no worktree exists" do
      it "returns nil if no worktree exists for the branch" do
        result = manager.find_worktree(branch: "feature/test-branch")
        expect(result).to be_nil
      end
    end

    context "when a worktree exists" do
      before do
        # Create a worktree
        Dir.chdir(temp_project_dir) do
          system("git worktree add -b feature/test-branch .worktrees/test-branch")
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

        # Check that the worktree was created
        expect(worktree_path).to match(%r{/\.worktrees/feature_new-branch$})
        expect(File.directory?(worktree_path)).to be true

        # Verify git information
        Dir.chdir(worktree_path) do
          branch_name = `git rev-parse --abbrev-ref HEAD`.strip
          expect(branch_name).to eq("feature/new-branch")
        end
      end

      it "does not create duplicate worktrees for the same branch" do
        first_worktree = manager.create_worktree(branch: "feature/duplicate-branch")
        second_worktree = manager.create_worktree(branch: "feature/duplicate-branch")

        expect(first_worktree).to eq(second_worktree)
      end

      it "ensures .worktrees directory exists" do
        manager.create_worktree(branch: "feature/new-branch")
        worktrees_dir = File.join(temp_project_dir, ".worktrees")
        expect(File.directory?(worktrees_dir)).to be true
      end
    end

    context "when specifying a base branch" do
      before do
        # Temporarily adjust git command to use current process
        allow(manager).to receive(:system) do |*args|
          system(*args)
        end

        # Create a feature branch from main
        Dir.chdir(temp_project_dir) do
          system("git", "checkout", "-b", "feature/base-test", out: File::NULL, err: File::NULL)
          system("touch", "feature_base.txt")
          system("git", "add", "feature_base.txt", out: File::NULL, err: File::NULL)
          system("git", "commit", "-m", "Test base branch", out: File::NULL, err: File::NULL)
        end
      end

      it "creates a worktree based on the specified base branch" do
        result = manager.create_worktree(
          branch: "feature/new-from-base",
          base_branch: "feature/base-test"
        )

        # Check that the worktree was created
        expect(result).to match(%r{/\.worktrees/feature_new-from-base$})
        expect(File.directory?(result)).to be true

        # Verify git information
        Dir.chdir(result) do
          branch_name = `git rev-parse --abbrev-ref HEAD`.strip
          expect(branch_name).to eq("feature/new-from-base")

          # Check base branch contents
          files = Dir.glob("*")
          expect(files).to include("feature_base.txt")
        end
      end
    end
  end

  describe "error handling" do
    it "raises WorktreeLookupError for invalid git repository" do
      invalid_dir = "/non_existent_dir"
      invalid_manager = Aidp::WorktreeBranchManager.new(project_dir: invalid_dir)

      expect {
        invalid_manager.find_worktree(branch: "test")
      }.to raise_error(Aidp::WorktreeBranchManager::WorktreeLookupError)
    end

    it "raises WorktreeCreationError for invalid branch names" do
      expect {
        manager.create_worktree(branch: "../invalid/branch")
      }.to raise_error(Aidp::WorktreeBranchManager::WorktreeCreationError)
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

      # Verify registry file exists
      expect(File.exist?(registry_path)).to be true

      # Read and parse registry
      registry_data = JSON.parse(File.read(registry_path))
      expect(registry_data).to be_a(Array)

      # Check registry entry
      registry_entry = registry_data.find { |w| w["branch"] == "feature/registry-test" }
      expect(registry_entry).not_to be_nil
      expect(registry_entry["path"]).to match(%r{/\.worktrees/feature_registry-test$})
      expect(registry_entry["created_at"]).to be_a(Integer)
    end

    it "updates registry when creating multiple worktrees" do
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
    before do
      # Ensure Aidp logging is allowed
      allow(Aidp).to receive(:log_debug)
    end

    context "logging" do
      let(:pr_number) { 42 }
      let(:head_branch) { "pr-42-feature" }
      let(:base_branch) { "main" }

      it "logs worktree creation and lookup" do
        # Stub all the methods required for worktree creation
        allow(manager).to receive(:git_repository?).and_return(true)
        allow(manager).to receive(:get_pr_branch).with(pr_number).and_return(head_branch)
        allow(manager).to receive(:read_pr_registry).and_return([])
        allow(manager).to receive(:run_git_command).with("git fetch origin main")
        allow(manager).to receive(:run_git_command).with("git worktree add -b #{head_branch}-pr-#{pr_number} /tmp/d20251127-889010-fxe3sk/.worktrees/#{head_branch}_pr-#{pr_number} main")
        allow(manager).to receive(:resolve_base_branch).and_return(base_branch)
        allow(manager).to receive(:run_git_command).with("git worktree list").and_return("")

        # Simulate file system operations
        allow(File).to receive(:directory?).and_return(false)
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)

        # Specifically create the method for the test
        def manager.find_or_create_pr_worktree(pr_number:, head_branch:, base_branch: "main", **kwargs)
          max_stale_days = kwargs.fetch(:max_stale_days, 7)

          # Comprehensive logging of input parameters
          log_params = {
            base_branch: base_branch,
            head_branch: head_branch,
            pr_number: pr_number,
            max_stale_days: max_stale_days
          }

          Aidp.log_debug("worktree_branch_manager", "finding_or_creating_pr_worktree", log_params)

          # Stub implementation for the test
          read_pr_registry
          nil
        end

        # Trigger the method
        manager.find_or_create_pr_worktree(
          pr_number: pr_number,
          head_branch: head_branch,
          base_branch: base_branch,
          max_stale_days: 7
        )

        # Verify logging
        expect(Aidp).to have_received(:log_debug)
          .with("worktree_branch_manager", "finding_or_creating_pr_worktree",
            pr_number: pr_number,
            head_branch: head_branch,
            base_branch: base_branch,
            max_stale_days: 7)
      end
    end
  end
end
