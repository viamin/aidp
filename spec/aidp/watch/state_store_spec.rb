# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::StateStore do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:repository) { "owner/repo" }
  let(:store) { described_class.new(project_dir: tmp_dir, repository: repository) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "plan persistence" do
    it "records and retrieves plan data" do
      expect(store.plan_processed?(101)).to be false

      store.record_plan(101, summary: "Build feature", tasks: ["Task"], questions: ["Q"], comment_body: "body")

      expect(store.plan_processed?(101)).to be true
      data = store.plan_data(101)
      expect(data["summary"]).to eq("Build feature")
      expect(data["tasks"]).to eq(["Task"])
      expect(data["questions"]).to eq(["Q"])

      # Reload to ensure persistence
      reloaded = described_class.new(project_dir: tmp_dir, repository: repository)
      expect(reloaded.plan_processed?(101)).to be true
      expect(reloaded.plan_data(101)["summary"]).to eq("Build feature")
    end

    it "tracks plan iterations" do
      # First plan
      store.record_plan(102, summary: "Initial plan", tasks: ["Task 1"], questions: [], comment_body: "body1", comment_id: "comment-1")

      expect(store.plan_iteration_count(102)).to eq(1)
      data = store.plan_data(102)
      expect(data["iteration"]).to eq(1)
      expect(data["previous_iteration_at"]).to be_nil

      # Second iteration
      first_timestamp = data["posted_at"]
      sleep 0.01 # Ensure different timestamp
      store.record_plan(102, summary: "Revised plan", tasks: ["Task 2"], questions: [], comment_body: "body2", comment_id: "comment-1")

      expect(store.plan_iteration_count(102)).to eq(2)
      data = store.plan_data(102)
      expect(data["iteration"]).to eq(2)
      expect(data["previous_iteration_at"]).to eq(first_timestamp)
      expect(data["summary"]).to eq("Revised plan")

      # Third iteration
      sleep 0.01
      store.record_plan(102, summary: "Final plan", tasks: ["Task 3"], questions: [], comment_body: "body3", comment_id: "comment-1")

      expect(store.plan_iteration_count(102)).to eq(3)
      data = store.plan_data(102)
      expect(data["iteration"]).to eq(3)
    end

    it "persists comment_id across iterations" do
      store.record_plan(103, summary: "Plan v1", tasks: [], questions: [], comment_body: "body", comment_id: "comment-123")

      data = store.plan_data(103)
      expect(data["comment_id"]).to eq("comment-123")

      store.record_plan(103, summary: "Plan v2", tasks: [], questions: [], comment_body: "body", comment_id: "comment-123")

      data = store.plan_data(103)
      expect(data["comment_id"]).to eq("comment-123")
    end
  end

  describe "build status" do
    it "records build lifecycle" do
      expect(store.build_status(202)).to eq({})

      store.record_build_status(202, status: "running", details: {branch: "aidp/issue-202"})
      status = store.build_status(202)
      expect(status["status"]).to eq("running")
      expect(status["branch"]).to eq("aidp/issue-202")

      store.record_build_status(202, status: "completed", details: {pr_url: "https://example.com"})
      final_status = store.build_status(202)
      expect(final_status["status"]).to eq("completed")
      expect(final_status["pr_url"]).to eq("https://example.com")
    end
  end

  describe "build/workstream lookup" do
    it "returns workstream details for an issue" do
      store.record_build_status(301, status: "completed", details: {branch: "aidp/issue-301", workstream: "issue-301-slug", pr_url: "https://github.com/test/repo/pull/400"})

      result = store.workstream_for_issue(301)

      expect(result[:issue_number]).to eq(301)
      expect(result[:branch]).to eq("aidp/issue-301")
      expect(result[:workstream]).to eq("issue-301-slug")
      expect(result[:pr_url]).to include("/pull/400")
      expect(result[:status]).to eq("completed")
    end

    it "finds build metadata by PR number" do
      store.record_build_status(302, status: "completed", details: {branch: "aidp/issue-302", workstream: "issue-302-slug", pr_url: "https://github.com/test/repo/pull/401"})

      result = store.find_build_by_pr(401)

      expect(result[:issue_number]).to eq(302)
      expect(result[:branch]).to eq("aidp/issue-302")
      expect(result[:workstream]).to eq("issue-302-slug")
      expect(result[:pr_url]).to include("/pull/401")
      expect(result[:status]).to eq("completed")
    end

    it "returns nil when PR is unknown" do
      store.record_build_status(303, status: "completed", details: {branch: "aidp/issue-303", workstream: "issue-303-slug", pr_url: "https://github.com/test/repo/pull/402"})

      expect(store.find_build_by_pr(999)).to be_nil
    end
  end

  describe "change request tracking" do
    it "tracks change request processing" do
      expect(store.change_request_processed?(303)).to be false

      store.record_change_request(303, status: "completed", changes_applied: 2, commits: 1)

      expect(store.change_request_processed?(303)).to be true
      data = store.change_request_data(303)
      expect(data["status"]).to eq("completed")
      expect(data["changes_applied"]).to eq(2)
      expect(data["commits"]).to eq(1)

      # Reload to ensure persistence
      reloaded = described_class.new(project_dir: tmp_dir, repository: repository)
      expect(reloaded.change_request_processed?(303)).to be true
      expect(reloaded.change_request_data(303)["status"]).to eq("completed")
    end

    it "tracks clarification count" do
      store.record_change_request(404, status: "needs_clarification", clarification_count: 1)
      data = store.change_request_data(404)
      expect(data["clarification_count"]).to eq(1)

      store.record_change_request(404, status: "needs_clarification", clarification_count: 2)
      data = store.change_request_data(404)
      expect(data["clarification_count"]).to eq(2)
    end

    it "resets change request state" do
      store.record_change_request(505, status: "completed", changes_applied: 1)
      expect(store.change_request_processed?(505)).to be true

      store.reset_change_request_state(505)
      expect(store.change_request_processed?(505)).to be false
    end
  end

  describe "detection comment tracking" do
    it "tracks posted detection comments" do
      detection_key = "issue_123_aidp-plan"
      expect(store.detection_comment_posted?(detection_key)).to be false

      timestamp = Time.now.utc.iso8601
      store.record_detection_comment(detection_key, timestamp: timestamp)

      expect(store.detection_comment_posted?(detection_key)).to be true

      # Reload to ensure persistence
      reloaded = described_class.new(project_dir: tmp_dir, repository: repository)
      expect(reloaded.detection_comment_posted?(detection_key)).to be true
    end

    it "tracks detection comments for different item types and labels" do
      issue_key = "issue_100_aidp-plan"
      pr_key = "pr_200_aidp-review"
      another_label_key = "issue_100_aidp-build"

      timestamp = Time.now.utc.iso8601
      store.record_detection_comment(issue_key, timestamp: timestamp)
      store.record_detection_comment(pr_key, timestamp: timestamp)

      expect(store.detection_comment_posted?(issue_key)).to be true
      expect(store.detection_comment_posted?(pr_key)).to be true
      expect(store.detection_comment_posted?(another_label_key)).to be false
    end
  end

  describe "worktree cleanup tracking" do
    it "returns nil when no cleanup has been performed" do
      expect(store.last_worktree_cleanup).to be_nil
    end

    it "records and retrieves cleanup timestamp" do
      store.record_worktree_cleanup(cleaned: 3, skipped: 2, errors: [])

      last_cleanup = store.last_worktree_cleanup
      expect(last_cleanup).to be_a(Time)
      expect(last_cleanup).to be_within(60).of(Time.now)
    end

    it "records cleanup statistics" do
      errors = [{slug: "issue-1", error: "failed"}]
      store.record_worktree_cleanup(cleaned: 5, skipped: 3, errors: errors)

      data = store.worktree_cleanup_data
      expect(data["last_cleaned_count"]).to eq(5)
      expect(data["last_skipped_count"]).to eq(3)
      expect(data["last_errors"]).to eq([{"slug" => "issue-1", "error" => "failed"}])
    end

    it "persists cleanup data across reloads" do
      store.record_worktree_cleanup(cleaned: 2, skipped: 1, errors: [])

      reloaded = described_class.new(project_dir: tmp_dir, repository: repository)
      expect(reloaded.last_worktree_cleanup).to be_a(Time)
      expect(reloaded.worktree_cleanup_data["last_cleaned_count"]).to eq(2)
    end

    it "overwrites previous cleanup data" do
      store.record_worktree_cleanup(cleaned: 1, skipped: 0, errors: [])
      first_cleanup = store.last_worktree_cleanup

      sleep 0.01 # Ensure different timestamp
      store.record_worktree_cleanup(cleaned: 5, skipped: 2, errors: [])
      second_cleanup = store.last_worktree_cleanup

      expect(second_cleanup).to be > first_cleanup
      expect(store.worktree_cleanup_data["last_cleaned_count"]).to eq(5)
    end

    it "handles invalid timestamp gracefully" do
      # Manually set invalid timestamp
      store.send(:state)["worktree_cleanup"] = {"last_cleanup_at" => "invalid-timestamp"}

      expect(store.last_worktree_cleanup).to be_nil
    end
  end
end
