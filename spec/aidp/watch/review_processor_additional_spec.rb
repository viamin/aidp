# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/review_processor"

RSpec.describe Aidp::Watch::ReviewProcessor do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:state_store) { instance_double(Aidp::Watch::StateStore, record_review: nil) }
  let(:reviewer) { instance_double("Reviewer") }
  let(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      reviewers: [reviewer]
    )
  end

  it "posts review and records comment" do
    allow(reviewer).to receive(:persona_name).and_return("Reviewer")
    allow(reviewer).to receive(:review).and_return({body: "Looks good", approve: true, findings: []})
    allow(repository_client).to receive(:post_review_comment).and_return("comment-id")
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:remove_labels)
    allow(repository_client).to receive(:fetch_pull_request).and_return({number: 1, title: "PR", head_sha: "sha"})
    allow(repository_client).to receive(:fetch_pull_request_files).and_return([])
    allow(repository_client).to receive(:fetch_pull_request_diff).and_return("diff")
    allow(repository_client).to receive(:fetch_pr_comments).and_return([])
    allow(repository_client).to receive(:find_comment).and_return(nil)

    processor.process(number: 1, title: "PR")

    expect(repository_client).to have_received(:post_comment).with(1, kind_of(String))
    expect(state_store).to have_received(:record_review).with(1, hash_including(total_findings: 0))
  end

  it "records errors when review fails" do
    allow(processor).to receive(:run_reviews).and_raise(StandardError.new("fail"))
    allow(repository_client).to receive(:fetch_pull_request).and_return({number: 2, title: "PR", head_sha: "sha", body: ""})
    allow(repository_client).to receive(:fetch_pull_request_files).and_return([])
    allow(repository_client).to receive(:fetch_pull_request_diff).and_return("diff")
    allow(repository_client).to receive(:fetch_pr_comments).and_return([])
    allow(repository_client).to receive(:find_comment).and_return(nil)

    processor.process(number: 2, title: "PR")

    expect(state_store).to have_received(:record_review).with(2, hash_including(status: "error", error: /fail/))
  end
end
