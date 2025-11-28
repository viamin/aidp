require "spec_helper"
require "aidp/pr_worktree_manager"
require "fileutils"
require "tmpdir"

RSpec.describe Aidp::PRWorktreeManager do
  let(:temp_repo_path) { Dir.mktmpdir }
  let(:pr_number) { 42 }
  let(:base_branch) { "main" }
  let(:head_branch) { "pr-#{pr_number}-feature" }

  before do
    # Setup a dummy git repository
    Dir.chdir(temp_repo_path) do
      system("git init")
      system('git config user.name "Test User"')
      system('git config user.email "test@example.com"')
      system("git checkout -b main")
      system("touch README.md")
      system("git add README.md")
      system('git commit -m "Initial commit"')
    end

    # Set the base repository path to the temporary repo with isolated project directory
    @pr_worktree_manager = Aidp::PRWorktreeManager.new(
      base_repo_path: temp_repo_path,
      project_dir: temp_repo_path
    )
  end

  after do
    # Clean up temporary files and directories
    FileUtils.rm_rf(temp_repo_path)
    if @pr_worktree_manager
      # Clean up any registry files
      FileUtils.rm_f(@pr_worktree_manager.worktree_registry_path)
      FileUtils.rm_f(File.join(temp_repo_path, "pr_worktrees.json"))
    end
  end

  describe "#find_worktree" do
    context "when no worktree exists" do
      it "returns nil for PR number" do
        expect(@pr_worktree_manager.find_worktree(pr_number)).to be_nil
      end

      it "returns nil for branch" do
        expect(@pr_worktree_manager.find_worktree(branch: "non-existent-branch")).to be_nil
      end

      it "raises error when no input provided" do
        expect {
          @pr_worktree_manager.find_worktree
        }.to raise_error(ArgumentError, "Must provide either pr_number or branch")
      end
    end

    context "when a worktree is created" do
      before do
        @created_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
      end

      it "finds existing worktree by PR number" do
        expect(@pr_worktree_manager.find_worktree(pr_number)).to eq(@created_path)
      end

      it "finds existing worktree by base branch" do
        expect(@pr_worktree_manager.find_worktree(branch: base_branch)).to eq(@created_path)
      end

      it "finds existing worktree by head branch" do
        expect(@pr_worktree_manager.find_worktree(branch: head_branch)).to eq(@created_path)
      end

      it "handles partial branch matches correctly" do
        expect(@pr_worktree_manager.find_worktree(branch: "non-matching-branch")).to be_nil
      end
    end

    context "when multiple worktrees exist" do
      before do
        # Add a second branch for testing
        Dir.chdir(temp_repo_path) do
          system("git checkout -b another-base")
          system("touch ANOTHER_README.md")
          system("git add ANOTHER_README.md")
          system('git commit -m "Create another base"')
          system("git checkout main")
        end

        @first_worktree = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
        @second_worktree = @pr_worktree_manager.create_worktree(99, "another-base", "pr-99-feature")
      end

      it "finds the correct worktree for each PR" do
        expect(@pr_worktree_manager.find_worktree(pr_number)).to eq(@first_worktree)
        expect(@pr_worktree_manager.find_worktree(99)).to eq(@second_worktree)
      end

      it "finds worktree by branch name from different PRs" do
        expect(@pr_worktree_manager.find_worktree(branch: base_branch)).to eq(@first_worktree)
        expect(@pr_worktree_manager.find_worktree(branch: "another-base")).to eq(@second_worktree)
      end
    end
  end

  describe "#create_worktree" do
    it "creates a new worktree" do
      worktree_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

      expect(File.exist?(worktree_path)).to be true
      expect(File.directory?(worktree_path)).to be true
    end

    it "raises an error with invalid inputs" do
      expect {
        @pr_worktree_manager.create_worktree(nil, base_branch, head_branch)
      }.to raise_error(ArgumentError, "PR number must be a positive integer")

      expect {
        @pr_worktree_manager.create_worktree(pr_number, nil, head_branch)
      }.to raise_error(ArgumentError, "Base branch cannot be empty")

      expect {
        @pr_worktree_manager.create_worktree(pr_number, base_branch, nil)
      }.to raise_error(ArgumentError, "Head branch cannot be empty")
    end

    it "prevents duplicate worktree creation" do
      first_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
      second_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

      expect(first_path).to eq(second_path)
    end

    it "handles conflicts with existing worktrees" do
      # Create first worktree
      first_worktree = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

      # Create another worktree with different parameters
      second_worktree = @pr_worktree_manager.create_worktree(99, base_branch, "pr-99-feature")

      # Should create different paths
      expect(first_worktree).not_to eq(second_worktree)
    end
  end

  describe "#remove_worktree" do
    context "when worktree exists" do
      before do
        @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
      end

      it "removes the worktree" do
        expect(@pr_worktree_manager.remove_worktree(pr_number)).to be true
        expect(@pr_worktree_manager.find_worktree(pr_number)).to be_nil
      end
    end

    context "when worktree does not exist" do
      it "returns false" do
        expect(@pr_worktree_manager.remove_worktree(pr_number)).to be false
      end
    end
  end

  describe "#list_worktrees" do
    context "when no worktrees exist" do
      it "returns an empty hash" do
        expect(@pr_worktree_manager.list_worktrees).to be_empty
      end
    end

    context "when worktrees exist" do
      before do
        @pr_worktree_manager.create_worktree(42, base_branch, "pr-42-feature")
        @pr_worktree_manager.create_worktree(99, base_branch, "pr-99-feature")
      end

      it "lists all worktrees" do
        listed_worktrees = @pr_worktree_manager.list_worktrees

        expect(listed_worktrees.size).to eq(2)
        expect(listed_worktrees.keys).to include("42", "99")

        listed_worktrees.each do |_, details|
          expect(details).to include("path", "base_branch", "head_branch", "created_at")
        end
      end
    end
  end

  describe "#cleanup_stale_worktrees" do
    context "when stale worktrees exist" do
      before do
        # Create worktrees with timestamps 31 days ago
        past_time = Time.now - (31 * 24 * 60 * 60)
        allow(Time).to receive(:now).and_return(past_time)
        @pr_worktree_manager.create_worktree(42, base_branch, "pr-42-feature")
        @pr_worktree_manager.create_worktree(99, base_branch, "pr-99-feature")
        # Reset time to current for cleanup calculation
        allow(Time).to receive(:now).and_call_original
      end

      it "removes stale worktrees" do
        @pr_worktree_manager.cleanup_stale_worktrees

        expect(@pr_worktree_manager.list_worktrees).to be_empty
      end
    end

    context "when no stale worktrees exist" do
      before do
        # Reset time to current
        allow(Time).to receive(:now).and_call_original
        @pr_worktree_manager.create_worktree(42, base_branch, "pr-42-feature")
      end

      it "does not remove recent worktrees" do
        @pr_worktree_manager.cleanup_stale_worktrees

        expect(@pr_worktree_manager.list_worktrees.size).to eq(1)
      end
    end
  end

  describe "logging" do
    before do
      allow(Aidp).to receive(:log_debug)
      allow(Aidp).to receive(:log_warn)
      allow(Aidp).to receive(:log_error)
    end

    it "logs worktree creation" do
      @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

      expect(Aidp).to have_received(:log_debug)
        .with("pr_worktree_manager", "creating_worktree",
          pr_number: pr_number,
          base_branch: base_branch,
          head_branch: head_branch)

      expect(Aidp).to have_received(:log_debug)
        .with("pr_worktree_manager", "worktree_created",
          path: anything,
          pr_number: pr_number)
    end
  end

  describe "edge cases and error handling" do
    context "when base repository is not a git repository" do
      let(:invalid_repo_path) { Dir.mktmpdir }

      it "raises an error" do
        invalid_pr_worktree_manager = Aidp::PRWorktreeManager.new(
          base_repo_path: invalid_repo_path,
          project_dir: invalid_repo_path
        )

        expect {
          invalid_pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
        }.to raise_error(RuntimeError, /Not a git repository/)
      end
    end

    context "when worktree registry is not writable" do
      let(:read_only_dir) { Dir.mktmpdir }

      before do
        # Make directory read-only
        FileUtils.chmod(0o555, read_only_dir)
      end

      after do
        FileUtils.chmod(0o755, read_only_dir)
        FileUtils.rm_rf(read_only_dir)
      end

      it "handles non-writable registry gracefully" do
        read_only_pr_worktree_manager = Aidp::PRWorktreeManager.new(
          base_repo_path: temp_repo_path,
          project_dir: read_only_dir
        )

        allow(Aidp).to receive(:log_error)
        allow(Aidp).to receive(:log_warn)

        expect {
          read_only_pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
        }.to raise_error(RuntimeError, /Failed to create worktree/)

        # Verify logging
        expect(Aidp).to have_received(:log_error)
          .with("pr_worktree_manager", "worktree_creation_failed",
            hash_including(
              pr_number: pr_number,
              base_branch: base_branch,
              head_branch: head_branch
            ))
      end
    end

    context "with invalid registry file" do
      let(:corrupt_registry_path) { File.join(temp_repo_path, "corrupt_registry.json") }

      before do
        # Create a corrupt JSON file
        File.write(corrupt_registry_path, "{invalid json")
      end

      it "handles corrupt registry gracefully" do
        allow(Aidp).to receive(:log_warn)

        corrupt_pr_worktree_manager = Aidp::PRWorktreeManager.new(
          base_repo_path: temp_repo_path,
          project_dir: temp_repo_path,
          worktree_registry_path: corrupt_registry_path
        )

        expect(corrupt_pr_worktree_manager.list_worktrees).to be_empty
        expect(Aidp).to have_received(:log_warn)
          .with("pr_worktree_manager", "invalid_registry", path: corrupt_registry_path)
      end
    end

    context "with concurrent worktree operations" do
      it "manages multiple worktree creations with locking" do
        # Use Mutex to synchronize worktree registry access
        mutex = Mutex.new

        expect {
          # Simulate concurrent worktree creations
          threads = 5.times.map do |i|
            Thread.new do
              mutex.synchronize do
                @pr_worktree_manager.create_worktree(
                  pr_number + i,
                  base_branch,
                  "pr-#{pr_number + i}-feature"
                )
              end
            end
          end

          # Wait for all threads to complete
          threads.each(&:join)
        }.not_to raise_error
      end

      it "prevents overwriting existing worktrees" do
        first_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

        # Attempt to create another worktree with the same PR number
        duplicate_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)

        expect(first_path).to eq(duplicate_path)
      end
    end

    describe "#extract_pr_changes" do
      it "extracts changes from a simple description" do
        changes_description = "modify file: README.md\nadd file: CONTRIBUTING.md"
        changes = @pr_worktree_manager.extract_pr_changes(changes_description)

        expect(changes).to include(
          files: ["README.md", "CONTRIBUTING.md"],
          operations: [],
          comments: []
        )
      end

      it "handles empty description" do
        expect(@pr_worktree_manager.extract_pr_changes("")).to be_nil
      end

      it "handles nil description" do
        expect(@pr_worktree_manager.extract_pr_changes(nil)).to be_nil
      end
    end

    describe "#apply_worktree_changes" do
      before do
        @worktree_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
      end

      it "applies file changes to the worktree" do
        changes = {
          files: ["README.md", "CONTRIBUTING.md"],
          operations: [:modify, :create]
        }

        result = @pr_worktree_manager.apply_worktree_changes(pr_number, changes)

        expect(result[:success]).to be true
        expect(result[:successful_files]).to match_array(["README.md", "CONTRIBUTING.md"])
        expect(result[:failed_files]).to be_empty

        expect(File.exist?(File.join(@worktree_path, "README.md"))).to be true
        expect(File.exist?(File.join(@worktree_path, "CONTRIBUTING.md"))).to be true
      end

      it "handles different file operations" do
        changes = {
          files: ["README.md", "OLD_README.md"],
          operations: [:modify, :delete]
        }

        result = @pr_worktree_manager.apply_worktree_changes(pr_number, changes)

        expect(result[:success]).to be true
        expect(result[:successful_files]).to match_array(["README.md", "OLD_README.md"])
        expect(result[:failed_files]).to be_empty

        expect(File.exist?(File.join(@worktree_path, "README.md"))).to be true
        expect(File.exist?(File.join(@worktree_path, "OLD_README.md"))).to be false
      end

      it "raises an error when no worktree exists for PR" do
        changes = {
          files: ["README.md"]
        }

        expect {
          @pr_worktree_manager.apply_worktree_changes(999, changes)
        }.to raise_error(RuntimeError, /No worktree found for PR 999/)
      end
    end

    describe "#push_worktree_changes" do
      before do
        @worktree_path = @pr_worktree_manager.create_worktree(pr_number, base_branch, head_branch)
      end

      it "pushes changes to the PR branch" do
        changes = {
          files: ["README.md"],
          operations: [:modify]
        }
        @pr_worktree_manager.apply_worktree_changes(pr_number, changes)

        # Mock the git system calls to succeed
        allow_any_instance_of(Object).to receive(:`).with(/git diff --staged --name-only/).and_return("README.md")
        allow_any_instance_of(Object).to receive(:$?).and_return(double(success?: true))
        allow_any_instance_of(Object).to receive(:`).with(/git commit/).and_return("Commit successful")
        allow_any_instance_of(Object).to receive(:`).with(/git push origin/).and_return("Push successful")

        result = @pr_worktree_manager.push_worktree_changes(pr_number)

        expect(result[:success]).to be true
        expect(result[:git_actions][:staged_changes]).to be true
        expect(result[:git_actions][:committed]).to be true
        expect(result[:git_actions][:pushed]).to be true
        expect(result[:changed_files]).to eq(["README.md"])
      end

      it "handles no changes to push" do
        # Mock an empty staged changes list
        allow_any_instance_of(Object).to receive(:`).with(/git diff --staged --name-only/).and_return("")
        allow_any_instance_of(Object).to receive(:$?).and_return(double(success?: true))

        result = @pr_worktree_manager.push_worktree_changes(pr_number)

        expect(result[:success]).to be true
        expect(result[:git_actions][:staged_changes]).to be false
        expect(result[:git_actions][:committed]).to be false
        expect(result[:git_actions][:pushed]).to be false
      end

      it "raises an error when no worktree exists for PR" do
        expect {
          @pr_worktree_manager.push_worktree_changes(999)
        }.to raise_error(RuntimeError, /No worktree found for PR 999/)
      end
    end

    describe "max_diff_size workflow" do
      it "creates worktree with max_diff_size parameter" do
        max_diff_size = 10_000
        different_pr_number = 123  # Use different PR number to avoid collision

        @pr_worktree_manager.create_worktree(
          different_pr_number, base_branch, head_branch, max_diff_size: max_diff_size
        )

        # Retrieve the registered worktree details
        stored_details = @pr_worktree_manager.list_worktrees[different_pr_number.to_s]

        expect(stored_details).to include(
          "max_diff_size" => max_diff_size
        )
      end
    end
  end
end
