# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/auto_pr_processor"

RSpec.describe Aidp::Watch::AutoPrProcessor do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:state_store) { instance_double(Aidp::Watch::StateStore, review_processed?: false) }
  let(:review_processor) { instance_double(Aidp::Watch::ReviewProcessor) }
  let(:ci_fix_processor) { instance_double(Aidp::Watch::CiFixProcessor) }
  let(:auto_label) { described_class::DEFAULT_AUTO_LABEL }

  let(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      review_processor: review_processor,
      ci_fix_processor: ci_fix_processor,
      label_config: {},
      verbose: false
    )
  end

  let(:pr) { {number: 456, title: "Example PR"} }

  before do
    allow(review_processor).to receive(:process)
    allow(ci_fix_processor).to receive(:process)
    # Mock state store iteration tracking
    allow(state_store).to receive(:record_auto_pr_iteration).and_return(1)
    allow(state_store).to receive(:auto_pr_iteration_count).and_return(1)
    allow(state_store).to receive(:complete_auto_pr)
  end

  describe "#process" do
    it "runs review and ci processors" do
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "pending", checks: []})

      processor.process(pr)

      expect(review_processor).to have_received(:process).with(pr)
      expect(ci_fix_processor).to have_received(:process).with(pr)
    end

    it "records iteration count on each process call" do
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "pending", checks: []})

      processor.process(pr)

      expect(state_store).to have_received(:record_auto_pr_iteration).with(456)
    end
  end

  describe "completion detection" do
    before do
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return("testuser")
      allow(repository_client).to receive(:request_reviewers).and_return(true)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
    end

    it "removes label when review complete and CI passing with success" do
      pr_with_comments = pr.merge(comments: [{"body" => "Review complete"}])
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_comments)
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "success", checks: []})
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)

      processor.process(pr)

      expect(repository_client).to have_received(:remove_labels).with(456, auto_label)
    end

    it "accepts skipped CI state as passing" do
      pr_with_comments = pr.merge(comments: [{"body" => "Review complete"}])
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_comments)
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "skipped", checks: []})
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)

      processor.process(pr)

      expect(repository_client).to have_received(:remove_labels).with(456, auto_label)
    end

    it "accepts checks with success and skipped conclusions" do
      pr_with_comments = pr.merge(comments: [{"body" => "Review complete"}])
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_comments)
      allow(repository_client).to receive(:fetch_ci_status).and_return({
        state: "completed",
        checks: [
          {name: "build", conclusion: "success"},
          {name: "lint", conclusion: "skipped"}
        ]
      })
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)

      processor.process(pr)

      expect(repository_client).to have_received(:remove_labels).with(456, auto_label)
    end

    it "does not finalize when CI has failures" do
      pr_with_comments = pr.merge(comments: [{"body" => "Review complete"}])
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_comments)
      allow(repository_client).to receive(:fetch_ci_status).and_return({
        state: "failure",
        checks: [{name: "build", conclusion: "failure"}]
      })
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)

      processor.process(pr)

      expect(repository_client).not_to have_received(:remove_labels)
    end
  end

  describe "iteration cap" do
    before do
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "pending", checks: []})
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return("testuser")
      allow(repository_client).to receive(:request_reviewers).and_return(true)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
    end

    it "has default iteration cap of 20" do
      expect(processor.iteration_cap).to eq(20)
    end

    it "can be configured with custom iteration cap" do
      custom_processor = described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        review_processor: review_processor,
        ci_fix_processor: ci_fix_processor,
        iteration_cap: 5
      )
      expect(custom_processor.iteration_cap).to eq(5)
    end

    it "finalizes PR when iteration cap is exceeded" do
      allow(state_store).to receive(:record_auto_pr_iteration).and_return(21)
      allow(state_store).to receive(:auto_pr_iteration_count).and_return(21)

      processor.process(pr)

      expect(repository_client).to have_received(:remove_labels).with(456, auto_label)
      expect(state_store).to have_received(:complete_auto_pr).with(456, reason: "iteration_cap_reached")
    end

    it "does not run review/ci processors when cap is exceeded" do
      allow(state_store).to receive(:record_auto_pr_iteration).and_return(21)

      processor.process(pr)

      expect(review_processor).not_to have_received(:process)
      expect(ci_fix_processor).not_to have_received(:process)
    end
  end

  describe "draft conversion and reviewer request" do
    before do
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "success", checks: []})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)
    end

    it "converts draft PR to ready for review" do
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return(nil)
      allow(repository_client).to receive(:request_reviewers).and_return(true)

      processor.process(pr)

      expect(repository_client).to have_received(:mark_pr_ready_for_review).with(456)
    end

    it "requests the label adder as reviewer" do
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return("label-adder")
      allow(repository_client).to receive(:request_reviewers).and_return(true)

      processor.process(pr)

      expect(repository_client).to have_received(:request_reviewers).with(456, reviewers: ["label-adder"])
    end

    it "skips reviewer request when no label actor found" do
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return(nil)
      allow(repository_client).to receive(:request_reviewers).and_return(true)

      processor.process(pr)

      expect(repository_client).not_to have_received(:request_reviewers)
    end
  end

  describe "completion comment" do
    before do
      allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
      allow(repository_client).to receive(:fetch_ci_status).and_return({state: "success", checks: []})
      allow(repository_client).to receive(:mark_pr_ready_for_review).and_return(true)
      allow(repository_client).to receive(:most_recent_pr_label_actor).and_return(nil)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(state_store).to receive(:review_processed?).with(456).and_return(true)
    end

    it "posts completion comment with iteration count" do
      allow(state_store).to receive(:auto_pr_iteration_count).and_return(3)

      processor.process(pr)

      expect(repository_client).to have_received(:post_comment) do |pr_num, body|
        expect(pr_num).to eq(456)
        expect(body).to include("3 iteration(s)")
        expect(body).to include("CI is passing")
      end
    end

    it "includes reason when iteration cap reached" do
      allow(state_store).to receive(:record_auto_pr_iteration).and_return(21)
      allow(state_store).to receive(:auto_pr_iteration_count).and_return(21)

      processor.process(pr)

      expect(repository_client).to have_received(:post_comment) do |pr_num, body|
        expect(body).to include("Iteration cap (20) reached")
      end
    end
  end
end
