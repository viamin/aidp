# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::AutoMerger do
  let(:repository_client) { instance_double("Aidp::Watch::RepositoryClient") }
  let(:state_store) { instance_double("Aidp::Watch::StateStore") }
  let(:config) { {enabled: true, sub_issue_prs_only: true, require_ci_success: true, merge_method: "squash"} }

  subject(:merger) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      config: config
    )
  end

  describe "#can_auto_merge?" do
    let(:pr_number) { 123 }

    context "when auto-merge is disabled" do
      let(:config) { {enabled: false} }

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("disabled")
      end
    end

    context "when PR is a parent PR" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-parent-pr"],
          state: "open",
          mergeable: true
        })
      end

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("Parent PRs require human review")
      end
    end

    context "when PR is not a sub-PR and sub_issue_prs_only is true" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: [],
          state: "open",
          mergeable: true
        })
      end

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("Not a sub-issue PR")
      end
    end

    context "when PR has merge conflicts" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-sub-pr"],
          state: "open",
          mergeable: false
        })
      end

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("merge conflicts")
      end
    end

    context "when CI has not passed" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-sub-pr"],
          state: "open",
          mergeable: true
        })
        allow(repository_client).to receive(:fetch_ci_status).with(pr_number).and_return({state: "pending"})
      end

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("CI has not passed")
      end
    end

    context "when all conditions are met" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-sub-pr"],
          state: "open",
          mergeable: true
        })
        allow(repository_client).to receive(:fetch_ci_status).with(pr_number).and_return({state: "success"})
      end

      it "returns can merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be true
      end
    end
  end

  describe "#merge_pr" do
    let(:pr_number) { 123 }

    context "when PR can be merged" do
      before do
        allow(merger).to receive(:can_auto_merge?).with(pr_number).and_return({can_merge: true, reason: "OK"})
        allow(repository_client).to receive(:merge_pull_request).and_return({sha: "abc123"})
        allow(repository_client).to receive(:post_comment)
        allow(state_store).to receive(:find_build_by_pr).and_return(nil)
      end

      it "merges the PR" do
        expect(repository_client).to receive(:merge_pull_request).with(pr_number, merge_method: "squash")
        merger.merge_pr(pr_number)
      end

      it "returns success" do
        result = merger.merge_pr(pr_number)
        expect(result[:success]).to be true
      end
    end

    context "when PR cannot be merged" do
      before do
        allow(merger).to receive(:can_auto_merge?).with(pr_number).and_return({can_merge: false, reason: "Not eligible"})
      end

      it "does not attempt merge" do
        expect(repository_client).not_to receive(:merge_pull_request)
        merger.merge_pr(pr_number)
      end

      it "returns failure" do
        result = merger.merge_pr(pr_number)
        expect(result[:success]).to be false
        expect(result[:reason]).to eq("Not eligible")
      end
    end
  end

  describe "#list_sub_pr_candidates" do
    it "lists PRs with sub-PR label" do
      expect(repository_client).to receive(:list_pull_requests).with(labels: ["aidp-sub-pr"], state: "open").and_return([{number: 1}])
      result = merger.list_sub_pr_candidates
      expect(result).to eq([{number: 1}])
    end

    it "returns empty array on error" do
      allow(repository_client).to receive(:list_pull_requests).and_raise(StandardError, "API error")
      result = merger.list_sub_pr_candidates
      expect(result).to eq([])
    end
  end

  describe "#can_auto_merge?" do
    let(:pr_number) { 123 }

    context "when fetch_pull_request fails" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).and_raise(StandardError, "Network error")
      end

      it "returns cannot merge with error message" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("Failed to fetch PR")
      end
    end

    context "when PR is not open" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-sub-pr"],
          state: "closed",
          mergeable: true
        })
      end

      it "returns cannot merge" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be false
        expect(result[:reason]).to include("not open")
      end
    end

    context "when sub_issue_prs_only is false" do
      let(:config) { {enabled: true, sub_issue_prs_only: false, require_ci_success: true} }

      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: [],
          state: "open",
          mergeable: true
        })
        allow(repository_client).to receive(:fetch_ci_status).with(pr_number).and_return({state: "success"})
      end

      it "allows PRs without sub-pr label" do
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be true
      end
    end

    context "when require_ci_success is false" do
      let(:config) { {enabled: true, sub_issue_prs_only: true, require_ci_success: false} }

      before do
        allow(repository_client).to receive(:fetch_pull_request).with(pr_number).and_return({
          labels: ["aidp-sub-pr"],
          state: "open",
          mergeable: true
        })
      end

      it "does not check CI status" do
        expect(repository_client).not_to receive(:fetch_ci_status)
        result = merger.can_auto_merge?(pr_number)
        expect(result[:can_merge]).to be true
      end
    end
  end

  describe "#merge_pr" do
    let(:pr_number) { 123 }

    context "when merge fails with API error" do
      before do
        allow(merger).to receive(:can_auto_merge?).with(pr_number).and_return({can_merge: true, reason: "OK"})
        allow(repository_client).to receive(:merge_pull_request).and_raise(StandardError, "Branch is protected")
      end

      it "returns failure with error message" do
        result = merger.merge_pr(pr_number)
        expect(result[:success]).to be false
        expect(result[:reason]).to include("Merge failed")
        expect(result[:reason]).to include("Branch is protected")
      end
    end
  end

  describe "#process_auto_merge_candidates" do
    let(:prs) { [{number: 1}, {number: 2}, {number: 3}] }

    context "when some PRs fail" do
      before do
        allow(merger).to receive(:can_auto_merge?).with(1).and_return({can_merge: true, reason: "OK"})
        allow(merger).to receive(:can_auto_merge?).with(2).and_return({can_merge: false, reason: "Not eligible"})
        allow(merger).to receive(:can_auto_merge?).with(3).and_return({can_merge: true, reason: "OK"})
        allow(merger).to receive(:merge_pr).with(1).and_return({success: true})
        allow(merger).to receive(:merge_pr).with(3).and_return({success: false, reason: "Failed"})
      end

      it "returns correct counts" do
        result = merger.process_auto_merge_candidates(prs)
        expect(result[:merged]).to eq(1)
        expect(result[:skipped]).to eq(1)
        expect(result[:failed]).to eq(1)
      end
    end
  end
end
