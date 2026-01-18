require "spec_helper"
require "aidp/watch/rebase_processor"

RSpec.describe Aidp::Watch::RebaseProcessor do
  let(:repository_client) { double("RepositoryClient") }
  let(:worktree_manager) { double("PrWorktreeManager") }
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:label_config) { {rebase_trigger: "aidp-rebase"} }
  let(:state_store) { double("StateStore") }

  subject(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      worktree_manager: worktree_manager,
      ai_decision_engine: ai_decision_engine,
      label_config: label_config,
      verbose: false
    )
  end

  describe "#can_process?" do
    context "when work item is a PR with the rebase label" do
      let(:work_item) do
        Aidp::Watch::WorkItem.new(
          number: 123,
          item_type: :pr,
          processor_type: :rebase,
          label: "aidp-rebase",
          data: {
            head: {ref: "feature-branch"},
            labels: [{name: "aidp-rebase"}]
          }
        )
      end

      it "returns true" do
        allow(work_item).to receive(:labels) { ["aidp-rebase"] }
        expect(processor.can_process?(work_item)).to be true
      end
    end

    context "when work item is not a PR" do
      let(:work_item) do
        Aidp::Watch::WorkItem.new(
          number: 123,
          item_type: :issue,
          processor_type: :rebase,
          label: "aidp-rebase",
          data: {}
        )
      end

      it "returns false" do
        allow(work_item).to receive(:labels) { ["aidp-rebase"] }
        expect(processor.can_process?(work_item)).to be false
      end
    end
  end

  describe "#process" do
    let(:work_item) do
      Aidp::Watch::WorkItem.new(
        number: 123,
        item_type: :pr,
        processor_type: :rebase,
        label: "aidp-rebase",
        data: {
          head: {ref: "feature-branch"},
          labels: [{name: "aidp-rebase"}]
        }
      )
    end

    let(:pr_details) do
      {
        base: {ref: "main"},
        head: {ref: "feature-branch"}
      }
    end

    let(:worktree_path) { "/tmp/worktree/123" }

    before do
      # Stubbing labels method
      allow(work_item).to receive(:labels) { ["aidp-rebase"] }
    end

    context "when rebase is successful" do
      before do
        # Expect PR retrieval
        expect(repository_client).to receive(:get_pull_request)
          .with(work_item.number)
          .and_return(pr_details)

        # Expect worktree creation
        expect(worktree_manager).to receive(:create_pr_worktree)
          .with(
            pr_number: work_item.number,
            base_branch: "main",
            head_branch: "feature-branch"
          )
          .and_return(worktree_path)

        # Simulate successful rebase
        expect(processor).to receive(:system)
          .with(/git fetch origin/)
          .and_return(true)

        expect(processor).to receive(:system)
          .with(/git rebase origin\/main/)
          .and_return(true)

        expect(processor).to receive(:system)
          .with(/git push -f origin feature-branch/)
          .and_return(true)

        # Expect label removal
        expect(repository_client).to receive(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        # Expect success status
        expect(repository_client).to receive(:add_success_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: "PR successfully rebased"
          )

        # Expect success comment
        expect(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            "✅ PR has been successfully rebased against the target branch."
          )

        # Expect worktree cleanup
        expect(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "processes the rebase successfully" do
        expect(processor.process(work_item)).to be true
      end
    end

    context "when rebase fails" do
      let(:error) { Errno::ENOENT.new("No such file or directory @ rb_sysopen - #{worktree_path}/conflicts.txt") }

      before do
        # Expect PR retrieval
        expect(repository_client).to receive(:get_pull_request)
          .with(work_item.number)
          .and_return(pr_details)

        # Expect worktree creation
        expect(worktree_manager).to receive(:create_pr_worktree)
          .with(
            pr_number: work_item.number,
            base_branch: "main",
            head_branch: "feature-branch"
          )
          .and_return(worktree_path)

        # Simulate rebase failure
        expect(processor).to receive(:system)
          .with(/git fetch origin/)
          .and_return(true)

        expect(processor).to receive(:system)
          .with(/git rebase origin\/main/)
          .and_return(false)

        # Simulate conflict during resolution
        expect(processor).to receive(:detect_conflicting_files)
          .with(worktree_path)
          .and_return(["conflicts.txt"])

        # Expect AI resolution
        expect(ai_decision_engine).to receive(:resolve_merge_conflict)
          .with(
            base_branch_path: worktree_path,
            conflict_files: ["conflicts.txt"]
          )
          .and_raise(error)

        # Expect label and status handling
        expect(repository_client).to receive(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        expect(repository_client).to receive(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: an_instance_of(String)
          )

        expect(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        # Expect worktree cleanup
        expect(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "processes the rebase with conflict resolution" do
        expect(processor.process(work_item)).to be false
      end
    end

    context "when an unexpected error occurs" do
      before do
        # Simulate a runtime error
        expect(repository_client).to receive(:get_pull_request)
          .and_raise(StandardError.new("Unknown error"))

        # Expect label removal
        expect(repository_client).to receive(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        # Expect failure status and comment
        expect(repository_client).to receive(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: an_instance_of(String)
          )

        expect(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        # Expect worktree cleanup
        expect(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "handles unexpected errors" do
        expect(processor.process(work_item)).to be false
      end
    end
  end
end
