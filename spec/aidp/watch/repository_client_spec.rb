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
        expect(client).to have_received(:create_pull_request_via_gh).with(pr_params)
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
end
