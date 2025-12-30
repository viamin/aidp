# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::WorktreeReconciler do
  let(:project_dir) { "/tmp/test_project" }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient, full_repo: "owner/repo") }
  let(:build_processor) { instance_double(Aidp::Watch::BuildProcessor, build_label: "aidp-build") }
  let(:state_store) { instance_double(Aidp::Watch::StateStore) }

  let(:reconciler) do
    described_class.new(
      project_dir: project_dir,
      repository_client: repository_client,
      build_processor: build_processor,
      state_store: state_store,
      config: config
    )
  end

  let(:config) { {enabled: true, interval_seconds: 300} }

  before do
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_error)
    allow(Aidp).to receive(:log_warn)
  end

  describe "#enabled?" do
    context "when enabled in config" do
      let(:config) { {enabled: true} }

      it "returns true" do
        expect(reconciler.enabled?).to be true
      end
    end

    context "when disabled in config" do
      let(:config) { {enabled: false} }

      it "returns false" do
        expect(reconciler.enabled?).to be false
      end
    end

    context "with default config" do
      let(:config) { {} }

      it "returns true by default" do
        expect(reconciler.enabled?).to be true
      end
    end
  end

  describe "#reconciliation_due?" do
    let(:config) { {enabled: true, interval_seconds: 300} }

    context "when disabled" do
      let(:config) { {enabled: false} }

      it "returns false" do
        expect(reconciler.reconciliation_due?(nil)).to be false
      end
    end

    context "when never run before" do
      it "returns true" do
        expect(reconciler.reconciliation_due?(nil)).to be true
      end
    end

    context "when run recently" do
      it "returns false" do
        last_run = Time.now - 100 # 100 seconds ago
        expect(reconciler.reconciliation_due?(last_run)).to be false
      end
    end

    context "when interval has passed" do
      it "returns true" do
        last_run = Time.now - 400 # 400 seconds ago, more than 300 interval
        expect(reconciler.reconciliation_due?(last_run)).to be true
      end
    end
  end

  describe "#execute" do
    context "when disabled" do
      let(:config) { {enabled: false} }

      it "returns empty results" do
        result = reconciler.execute
        expect(result).to eq({resumed: 0, reconciled: 0, cleaned: 0, skipped: 0, errors: []})
      end
    end

    context "when enabled with no dirty worktrees" do
      before do
        allow(Aidp::Worktree).to receive(:list).and_return([])
      end

      it "returns zero counts" do
        result = reconciler.execute
        expect(result[:resumed]).to eq(0)
        expect(result[:reconciled]).to eq(0)
        expect(result[:skipped]).to eq(0)
        expect(result[:errors]).to be_empty
      end
    end

    context "when worktree list fails" do
      before do
        allow(Aidp::Worktree).to receive(:list).and_raise(StandardError.new("list failed"))
      end

      it "returns empty results and logs error" do
        expect(Aidp).to receive(:log_error).with("worktree_reconciler", "list_worktrees_failed", error: "list failed")
        result = reconciler.execute
        expect(result[:resumed]).to eq(0)
      end
    end
  end

  describe "issue number extraction" do
    it "extracts issue number from slug" do
      expect(reconciler.send(:extract_issue_number, "issue-123-fix-bug")).to eq(123)
      expect(reconciler.send(:extract_issue_number, "issue-456-long-description-here")).to eq(456)
    end

    it "returns nil for non-issue slugs" do
      expect(reconciler.send(:extract_issue_number, "pr-123-ci-fix")).to be_nil
      expect(reconciler.send(:extract_issue_number, "random-slug")).to be_nil
    end
  end

  describe "PR number extraction" do
    it "extracts PR number from slug" do
      expect(reconciler.send(:extract_pr_number, "pr-123-ci-fix")).to eq(123)
      expect(reconciler.send(:extract_pr_number, "pr-456-something")).to eq(456)
    end

    it "returns nil for non-PR slugs" do
      expect(reconciler.send(:extract_pr_number, "issue-123-fix-bug")).to be_nil
      expect(reconciler.send(:extract_pr_number, "random-slug")).to be_nil
    end
  end

  describe "#process_dirty_worktree" do
    let(:worktree) do
      {
        slug: "issue-375-thinking-tiers",
        branch: "aidp/issue-375-thinking-tiers",
        path: "/tmp/test/.worktrees/issue-375-thinking-tiers",
        active: true
      }
    end

    before do
      allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])
    end

    context "when issue is open with build label" do
      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "list", "--repo", "owner/repo", "--head", "aidp/issue-375-thinking-tiers", "--state", "all", "--json", "number", "--limit", "1")
          .and_return(["[]", "", instance_double(Process::Status, success?: true)])

        allow(Open3).to receive(:capture3)
          .with("gh", "issue", "view", "375", "--repo", "owner/repo", "--json", "number,state,title,labels")
          .and_return([
            '{"number":375,"state":"OPEN","title":"Test","labels":[{"name":"aidp-build"}]}',
            "",
            instance_double(Process::Status, success?: true)
          ])

        allow(repository_client).to receive(:fetch_issue).with(375).and_return({number: 375, title: "Test"})
        allow(build_processor).to receive(:process)
      end

      it "resumes work via build processor" do
        expect(build_processor).to receive(:process)
        result = reconciler.send(:process_dirty_worktree, worktree)
        expect(result[:action]).to eq(:resumed)
      end
    end

    context "when issue is open without build label" do
      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "list", "--repo", "owner/repo", "--head", "aidp/issue-375-thinking-tiers", "--state", "all", "--json", "number", "--limit", "1")
          .and_return(["[]", "", instance_double(Process::Status, success?: true)])

        allow(Open3).to receive(:capture3)
          .with("gh", "issue", "view", "375", "--repo", "owner/repo", "--json", "number,state,title,labels")
          .and_return([
            '{"number":375,"state":"OPEN","title":"Test","labels":[]}',
            "",
            instance_double(Process::Status, success?: true)
          ])
      end

      it "skips with missing label reason" do
        result = reconciler.send(:process_dirty_worktree, worktree)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("issue_missing_build_label")
      end
    end

    context "when issue is closed" do
      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "list", "--repo", "owner/repo", "--head", "aidp/issue-375-thinking-tiers", "--state", "all", "--json", "number", "--limit", "1")
          .and_return(["[]", "", instance_double(Process::Status, success?: true)])

        allow(Open3).to receive(:capture3)
          .with("gh", "issue", "view", "375", "--repo", "owner/repo", "--json", "number,state,title,labels")
          .and_return([
            '{"number":375,"state":"CLOSED","title":"Test","labels":[]}',
            "",
            instance_double(Process::Status, success?: true)
          ])
      end

      it "skips with closed reason" do
        result = reconciler.send(:process_dirty_worktree, worktree)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("issue_closed_with_uncommitted_changes")
      end
    end

    context "when orphan worktree (no issue or PR found)" do
      let(:worktree) do
        {
          slug: "random-worktree",
          branch: "some-branch",
          path: "/tmp/test/.worktrees/random",
          active: true
        }
      end

      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "list", "--repo", "owner/repo", "--head", "some-branch", "--state", "all", "--json", "number", "--limit", "1")
          .and_return(["[]", "", instance_double(Process::Status, success?: true)])
      end

      it "skips orphan worktrees" do
        result = reconciler.send(:process_dirty_worktree, worktree)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("orphan_worktree")
      end
    end
  end

  describe "#process_pr_worktree" do
    let(:worktree) do
      {
        slug: "issue-100-feature",
        branch: "aidp/issue-100-feature",
        path: "/tmp/test/.worktrees/issue-100-feature",
        active: true
      }
    end

    context "when PR is merged" do
      before do
        allow(Dir).to receive(:exist?).and_return(true)
        # Default stub for all Open3 calls
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])

        # PR state fetch
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "view", "50", "--repo", "owner/repo", "--json", "number,state,mergedAt,baseRefName,headRefName,title")
          .and_return([
            '{"number":50,"state":"MERGED","mergedAt":"2025-01-01T00:00:00Z","baseRefName":"main","title":"Test PR"}',
            "",
            instance_double(Process::Status, success?: true)
          ])
      end

      context "with no remaining changes" do
        before do
          # git status returns empty (clean after fetch)
          allow(Open3).to receive(:capture3)
            .with("git", "status", "--porcelain", chdir: worktree[:path])
            .and_return(["", "", instance_double(Process::Status, success?: true)])

          allow(Aidp::Worktree).to receive(:remove)
        end

        it "cleans up the worktree" do
          expect(Aidp::Worktree).to receive(:remove).with(
            slug: worktree[:slug],
            project_dir: project_dir,
            delete_branch: true
          )

          result = reconciler.send(:process_pr_worktree, worktree, 50, 100)
          expect(result[:action]).to eq(:cleaned)
        end
      end
    end

    context "when PR is open" do
      let(:pr) { {number: 50, state: "OPEN", base_branch: "main"} }

      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "view", "50", "--repo", "owner/repo", "--json", "number,state,mergedAt,baseRefName,headRefName,title")
          .and_return([
            '{"number":50,"state":"OPEN","baseRefName":"main"}',
            "",
            instance_double(Process::Status, success?: true)
          ])

        allow(repository_client).to receive(:fetch_issue).with(100).and_return({number: 100})
        allow(build_processor).to receive(:process)
      end

      it "resumes work if linked to issue" do
        expect(build_processor).to receive(:process)
        result = reconciler.send(:process_pr_worktree, worktree, 50, 100)
        expect(result[:action]).to eq(:resumed)
      end
    end

    context "when PR is closed (not merged)" do
      before do
        allow(Open3).to receive(:capture3)
          .with("gh", "pr", "view", "50", "--repo", "owner/repo", "--json", "number,state,mergedAt,baseRefName,headRefName,title")
          .and_return([
            '{"number":50,"state":"CLOSED","baseRefName":"main"}',
            "",
            instance_double(Process::Status, success?: true)
          ])
      end

      it "skips with closed reason" do
        result = reconciler.send(:process_pr_worktree, worktree, 50, 100)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("pr_closed_without_merge")
      end
    end
  end

  describe "configuration" do
    context "with string keys" do
      let(:config) { {"enabled" => true, "interval_seconds" => 600} }

      it "normalizes string keys" do
        expect(reconciler.enabled?).to be true
        expect(reconciler.reconciliation_interval_seconds).to eq(600)
      end
    end

    context "with auto_resume disabled" do
      let(:config) { {enabled: true, auto_resume: false} }

      it "skips resume actions" do
        worktree = {slug: "issue-1-test", branch: "aidp/issue-1-test", path: "/tmp/x", active: true}
        issue = {number: 1, state: "OPEN", labels: [{"name" => "aidp-build"}]}

        result = reconciler.send(:resume_open_issue, worktree, issue)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("auto_resume_disabled")
      end
    end

    context "with auto_reconcile disabled" do
      let(:config) { {enabled: true, auto_reconcile: false} }

      it "skips reconcile actions" do
        worktree = {slug: "issue-1-test", branch: "aidp/issue-1-test", path: "/tmp/x", active: true}
        pr = {number: 1, state: "MERGED", base_branch: "main"}

        result = reconciler.send(:reconcile_merged_pr, worktree, pr, 1)
        expect(result[:action]).to eq(:skipped)
        expect(result[:reason]).to eq("auto_reconcile_disabled")
      end
    end
  end
end
