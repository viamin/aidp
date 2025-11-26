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
  end

  it "runs review and ci processors" do
    allow(repository_client).to receive(:fetch_pull_request).and_return(pr.merge(comments: []))
    allow(repository_client).to receive(:fetch_ci_status).and_return({state: "pending"})

    processor.process(pr)

    expect(review_processor).to have_received(:process).with(pr)
    expect(ci_fix_processor).to have_received(:process).with(pr)
  end

  it "removes label when review complete and CI passing" do
    pr_with_comments = pr.merge(comments: [{"body" => "Review complete"}])
    allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_comments)
    allow(repository_client).to receive(:fetch_ci_status).and_return({state: "success"})
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:remove_labels)
    allow(state_store).to receive(:review_processed?).with(456).and_return(true)

    processor.process(pr)

    expect(repository_client).to have_received(:remove_labels).with(456, auto_label)
  end
end
