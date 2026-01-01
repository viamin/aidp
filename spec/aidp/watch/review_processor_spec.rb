# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::ReviewProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:verifier) { instance_double(Aidp::Watch::ImplementationVerifier) }

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
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, reviewers: reviewers, verifier: verifier) }
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

  before do
    # Mock verifier to return no linked issue by default (skip verification)
    allow(verifier).to receive(:verify).and_return({verified: true})
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
      # Add review completion comment to PR
      pr_with_review = pr.merge(
        comments: [
          {"body" => "🔍 Review complete for this PR", "author" => "aidp-bot", "createdAt" => Time.now.utc.iso8601}
        ]
      )
      expect(repository_client).not_to receive(:fetch_pull_request)
      processor.process(pr_with_review)
    end

    it "fetches PR data and runs reviews" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

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

      expect(repository_client).to receive(:remove_labels).with(123, "aidp-review")

      processor.process(pr)
    end

    it "logs error internally when review fails but does not post to GitHub" do
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_raise(StandardError.new("API error"))
      allow(state_store).to receive(:record_review)

      expect(repository_client).not_to receive(:post_comment)
      expect(Aidp).to receive(:log_error).with("review_processor", "Review failed", hash_including(pr: 123, error: "API error"))
      expect(state_store).to receive(:record_review).with(123, hash_including(status: "error", error: "API error"))

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

  describe "incomplete implementation guidance" do
    let(:state_extractor) { instance_double(Aidp::Watch::GitHubStateExtractor) }
    let(:pr_with_issue) do
      pr.merge(body: "Fixes #42\n\nThis PR adds a new feature")
    end

    before do
      allow(Aidp::Watch::GitHubStateExtractor).to receive(:new).and_return(state_extractor)
      allow(state_extractor).to receive(:review_completed?).and_return(false)
      allow(state_extractor).to receive(:extract_linked_issue).and_return(42)
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr_with_issue)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:fetch_issue).with(42).and_return({number: 42, title: "Add feature", body: "Feature description"})
      allow(repository_client).to receive(:remove_labels)
      allow(Aidp::Worktree).to receive(:find_by_branch).and_return(nil)
    end

    it "includes missing requirements and additional work when implementation is incomplete" do
      allow(verifier).to receive(:verify).and_return({
        verified: false,
        reason: "Implementation does not fully address all requirements",
        missing_items: ["Database migration for new field", "API endpoint for data retrieval"],
        additional_work: ["Add migration file for users table", "Create GET /api/data endpoint"]
      })

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("⚠️ Implementation Incomplete")
        expect(body).to include("**Summary:** Implementation does not fully address all requirements")
        expect(body).to include("**Missing Requirements:**")
        expect(body).to include("- Database migration for new field")
        expect(body).to include("- API endpoint for data retrieval")
        expect(body).to include("**Additional Work Needed:**")
        expect(body).to include("- Add migration file for users table")
        expect(body).to include("- Create GET /api/data endpoint")
        expect(body).to include("aidp-request-changes")
      end

      processor.process(pr)
    end

    it "omits missing requirements section when empty" do
      allow(verifier).to receive(:verify).and_return({
        verified: false,
        reason: "Only documentation files were changed",
        missing_items: [],
        additional_work: ["Implement the actual code changes"]
      })

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("⚠️ Implementation Incomplete")
        expect(body).to include("**Summary:** Only documentation files were changed")
        expect(body).not_to include("**Missing Requirements:**")
        expect(body).to include("**Additional Work Needed:**")
        expect(body).to include("- Implement the actual code changes")
      end

      processor.process(pr)
    end

    it "omits additional work section when empty" do
      allow(verifier).to receive(:verify).and_return({
        verified: false,
        reason: "Some requirements are missing",
        missing_items: ["Feature X not implemented"],
        additional_work: []
      })

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("⚠️ Implementation Incomplete")
        expect(body).to include("**Missing Requirements:**")
        expect(body).to include("- Feature X not implemented")
        expect(body).not_to include("**Additional Work Needed:**")
      end

      processor.process(pr)
    end

    context "when verifier raises an exception" do
      before do
        allow(verifier).to receive(:verify).and_raise(StandardError.new("Verification crashed"))
      end

      it "does not include verification section in comment" do
        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).not_to include("Implementation Incomplete")
          expect(body).not_to include("Implementation Verification")
          expect(body).to include("AIDP Code Review")
        end

        processor.process(pr)
      end

      it "logs the verification failure" do
        allow(repository_client).to receive(:post_comment)

        expect(Aidp).to receive(:log_error).with(
          "review_processor",
          "Verification failed",
          hash_including(error: "Verification crashed")
        )

        processor.process(pr)
      end
    end

    context "when verifier returns a technical error result" do
      # This tests the current behavior where verification errors are displayed
      # as "Implementation Incomplete" - documenting this as a potential issue
      before do
        allow(verifier).to receive(:verify).and_return({
          verified: false,
          reason: "Verification failed due to error: wrong number of arguments (given 3, expected 2)",
          missing_items: ["Unable to verify due to technical error"],
          additional_work: []
        })
      end

      it "currently displays technical errors as incomplete (documents existing behavior)" do
        # NOTE: This test documents current behavior that may need improvement
        # A technical error should ideally be distinguishable from a genuine
        # "implementation incomplete" determination
        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).to include("⚠️ Implementation Incomplete")
          expect(body).to include("wrong number of arguments")
          expect(body).to include("Unable to verify due to technical error")
        end

        processor.process(pr)
      end

      it "includes error message in summary which hints at technical failure" do
        expect(repository_client).to receive(:post_comment) do |_number, body|
          # The summary should at least show the error nature
          expect(body).to include("**Summary:** Verification failed due to error")
        end

        processor.process(pr)
      end
    end

    context "when verifier returns AI engine unavailable error" do
      before do
        allow(verifier).to receive(:verify).and_return({
          verified: false,
          reason: "AI decision engine not available for verification",
          missing_items: ["Unable to verify - AI decision engine initialization failed"],
          additional_work: []
        })
      end

      it "displays AI unavailable as incomplete (documents existing behavior)" do
        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).to include("⚠️ Implementation Incomplete")
          expect(body).to include("AI decision engine not available")
        end

        processor.process(pr)
      end
    end
  end

  describe "distinguishing verification errors from incomplete determinations" do
    # These tests document the gap where technical errors look like incomplete implementations
    let(:state_extractor) { instance_double(Aidp::Watch::GitHubStateExtractor) }
    let(:pr_with_issue) do
      pr.merge(body: "Fixes #42\n\nThis PR adds a new feature")
    end

    before do
      allow(Aidp::Watch::GitHubStateExtractor).to receive(:new).and_return(state_extractor)
      allow(state_extractor).to receive(:review_completed?).and_return(false)
      allow(state_extractor).to receive(:extract_linked_issue).and_return(42)
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(pr_with_issue)
      allow(repository_client).to receive(:fetch_pull_request_files).with(123).and_return(files)
      allow(repository_client).to receive(:fetch_pull_request_diff).with(123).and_return(diff)
      allow(repository_client).to receive(:fetch_issue).with(42).and_return({number: 42, title: "Add feature", body: "Feature description"})
      allow(repository_client).to receive(:remove_labels)
      allow(Aidp::Worktree).to receive(:find_by_branch).and_return(nil)
    end

    it "genuine incomplete: missing items describe actual missing features" do
      allow(verifier).to receive(:verify).and_return({
        verified: false,
        reason: "Implementation does not address all requirements",
        missing_items: ["User authentication endpoint", "Database migration"],
        additional_work: ["Add login route", "Create users table migration"]
      })

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("⚠️ Implementation Incomplete")
        # Missing items are specific feature descriptions
        expect(body).to include("User authentication endpoint")
        expect(body).to include("Database migration")
        # Additional work is actionable
        expect(body).to include("Add login route")
      end

      processor.process(pr)
    end

    it "technical error: missing items indicate verification failure" do
      allow(verifier).to receive(:verify).and_return({
        verified: false,
        reason: "Verification failed due to error: connection refused",
        missing_items: ["Unable to verify due to technical error"],
        additional_work: []
      })

      expect(repository_client).to receive(:post_comment) do |_number, body|
        expect(body).to include("⚠️ Implementation Incomplete")
        # These are error indicators, not missing features
        expect(body).to include("Unable to verify due to technical error")
        expect(body).to include("Verification failed due to error")
      end

      processor.process(pr)
    end
  end
end
