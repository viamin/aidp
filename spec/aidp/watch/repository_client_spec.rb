# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Aidp::Watch::RepositoryClient do
  let(:owner) { "testowner" }
  let(:repo) { "testrepo" }
  let(:client) { described_class.new(owner: owner, repo: repo, gh_available: gh_available) }
  let(:gh_available) { true }

  describe ".parse_issues_url" do
    it "parses GitHub issues URL with full path" do
      url = "https://github.com/owner/repo/issues"
      expect(described_class.parse_issues_url(url)).to eq(%w[owner repo])
    end

    it "parses GitHub issues URL without /issues" do
      url = "https://github.com/owner/repo"
      expect(described_class.parse_issues_url(url)).to eq(%w[owner repo])
    end

    it "parses GitHub issues URL with trailing slash" do
      url = "https://github.com/owner/repo/"
      expect(described_class.parse_issues_url(url)).to eq(%w[owner repo])
    end

    it "parses shorthand owner/repo format" do
      url = "owner/repo"
      expect(described_class.parse_issues_url(url)).to eq(%w[owner repo])
    end

    it "raises error for invalid URL" do
      expect do
        described_class.parse_issues_url("invalid-url")
      end.to raise_error(ArgumentError, /Unsupported issues URL/)
    end
  end

  describe "#initialize" do
    it "creates instance with owner and repo" do
      expect(client.owner).to eq(owner)
      expect(client.repo).to eq(repo)
    end

    it "sets gh_available when provided" do
      client = described_class.new(owner: owner, repo: repo, gh_available: false)
      expect(client.gh_available?).to be false
    end

    it "auto-detects gh_available when not provided" do
      binary_checker = double("BinaryChecker", gh_cli_available?: true)
      client = described_class.new(owner: owner, repo: repo, binary_checker: binary_checker)
      expect(client.gh_available?).to be true
    end
  end

  describe "#full_repo" do
    it "returns owner/repo format" do
      expect(client.full_repo).to eq("testowner/testrepo")
    end
  end

  describe "#list_issues" do
    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "calls GitHub CLI to list issues" do
        allow(client).to receive(:list_issues_via_gh).and_return([])
        client.list_issues
        expect(client).to have_received(:list_issues_via_gh).with(labels: [], state: "open")
      end

      it "passes labels and state parameters" do
        allow(client).to receive(:list_issues_via_gh).and_return([])
        client.list_issues(labels: %w[bug enhancement], state: "closed")
        expect(client).to have_received(:list_issues_via_gh).with(labels: %w[bug enhancement], state: "closed")
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "calls GitHub API to list issues" do
        allow(client).to receive(:list_issues_via_api).and_return([])
        client.list_issues
        expect(client).to have_received(:list_issues_via_api).with(labels: [], state: "open")
      end
    end
  end

  describe "#fetch_issue" do
    let(:issue_number) { 123 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "calls GitHub CLI to fetch issue" do
        allow(client).to receive(:fetch_issue_via_gh).and_return({})
        client.fetch_issue(issue_number)
        expect(client).to have_received(:fetch_issue_via_gh).with(issue_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "calls GitHub API to fetch issue" do
        allow(client).to receive(:fetch_issue_via_api).and_return({})
        client.fetch_issue(issue_number)
        expect(client).to have_received(:fetch_issue_via_api).with(issue_number)
      end
    end
  end

  describe "#post_comment" do
    let(:issue_number) { 123 }
    let(:body) { "Test comment" }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "calls GitHub CLI to post comment" do
        allow(client).to receive(:post_comment_via_gh).and_return("success")
        client.post_comment(issue_number, body)
        expect(client).to have_received(:post_comment_via_gh).with(issue_number, body)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "calls GitHub API to post comment" do
        allow(client).to receive(:post_comment_via_api).and_return("success")
        client.post_comment(issue_number, body)
        expect(client).to have_received(:post_comment_via_api).with(issue_number, body)
      end
    end
  end

  describe "#create_pull_request" do
    let(:pr_params) do
      {
        title: "Test PR",
        body: "Test PR body",
        head: "feature-branch",
        base: "main",
        issue_number: 123
      }
    end

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "calls GitHub CLI to create PR" do
        allow(client).to receive(:create_pull_request_via_gh).and_return("PR created")
        client.create_pull_request(**pr_params)
        expect(client).to have_received(:create_pull_request_via_gh).with(pr_params.merge(draft: false, assignee: nil))
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "raises error" do
        expect do
          client.create_pull_request(**pr_params)
        end.to raise_error("GitHub CLI not available - cannot create PR")
      end
    end
  end

  describe "#create_pull_request_via_gh" do
    let(:gh_available) { true }
    let(:status) { instance_double(Process::Status, success?: true) }

    it "uses supported flags only for gh pr create" do
      expect(Open3).to receive(:capture3).with(
        "gh", "pr", "create",
        "--repo", "testowner/testrepo",
        "--title", "Title",
        "--body", "Body",
        "--head", "feature",
        "--base", "main",
        "--draft",
        "--assignee", "octocat"
      ).and_return(["https://example.com/pr/1", "", status])

      output = client.send(
        :create_pull_request_via_gh,
        title: "Title",
        body: "Body",
        head: "feature",
        base: "main",
        issue_number: 123,
        draft: true,
        assignee: "octocat"
      )
      expect(output).to include("https://example.com/pr/1")
    end
  end

  describe "#add_labels" do
    let(:issue_number) { 123 }
    let(:labels) { %w[bug enhancement] }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "adds labels via gh CLI" do
        expect(Open3).to receive(:capture3).with(
          "gh", "issue", "edit", "123", "--repo", "testowner/testrepo",
          "--add-label", "bug", "--add-label", "enhancement"
        ).and_return(["success", "", double(success?: true)])

        client.add_labels(issue_number, labels)
      end

      it "skips when labels array is empty" do
        expect(Open3).not_to receive(:capture3)
        client.add_labels(issue_number, [])
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "adds labels via GitHub API" do
        uri = URI("https://api.github.com/repos/testowner/testrepo/issues/123/labels")
        request = instance_double(Net::HTTP::Post)
        http = instance_double(Net::HTTP)
        response = double(code: "201", body: "success")

        expect(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)
        expect(request).to receive(:[]=).with("Content-Type", "application/json")
        expect(request).to receive(:body=).with(JSON.dump({labels: labels}))
        expect(Net::HTTP).to receive(:start).with(uri.hostname, uri.port, use_ssl: true).and_yield(http)
        expect(http).to receive(:request).with(request).and_return(response)

        client.add_labels(issue_number, labels)
      end

      it "skips when labels array is empty" do
        expect(Net::HTTP).not_to receive(:start)
        client.add_labels(issue_number, [])
      end
    end
  end

  describe "#remove_labels" do
    let(:issue_number) { 123 }
    let(:labels) { %w[wontfix duplicate] }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "removes labels via gh CLI" do
        expect(Open3).to receive(:capture3).with(
          "gh", "issue", "edit", issue_number.to_s, "--repo", client.full_repo,
          "--remove-label", "wontfix", "--remove-label", "duplicate"
        ).and_return(["success", "", double(success?: true)])

        client.remove_labels(issue_number, labels)
      end

      it "skips when labels array is empty" do
        expect(Open3).not_to receive(:capture3)
        client.remove_labels(issue_number, [])
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "removes labels via GitHub API" do
        http = instance_double(Net::HTTP)

        # Mock the first label deletion
        uri1 = URI("https://api.github.com/repos/#{client.full_repo}/issues/#{issue_number}/labels/wontfix")
        request1 = instance_double(Net::HTTP::Delete)
        response1 = double(code: "204")

        expect(Net::HTTP::Delete).to receive(:new).with(uri1).and_return(request1)
        expect(Net::HTTP).to receive(:start).with(uri1.hostname, uri1.port, use_ssl: true).and_yield(http)
        expect(http).to receive(:request).with(request1).and_return(response1)

        # Mock the second label deletion
        uri2 = URI("https://api.github.com/repos/#{client.full_repo}/issues/#{issue_number}/labels/duplicate")
        request2 = instance_double(Net::HTTP::Delete)
        response2 = double(code: "204")

        expect(Net::HTTP::Delete).to receive(:new).with(uri2).and_return(request2)
        expect(Net::HTTP).to receive(:start).with(uri2.hostname, uri2.port, use_ssl: true).and_yield(http)
        expect(http).to receive(:request).with(request2).and_return(response2)

        client.remove_labels(issue_number, labels)
      end

      it "handles 404 responses gracefully" do
        http = instance_double(Net::HTTP)
        uri = URI("https://api.github.com/repos/#{client.full_repo}/issues/#{issue_number}/labels/nonexistent")
        request = instance_double(Net::HTTP::Delete)
        response = double(code: "404")

        expect(Net::HTTP::Delete).to receive(:new).with(uri).and_return(request)
        expect(Net::HTTP).to receive(:start).with(uri.hostname, uri.port, use_ssl: true).and_yield(http)
        expect(http).to receive(:request).with(request).and_return(response)

        expect {
          client.remove_labels(issue_number, ["nonexistent"])
        }.not_to raise_error
      end

      it "skips when labels array is empty" do
        expect(Net::HTTP).not_to receive(:start)
        client.remove_labels(issue_number, [])
      end
    end
  end

  describe "#replace_labels" do
    let(:issue_number) { 123 }
    let(:old_labels) { %w[aidp-plan] }
    let(:new_labels) { %w[aidp-needs-input] }

    it "removes old labels and adds new labels" do
      allow(client).to receive(:remove_labels)
      allow(client).to receive(:add_labels)

      client.replace_labels(issue_number, old_labels: old_labels, new_labels: new_labels)

      expect(client).to have_received(:remove_labels).with(issue_number, *old_labels)
      expect(client).to have_received(:add_labels).with(issue_number, *new_labels)
    end

    it "skips removing when old_labels is empty" do
      allow(client).to receive(:remove_labels)
      allow(client).to receive(:add_labels)

      client.replace_labels(issue_number, old_labels: [], new_labels: new_labels)

      expect(client).not_to have_received(:remove_labels)
      expect(client).to have_received(:add_labels).with(issue_number, *new_labels)
    end

    it "skips adding when new_labels is empty" do
      allow(client).to receive(:remove_labels)
      allow(client).to receive(:add_labels)

      client.replace_labels(issue_number, old_labels: old_labels, new_labels: [])

      expect(client).to have_received(:remove_labels).with(issue_number, *old_labels)
      expect(client).not_to have_received(:add_labels)
    end
  end

  describe Aidp::Watch::RepositoryClient::BinaryChecker do
    let(:checker) { described_class.new }

    describe "#gh_cli_available?" do
      it "returns true when gh command is available" do
        allow(Open3).to receive(:capture3).with("gh", "--version").and_return(["", "", double(success?: true)])
        expect(checker.gh_cli_available?).to be true
      end

      it "returns false when gh command fails" do
        allow(Open3).to receive(:capture3).with("gh", "--version").and_return(["", "error", double(success?: false)])
        expect(checker.gh_cli_available?).to be false
      end

      it "returns false when gh command is not found" do
        allow(Open3).to receive(:capture3).with("gh", "--version").and_raise(Errno::ENOENT)
        expect(checker.gh_cli_available?).to be false
      end
    end
  end

  describe "private methods" do
    describe "#list_issues_via_gh" do
      let(:gh_response) do
        JSON.dump([
          {
            "number" => 1,
            "title" => "Test issue",
            "labels" => [{"name" => "bug"}],
            "updatedAt" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "url" => "https://github.com/testowner/testrepo/issues/1",
            "assignees" => [{"login" => "user1"}]
          }
        ])
      end

      it "successfully lists issues" do
        allow(Open3).to receive(:capture3).and_return([gh_response, "", double(success?: true)])
        result = client.send(:list_issues_via_gh, labels: [], state: "open")

        expect(result).to be_an(Array)
        expect(result.first).to include(:number, :title, :labels, :updated_at, :state, :url, :assignees)
      end

      it "handles GitHub CLI error" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])
        allow(client).to receive(:warn)

        result = client.send(:list_issues_via_gh, labels: [], state: "open")
        expect(result).to eq([])
      end

      it "handles JSON parsing error" do
        allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])
        allow(client).to receive(:warn)

        result = client.send(:list_issues_via_gh, labels: [], state: "open")
        expect(result).to eq([])
      end

      it "includes labels in command when provided" do
        expected_cmd = ["gh", "issue", "list", "--repo", "testowner/testrepo", "--state", "open", "--json",
          "number,title,labels,updatedAt,state,url,assignees", "--label", "bug", "--label", "enhancement"]
        allow(Open3).to receive(:capture3).with(*expected_cmd).and_return([gh_response, "", double(success?: true)])

        client.send(:list_issues_via_gh, labels: %w[bug enhancement], state: "open")
        expect(Open3).to have_received(:capture3).with(*expected_cmd)
      end
    end

    describe "#list_issues_via_api" do
      let(:api_response) do
        JSON.dump([
          {
            "number" => 1,
            "title" => "Test issue",
            "labels" => [{"name" => "bug"}],
            "updated_at" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "html_url" => "https://github.com/testowner/testrepo/issues/1",
            "assignees" => [{"login" => "user1"}]
          }
        ])
      end

      it "successfully lists issues" do
        uri = URI("https://api.github.com/repos/testowner/testrepo/issues?state=open")
        response = double(code: "200", body: api_response)
        allow(Net::HTTP).to receive(:get_response).with(uri).and_return(response)

        result = client.send(:list_issues_via_api, labels: [], state: "open")
        expect(result).to be_an(Array)
        expect(result.first).to include(:number, :title, :labels, :updated_at, :state, :url, :assignees)
      end

      it "returns empty array on API error" do
        uri = URI("https://api.github.com/repos/testowner/testrepo/issues?state=open")
        response = double(code: "404", body: "Not found")
        allow(Net::HTTP).to receive(:get_response).with(uri).and_return(response)

        result = client.send(:list_issues_via_api, labels: [], state: "open")
        expect(result).to eq([])
      end

      it "includes labels in query when provided" do
        uri_with_labels = URI("https://api.github.com/repos/testowner/testrepo/issues?state=open&labels=bug%2Cenhancement")
        response = double(code: "200", body: "[]")
        allow(Net::HTTP).to receive(:get_response).with(uri_with_labels).and_return(response)

        client.send(:list_issues_via_api, labels: %w[bug enhancement], state: "open")
        expect(Net::HTTP).to have_received(:get_response).with(uri_with_labels)
      end

      it "filters out pull requests" do
        api_response_with_pr = JSON.dump([
          {
            "number" => 1,
            "title" => "Test issue",
            "labels" => [],
            "updated_at" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "html_url" => "https://github.com/testowner/testrepo/issues/1",
            "assignees" => []
          },
          {
            "number" => 2,
            "title" => "Test PR",
            "labels" => [],
            "updated_at" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "html_url" => "https://github.com/testowner/testrepo/pull/2",
            "assignees" => [],
            "pull_request" => {"url" => "https://api.github.com/repos/testowner/testrepo/pulls/2"}
          }
        ])

        uri = URI("https://api.github.com/repos/testowner/testrepo/issues?state=open")
        response = double(code: "200", body: api_response_with_pr)
        allow(Net::HTTP).to receive(:get_response).with(uri).and_return(response)

        result = client.send(:list_issues_via_api, labels: [], state: "open")
        expect(result.size).to eq(1)
        expect(result.first[:number]).to eq(1)
      end

      it "handles exception gracefully" do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Network error"))
        allow(client).to receive(:warn)

        result = client.send(:list_issues_via_api, labels: [], state: "open")
        expect(result).to eq([])
      end
    end

    describe "#normalize_issue" do
      it "normalizes GitHub CLI issue data" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "labels" => [{"name" => "bug"}],
          "updatedAt" => "2023-01-01T00:00:00Z",
          "state" => "open",
          "url" => "https://github.com/test/test/issues/1",
          "assignees" => [{"login" => "user1"}]
        }

        result = client.send(:normalize_issue, raw)
        expect(result).to eq({
          number: 1,
          title: "Test",
          labels: ["bug"],
          updated_at: "2023-01-01T00:00:00Z",
          state: "open",
          url: "https://github.com/test/test/issues/1",
          assignees: ["user1"]
        })
      end

      it "handles string labels" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "labels" => %w[bug enhancement],
          "updatedAt" => "2023-01-01T00:00:00Z",
          "state" => "open",
          "url" => "https://github.com/test/test/issues/1",
          "assignees" => ["user1"]
        }

        result = client.send(:normalize_issue, raw)
        expect(result[:labels]).to eq(%w[bug enhancement])
      end
    end

    describe "#normalize_issue_api" do
      it "normalizes GitHub API issue data" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "labels" => [{"name" => "bug"}],
          "updated_at" => "2023-01-01T00:00:00Z",
          "state" => "open",
          "html_url" => "https://github.com/test/test/issues/1",
          "assignees" => [{"login" => "user1"}]
        }

        result = client.send(:normalize_issue_api, raw)
        expect(result).to eq({
          number: 1,
          title: "Test",
          labels: ["bug"],
          updated_at: "2023-01-01T00:00:00Z",
          state: "open",
          url: "https://github.com/test/test/issues/1",
          assignees: ["user1"]
        })
      end
    end

    describe "#normalize_comment" do
      it "normalizes hash comment data" do
        comment = {
          "body" => "Test comment",
          "author" => "user1",
          "createdAt" => "2023-01-01T00:00:00Z"
        }

        result = client.send(:normalize_comment, comment)
        expect(result).to eq({
          "body" => "Test comment",
          "author" => "user1",
          "createdAt" => "2023-01-01T00:00:00Z"
        })
      end

      it "handles API format with user.login" do
        comment = {
          "body" => "Test comment",
          "user" => {"login" => "user1"},
          "created_at" => "2023-01-01T00:00:00Z"
        }

        result = client.send(:normalize_comment, comment)
        expect(result).to eq({
          "body" => "Test comment",
          "author" => "user1",
          "createdAt" => "2023-01-01T00:00:00Z"
        })
      end

      it "handles string comment" do
        comment = "Just a string comment"

        result = client.send(:normalize_comment, comment)
        expect(result).to eq({"body" => "Just a string comment"})
      end
    end
  end

  describe "#most_recent_label_actor" do
    let(:issue_number) { 123 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches the most recent label actor via GraphQL" do
        graphql_response = {
          "data" => {
            "repository" => {
              "issue" => {
                "timelineItems" => {
                  "nodes" => [
                    {
                      "createdAt" => "2023-01-01T10:00:00Z",
                      "actor" => {"login" => "user1"}
                    },
                    {
                      "createdAt" => "2023-01-02T10:00:00Z",
                      "actor" => {"login" => "user2"}
                    }
                  ]
                }
              }
            }
          }
        }

        allow(Open3).to receive(:capture3).and_return([JSON.dump(graphql_response), "", double(success?: true)])
        result = client.most_recent_label_actor(issue_number)

        expect(result).to eq("user2")
      end

      it "returns nil when there are no label events" do
        graphql_response = {
          "data" => {
            "repository" => {
              "issue" => {
                "timelineItems" => {
                  "nodes" => []
                }
              }
            }
          }
        }

        allow(Open3).to receive(:capture3).and_return([JSON.dump(graphql_response), "", double(success?: true)])
        result = client.most_recent_label_actor(issue_number)

        expect(result).to be_nil
      end

      it "filters out events without actors" do
        graphql_response = {
          "data" => {
            "repository" => {
              "issue" => {
                "timelineItems" => {
                  "nodes" => [
                    {
                      "createdAt" => "2023-01-01T10:00:00Z",
                      "actor" => nil
                    },
                    {
                      "createdAt" => "2023-01-02T10:00:00Z",
                      "actor" => {"login" => "user2"}
                    }
                  ]
                }
              }
            }
          }
        }

        allow(Open3).to receive(:capture3).and_return([JSON.dump(graphql_response), "", double(success?: true)])
        result = client.most_recent_label_actor(issue_number)

        expect(result).to eq("user2")
      end

      it "returns nil when GraphQL query fails" do
        allow(Open3).to receive(:capture3).and_return(["", "GraphQL error", double(success?: false)])
        result = client.most_recent_label_actor(issue_number)

        expect(result).to be_nil
      end

      it "returns nil when JSON parsing fails" do
        allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])
        result = client.most_recent_label_actor(issue_number)

        expect(result).to be_nil
      end

      it "returns nil on unexpected errors" do
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Unexpected error"))
        result = client.most_recent_label_actor(issue_number)

        expect(result).to be_nil
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "returns nil" do
        result = client.most_recent_label_actor(issue_number)
        expect(result).to be_nil
      end
    end
  end

  describe "#fetch_pull_request" do
    let(:pr_number) { 456 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches PR via gh CLI" do
        allow(client).to receive(:fetch_pull_request_via_gh).and_return({number: pr_number})
        client.fetch_pull_request(pr_number)
        expect(client).to have_received(:fetch_pull_request_via_gh).with(pr_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "fetches PR via API" do
        allow(client).to receive(:fetch_pull_request_via_api).and_return({number: pr_number})
        client.fetch_pull_request(pr_number)
        expect(client).to have_received(:fetch_pull_request_via_api).with(pr_number)
      end
    end
  end

  describe "#fetch_pull_request_diff" do
    let(:pr_number) { 456 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches diff via gh CLI" do
        allow(client).to receive(:fetch_pull_request_diff_via_gh).and_return("diff content")
        client.fetch_pull_request_diff(pr_number)
        expect(client).to have_received(:fetch_pull_request_diff_via_gh).with(pr_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "fetches diff via API" do
        allow(client).to receive(:fetch_pull_request_diff_via_api).and_return("diff content")
        client.fetch_pull_request_diff(pr_number)
        expect(client).to have_received(:fetch_pull_request_diff_via_api).with(pr_number)
      end
    end
  end

  describe "#fetch_pull_request_files" do
    let(:pr_number) { 456 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches files via gh CLI" do
        allow(client).to receive(:fetch_pull_request_files_via_gh).and_return([])
        client.fetch_pull_request_files(pr_number)
        expect(client).to have_received(:fetch_pull_request_files_via_gh).with(pr_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "fetches files via API" do
        allow(client).to receive(:fetch_pull_request_files_via_api).and_return([])
        client.fetch_pull_request_files(pr_number)
        expect(client).to have_received(:fetch_pull_request_files_via_api).with(pr_number)
      end
    end
  end

  describe "#fetch_pr_comments" do
    let(:pr_number) { 789 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches comments via gh CLI" do
        allow(client).to receive(:fetch_pr_comments_via_gh).and_return([])
        client.fetch_pr_comments(pr_number)
        expect(client).to have_received(:fetch_pr_comments_via_gh).with(pr_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "fetches comments via API" do
        allow(client).to receive(:fetch_pr_comments_via_api).and_return([])
        client.fetch_pr_comments(pr_number)
        expect(client).to have_received(:fetch_pr_comments_via_api).with(pr_number)
      end
    end
  end

  describe "#fetch_ci_status" do
    let(:pr_number) { 456 }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "fetches CI status via gh CLI" do
        allow(client).to receive(:fetch_ci_status_via_gh).and_return({state: "success"})
        client.fetch_ci_status(pr_number)
        expect(client).to have_received(:fetch_ci_status_via_gh).with(pr_number)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "fetches CI status via API" do
        allow(client).to receive(:fetch_ci_status_via_api).and_return({state: "success"})
        client.fetch_ci_status(pr_number)
        expect(client).to have_received(:fetch_ci_status_via_api).with(pr_number)
      end
    end
  end

  describe "#post_review_comment" do
    let(:pr_number) { 456 }
    let(:body) { "Review comment" }

    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "posts review comment via gh CLI" do
        allow(client).to receive(:post_review_comment_via_gh).and_return("success")
        client.post_review_comment(pr_number, body)
        expect(client).to have_received(:post_review_comment_via_gh).with(pr_number, body, commit_id: nil, path: nil, line: nil)
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "posts review comment via API" do
        allow(client).to receive(:post_review_comment_via_api).and_return("success")
        client.post_review_comment(pr_number, body)
        expect(client).to have_received(:post_review_comment_via_api).with(pr_number, body, commit_id: nil, path: nil, line: nil)
      end
    end
  end

  describe "#list_pull_requests" do
    context "when GitHub CLI is available" do
      let(:gh_available) { true }

      it "lists PRs via gh CLI" do
        allow(client).to receive(:list_pull_requests_via_gh).and_return([])
        client.list_pull_requests
        expect(client).to have_received(:list_pull_requests_via_gh).with(labels: [], state: "open")
      end
    end

    context "when GitHub CLI is not available" do
      let(:gh_available) { false }

      it "lists PRs via API" do
        allow(client).to receive(:list_pull_requests_via_api).and_return([])
        client.list_pull_requests
        expect(client).to have_received(:list_pull_requests_via_api).with(labels: [], state: "open")
      end
    end
  end

  describe "PR operations via gh CLI" do
    let(:gh_available) { true }
    let(:pr_number) { 456 }

    describe "#fetch_pull_request_via_gh" do
      it "fetches PR details successfully" do
        gh_response = JSON.dump({
          "number" => pr_number,
          "title" => "Test PR",
          "body" => "PR description",
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "url" => "https://github.com/testowner/testrepo/pull/456",
          "headRefName" => "feature-branch",
          "baseRefName" => "main",
          "commits" => [{"oid" => "abc123"}],
          "author" => {"login" => "user1"},
          "mergeable" => "MERGEABLE"
        })

        allow(Open3).to receive(:capture3).and_return([gh_response, "", double(success?: true)])
        result = client.send(:fetch_pull_request_via_gh, pr_number)

        expect(result).to include(:number, :title, :body, :head_ref, :base_ref, :head_sha)
        expect(result[:number]).to eq(pr_number)
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:fetch_pull_request_via_gh, pr_number)
        }.to raise_error(/GitHub CLI error/)
      end

      it "raises error on JSON parse failure" do
        allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])

        expect {
          client.send(:fetch_pull_request_via_gh, pr_number)
        }.to raise_error(/Failed to parse/)
      end
    end

    describe "#fetch_pull_request_diff_via_gh" do
      it "fetches PR diff successfully" do
        diff_content = "diff --git a/file.rb b/file.rb\n+new line"
        allow(Open3).to receive(:capture3).and_return([diff_content, "", double(success?: true)])

        result = client.send(:fetch_pull_request_diff_via_gh, pr_number)
        expect(result).to eq(diff_content)
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:fetch_pull_request_diff_via_gh, pr_number)
        }.to raise_error(/Failed to fetch PR diff/)
      end
    end

    describe "#fetch_pull_request_files_via_gh" do
      it "fetches PR files successfully" do
        files_response = JSON.dump([
          {
            "filename" => "test.rb",
            "status" => "modified",
            "additions" => 5,
            "deletions" => 2,
            "changes" => 7,
            "patch" => "@@ -1,1 +1,1 @@"
          }
        ])

        allow(Open3).to receive(:capture3).and_return([files_response, "", double(success?: true)])
        result = client.send(:fetch_pull_request_files_via_gh, pr_number)

        expect(result).to be_an(Array)
        expect(result.first).to include(:filename, :status, :additions, :deletions)
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:fetch_pull_request_files_via_gh, pr_number)
        }.to raise_error(/Failed to fetch PR files/)
      end

      it "raises error on JSON parse failure" do
        allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])

        expect {
          client.send(:fetch_pull_request_files_via_gh, pr_number)
        }.to raise_error(/Failed to parse PR files/)
      end
    end

    describe "#list_pull_requests_via_gh" do
      it "lists PRs successfully" do
        gh_response = JSON.dump([
          {
            "number" => 1,
            "title" => "Test PR",
            "labels" => [{"name" => "bug"}],
            "updatedAt" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "url" => "https://github.com/testowner/testrepo/pull/1",
            "headRefName" => "feature",
            "baseRefName" => "main"
          }
        ])

        allow(Open3).to receive(:capture3).and_return([gh_response, "", double(success?: true)])
        result = client.send(:list_pull_requests_via_gh, labels: [], state: "open")

        expect(result).to be_an(Array)
        expect(result.first).to include(:number, :title, :head_ref, :base_ref)
      end

      it "handles CLI error" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])
        allow(client).to receive(:warn)

        result = client.send(:list_pull_requests_via_gh, labels: [], state: "open")
        expect(result).to eq([])
      end

      it "handles JSON parse error" do
        allow(Open3).to receive(:capture3).and_return(["invalid json", "", double(success?: true)])
        allow(client).to receive(:warn)

        result = client.send(:list_pull_requests_via_gh, labels: [], state: "open")
        expect(result).to eq([])
      end
    end

    describe "#post_review_comment_via_gh" do
      it "posts general review comment" do
        allow(Open3).to receive(:capture3).and_return(["success", "", double(success?: true)])

        result = client.send(:post_review_comment_via_gh, pr_number, "comment")
        expect(result).to eq("success")
      end

      it "delegates to API for inline comments" do
        allow(client).to receive(:post_review_comment_via_api).and_return("success")

        client.send(:post_review_comment_via_gh, pr_number, "comment", commit_id: "abc", path: "file.rb", line: 10)
        expect(client).to have_received(:post_review_comment_via_api)
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:post_review_comment_via_gh, pr_number, "comment")
        }.to raise_error(/Failed to post review comment/)
      end
    end
  end

  describe "PR operations via API" do
    let(:gh_available) { false }
    let(:pr_number) { 456 }

    describe "#fetch_pull_request_via_api" do
      it "fetches PR details successfully" do
        api_response = JSON.dump({
          "number" => pr_number,
          "title" => "Test PR",
          "body" => "PR description",
          "user" => {"login" => "user1"},
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "html_url" => "https://github.com/testowner/testrepo/pull/456",
          "head" => {"ref" => "feature-branch", "sha" => "abc123"},
          "base" => {"ref" => "main"},
          "mergeable" => true
        })

        response = double(code: "200", body: api_response)
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        result = client.send(:fetch_pull_request_via_api, pr_number)
        expect(result).to include(:number, :title, :body, :head_ref, :base_ref, :head_sha)
      end

      it "raises error on API failure" do
        response = double(code: "404", body: "Not found")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect {
          client.send(:fetch_pull_request_via_api, pr_number)
        }.to raise_error(/GitHub API error/)
      end
    end

    describe "#fetch_pull_request_diff_via_api" do
      it "fetches diff successfully" do
        diff_content = "diff --git a/file.rb b/file.rb\n+new line"
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Get)
        response = double(code: "200", body: diff_content)

        allow(Net::HTTP::Get).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:fetch_pull_request_diff_via_api, pr_number)
        expect(result).to eq(diff_content)
      end

      it "raises error on API failure" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Get)
        response = double(code: "404")

        allow(Net::HTTP::Get).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:fetch_pull_request_diff_via_api, pr_number)
        }.to raise_error(/GitHub API diff failed/)
      end
    end

    describe "#fetch_pull_request_files_via_api" do
      it "fetches files successfully" do
        files_response = JSON.dump([
          {
            "filename" => "test.rb",
            "status" => "modified",
            "additions" => 5,
            "deletions" => 2,
            "changes" => 7,
            "patch" => "@@ -1,1 +1,1 @@"
          }
        ])

        response = double(code: "200", body: files_response)
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        result = client.send(:fetch_pull_request_files_via_api, pr_number)
        expect(result).to be_an(Array)
        expect(result.first).to include(:filename, :status)
      end

      it "raises error on API failure" do
        response = double(code: "404", body: "Not found")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect {
          client.send(:fetch_pull_request_files_via_api, pr_number)
        }.to raise_error(/GitHub API files failed/)
      end

      it "raises error on JSON parse failure" do
        response = double(code: "200", body: "invalid json")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect {
          client.send(:fetch_pull_request_files_via_api, pr_number)
        }.to raise_error(/Failed to parse PR files/)
      end
    end

    describe "#list_pull_requests_via_api" do
      it "lists PRs successfully" do
        api_response = JSON.dump([
          {
            "number" => 1,
            "title" => "Test PR",
            "labels" => [{"name" => "bug"}],
            "updated_at" => "2023-01-01T00:00:00Z",
            "state" => "open",
            "html_url" => "https://github.com/testowner/testrepo/pull/1",
            "head" => {"ref" => "feature"},
            "base" => {"ref" => "main"}
          }
        ])

        response = double(code: "200", body: api_response)
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        result = client.send(:list_pull_requests_via_api, labels: [], state: "open")
        expect(result).to be_an(Array)
        expect(result.first).to include(:number, :title, :head_ref, :base_ref)
      end

      it "handles API error" do
        response = double(code: "500", body: "Server error")
        allow(Net::HTTP).to receive(:get_response).and_return(response)
        allow(client).to receive(:warn)

        result = client.send(:list_pull_requests_via_api, labels: [], state: "open")
        expect(result).to eq([])
      end

      it "handles exception" do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Network error"))
        allow(client).to receive(:warn)

        result = client.send(:list_pull_requests_via_api, labels: [], state: "open")
        expect(result).to eq([])
      end
    end

    describe "#post_review_comment_via_api" do
      it "posts general comment successfully" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "201", body: "success")

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:post_review_comment_via_api, pr_number, "comment")
        expect(result).to eq("success")
      end

      it "posts inline review comment successfully" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "200", body: "success")

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:post_review_comment_via_api, pr_number, "comment", commit_id: "abc", path: "file.rb", line: 10)
        expect(result).to eq("success")
      end

      it "raises error on API failure for general comment" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "400", body: "Bad request")

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:post_review_comment_via_api, pr_number, "comment")
        }.to raise_error(/GitHub API comment failed/)
      end

      it "raises error on API failure for inline comment" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "422", body: "Unprocessable", start_with?: false)

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:post_review_comment_via_api, pr_number, "comment", commit_id: "abc", path: "file.rb", line: 10)
        }.to raise_error(/GitHub API review comment failed/)
      end
    end
  end

  describe "CI status operations" do
    let(:pr_number) { 456 }
    let(:head_sha) { "abc123" }

    describe "#fetch_ci_status_via_gh" do
      let(:gh_available) { true }

      it "fetches CI status successfully" do
        pr_data = {head_sha: head_sha}
        check_runs_response = JSON.dump({
          "check_runs" => [
            {
              "name" => "test",
              "status" => "completed",
              "conclusion" => "success",
              "details_url" => "https://example.com",
              "output" => {"title" => "Tests passed"}
            }
          ]
        })

        allow(client).to receive(:fetch_pull_request_via_gh).and_return(pr_data)
        allow(Open3).to receive(:capture3).and_return([check_runs_response, "", double(success?: true)])

        result = client.send(:fetch_ci_status_via_gh, pr_number)
        expect(result[:sha]).to eq(head_sha)
        expect(result[:state]).to eq("success")
        expect(result[:checks]).to be_an(Array)
      end

      it "returns unknown state on CLI failure" do
        pr_data = {head_sha: head_sha}
        allow(client).to receive(:fetch_pull_request_via_gh).and_return(pr_data)
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        result = client.send(:fetch_ci_status_via_gh, pr_number)
        expect(result[:state]).to eq("unknown")
      end

      it "returns unknown state on exception" do
        allow(client).to receive(:fetch_pull_request_via_gh).and_raise(StandardError.new("Error"))

        result = client.send(:fetch_ci_status_via_gh, pr_number)
        expect(result[:state]).to eq("unknown")
        expect(result[:sha]).to be_nil
      end
    end

    describe "#fetch_ci_status_via_api" do
      let(:gh_available) { false }

      it "fetches CI status successfully" do
        pr_data = {head_sha: head_sha}
        check_runs_response = JSON.dump({
          "check_runs" => [
            {
              "name" => "test",
              "status" => "completed",
              "conclusion" => "success",
              "details_url" => "https://example.com",
              "output" => {"title" => "Tests passed"}
            }
          ]
        })

        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Get)
        response = double(code: "200", body: check_runs_response)

        allow(client).to receive(:fetch_pull_request_via_api).and_return(pr_data)
        allow(Net::HTTP::Get).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:fetch_ci_status_via_api, pr_number)
        expect(result[:sha]).to eq(head_sha)
        expect(result[:state]).to eq("success")
      end

      it "returns unknown state on API failure" do
        pr_data = {head_sha: head_sha}
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Get)
        response = double(code: "404")

        allow(client).to receive(:fetch_pull_request_via_api).and_return(pr_data)
        allow(Net::HTTP::Get).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:fetch_ci_status_via_api, pr_number)
        expect(result[:state]).to eq("unknown")
      end

      it "returns unknown state on exception" do
        allow(client).to receive(:fetch_pull_request_via_api).and_raise(StandardError.new("Error"))

        result = client.send(:fetch_ci_status_via_api, pr_number)
        expect(result[:state]).to eq("unknown")
        expect(result[:sha]).to be_nil
      end
    end

    describe "#normalize_ci_status" do
      it "returns success when all checks pass" do
        check_runs = [
          {"name" => "test1", "status" => "completed", "conclusion" => "success", "details_url" => "url", "output" => {}},
          {"name" => "test2", "status" => "completed", "conclusion" => "success", "details_url" => "url", "output" => {}}
        ]

        result = client.send(:normalize_ci_status, check_runs, head_sha)
        expect(result[:state]).to eq("success")
        expect(result[:sha]).to eq(head_sha)
      end

      it "returns failure when any check fails" do
        check_runs = [
          {"name" => "test1", "status" => "completed", "conclusion" => "success", "details_url" => "url", "output" => {}},
          {"name" => "test2", "status" => "completed", "conclusion" => "failure", "details_url" => "url", "output" => {}}
        ]

        result = client.send(:normalize_ci_status, check_runs, head_sha)
        expect(result[:state]).to eq("failure")
      end

      it "returns pending when checks are not completed" do
        check_runs = [
          {"name" => "test1", "status" => "in_progress", "conclusion" => nil, "details_url" => "url", "output" => {}}
        ]

        result = client.send(:normalize_ci_status, check_runs, head_sha)
        expect(result[:state]).to eq("pending")
      end

      it "returns unknown for mixed conclusions" do
        check_runs = [
          {"name" => "test1", "status" => "completed", "conclusion" => "skipped", "details_url" => "url", "output" => {}}
        ]

        result = client.send(:normalize_ci_status, check_runs, head_sha)
        expect(result[:state]).to eq("unknown")
      end
    end
  end

  describe "normalization methods for PRs" do
    describe "#normalize_pull_request" do
      it "normalizes gh CLI PR data" do
        raw = {
          "number" => 1,
          "title" => "Test PR",
          "labels" => [{"name" => "bug"}],
          "updatedAt" => "2023-01-01T00:00:00Z",
          "state" => "open",
          "url" => "https://github.com/test/test/pull/1",
          "headRefName" => "feature",
          "baseRefName" => "main"
        }

        result = client.send(:normalize_pull_request, raw)
        expect(result[:head_ref]).to eq("feature")
        expect(result[:base_ref]).to eq("main")
      end
    end

    describe "#normalize_pull_request_api" do
      it "normalizes API PR data" do
        raw = {
          "number" => 1,
          "title" => "Test PR",
          "labels" => [{"name" => "bug"}],
          "updated_at" => "2023-01-01T00:00:00Z",
          "state" => "open",
          "html_url" => "https://github.com/test/test/pull/1",
          "head" => {"ref" => "feature"},
          "base" => {"ref" => "main"}
        }

        result = client.send(:normalize_pull_request_api, raw)
        expect(result[:head_ref]).to eq("feature")
        expect(result[:base_ref]).to eq("main")
      end
    end

    describe "#normalize_pull_request_detail" do
      it "normalizes detailed PR data with commits" do
        raw = {
          "number" => 1,
          "title" => "Test PR",
          "body" => "Description",
          "author" => {"login" => "user1"},
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "url" => "https://github.com/test/test/pull/1",
          "headRefName" => "feature",
          "baseRefName" => "main",
          "commits" => [{"oid" => "abc123"}],
          "mergeable" => "MERGEABLE"
        }

        result = client.send(:normalize_pull_request_detail, raw)
        expect(result[:head_sha]).to eq("abc123")
        expect(result[:mergeable]).to eq("MERGEABLE")
      end

      it "handles missing body" do
        raw = {
          "number" => 1,
          "title" => "Test PR",
          "author" => {"login" => "user1"},
          "labels" => [],
          "state" => "open",
          "url" => "https://github.com/test/test/pull/1",
          "headRefName" => "feature",
          "baseRefName" => "main",
          "headRefOid" => "abc123",
          "mergeable" => "MERGEABLE"
        }

        result = client.send(:normalize_pull_request_detail, raw)
        expect(result[:body]).to eq("")
        expect(result[:head_sha]).to eq("abc123")
      end
    end

    describe "#normalize_pull_request_detail_api" do
      it "normalizes detailed API PR data" do
        raw = {
          "number" => 1,
          "title" => "Test PR",
          "body" => "Description",
          "user" => {"login" => "user1"},
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "html_url" => "https://github.com/test/test/pull/1",
          "head" => {"ref" => "feature", "sha" => "abc123"},
          "base" => {"ref" => "main"},
          "mergeable" => true
        }

        result = client.send(:normalize_pull_request_detail_api, raw)
        expect(result[:head_sha]).to eq("abc123")
        expect(result[:mergeable]).to be true
      end
    end

    describe "#normalize_pr_file" do
      it "normalizes PR file data" do
        raw = {
          "filename" => "test.rb",
          "status" => "modified",
          "additions" => 5,
          "deletions" => 2,
          "changes" => 7,
          "patch" => "@@ -1,1 +1,1 @@"
        }

        result = client.send(:normalize_pr_file, raw)
        expect(result).to eq({
          filename: "test.rb",
          status: "modified",
          additions: 5,
          deletions: 2,
          changes: 7,
          patch: "@@ -1,1 +1,1 @@"
        })
      end
    end
  end

  describe "issue detail operations" do
    let(:issue_number) { 123 }

    describe "#fetch_issue_via_gh" do
      let(:gh_available) { true }

      it "fetches issue details successfully" do
        gh_response = JSON.dump({
          "number" => issue_number,
          "title" => "Test issue",
          "body" => "Issue description",
          "author" => {"login" => "user1"},
          "comments" => [{"body" => "Comment", "author" => "user2", "createdAt" => "2023-01-01"}],
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "assignees" => [{"login" => "user3"}],
          "url" => "https://github.com/testowner/testrepo/issues/123",
          "updatedAt" => "2023-01-01T00:00:00Z"
        })

        allow(Open3).to receive(:capture3).and_return([gh_response, "", double(success?: true)])
        result = client.send(:fetch_issue_via_gh, issue_number)

        expect(result).to include(:number, :title, :body, :comments, :author)
        expect(result[:comments]).to be_an(Array)
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:fetch_issue_via_gh, issue_number)
        }.to raise_error(/GitHub CLI error/)
      end
    end

    describe "#fetch_issue_via_api" do
      let(:gh_available) { false }

      it "fetches issue details successfully" do
        issue_response = JSON.dump({
          "number" => issue_number,
          "title" => "Test issue",
          "body" => "Issue description",
          "user" => {"login" => "user1"},
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "assignees" => [{"login" => "user3"}],
          "html_url" => "https://github.com/testowner/testrepo/issues/123",
          "updated_at" => "2023-01-01T00:00:00Z"
        })

        comments_response = JSON.dump([
          {"body" => "Comment", "user" => {"login" => "user2"}, "created_at" => "2023-01-01"}
        ])

        allow(Net::HTTP).to receive(:get_response).and_return(
          double(code: "200", body: issue_response),
          double(code: "200", body: comments_response)
        )

        result = client.send(:fetch_issue_via_api, issue_number)
        expect(result).to include(:number, :title, :body, :comments)
      end

      it "raises error on API failure" do
        response = double(code: "404", body: "Not found")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect {
          client.send(:fetch_issue_via_api, issue_number)
        }.to raise_error(/GitHub API error/)
      end
    end

    describe "#fetch_comments_via_api" do
      let(:gh_available) { false }

      it "fetches comments successfully" do
        comments_response = JSON.dump([
          {"body" => "Comment 1", "user" => {"login" => "user1"}, "created_at" => "2023-01-01"},
          {"body" => "Comment 2", "user" => {"login" => "user2"}, "created_at" => "2023-01-02"}
        ])

        response = double(code: "200", body: comments_response)
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        result = client.send(:fetch_comments_via_api, issue_number)
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result.first["author"]).to eq("user1")
      end

      it "returns empty array on API failure" do
        response = double(code: "404")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        result = client.send(:fetch_comments_via_api, issue_number)
        expect(result).to eq([])
      end

      it "returns empty array on exception" do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Error"))

        result = client.send(:fetch_comments_via_api, issue_number)
        expect(result).to eq([])
      end
    end

    describe "#post_comment_via_gh" do
      let(:gh_available) { true }

      it "posts comment successfully" do
        allow(Open3).to receive(:capture3).and_return(["success", "", double(success?: true)])

        result = client.send(:post_comment_via_gh, issue_number, "Test comment")
        expect(result).to eq("success")
      end

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:post_comment_via_gh, issue_number, "Test comment")
        }.to raise_error(/Failed to post comment/)
      end
    end

    describe "#post_comment_via_api" do
      let(:gh_available) { false }

      it "posts comment successfully" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "201", body: "success")

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        result = client.send(:post_comment_via_api, issue_number, "Test comment")
        expect(result).to eq("success")
      end

      it "raises error on API failure" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "400", body: "Bad request", start_with?: false)

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:post_comment_via_api, issue_number, "Test comment")
        }.to raise_error(/GitHub API comment failed/)
      end
    end

    describe "#add_labels_via_gh" do
      let(:gh_available) { true }

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:add_labels_via_gh, issue_number, ["bug"])
        }.to raise_error(/Failed to add labels/)
      end
    end

    describe "#add_labels_via_api" do
      let(:gh_available) { false }

      it "raises error on API failure" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = double(code: "400", start_with?: false)

        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:add_labels_via_api, issue_number, ["bug"])
        }.to raise_error(/Failed to add labels/)
      end
    end

    describe "#remove_labels_via_gh" do
      let(:gh_available) { true }

      it "raises error on CLI failure" do
        allow(Open3).to receive(:capture3).and_return(["", "Error", double(success?: false)])

        expect {
          client.send(:remove_labels_via_gh, issue_number, ["bug"])
        }.to raise_error(/Failed to remove labels/)
      end
    end

    describe "#remove_labels_via_api" do
      let(:gh_available) { false }

      it "raises error on API failure with non-404 code" do
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Delete)
        response = double(code: "500", start_with?: false)

        allow(Net::HTTP::Delete).to receive(:new).and_return(request)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect {
          client.send(:remove_labels_via_api, issue_number, ["bug"])
        }.to raise_error(/Failed to remove label/)
      end
    end

    describe "#normalize_issue_detail" do
      it "normalizes gh CLI issue detail" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "body" => "Description",
          "author" => {"login" => "user1"},
          "comments" => [{"body" => "Comment", "author" => "user2", "createdAt" => "2023-01-01"}],
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "assignees" => [{"login" => "user3"}],
          "url" => "https://github.com/test/test/issues/1",
          "updatedAt" => "2023-01-01T00:00:00Z"
        }

        result = client.send(:normalize_issue_detail, raw)
        expect(result[:comments]).to be_an(Array)
        expect(result[:author]).to eq("user1")
      end

      it "handles missing body" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "author" => {"login" => "user1"},
          "comments" => [],
          "labels" => [],
          "state" => "open",
          "assignees" => [],
          "url" => "https://github.com/test/test/issues/1",
          "updatedAt" => "2023-01-01T00:00:00Z"
        }

        result = client.send(:normalize_issue_detail, raw)
        expect(result[:body]).to eq("")
      end
    end

    describe "#normalize_issue_detail_api" do
      it "normalizes API issue detail" do
        raw = {
          "number" => 1,
          "title" => "Test",
          "body" => "Description",
          "user" => {"login" => "user1"},
          "comments" => [{"body" => "Comment", "author" => "user2", "createdAt" => "2023-01-01"}],
          "labels" => [{"name" => "bug"}],
          "state" => "open",
          "assignees" => [{"login" => "user3"}],
          "html_url" => "https://github.com/test/test/issues/1",
          "updated_at" => "2023-01-01T00:00:00Z"
        }

        result = client.send(:normalize_issue_detail_api, raw)
        expect(result[:author]).to eq("user1")
      end
    end
  end
end
