# frozen_string_literal: true

require "spec_helper"
require_relative "../change_request_processor"

RSpec.describe Aidp::Watch::ChangeRequestProcessor do
  let(:repository_client) { double("RepositoryClient") }
  let(:state_store) { double("StateStore") }
  let(:project_dir) { "/tmp/test_project" }
  let(:change_request_config) { {} }
  let(:safety_config) { {} }
  let(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      project_dir: project_dir,
      change_request_config: change_request_config,
      safety_config: safety_config
    )
  end

  describe "#checkout_pr_branch" do
    let(:pr_data) do
      {
        number: 123,
        head_ref: "feature-branch",
        base_ref: "main",
        title: "Test PR"
      }
    end

    context "when no existing worktree" do
      before do
        allow(Aidp::Worktree).to receive(:find_by_branch).and_return(nil)
        allow(Aidp::Worktree).to receive(:create).and_return(
          path: "/tmp/worktrees/pr-123-feature-branch",
          active: true
        )
        allow(processor).to receive(:run_git).and_return(true)
      end

      it "creates a new worktree" do
        expect(Aidp::Worktree).to receive(:create).with(
          slug: "pr-123-feature-branch",
          project_dir: project_dir,
          branch: "feature-branch",
          base_branch: "main"
        )

        processor.send(:checkout_pr_branch, pr_data)
      end
    end

    context "when existing worktree exists" do
      let(:existing_worktree) do
        {
          active: true,
          path: "/tmp/worktrees/pr-123-existing",
          branch: "feature-branch"
        }
      end

      before do
        allow(Aidp::Worktree).to receive(:find_by_branch).and_return(existing_worktree)
        allow(processor).to receive(:run_git).and_return(true)
      end

      it "uses existing worktree" do
        processor.send(:checkout_pr_branch, pr_data)
        expect(processor.instance_variable_get(:@project_dir)).to eq(existing_worktree[:path])
      end
    end
  end

  describe "#process" do
    let(:pr_data) do
      {
        number: 123,
        head_ref: "feature-branch",
        base_ref: "main",
        title: "Test PR"
      }
    end

    context "when diff size exceeds max_diff_size" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr_data)
        allow(repository_client).to receive(:fetch_pr_comments).and_return([])
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return("x" * 5000)
      end

      it "creates a worktree for large PRs" do
        expect(processor).to receive(:create_worktree_for_pr).with(pr_data)
        processor.process(pr_data)
      end
    end
  end
end
