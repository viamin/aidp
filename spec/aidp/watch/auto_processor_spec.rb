# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/auto_processor"

RSpec.describe Aidp::Watch::AutoProcessor do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:state_store) { instance_double(Aidp::Watch::StateStore) }
  let(:build_processor) { instance_double(Aidp::Watch::BuildProcessor) }
  let(:auto_label) { described_class::DEFAULT_AUTO_LABEL }
  let(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      build_processor: build_processor,
      label_config: {},
      verbose: false
    )
  end

  let(:issue) { {number: 123, title: "Example"} }

  before do
    allow(build_processor).to receive(:process)
  end

  it "delegates to build processor and transfers label when PR created" do
    allow(state_store).to receive(:build_status).with(123).and_return({"status" => "completed", "pr_url" => "https://github.com/org/repo/pull/456"})
    allow(repository_client).to receive(:add_labels)
    allow(repository_client).to receive(:remove_labels)

    processor.process(issue)

    expect(build_processor).to have_received(:process).with(issue)
    expect(repository_client).to have_received(:add_labels).with(456, auto_label)
    expect(repository_client).to have_received(:remove_labels).with(123, auto_label)
  end

  it "skips transfer when no PR URL available" do
    allow(state_store).to receive(:build_status).with(123).and_return({"status" => "completed", "pr_url" => nil})

    expect(repository_client).not_to receive(:add_labels)

    processor.process(issue)
  end
end
