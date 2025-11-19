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

  it "skips processing when plan generation fails" do
    failed_plan_generator = instance_double(Aidp::Watch::PlanGenerator, generate: nil)
    failed_processor = described_class.new(repository_client: repository_client, state_store: state_store, plan_generator: failed_plan_generator)

    # Should not post comment or update labels when plan_data is nil
    expect(repository_client).not_to receive(:post_comment)
    expect(repository_client).not_to receive(:replace_labels)

    failed_processor.process(issue)

    # State should not be updated
    expect(state_store.plan_data(42)).to be_nil
  end

  it "updates existing plan when re-planning" do
    # First plan
    state_store.record_plan(42, summary: "Initial plan", tasks: ["Task 1"], questions: [], comment_body: "body1", comment_id: "comment-123")

    # Mock the update_comment call for re-planning
    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    expect(repository_client).to receive(:update_comment).with("comment-123", /AIDP Plan Proposal/)
    expect(repository_client).to receive(:replace_labels).with(
      42,
      old_labels: ["aidp-plan"],
      new_labels: ["aidp-needs-input"]
    )

    processor.process(issue)

    # Verify iteration tracking
    data = state_store.plan_data(42)
    expect(state_store.plan_iteration_count(42)).to eq(2)
    expect(data["iteration"]).to eq(2)
  end

  it "archives previous plan content when updating" do
    # First plan
    state_store.record_plan(42, summary: "Old summary", tasks: ["Old task"], questions: [], comment_body: "body1", comment_id: "comment-123")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    expect(repository_client).to receive(:update_comment) do |_id, body|
      # Verify archived content is present
      expect(body).to include("ARCHIVED_PLAN_START")
      expect(body).to include("Previous Plan (Iteration 1)")
      expect(body).to include("Old summary")
      expect(body).to include("Old task")
      expect(body).to include("ARCHIVED_PLAN_END")
    end

    processor.process(issue)
  end

  it "finds and updates comment when comment_id is missing" do
    # Plan exists but without comment_id
    state_store.record_plan(42, summary: "Old plan", tasks: [], questions: [], comment_body: "body1")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    # Mock finding the comment
    expect(repository_client).to receive(:find_comment).with(42, "## 🤖 AIDP Plan Proposal").and_return({id: "found-123", body: "old body"})
    expect(repository_client).to receive(:update_comment).with("found-123", /AIDP Plan Proposal/)

    processor.process(issue)

    # Verify comment_id is now stored
    data = state_store.plan_data(42)
    expect(data["comment_id"]).to eq("found-123")
  end

  it "posts new comment when existing comment cannot be found" do
    # Plan exists but comment cannot be found
    state_store.record_plan(42, summary: "Old plan", tasks: [], questions: [], comment_body: "body1")

    allow(repository_client).to receive(:most_recent_label_actor).with(42).and_return(nil)
    allow(repository_client).to receive(:replace_labels)

    expect(repository_client).to receive(:find_comment).with(42, "## 🤖 AIDP Plan Proposal").and_return(nil)
    expect(repository_client).to receive(:post_comment).with(42, /AIDP Plan Proposal/)

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
