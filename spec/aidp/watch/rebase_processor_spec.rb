require "spec_helper"
require "aidp/watch/rebase_processor"

RSpec.describe Aidp::Watch::RebaseProcessor do
  let(:repository_client) { double("RepositoryClient") }
  let(:worktree_manager) { double("PrWorktreeManager") }
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:label_config) { {rebase_trigger: "aidp-rebase"} }
  let(:state_store) { double("StateStore") }
  let(:shell_executor) { double("ShellExecutor") }

  subject(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      worktree_manager: worktree_manager,
      ai_decision_engine: ai_decision_engine,
      label_config: label_config,
      verbose: false,
      shell_executor: shell_executor
    )
  end

  describe "#can_process?" do
    context "when work item is a PR with the rebase label" do
      let(:work_item) do
        Aidp::Watch::WorkItem.new(
          number: 123,
          item_type: :pr,
          processor_type: :auto_pr,
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
          processor_type: :auto_pr,
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
        processor_type: :auto_pr,
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

      # Expect PR retrieval
      allow(repository_client).to receive(:get_pull_request)
        .with(work_item.number)
        .and_return(pr_details)

      # Expect worktree creation
      allow(worktree_manager).to receive(:create_pr_worktree)
        .with(
          pr_number: work_item.number,
          base_branch: "main",
          head_branch: "feature-branch"
        )
        .and_return(worktree_path)

      # Expect label removal
      allow(repository_client).to receive(:remove_labels)
        .with(work_item.number, ["aidp-rebase"])
    end

    context "when rebase is successful" do
      before do
        # Simulate successful rebase
        allow(shell_executor).to receive(:system)
          .with(/git fetch origin/)
          .and_return(true)

        allow(shell_executor).to receive(:system)
          .with(/git rebase origin\/main/)
          .and_return(true)

        allow(shell_executor).to receive(:system)
          .with(/git push -f origin feature-branch/)
          .and_return(true)

        # Stub success status
        allow(repository_client).to receive(:add_success_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: "PR successfully rebased"
          )

        # Stub success comment
        allow(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            "✅ PR has been successfully rebased against the target branch."
          )

        # Stub worktree cleanup
        allow(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "processes the rebase successfully" do
        expect(processor.process(work_item)).to be true

        # Verify method calls
        expect(repository_client).to have_received(:add_success_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: "PR successfully rebased"
          )

        expect(repository_client).to have_received(:post_comment)
          .with(
            work_item.number,
            "✅ PR has been successfully rebased against the target branch."
          )

        expect(worktree_manager).to have_received(:cleanup_pr_worktree)
          .with(work_item.number)
      end
    end

    context "when rebase fails" do
      let(:error) { Errno::ENOENT.new("No such file or directory @ rb_sysopen - #{worktree_path}/conflicts.txt") }

      before do
        # Simulate rebase failure
        allow(shell_executor).to receive(:system)
          .with(/git fetch origin/)
          .and_return(true)

        allow(shell_executor).to receive(:system)
          .with(/git rebase origin\/main/)
          .and_return(false)

        # Simulate conflict during resolution
        allow(processor).to receive(:detect_conflicting_files)
          .with(worktree_path)
          .and_return(["conflicts.txt"])

        # Simulate AI resolution failure
        allow(ai_decision_engine).to receive(:resolve_merge_conflict)
          .and_raise(error)

        # Stub label removal and status handling
        allow(repository_client).to receive(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        allow(repository_client).to receive(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: an_instance_of(String)
          )

        allow(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        # Stub worktree cleanup
        allow(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "processes the rebase with conflict resolution" do
        expect(processor.process(work_item)).to be false

        # Verify method calls
        expect(repository_client).to have_received(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        expect(repository_client).to have_received(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: an_instance_of(String)
          )

        expect(repository_client).to have_received(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        expect(worktree_manager).to have_received(:cleanup_pr_worktree)
          .with(work_item.number)
      end
    end

    context "when an unexpected error occurs" do
      before do
        # Simulate a runtime error
        allow(repository_client).to receive(:get_pull_request)
          .with(work_item.number)
          .and_raise(StandardError.new("Unknown error"))

        # Stub label removal and status handling
        allow(repository_client).to receive(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        allow(repository_client).to receive(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: an_instance_of(String)
          )

        allow(repository_client).to receive(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        # Stub worktree cleanup
        allow(worktree_manager).to receive(:cleanup_pr_worktree)
          .with(work_item.number)
      end

      it "handles unexpected errors" do
        # Expect the error to propagate error details
        expect(processor.process(work_item)).to be false

        # Verify method calls
        expect(repository_client).to have_received(:remove_labels)
          .with(work_item.number, ["aidp-rebase"])

        expect(repository_client).to have_received(:add_failure_status)
          .with(
            work_item.number,
            context: "aidp/rebase",
            description: "Unknown error"
          )

        expect(repository_client).to have_received(:post_comment)
          .with(
            work_item.number,
            an_instance_of(String)
          )

        expect(worktree_manager).to have_received(:cleanup_pr_worktree)
          .with(work_item.number)
      end
    end
  end
end
