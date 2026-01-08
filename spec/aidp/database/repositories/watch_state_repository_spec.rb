# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::WatchStateRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_watch_state_repo_test")}
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db")}
  let(:repository) { described_class.new(project_dir: temp_dir, repository: "owner/repo")}

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "plan tracking" do
    describe "#plan_processed?" do
      it "returns false when not processed" do
        expect(repository.plan_processed?(123)).to be false
      end

      it "returns true when processed" do
        repository.record_plan(123, {summary: "Test plan"})

        expect(repository.plan_processed?(123)).to be true
      end
    end

    describe "#plan_data" do
      it "returns nil when not processed" do
        expect(repository.plan_data(123)).to be_nil
      end

      it "returns plan data" do
        repository.record_plan(123, {summary: "Test plan", tasks: ["Task 1"]})

        data = repository.plan_data(123)

        expect(data[:summary]).to eq("Test plan")
        expect(data[:tasks]).to eq(["Task 1"])
      end
    end

    describe "#record_plan" do
      it "increments iteration on subsequent plans" do
        repository.record_plan(123, {summary: "Plan 1"})
        expect(repository.plan_iteration_count(123)).to eq(1)

        repository.record_plan(123, {summary: "Plan 2"})
        expect(repository.plan_iteration_count(123)).to eq(2)
      end
    end
  end

  describe "build tracking" do
    describe "#build_status" do
      it "returns empty hash when not recorded" do
        expect(repository.build_status(123)).to eq({})
      end

      it "returns build status" do
        repository.record_build_status(123, status: "in_progress", details: {branch: "feature/123"})

        status = repository.build_status(123)

        expect(status[:status]).to eq("in_progress")
        expect(status[:branch]).to eq("feature/123")
      end
    end

    describe "#workstream_for_issue" do
      it "returns nil when no build" do
        expect(repository.workstream_for_issue(123)).to be_nil
      end

      it "returns workstream info" do
        repository.record_build_status(123,
          status: "in_progress",
          details: {branch: "feature/123", workstream: "ws-123", pr_url: "https://github.com/owner/repo/pull/456"})

        info = repository.workstream_for_issue(123)

        expect(info[:issue_number]).to eq(123)
        expect(info[:branch]).to eq("feature/123")
        expect(info[:workstream]).to eq("ws-123")
      end
    end

    describe "#find_build_by_pr" do
      before do
        repository.record_build_status(123,
          status: "completed",
          details: {branch: "feature/123", pr_url: "https://github.com/owner/repo/pull/456"})
      end

      it "finds build by PR number" do
        build = repository.find_build_by_pr(456)

        expect(build[:issue_number]).to eq(123)
      end

      it "returns nil for unknown PR" do
        expect(repository.find_build_by_pr(999)).to be_nil
      end
    end
  end

  describe "review tracking" do
    describe "#review_processed?" do
      it "returns false when not processed" do
        expect(repository.review_processed?(456)).to be false
      end

      it "returns true when processed" do
        repository.record_review(456, {reviewers: ["user1"]})

        expect(repository.review_processed?(456)).to be true
      end
    end

    describe "#record_review" do
      it "stores review data" do
        repository.record_review(456, {reviewers: ["user1", "user2"], total_findings: 5})

        data = repository.review_data(456)

        expect(data[:reviewers]).to eq(["user1", "user2"])
        expect(data[:total_findings]).to eq(5)
      end
    end
  end

  describe "CI fix tracking" do
    describe "#ci_fix_completed?" do
      it "returns false when not recorded" do
        expect(repository.ci_fix_completed?(456)).to be false
      end

      it "returns true when completed" do
        repository.record_ci_fix(456, {status: "completed", fixes_count: 3})

        expect(repository.ci_fix_completed?(456)).to be true
      end

      it "returns false when not completed" do
        repository.record_ci_fix(456, {status: "in_progress"})

        expect(repository.ci_fix_completed?(456)).to be false
      end
    end
  end

  describe "change request tracking" do
    describe "#change_request_processed?" do
      it "returns false when not processed" do
        expect(repository.change_request_processed?(456)).to be false
      end

      it "returns true when processed" do
        repository.record_change_request(456, {status: "completed"})

        expect(repository.change_request_processed?(456)).to be true
      end
    end

    describe "#reset_change_request_state" do
      it "removes change request state" do
        repository.record_change_request(456, {status: "completed"})
        repository.reset_change_request_state(456)

        expect(repository.change_request_processed?(456)).to be false
      end
    end
  end

  describe "auto PR tracking" do
    describe "#auto_pr_iteration_count" do
      it "returns 0 when not tracked" do
        expect(repository.auto_pr_iteration_count(456)).to eq(0)
      end

      it "returns current count" do
        repository.record_auto_pr_iteration(456)
        repository.record_auto_pr_iteration(456)

        expect(repository.auto_pr_iteration_count(456)).to eq(2)
      end
    end

    describe "#auto_pr_cap_reached?" do
      before do
        3.times { repository.record_auto_pr_iteration(456)}
      end

      it "returns true when cap reached" do
        expect(repository.auto_pr_cap_reached?(456, cap: 3)).to be true
      end

      it "returns false when under cap" do
        expect(repository.auto_pr_cap_reached?(456, cap: 5)).to be false
      end
    end

    describe "#complete_auto_pr" do
      it "marks PR as completed" do
        repository.record_auto_pr_iteration(456)
        repository.complete_auto_pr(456)

        data = repository.auto_pr_data(456)
        expect(data[:status]).to eq("completed")
      end
    end
  end

  describe "detection comment tracking" do
    describe "#detection_comment_posted?" do
      it "returns false when not posted" do
        expect(repository.detection_comment_posted?("issue_123_merge_conflict")).to be false
      end

      it "returns true when posted" do
        repository.record_detection_comment("issue_123_merge_conflict", timestamp: Time.now.utc.iso8601)

        expect(repository.detection_comment_posted?("issue_123_merge_conflict")).to be true
      end
    end
  end

  describe "feedback tracking" do
    describe "#tracked_comments" do
      it "returns comments from plans" do
        repository.record_plan(123, {summary: "Plan", comment_id: "comment_1"})

        comments = repository.tracked_comments

        expect(comments.size).to eq(1)
        expect(comments.first[:comment_id]).to eq("comment_1")
        expect(comments.first[:processor_type]).to eq("plan")
      end
    end

    describe "#track_comment_for_feedback" do
      it "tracks comment" do
        repository.track_comment_for_feedback(comment_id: "123", processor_type: "custom", number: 456)

        comments = repository.tracked_comments
        custom = comments.find { |c| c[:processor_type] == "custom"}

        expect(custom[:comment_id]).to eq("123")
        expect(custom[:number]).to eq(456)
      end
    end

    describe "#processed_reaction_ids" do
      it "returns empty array when none processed" do
        expect(repository.processed_reaction_ids("comment_1")).to eq([])
      end

      it "returns processed IDs" do
        repository.mark_reaction_processed("comment_1", 100)
        repository.mark_reaction_processed("comment_1", 101)

        ids = repository.processed_reaction_ids("comment_1")

        expect(ids).to contain_exactly(100, 101)
      end
    end
  end
end
