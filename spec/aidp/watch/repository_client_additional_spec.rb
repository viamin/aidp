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
      allow(Aidp).to receive(:log_warn)
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

  describe "utility helpers and fallbacks" do
    let(:client) { described_class.new(owner: owner, repo: repo, gh_available: true) }

    before do
      allow(Aidp).to receive(:log_warn)
      allow(Aidp).to receive(:log_debug)
      allow(Aidp).to receive(:log_error)
      allow(client).to receive(:sleep)
    end

    it "parses issues urls and raises on invalid format" do
      expect(described_class.parse_issues_url("https://github.com/a/b")).to eq(%w[a b])
      expect(described_class.parse_issues_url("a/b")).to eq(%w[a b])
      expect { described_class.parse_issues_url("bad://url") }.to raise_error(ArgumentError)
    end

    it "retries gh operations on transient errors" do
      attempts = 0
      result = client.send(:with_gh_retry, "op", max_retries: 2, initial_delay: 0.1) do
        attempts += 1
        raise "connection reset" if attempts < 3
        "ok"
      end

      expect(result).to eq("ok")
      expect(attempts).to eq(3)
      expect(client).to have_received(:sleep).with(0.1)
      expect(client).to have_received(:sleep).with(0.2)
    end

    it "fails gh retry after exhaustion" do
      expect do
        client.send(:with_gh_retry, "op") { raise "unexpected EOF" }
      end.to raise_error(RuntimeError)
    end

    it "lists pull requests via gh and api" do
      gh_list = [{number: 1, title: "PR", labels: [{name: "bug"}], updatedAt: "t", state: "open", url: "u", headRefName: "h", baseRefName: "b"}].to_json
      gh_status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return([gh_list, "", gh_status])
      pr_client = described_class.new(owner: owner, repo: repo, gh_available: true)
      expect(pr_client.list_pull_requests(labels: [], state: "open").first[:head_ref]).to eq("h")

      api_pr = [{number: 2, title: "API PR", labels: [{name: "api"}], updated_at: "t2", state: "closed", html_url: "u2", head: {ref: "h2"}, base: {ref: "b2"}}].to_json
      api_response = instance_double(Net::HTTPResponse, code: "200", body: api_pr)
      allow(Net::HTTP).to receive(:get_response).and_return(api_response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)
      expect(api_client.list_pull_requests(labels: [], state: "open").first[:head_ref]).to eq("h2")
    end

    it "fetches pull request details via gh" do
      pr_body = {number: 1, title: "PR", body: "body", labels: ["bug"], state: "open", url: "u", headRefName: "h", baseRefName: "b", commits: [{oid: "sha"}], mergeable: true}.to_json
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return([pr_body, "", status])

      detail = client.send(:fetch_pull_request_via_gh, 1)
      expect(detail[:head_sha]).to eq("sha")
      expect(detail[:mergeable]).to eq(true)
    end

    it "raises when fetch_pull_request_via_api fails" do
      api_response = instance_double(Net::HTTPResponse, code: "500", body: "{}")
      allow(Net::HTTP).to receive(:get_response).and_return(api_response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)

      expect { api_client.send(:fetch_pull_request_via_api, 5) }.to raise_error(/GitHub API error/)
    end

    it "fetches pull request diff via api and raises on failure" do
      success_response = instance_double(Net::HTTPResponse, code: "200", body: "diff")
      allow(Net::HTTP).to receive(:start).and_return(success_response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)

      expect(api_client.send(:fetch_pull_request_diff_via_api, 10)).to eq("diff")

      fail_response = instance_double(Net::HTTPResponse, code: "404", body: "")
      allow(Net::HTTP).to receive(:start).and_return(fail_response)
      expect { api_client.send(:fetch_pull_request_diff_via_api, 10) }.to raise_error(/diff failed/)
    end

    it "fetches pull request files via gh and api" do
      files_json = [{filename: "a.rb", status: "modified", additions: 1, deletions: 0, changes: 1, patch: "diff"}].to_json
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return([files_json, "", status])
      expect(client.send(:fetch_pull_request_files_via_gh, 3).first[:filename]).to eq("a.rb")

      api_response = instance_double(Net::HTTPResponse, code: "200", body: files_json)
      allow(Net::HTTP).to receive(:get_response).and_return(api_response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)
      expect(api_client.send(:fetch_pull_request_files_via_api, 3).first[:filename]).to eq("a.rb")
    end

    it "posts review comment via api for general comment" do
      response = instance_double(Net::HTTPResponse, code: "201", body: "ok")
      allow(Net::HTTP).to receive(:start).and_return(response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)

      expect(api_client.send(:post_review_comment_via_api, 9, "body")).to eq("ok")
    end

    it "raises when inline review comment fails" do
      response = instance_double(Net::HTTPResponse, code: "500", body: "err")
      allow(Net::HTTP).to receive(:start).and_return(response)
      api_client = described_class.new(owner: owner, repo: repo, gh_available: false)

      expect {
        api_client.send(:post_review_comment_via_api, 9, "body", commit_id: "sha", path: "file.rb", line: 2)
      }.to raise_error(/review comment failed/)
    end

    it "fetches pr comments via api and handles failures" do
      ok_response = instance_double(Net::HTTPResponse, code: "200", body: [{id: 1, body: "b", user: {login: "me"}, created_at: "t", updated_at: "t"}].to_json)
      allow(Net::HTTP).to receive(:get_response).and_return(ok_response)
      expect(client.send(:fetch_pr_comments_via_api, 11).first[:id]).to eq(1)

      bad_response = instance_double(Net::HTTPResponse, code: "500", body: "{}")
      allow(Net::HTTP).to receive(:get_response).and_return(bad_response)
      expect(client.send(:fetch_pr_comments_via_api, 11)).to eq([])
    end

    it "returns most recent label actor via gh" do
      graphql_response = {
        data: {
          repository: {
            issue: {
              timelineItems: {
                nodes: [
                  {"createdAt" => "2023-01-01", "actor" => {"login" => "bot"}},
                  {"createdAt" => "2023-01-02", "actor" => {"login" => "human"}}
                ]
              }
            }
          }
        }
      }.to_json
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return([graphql_response, "", status])

      expect(client.send(:most_recent_label_actor_via_gh, 7)).to eq("human")
    end
  end
end
