# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::BuildProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:issue) do
    {
      number: 77,
      title: "Implement search",
      body: "Detailed issue body",
      url: "https://example.com/issues/77",
      comments: [
        {"body" => "Looks good", "author" => "maintainer", "createdAt" => Time.now.utc.iso8601}
      ]
    }
  end
  let(:plan_data) do
    {
      "summary" => "Implement search",
      "tasks" => ["Add endpoint"],
      "questions" => ["Any rate limits?"],
      "comment_hint" => Aidp::Watch::PlanProcessor::COMMENT_HEADER
    }
  end
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }

  before do
    state_store.record_plan(issue[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])

    allow(processor).to receive(:ensure_git_repo!)
    allow(processor).to receive(:detect_base_branch).and_return("main")
    allow(processor).to receive(:checkout_branch)
    allow(processor).to receive(:write_prompt)
    allow(processor).to receive(:stage_and_commit)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "runs harness and posts success comment" do
    allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
    allow(processor).to receive(:create_pull_request).and_return("https://example.com/pr/77")
    expect(repository_client).to receive(:post_comment).with(issue[:number], include("Implementation complete"))

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("completed")
    expect(status["pr_url"]).to eq("https://example.com/pr/77")
  end

  it "records failure when harness fails" do
    allow(processor).to receive(:run_harness).and_return({status: "error", message: "tests failed"})
    expect(repository_client).to receive(:post_comment).with(issue[:number], include("failed"))

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("failed")
    expect(status["message"]).to eq("tests failed")
  end
end
