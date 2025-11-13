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
end
