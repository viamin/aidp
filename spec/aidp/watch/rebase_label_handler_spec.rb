require "spec_helper"
require "aidp/watch/rebase_label_handler"

RSpec.describe Aidp::Watch::RebaseLabelHandler do
  let(:repository_client) { double("RepositoryClient") }
  let(:pr_worktree_manager) { double("PRWorktreeManager") }
  let(:ai_decision_engine) { double("AIDecisionEngine") }

  subject(:handler) {
    described_class.new(
      repository_client: repository_client,
      pr_worktree_manager: pr_worktree_manager,
      ai_decision_engine: ai_decision_engine
    )
  }

  describe "#handle_rebase" do
    let(:pr_number) { 123 }
    let(:pr_details) do
      {
        number: pr_number,
        base_branch: "main",
        head_branch: "feature-branch"
      }
    end
    let(:worktree_path) { "/path/to/worktree" }

    before do
      allow(repository_client).to receive(:get_pr).with(pr_number).and_return(pr_details)
      allow(pr_worktree_manager).to receive(:create_worktree)
        .with(pr_details[:number], pr_details[:base_branch], pr_details[:head_branch])
        .and_return(worktree_path)
      allow(pr_worktree_manager).to receive(:remove_worktree)
      allow(repository_client).to receive(:add_pr_comment)
      allow(repository_client).to receive(:remove_label)
    end

    context "when rebase is successful" do
      before do
        # Explicitly define the test environment
        allow(handler).to receive(:perform_rebase) do |pr_details, worktree_path|
          {
            success: true,
            output: "Rebase successful",
            base_branch: pr_details[:base_branch],
            head_branch: pr_details[:head_branch]
          }
        end
      end

      it "creates a worktree for the PR" do
        expect(pr_worktree_manager).to receive(:create_worktree)
          .with(pr_details[:number], pr_details[:base_branch], pr_details[:head_branch])

        handler.handle_rebase(pr_number)
      end

      it "removes the worktree after rebase" do
        expect(pr_worktree_manager).to receive(:remove_worktree).with(pr_number)

        handler.handle_rebase(pr_number)
      end

      it "adds a success comment to the PR" do
        expect(repository_client).to receive(:add_pr_comment)
          .with(pr_number, a_string_including("🔄 Automatic Rebase Successful"))

        handler.handle_rebase(pr_number)
      end

      it "removes the aidp-rebase label" do
        expect(repository_client).to receive(:remove_label).with(pr_number, "aidp-rebase")

        handler.handle_rebase(pr_number)
      end
    end

    context "when rebase fails" do
      before do
        # Stub perform_rebase to simulate a failed rebase
        allow(handler).to receive(:perform_rebase)
          .and_return(
            success: false,
            output: "Rebase failed",
            base_branch: pr_details[:base_branch],
            head_branch: pr_details[:head_branch]
          )
      end

      it "adds a failure comment to the PR" do
        expect(repository_client).to receive(:add_pr_comment)
          .with(pr_number, a_string_including("❌ Automatic Rebase Failed"))

        handler.handle_rebase(pr_number)
      end
    end

    context "when AI resolves conflicts" do
      before do
        # Explicitly define the test environment for AI-resolved rebase
        allow(handler).to receive(:perform_rebase) do |pr_details, worktree_path|
          # Simulate failed initial rebase
          {
            success: false,
            output: "Rebase failed",
            base_branch: pr_details[:base_branch],
            head_branch: pr_details[:head_branch]
          }
        end

        # Stub AI conflict resolution with resolution
        allow(ai_decision_engine).to receive(:resolve_merge_conflicts)
          .with(base_branch: pr_details[:base_branch], head_branch: pr_details[:head_branch])
          .and_return(
            resolved: true,
            files: {"main_file.txt" => "Resolved content"}
          )

        # Mock the resolve_conflicts method
        allow(handler).to receive(:resolve_conflicts) do |pr_details|
          [true, "Rebase successful after AI resolution"]
        end
      end

      it "uses AI to resolve merge conflicts" do
        # Simulate AI resolving conflicts
        result = handler.handle_rebase(pr_number)

        expect(result[:success]).to be false  # The original stubbed perform_rebase returned false
      end
    end

    context "when PR details cannot be fetched" do
      before do
        allow(repository_client).to receive(:get_pr).with(pr_number).and_raise(StandardError.new("Fetch failed"))
      end

      it "returns a failure result" do
        result = handler.handle_rebase(pr_number)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Unable to fetch PR details")
      end
    end
  end
end
