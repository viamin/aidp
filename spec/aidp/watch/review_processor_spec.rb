# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::ReviewProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }

  # Create test double reviewers with default behavior
  let(:senior_dev_reviewer) do
    instance_double(Aidp::Watch::Reviewers::SeniorDevReviewer).tap do |reviewer|
      allow(reviewer).to receive(:review).and_return({persona: "Senior Developer", findings: []})
    end
  end

  let(:security_reviewer) do
    instance_double(Aidp::Watch::Reviewers::SecurityReviewer).tap do |reviewer|
      allow(reviewer).to receive(:review).and_return({persona: "Security Specialist", findings: []})
    end
  end

  let(:performance_reviewer) do
    instance_double(Aidp::Watch::Reviewers::PerformanceReviewer).tap do |reviewer|
      allow(reviewer).to receive(:review).and_return({persona: "Performance Analyst", findings: []})
    end
  end

  let(:reviewers) { [senior_dev_reviewer, security_reviewer, performance_reviewer] }
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, reviewers: reviewers) }
  let(:pr) do
    {
      number: 123,
      title: "Add new feature",
      body: "This PR adds a new feature",
      url: "https://github.com/owner/repo/pull/123",
      head_ref: "feature-branch",
      base_ref: "main",
      head_sha: "abc123"
    }
  end
  let(:files) do
    [
      {filename: "lib/feature.rb", additions: 50, deletions: 10, changes: 60, patch: "diff content"},
      {filename: "spec/feature_spec.rb", additions: 30, deletions: 0, changes: 30, patch: "diff content"}
    ]
  end
  let(:diff) { "diff --git a/lib/feature.rb..." }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#process" do
    it "skips when review already processed" do
      state_store.record_review(123, timestamp: Time.now.utc.iso8601, reviewers: [], total_findings: 0)
      expect(repository_client).not_to receive(:fetch_pull_request)
      processor.process(pr)
    end

    it "fetches PR data and runs reviews" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Reviewer test doubles already configured with default responses via let blocks

      expect(repository_client).to receive(:post_comment).with(123, /AIDP Code Review/)

      processor.process(pr)

      data = state_store.review_data(123)
      expect(data["reviewers"]).to include("Senior Developer", "Security Specialist", "Performance Analyst")
    end

    it "removes review label after processing" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:post_comment)

      # Reviewer test doubles already configured with default responses via let blocks

      expect(repository_client).to receive(:remove_labels).with(123, "aidp-review")

      processor.process(pr)
    end

    it "posts error comment when review fails" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_raise(StandardError.new("API error"))
      allow(repository_client).to receive(:post_comment)

      expect(repository_client).to receive(:post_comment).with(123, /Automated review failed/)

      processor.process(pr)
    end

    it "categorizes findings by severity" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:remove_labels)

      # Override senior dev reviewer to return findings with different severities
      allow(senior_dev_reviewer).to receive(:review).and_return(
        {
          persona: "Senior Developer",
          findings: [
            {"severity" => "high", "category" => "Logic Error", "message" => "Critical bug"},
            {"severity" => "minor", "category" => "Code Style", "message" => "Improve naming"}
          ]
        }
      )

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("🔴 High Priority")
        expect(body).to include("🟡 Minor")
        expect(body).to include("Logic Error")
        expect(body).to include("Code Style")
      end

      processor.process(pr)
    end

    it "logs review results to file" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Reviewer test doubles already configured with default responses via let blocks

      processor.process(pr)

      log_dir = File.join(tmp_dir, ".aidp", "logs", "pr_reviews")
      expect(Dir.exist?(log_dir)).to be true
      log_files = Dir.glob(File.join(log_dir, "pr_123_*.json"))
      expect(log_files).not_to be_empty
    end
  end

  describe "custom label configuration" do
    let(:custom_processor) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: tmp_dir,
        label_config: {review_trigger: "custom-review"}
      )
    end

    it "uses custom review label" do
      expect(custom_processor.review_label).to eq("custom-review")
    end
  end
end
