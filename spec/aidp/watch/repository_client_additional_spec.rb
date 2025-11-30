# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Aidp::Watch::RepositoryClient do
  let(:owner) { "testowner" }
  let(:repo) { "testrepo" }

  describe "#list_issues_via_gh" do
    it "parses gh output and normalizes issues" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      gh_output = [
        {number: 1, title: "Issue", labels: [{name: "bug"}], updatedAt: "2024-01-01", state: "open", url: "https://example", assignees: [{login: "octo"}]}
      ].to_json

      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).and_return([gh_output, "", status])

      issues = client.list_issues(labels: [], state: "open")

      expect(issues.first).to include(
        number: 1,
        title: "Issue",
        labels: ["bug"],
        assignees: ["octo"]
      )
    end

    it "returns empty when gh fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      status = instance_double(Process::Status, success?: false)
      expect(Open3).to receive(:capture3).and_return(["", "err", status])

      issues = client.list_issues(labels: [], state: "open")
      expect(issues).to eq([])
    end
  end

  describe "#list_issues_via_api" do
    it "parses API response and normalizes issues" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response_body = [
        {number: 2, title: "API Issue", labels: [{name: "help"}], updated_at: "2024-02-02", state: "open", html_url: "https://api.example", assignees: [{login: "alice"}]}
      ].to_json

      response = instance_double(Net::HTTPResponse, code: "200", body: response_body)
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      issues = client.list_issues(labels: [], state: "open")

      expect(issues.first).to include(
        number: 2,
        title: "API Issue",
        labels: ["help"],
        assignees: ["alice"]
      )
    end

    it "returns empty when API fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response = instance_double(Net::HTTPResponse, code: "500", body: "{}")
      expect(Net::HTTP).to receive(:get_response).and_return(response)

      expect(client.list_issues(labels: [], state: "open")).to eq([])
    end
  end

  describe "CI status normalization" do
    let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

    before do
      allow(Aidp).to receive(:log_debug)
    end

    it "returns unknown when no checks exist" do
      status = client.send(:normalize_ci_status, [], "sha123")
      expect(status[:state]).to eq("unknown")
      expect(status[:checks]).to be_empty
    end

    it "returns failure when any check failed" do
      checks = [
        {"name" => "lint", "status" => "completed", "conclusion" => "failure"},
        {"name" => "test", "status" => "completed", "conclusion" => "success"}
      ]
      status = client.send(:normalize_ci_status, checks, "sha123")
      expect(status[:state]).to eq("failure")
    end

    it "returns pending when incomplete checks exist" do
      checks = [
        {"name" => "lint", "status" => "in_progress", "conclusion" => nil}
      ]
      status = client.send(:normalize_ci_status, checks, "sha123")
      expect(status[:state]).to eq("pending")
    end

    it "returns success when all checks succeeded" do
      checks = [
        {"name" => "lint", "status" => "completed", "conclusion" => "success"},
        {"name" => "test", "status" => "completed", "conclusion" => "success"}
      ]
      status = client.send(:normalize_ci_status, checks, "sha123")
      expect(status[:state]).to eq("success")
    end

    it "returns unknown when checks completed without success or failure" do
      checks = [
        {"name" => "lint", "status" => "completed", "conclusion" => "neutral"}
      ]
      status = client.send(:normalize_ci_status, checks, "sha123")
      expect(status[:state]).to eq("unknown")
    end

    it "normalizes commit status states to conclusions" do
      expect(client.send(:normalize_commit_status_to_conclusion, "success")).to eq("success")
      expect(client.send(:normalize_commit_status_to_conclusion, "failure")).to eq("failure")
      expect(client.send(:normalize_commit_status_to_conclusion, "error")).to eq("failure")
      expect(client.send(:normalize_commit_status_to_conclusion, "pending")).to be_nil
      expect(client.send(:normalize_commit_status_to_conclusion, nil)).to be_nil
    end

    it "normalizes issue data helpers" do
      raw = {"number" => 1, "title" => "t", "labels" => [{"name" => "bug"}], "updatedAt" => "now", "state" => "open", "url" => "u", "assignees" => [{"login" => "me"}]}
      api_raw = {"number" => 2, "title" => "t2", "labels" => [{"name" => "api"}], "updated_at" => "now2", "state" => "closed", "html_url" => "u2", "assignees" => [{"login" => "you"}]}
      detail_raw = raw.merge("body" => "body", "comments" => [{"body" => "c", "author" => "a", "createdAt" => "t"}])
      api_detail = api_raw.merge("body" => "b2", "comments" => [{"body" => "c2", "user" => {"login" => "b"}}])

      expect(client.send(:normalize_issue, raw)[:labels]).to eq(["bug"])
      expect(client.send(:normalize_issue_api, api_raw)[:labels]).to eq(["api"])
      expect(client.send(:normalize_issue_detail, detail_raw)[:comments].first["author"]).to eq("a")
      expect(client.send(:normalize_issue_detail_api, api_detail)[:comments].first["author"]).to eq("b")
      expect(client.send(:normalize_comment, "plain")).to eq({"body" => "plain"})
    end
  end

  describe "#fetch_ci_status_via_gh" do
    it "combines check runs and commit statuses" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      allow(client).to receive(:fetch_pull_request_via_gh).and_return(head_sha: "abc123")

      check_runs_response = {
        "check_runs" => [
          {"name" => "lint", "status" => "completed", "conclusion" => "success"}
        ]
      }.to_json
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).and_return([check_runs_response, "", status])
      allow(client).to receive(:fetch_commit_statuses_via_gh).and_return([
        {"context" => "ci", "state" => "failure", "target_url" => "http://ci", "description" => "failed"}
      ])

      result = client.send(:fetch_ci_status_via_gh, 1)

      expect(result[:state]).to eq("failure")
      expect(result[:checks].length).to eq(2)
    end
  end

  describe "#fetch_ci_status_via_api" do
    it "returns pending when check is not completed" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      allow(client).to receive(:fetch_pull_request_via_api).and_return(head_sha: "def456")
      allow(client).to receive(:fetch_commit_statuses_via_api).and_return([])

      response_body = {
        "check_runs" => [
          {"name" => "lint", "status" => "in_progress", "conclusion" => nil}
        ]
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: response_body)
      expect(Net::HTTP).to receive(:start).and_return(response)

      result = client.send(:fetch_ci_status_via_api, 2)

      expect(result[:state]).to eq("pending")
      expect(result[:checks].first[:name]).to eq("lint")
    end

    it "returns unknown when API fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      allow(client).to receive(:fetch_pull_request_via_api).and_return(head_sha: "xyz789")
      allow(client).to receive(:fetch_commit_statuses_via_api).and_return([])

      response = instance_double(Net::HTTPResponse, code: "500", body: "{}")
      expect(Net::HTTP).to receive(:start).and_return(response)

      result = client.send(:fetch_ci_status_via_api, 3)
      expect(result[:state]).to eq("unknown")
      expect(result[:checks]).to eq([])
    end
  end

  describe "comment operations" do
    it "finds comment via gh" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      allow(client).to receive(:find_comment_via_gh).and_return({id: 1})
      expect(client.find_comment(1, "Header")).to eq({id: 1})
    end

    it "finds comment via api" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      allow(client).to receive(:find_comment_via_api).and_return({id: 2})
      expect(client.find_comment(2, "Header")).to eq({id: 2})
    end
  end

  describe "label operations" do
    it "replaces labels via gh" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      allow(client).to receive(:remove_labels).and_return(true)
      allow(client).to receive(:add_labels).and_return(true)

      expect(client.replace_labels(5, old_labels: ["a"], new_labels: ["b"])).to be_truthy
      expect(client).to have_received(:remove_labels).with(5, "a")
      expect(client).to have_received(:add_labels).with(5, "b")
    end

    it "fails add_labels_via_api on non-200" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response = instance_double(Net::HTTPResponse, code: "500", body: "err")
      expect(Net::HTTP).to receive(:start).and_return(response)

      expect {
        client.send(:add_labels_via_api, 1, ["bug"])
      }.to raise_error(/Failed to add labels/)
    end

    it "fails remove_labels_via_api on non-200" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response = instance_double(Net::HTTPResponse, code: "500", body: "err")
      expect(Net::HTTP).to receive(:start).and_return(response)

      expect {
        client.send(:remove_labels_via_api, 1, ["bug"])
      }.to raise_error(/Failed to remove label/)
    end
  end

  describe "comment posting and updates" do
    it "raises when post_comment_via_api fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response = instance_double(Net::HTTPResponse, code: "400", body: "err")
      expect(Net::HTTP).to receive(:start).and_return(response)

      expect {
        client.send(:post_comment_via_api, 1, "body")
      }.to raise_error(/GitHub API comment failed/)
    end

    it "raises when update_comment_via_api fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response = instance_double(Net::HTTPResponse, code: "500", body: "err")
      expect(Net::HTTP).to receive(:start).and_return(response)

      expect {
        client.send(:update_comment_via_api, 10, "body")
      }.to raise_error(/update comment failed/)
    end

    it "raises when post_comment_via_gh fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      expect(Open3).to receive(:capture3).and_return(["", "err", status])

      expect {
        client.send(:post_comment_via_gh, 1, "body")
      }.to raise_error(/Failed to post comment/)
    end

    it "raises when update_comment_via_gh fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      expect(Open3).to receive(:capture3).and_return(["", "err", status])

      expect {
        client.send(:update_comment_via_gh, 1, "body")
      }.to raise_error(/Failed to update comment/)
    end
  end
  describe "#fetch_ci_status_via_gh" do
    it "returns unknown when gh call fails" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      allow(client).to receive(:fetch_pull_request_via_gh).and_raise(StandardError.new("boom"))

      result = client.send(:fetch_ci_status_via_gh, 4)
      expect(result[:state]).to eq("unknown")
      expect(result[:sha]).to be_nil
    end
  end

  describe "#fetch_commit_statuses_via_api" do
    it "returns statuses when API succeeds" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      response_body = {statuses: [{context: "ci/check", state: "success"}]}.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: response_body)
      expect(Net::HTTP).to receive(:start).and_return(response)

      statuses = client.send(:fetch_commit_statuses_via_api, "sha123")
      expect(statuses.first["context"]).to eq("ci/check")
    end
  end

  describe "#post_review_comment_via_gh" do
    it "delegates inline comments to API path" do
      client = described_class.new(owner: owner, repo: repo, gh_available: true)
      expect(client).to receive(:post_review_comment_via_api).with(
        12,
        "body",
        commit_id: "abc",
        path: "lib/file.rb",
        line: 10
      )

      client.send(:post_review_comment_via_gh, 12, "body", commit_id: "abc", path: "lib/file.rb", line: 10)
    end
  end
end
