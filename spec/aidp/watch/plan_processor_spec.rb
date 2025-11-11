# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::PlanProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:plan_generator) do
    instance_double(Aidp::Watch::PlanGenerator, generate: {
      summary: "Implement the requested feature",
      tasks: ["Add API endpoint", "Write tests"],
      questions: ["Any performance constraints?"]
    })
  end
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, plan_generator: plan_generator) }
  let(:issue) do
    {
      number: 42,
      title: "Add search",
      body: "Please add search capability.",
      url: "https://example.com",
      comments: []
    }
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "posts plan comment and stores metadata" do
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    expect(repository_client).to receive(:post_comment).with(42, /AIDP Plan Proposal/)
    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-plan"],
      new_labels: ["aidp-needs-input"]
    )
    processor.process(issue)

    data = state_store.plan_data(42)
    expect(data["summary"]).to eq("Implement the requested feature")
    expect(data["tasks"]).to include("Add API endpoint")
    expect(data["questions"]).to include("Any performance constraints?")
  end

  it "skips when plan already recorded" do
    state_store.record_plan(42, summary: "cached", tasks: [], questions: [], comment_body: "cached")
    expect(repository_client).not_to receive(:post_comment)
    processor.process(issue)
  end

  describe "label actor tagging" do
    it "tags the label actor in the comment when available" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return("testuser")
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("cc @testuser")
      end

      processor.process(issue)
    end

    it "does not include tag when label actor is nil" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).not_to include("cc @")
      end

      processor.process(issue)
    end

    it "includes label actor tag before issue details" do
      allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return("alice")
      allow(repository_client).to receive(:replace_labels)

      expect(repository_client).to receive(:post_comment) do |_number, body|
        lines = body.split("\n")
        tag_index = lines.index { |line| line.include?("cc @alice") }
        issue_index = lines.index { |line| line.include?("**Issue**:") }

        expect(tag_index).not_to be_nil
        expect(issue_index).not_to be_nil
        expect(tag_index).to be < issue_index
      end

      processor.process(issue)
    end
  end
end
