# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::CiFixProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }
  let(:pr) do
    {
      number: 456,
      title: "Fix bug",
      body: "This PR fixes a bug",
      url: "https://github.com/owner/repo/pull/456",
      head_ref: "bugfix-branch",
      base_ref: "main",
      head_sha: "def456"
    }
  end
  let(:ci_status_failing) do
    {
      sha: "def456",
      state: "failure",
      checks: [
        {name: "RSpec", status: "completed", conclusion: "failure", output: {"summary" => "5 failures"}},
        {name: "RuboCop", status: "completed", conclusion: "failure", output: {"summary" => "3 offenses"}}
      ]
    }
  end
  let(:ci_status_passing) do
    {
      sha: "def456",
      state: "success",
      checks: [
        {name: "RSpec", status: "completed", conclusion: "success"},
        {name: "RuboCop", status: "completed", conclusion: "success"}
      ]
    }
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#process" do
    it "skips when CI fix already completed" do
      state_store.record_ci_fix(456, status: "completed", timestamp: Time.now.utc.iso8601)
      expect(repository_client).not_to receive(:fetch_pull_request)
      processor.process(pr)
    end

    it "posts success comment when CI is already passing" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_passing)
      allow(repository_client).to receive(:remove_labels)

      expect(repository_client).to receive(:post_comment).with(456, /CI is already passing/)

      processor.process(pr)

      data = state_store.ci_fix_data(456)
      expect(data["status"]).to eq("no_failures")
    end

    it "skips when CI is still pending" do
      ci_status_pending = {sha: "def456", state: "pending", checks: []}
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_pending)

      expect(repository_client).not_to receive(:post_comment)

      processor.process(pr)
    end

    it "analyzes failures and attempts to fix" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_failing)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Mock provider response
      provider = instance_double(Aidp::Providers::Anthropic::Provider)
      allow(Aidp::Providers::Factory).to receive(:create).and_return(provider)
      allow(provider).to receive(:chat).and_return(
        {
          content: JSON.dump({
            "can_fix" => false,
            "reason" => "Failures require manual investigation",
            "root_causes" => ["Complex test failures"],
            "fixes" => []
          })
        }
      )

      expect(repository_client).to receive(:post_comment).with(456, /Could not automatically fix/)

      processor.process(pr)

      data = state_store.ci_fix_data(456)
      expect(data["status"]).to eq("failed")
    end

    it "posts error comment when analysis fails" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_raise(StandardError.new("API error"))
      allow(repository_client).to receive(:post_comment)

      expect(repository_client).to receive(:post_comment).with(456, /Automated CI fix failed/)

      processor.process(pr)
    end

    it "logs CI fix attempts to file" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_failing)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Mock provider response
      provider = instance_double(Aidp::Providers::Anthropic::Provider)
      allow(Aidp::Providers::Factory).to receive(:create).and_return(provider)
      allow(provider).to receive(:chat).and_return(
        {
          content: JSON.dump({
            "can_fix" => false,
            "reason" => "Test failures",
            "root_causes" => [],
            "fixes" => []
          })
        }
      )

      processor.process(pr)

      log_dir = File.join(tmp_dir, ".aidp", "logs", "pr_reviews")
      expect(Dir.exist?(log_dir)).to be true
      log_files = Dir.glob(File.join(log_dir, "ci_fix_456_*.json"))
      expect(log_files).not_to be_empty
    end
  end

  describe "custom label configuration" do
    let(:custom_processor) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: tmp_dir,
        label_config: {ci_fix_trigger: "custom-ci-fix"}
      )
    end

    it "uses custom CI fix label" do
      expect(custom_processor.ci_fix_label).to eq("custom-ci-fix")
    end
  end
end
