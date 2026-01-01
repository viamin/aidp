# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Worktree-based PR change requests" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:verifier) { instance_double(Aidp::Watch::ImplementationVerifier) }

  # Configuration with worktree strategy for large PRs
  let(:change_request_config) do
    {
      enabled: true,
      run_tests_before_push: false,
      max_diff_size: 2000,
      large_pr_strategy: "create_worktree"
    }
  end

  let(:safety_config) { {author_allowlist: []} }

  let(:processor) do
    Aidp::Watch::ChangeRequestProcessor.new(
      repository_client: repository_client,
      state_store: state_store,
      project_dir: tmp_dir,
      change_request_config: change_request_config,
      safety_config: safety_config
    )
  end

  before do
    # Mock verifier to return success by default
    allow(Aidp::Watch::ImplementationVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:verify).and_return({verified: true})

    # Initialize temp git repo
    Dir.chdir(tmp_dir) do
      system("git init")
      system('git config user.name "Test User"')
      system('git config user.email "test@example.com"')
      system("git checkout -b main")
      system("touch README.md")
      system("git add README.md")
      system('git commit -m "Initial commit"')
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  let(:pr) do
    {
      number: 456,
      title: "Large PR implementation",
      body: "This is a large PR with many changes",
      url: "https://github.com/owner/repo/pull/456",
      head_ref: "large-feature-branch",
      base_ref: "main",
      head_sha: "abc123",
      author: "alice"
    }
  end

  let(:comments) do
    [
      {
        id: 1,
        body: "Please modify the configuration to use the new worktree feature",
        author: "alice",
        created_at: "2024-01-01T10:00:00Z",
        updated_at: "2024-01-01T10:00:00Z"
      }
    ]
  end

  # Create a large diff (exceeding the max_diff_size)
  let(:large_diff) { "diff --git a/file.rb b/file.rb\n" + ("@@ -#{rand(100)},1 +#{rand(100)},1 @@\n-old line\n+new line\n" * 1100) }

  describe "handling large PRs with worktree strategy" do
    let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }
    let(:worktree_path) { File.join(tmp_dir, ".worktrees", "large-feature-branch-pr-456") }

    before do
      # Set up mocks for repository client calls
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
      allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
      allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(repository_client).to receive(:replace_labels)

      # Set the mock branch manager on the processor instance
      processor.worktree_branch_manager = branch_manager

      # Mock get_pr_branch to return the head branch
      allow(branch_manager).to receive(:get_pr_branch)
        .with(456)
        .and_return("large-feature-branch")
    end

    context "when no existing worktree is found" do
      before do
        # Simulate no existing worktree
        allow(branch_manager).to receive(:find_worktree)
          .with(branch: "large-feature-branch", pr_number: 456)
          .and_return(nil)

        # Expect a new worktree to be created
        allow(branch_manager).to receive(:find_or_create_pr_worktree)
          .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")
          .and_return(worktree_path)

        # Mock successful change analysis
        allow(processor).to receive(:analyze_change_requests)
          .and_return({
            can_implement: true,
            needs_clarification: false,
            changes: [
              {
                "file" => "config.rb",
                "action" => "edit",
                "content" => "# Configuration\nuse_worktree_strategy = true\n",
                "description" => "Update configuration"
              }
            ],
            reason: "Clear change request for large PR"
          })

        # Mock file operations
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(File).to receive(:write).and_call_original
        allow(Dir).to receive(:chdir).and_yield

        # Mock git operations
        allow(processor).to receive(:run_git).and_return("")
        allow(processor).to receive(:checkout_pr_branch).and_call_original
        allow(processor).to receive(:apply_changes).and_call_original
        allow(processor).to receive(:commit_and_push).and_return(true)
      end

      it "creates a new worktree and processes the changes" do
        # Expect branch manager to be called correctly
        expect(branch_manager).to receive(:find_worktree)
          .with(branch: "large-feature-branch", pr_number: 456)

        expect(branch_manager).to receive(:find_or_create_pr_worktree)
          .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")

        # Expect the PR to be processed without raising exceptions
        expect { processor.process(pr) }.not_to raise_error

        # Verify that a success comment was posted
        expect(repository_client).to have_received(:post_comment)
          .with(456, /Successfully implemented/)

        # Verify that the label was removed
        expect(repository_client).to have_received(:remove_labels)
          .with(456, "aidp-request-changes")
      end
    end

    context "when an existing worktree is found" do
      before do
        # Simulate existing worktree
        allow(branch_manager).to receive(:find_worktree)
          .with(branch: "large-feature-branch", pr_number: 456)
          .and_return(worktree_path)

        # Still allow find_or_create_pr_worktree to be called (used in checkout_pr_branch)
        allow(branch_manager).to receive(:find_or_create_pr_worktree)
          .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")
          .and_return(worktree_path)

        # Mock successful change analysis
        allow(processor).to receive(:analyze_change_requests)
          .and_return({
            can_implement: true,
            needs_clarification: false,
            changes: [
              {
                "file" => "config.rb",
                "action" => "edit",
                "content" => "# Configuration\nuse_worktree_strategy = true\n",
                "description" => "Update configuration"
              }
            ],
            reason: "Clear change request for large PR"
          })

        # Mock directory and file operations
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(File).to receive(:write).and_call_original
        allow(Dir).to receive(:chdir).and_yield

        # Mock git operations
        allow(processor).to receive(:run_git).and_return("")
        allow(processor).to receive(:checkout_pr_branch).and_call_original
        allow(processor).to receive(:apply_changes).and_call_original
        allow(processor).to receive(:commit_and_push).and_return(true)
      end

      it "uses the existing worktree to process changes" do
        # Expect existing worktree to be found and used
        expect(branch_manager).to receive(:find_worktree)
          .with(branch: "large-feature-branch", pr_number: 456)
          .and_return(worktree_path)

        # Expect the PR to be processed without raising exceptions
        expect { processor.process(pr) }.not_to raise_error

        # Verify that a success comment was posted
        expect(repository_client).to have_received(:post_comment)
          .with(456, /Successfully implemented/)
      end
    end

    context "when worktree creation fails" do
      before do
        # Simulate no existing worktree
        allow(branch_manager).to receive(:find_worktree)
          .with(branch: "large-feature-branch", pr_number: 456)
          .and_return(nil)

        # Simulate failure when creating new worktree
        allow(branch_manager).to receive(:find_or_create_pr_worktree)
          .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")
          .and_raise(StandardError.new("Failed to create worktree: Permission denied"))

        # Expect error handling
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
        allow(repository_client).to receive(:replace_labels)
      end

      it "handles worktree creation failures and posts an error comment" do
        # Should post a comment about large diff
        expect(repository_client).to receive(:post_comment)
          .with(456, /diff is too large/)

        # Should remove the change request label
        expect(repository_client).to receive(:remove_labels)
          .with(456, "aidp-request-changes")

        # Exceptions are caught by the process method's rescue block
        expect {
          processor.process(pr)
        }.not_to raise_error

        # Verify state storage was updated
        expect(state_store.change_request_data(456)["status"]).to eq("error")
      end
    end
  end

  describe "different large PR strategies" do
    let(:large_diff) { "diff --git a/file.rb b/file.rb\n" + ("@@ -#{rand(100)},1 +#{rand(100)},1 @@\n-old line\n+new line\n" * 1100) }

    before do
      # Set up mocks for repository client calls
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
      allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
      allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(repository_client).to receive(:replace_labels)
    end

    context "with 'skip' strategy" do
      let(:change_request_config) { {enabled: true, max_diff_size: 2000, large_pr_strategy: "skip"} }

      it "skips large PR processing and posts a comment" do
        expect(repository_client).to receive(:post_comment)
          .with(456, /diff is too large/)

        expect(repository_client).to receive(:remove_labels)
          .with(456, "aidp-request-changes")

        expect(processor).not_to receive(:analyze_change_requests)

        processor.process(pr)
      end
    end

    context "with 'manual' strategy" do
      let(:change_request_config) { {enabled: true, max_diff_size: 2000, large_pr_strategy: "manual"} }

      it "stops processing and posts large PR comment" do
        expect(repository_client).to receive(:post_comment)
          .with(456, /diff is too large/)

        expect(repository_client).to receive(:remove_labels)
          .with(456, "aidp-request-changes")

        # The error is caught by the process method's rescue block
        expect {
          processor.process(pr)
        }.not_to raise_error

        # Check that the state was updated correctly
        expect(state_store.change_request_data(456)["status"]).to eq("error")
      end
    end
  end

  describe "integration with WorktreeBranchManager" do
    let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }
    let(:worktree_path) { File.join(tmp_dir, ".worktrees", "large-feature-branch-pr-456") }

    before do
      # Mock repository client
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
      allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
      allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(repository_client).to receive(:replace_labels)

      # Set the mock branch manager on the processor
      processor.worktree_branch_manager = branch_manager

      # Mock branch manager methods
      allow(branch_manager).to receive(:get_pr_branch).with(456).and_return("large-feature-branch")
      allow(branch_manager).to receive(:find_worktree)
        .with(branch: "large-feature-branch", pr_number: 456)
        .and_return(nil)
      allow(branch_manager).to receive(:find_or_create_pr_worktree)
        .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")
        .and_return(worktree_path)

      # Mock analysis result
      allow(processor).to receive(:analyze_change_requests)
        .and_return({
          can_implement: true,
          needs_clarification: false,
          changes: [{"file" => "config.rb", "action" => "edit", "content" => "new content", "description" => "Update"}],
          reason: "Clear request"
        })

      # Mock checkout and apply operations
      allow(processor).to receive(:checkout_pr_branch).and_call_original
      allow(processor).to receive(:apply_changes)
      allow(processor).to receive(:commit_and_push).and_return(true)
      allow(processor).to receive(:run_git).and_return("")
      allow(Dir).to receive(:chdir).and_yield
    end

    it "properly integrates with WorktreeBranchManager for worktree handling" do
      # Should use get_pr_branch to get the branch name
      expect(branch_manager).to receive(:get_pr_branch)
        .with(456)
        .and_return("large-feature-branch")

      # Should check for existing worktree
      expect(branch_manager).to receive(:find_worktree)
        .with(branch: "large-feature-branch", pr_number: 456)

      # Should create a new worktree
      expect(branch_manager).to receive(:find_or_create_pr_worktree)
        .with(pr_number: 456, head_branch: "large-feature-branch", base_branch: "main")

      # Should update the project directory to use the worktree
      expect(processor.project_dir).to eq(tmp_dir) # Before processing

      processor.process(pr)

      # After processing, the project_dir should be updated to the worktree path
      expect(processor.project_dir).to eq(worktree_path)

      # Verify that a success comment was posted
      expect(repository_client).to have_received(:post_comment)
        .with(456, /Successfully implemented/)
    end
  end
end
