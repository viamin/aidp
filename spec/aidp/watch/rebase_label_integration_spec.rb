require "spec_helper"
require "aidp/watch/rebase_label_handler"
require "tmpdir"
require "shellwords"
require "fileutils"

RSpec.describe Aidp::Watch::RebaseLabelHandler, integration: true do
  let(:temp_repo_dir) { Dir.mktmpdir("aidp_rebase_integration_test") }
  let(:worktree_dir) { Dir.mktmpdir("aidp_rebase_worktree") }
  let(:repository_client) { double("RepositoryClient") }
  let(:pr_worktree_manager) { double("PRWorktreeManager") }
  let(:ai_decision_engine) { double("AIDecisionEngine") }

  subject(:handler) do
    described_class.new(
      repository_client: repository_client,
      pr_worktree_manager: pr_worktree_manager,
      ai_decision_engine: ai_decision_engine
    )
  end

  before(:each) do
    # Setup test git repository
    Dir.chdir(temp_repo_dir) do
      system("git init")
      system("git config user.email 'test@example.com'")
      system("git config user.name 'Test User'")

      # Create initial main branch with a file
      system("echo 'Initial content' > main_file.txt")
      system("git add main_file.txt")
      system("git commit -m 'Initial commit'")
    end
  end

  after(:each) do
    FileUtils.rm_rf(temp_repo_dir)
    FileUtils.rm_rf(worktree_dir) if File.exist?(worktree_dir)
  end

  # Helper to set up a worktree by cloning from the main repo
  def setup_worktree_clone(source_dir, target_dir, base_branch, head_branch)
    # Clone the repo to the target directory
    system("git clone #{Shellwords.escape(source_dir)} #{Shellwords.escape(target_dir)}")

    Dir.chdir(target_dir) do
      system("git config user.email 'test@example.com'")
      system("git config user.name 'Test User'")

      # Fetch all branches to ensure we have the latest
      system("git fetch origin")

      # Checkout the head branch (this creates local tracking branch from remote)
      system("git checkout -b #{Shellwords.escape(head_branch)} origin/#{Shellwords.escape(head_branch)} 2>/dev/null")

      # If the previous checkout failed, try switching to the branch
      unless File.exist?(".git") && system("git rev-parse HEAD > /dev/null 2>&1")
        system("git checkout #{Shellwords.escape(head_branch)}")
      end
    end
    target_dir
  end

  context "when rebase is needed" do
    let(:pr_number) { 123 }
    let(:base_branch) { "main" }
    let(:head_branch) { "feature_branch" }

    before do
      Dir.chdir(temp_repo_dir) do
        # Create a feature branch
        system("git checkout -b #{head_branch}")
        system("echo 'Feature branch content' > feature_file.txt")
        system("git add feature_file.txt")
        system("git commit -m 'Feature branch commit'")

        # Switch back to main and create a new commit
        system("git checkout main")
        system("echo 'Main branch update' >> main_file.txt")
        system("git add main_file.txt")
        system("git commit -m 'Main branch update'")
      end

      # Set up worktree by cloning
      actual_worktree_path = setup_worktree_clone(temp_repo_dir, "#{worktree_dir}/pr-#{pr_number}", base_branch, head_branch)

      # Stub repository client methods
      allow(repository_client).to receive(:get_pr).with(pr_number).and_return(
        number: pr_number,
        base_branch: base_branch,
        head_branch: head_branch
      )
      allow(repository_client).to receive(:add_pr_comment)
      allow(repository_client).to receive(:remove_label)

      # Stub worktree manager to return our test worktree
      allow(pr_worktree_manager).to receive(:create_worktree)
        .with(pr_number, base_branch, head_branch)
        .and_return(actual_worktree_path)
      allow(pr_worktree_manager).to receive(:remove_worktree)
    end

    it "successfully rebases the branch" do
      # Perform the rebase
      rebase_result = handler.handle_rebase(pr_number)

      # Verify rebase was successful
      expect(rebase_result[:success]).to be true
      expect(rebase_result[:base_branch]).to eq(base_branch)
      expect(rebase_result[:head_branch]).to eq(head_branch)

      # Verify repository client method calls indicating success
      expect(repository_client).to have_received(:add_pr_comment).with(
        pr_number,
        a_string_including("🔄 Automatic Rebase Successful")
      )
      expect(repository_client).to have_received(:remove_label).with(pr_number, "aidp-rebase")
    end
  end

  context "when rebase encounters conflicts" do
    let(:pr_number) { 456 }
    let(:base_branch) { "main" }
    let(:head_branch) { "conflicting_branch" }

    before do
      Dir.chdir(temp_repo_dir) do
        # Create a feature branch with conflicting changes
        system("git checkout -b #{head_branch}")
        system("echo 'Feature branch conflicting content' > main_file.txt")
        system("git add main_file.txt")
        system("git commit -m 'Conflicting feature branch commit'")

        # Switch back to main and create a different update
        system("git checkout main")
        system("echo 'Main branch different update' >> main_file.txt")
        system("git add main_file.txt")
        system("git commit -m 'Different main branch update'")
      end

      # Set up worktree by cloning
      actual_worktree_path = setup_worktree_clone(temp_repo_dir, "#{worktree_dir}/pr-#{pr_number}", base_branch, head_branch)

      # Stub repository client methods
      allow(repository_client).to receive(:get_pr).with(pr_number).and_return(
        number: pr_number,
        base_branch: base_branch,
        head_branch: head_branch
      )
      allow(repository_client).to receive(:add_pr_comment)
      allow(repository_client).to receive(:remove_label)

      # Stub worktree manager to return our test worktree
      allow(pr_worktree_manager).to receive(:create_worktree)
        .with(pr_number, base_branch, head_branch)
        .and_return(actual_worktree_path)
      allow(pr_worktree_manager).to receive(:remove_worktree)

      # Setup AI conflict resolution mock
      allow(ai_decision_engine).to receive(:resolve_merge_conflicts).and_return(
        resolved: true,
        files: {"main_file.txt" => "Merged content from main and feature branch\n"}
      )
    end

    it "uses AI to resolve merge conflicts" do
      # Perform the rebase with conflicts
      rebase_result = handler.handle_rebase(pr_number)

      # Verify rebase result
      expect(rebase_result[:success]).to be true

      # Check that AI conflict resolution was called
      expect(ai_decision_engine).to have_received(:resolve_merge_conflicts).with(
        base_branch: base_branch,
        head_branch: head_branch
      )

      # Verify repository client method calls
      expect(repository_client).to have_received(:add_pr_comment).with(
        pr_number,
        a_string_including("🔄 Automatic Rebase Successful")
      )
      expect(repository_client).to have_received(:remove_label).with(pr_number, "aidp-rebase")
    end
  end

  context "when AI cannot resolve conflicts" do
    let(:pr_number) { 789 }
    let(:base_branch) { "main" }
    let(:head_branch) { "unresolvable_branch" }

    before do
      Dir.chdir(temp_repo_dir) do
        # Create a feature branch with conflicting changes
        system("git checkout -b #{head_branch}")
        system("echo 'Feature branch conflicting content' > main_file.txt")
        system("git add main_file.txt")
        system("git commit -m 'Unresolvable feature branch commit'")

        # Switch back to main and create a different update
        system("git checkout main")
        system("echo 'Main branch different update' >> main_file.txt")
        system("git add main_file.txt")
        system("git commit -m 'Different main branch update'")
      end

      # Set up worktree by cloning
      actual_worktree_path = setup_worktree_clone(temp_repo_dir, "#{worktree_dir}/pr-#{pr_number}", base_branch, head_branch)

      # Stub repository client methods
      allow(repository_client).to receive(:get_pr).with(pr_number).and_return(
        number: pr_number,
        base_branch: base_branch,
        head_branch: head_branch
      )
      allow(repository_client).to receive(:add_pr_comment)
      allow(repository_client).to receive(:remove_label)

      # Stub worktree manager to return our test worktree
      allow(pr_worktree_manager).to receive(:create_worktree)
        .with(pr_number, base_branch, head_branch)
        .and_return(actual_worktree_path)
      allow(pr_worktree_manager).to receive(:remove_worktree)

      # Setup AI conflict resolution mock to fail
      allow(ai_decision_engine).to receive(:resolve_merge_conflicts).and_return(
        resolved: false,
        reason: "Conflicts too complex to resolve automatically"
      )
    end

    it "fails when AI cannot resolve conflicts" do
      # Simulate a conflicted rebase with unresolvable conflicts
      rebase_result = handler.handle_rebase(pr_number)

      # Verify rebase result
      expect(rebase_result[:success]).to be false

      # Check that AI conflict resolution was called
      expect(ai_decision_engine).to have_received(:resolve_merge_conflicts).with(
        base_branch: base_branch,
        head_branch: head_branch
      )

      # Verify repository client method calls
      expect(repository_client).to have_received(:add_pr_comment).with(
        pr_number,
        a_string_including("❌ Automatic Rebase Failed")
      )

      # Verify the rebase label is not removed when failing
      expect(repository_client).not_to have_received(:remove_label)
    end
  end
end
