# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/aidp/cli/issue_importer"

RSpec.describe Aidp::IssueImporter do
  let(:test_prompt) { TestPrompt.new }
  let(:importer) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  before do
    # Mock the MessageDisplay module methods
    allow(importer).to receive(:display_message)

    # Change to temp directory for tests
    @original_dir = Dir.pwd
    Dir.chdir(temp_dir)
  end

  after do
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "checks for GitHub CLI availability" do
      # IssueImporter supports gh_available: parameter for test injection
      # When nil, it auto-detects; when set, it uses that value
      importer_with_detection = described_class.new(gh_available: nil)
      expect([true, false]).to include(importer_with_detection.instance_variable_get(:@gh_available))
    end
  end

  describe "#import_issue" do
    let(:issue_data) do
      {
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug", "priority-high"],
        milestone: "v1.0",
        assignees: ["user1"],
        comments: 5,
        source: "api"
      }
    end

    context "with valid identifier" do
      before do
        allow(importer).to receive(:normalize_issue_identifier).and_return("https://github.com/owner/repo/issues/123")
        allow(importer).to receive(:fetch_issue_data).and_return(issue_data)
        allow(importer).to receive(:display_imported_issue)
        allow(importer).to receive(:create_work_loop_prompt)
      end

      it "imports issue successfully" do
        result = importer.import_issue("owner/repo#123")

        expect(result).to eq(issue_data)
        expect(importer).to have_received(:normalize_issue_identifier).with("owner/repo#123")
        expect(importer).to have_received(:fetch_issue_data).with("https://github.com/owner/repo/issues/123")
        expect(importer).to have_received(:display_imported_issue).with(issue_data)
        expect(importer).to have_received(:create_work_loop_prompt).with(issue_data)
      end
    end

    context "with invalid identifier" do
      before do
        allow(importer).to receive(:normalize_issue_identifier).and_return(nil)
      end

      it "returns nil for invalid identifier" do
        result = importer.import_issue("invalid")
        expect(result).to be_nil
      end
    end

    context "when fetch fails" do
      before do
        allow(importer).to receive(:normalize_issue_identifier).and_return("https://github.com/owner/repo/issues/123")
        allow(importer).to receive(:fetch_issue_data).and_return(nil)
      end

      it "returns nil when fetch fails" do
        result = importer.import_issue("owner/repo#123")
        expect(result).to be_nil
      end
    end
  end

  describe "#normalize_issue_identifier" do
    context "with full GitHub URL" do
      it "returns the URL unchanged" do
        url = "https://github.com/rails/rails/issues/12345"
        result = importer.send(:normalize_issue_identifier, url)
        expect(result).to eq(url)
      end
    end

    context "with issue number only" do
      before do
        # Create a git repository with GitHub remote
        system("git init --quiet")
        system("git remote add origin https://github.com/owner/repo.git")
      end

      it "detects current repo and builds URL" do
        result = importer.send(:normalize_issue_identifier, "123")
        expect(result).to eq("https://github.com/owner/repo/issues/123")
      end

      context "when not in a git repo" do
        before do
          FileUtils.rm_rf(".git")
        end

        it "returns nil and displays error" do
          result = importer.send(:normalize_issue_identifier, "123")
          expect(result).to be_nil
          expect(importer).to have_received(:display_message).with(
            "❌ Issue number provided but not in a GitHub repository",
            type: :error
          )
        end
      end
    end

    context "with shorthand format" do
      it "converts owner/repo#123 to full URL" do
        result = importer.send(:normalize_issue_identifier, "rails/rails#12345")
        expect(result).to eq("https://github.com/rails/rails/issues/12345")
      end
    end

    context "with invalid format" do
      it "returns nil and displays error for invalid format" do
        result = importer.send(:normalize_issue_identifier, "invalid-format")
        expect(result).to be_nil
        expect(importer).to have_received(:display_message).with(
          "❌ Invalid issue identifier. Use: URL, number, or owner/repo#number",
          type: :error
        )
      end
    end
  end

  describe "#detect_current_github_repo" do
    context "when in a git repo with GitHub origin" do
      before do
        system("git init --quiet")
      end

      it "detects HTTPS GitHub URL" do
        system("git remote add origin https://github.com/owner/repo.git")
        result = importer.send(:detect_current_github_repo)
        expect(result).to eq("owner/repo")
      end

      it "detects SSH GitHub URL" do
        system("git remote add origin git@github.com:owner/repo.git")
        result = importer.send(:detect_current_github_repo)
        expect(result).to eq("owner/repo")
      end

      it "handles repo names without .git suffix" do
        system("git remote add origin https://github.com/owner/repo")
        result = importer.send(:detect_current_github_repo)
        expect(result).to eq("owner/repo")
      end
    end

    context "when not in a git repo" do
      it "returns nil" do
        result = importer.send(:detect_current_github_repo)
        expect(result).to be_nil
      end
    end

    context "when git command fails" do
      before do
        system("git init --quiet")
        # No remote added, so git remote get-url origin will fail
      end

      it "returns nil when git command fails" do
        result = importer.send(:detect_current_github_repo)
        expect(result).to be_nil
      end
    end
  end

  describe "#fetch_issue_data" do
    let(:issue_url) { "https://github.com/owner/repo/issues/123" }

    context "when GitHub CLI is available" do
      let(:importer) { described_class.new(gh_available: true, enable_bootstrap: false) }

      it "tries GitHub CLI first" do
        allow(importer).to receive(:fetch_via_gh_cli).and_return({number: 123})

        result = importer.send(:fetch_issue_data, issue_url)
        expect(result).to eq({number: 123})
        expect(importer).to have_received(:fetch_via_gh_cli).with("owner", "repo", "123")
      end

      it "falls back to API when GitHub CLI fails" do
        allow(importer).to receive(:fetch_via_gh_cli).and_return(nil)
        allow(importer).to receive(:fetch_via_api).and_return({number: 123})

        result = importer.send(:fetch_issue_data, issue_url)
        expect(result).to eq({number: 123})
        expect(importer).to have_received(:fetch_via_api).with("owner", "repo", "123")
      end
    end

    context "when GitHub CLI is not available" do
      let(:importer) { described_class.new(gh_available: false, enable_bootstrap: false) }

      it "uses API directly" do
        allow(importer).to receive(:fetch_via_api).and_return({number: 123})

        result = importer.send(:fetch_issue_data, issue_url)
        expect(result).to eq({number: 123})
        expect(importer).to have_received(:fetch_via_api).with("owner", "repo", "123")
      end

      it "uses fixture when provided" do
        fixture_data = {
          "owner/repo#123" => {
            "status" => 200,
            "data" => {
              "number" => 123,
              "title" => "Fixture Issue",
              "body" => "Fixture body",
              "state" => "open",
              "html_url" => "https://github.com/owner/repo/issues/123",
              "labels" => [],
              "milestone" => nil,
              "assignees" => [],
              "comments" => 0
            }
          }
        }
        previous = ENV["AIDP_TEST_ISSUE_FIXTURES"]
        ENV["AIDP_TEST_ISSUE_FIXTURES"] = fixture_data.to_json
        allow(importer).to receive(:fetch_via_api)
        allow(importer).to receive(:display_message)

        result = importer.send(:fetch_issue_data, issue_url)
        expect(result).to include(number: 123, title: "Fixture Issue", source: "api")
        expect(importer).not_to have_received(:fetch_via_api)
      ensure
        ENV["AIDP_TEST_ISSUE_FIXTURES"] = previous
      end
    end

    context "with invalid URL" do
      it "returns nil for invalid GitHub URL" do
        result = importer.send(:fetch_issue_data, "not-a-github-url")
        expect(result).to be_nil
      end
    end
  end

  describe "#fetch_via_gh_cli" do
    let(:gh_response) do
      {
        "number" => 123,
        "title" => "Test Issue",
        "body" => "Test description",
        "state" => "OPEN",
        "url" => "https://github.com/owner/repo/issues/123",
        "labels" => [{"name" => "bug"}],
        "milestone" => {"title" => "v1.0"},
        "assignees" => [{"login" => "user1"}],
        "comments" => [1, 2, 3, 4, 5]
      }
    end

    it "executes gh command and normalizes response" do
      allow(importer).to receive(:capture3_with_timeout).and_return([
        JSON.generate(gh_response),
        "",
        double(success?: true, exitstatus: 0)
      ])

      result = importer.send(:fetch_via_gh_cli, "owner", "repo", "123")

      expect(result).to include(
        number: 123,
        title: "Test Issue",
        state: "OPEN",
        source: "gh_cli"
      )
    end

    it "returns nil when gh command fails" do
      allow(importer).to receive(:capture3_with_timeout).and_return([
        "",
        "Error: Not found",
        double(success?: false, exitstatus: 1)
      ])

      result = importer.send(:fetch_via_gh_cli, "owner", "repo", "123")
      expect(result).to be_nil
      expect(importer).to have_received(:display_message).with(
        "⚠️ GitHub CLI failed: Error: Not found",
        type: :warn
      )
    end

    it "returns nil when JSON parsing fails" do
      allow(importer).to receive(:capture3_with_timeout).and_return([
        "invalid json",
        "",
        double(success?: true, exitstatus: 0)
      ])

      result = importer.send(:fetch_via_gh_cli, "owner", "repo", "123")
      expect(result).to be_nil
    end
  end

  describe "#fetch_via_api" do
    let(:api_response) do
      {
        "number" => 123,
        "title" => "Test Issue",
        "body" => "Test description",
        "state" => "open",
        "html_url" => "https://github.com/owner/repo/issues/123",
        "labels" => [{"name" => "bug"}],
        "milestone" => {"title" => "v1.0"},
        "assignees" => [{"login" => "user1"}],
        "comments" => 5
      }
    end

    it "fetches from GitHub API and normalizes response" do
      response = double(
        code: "200",
        body: JSON.generate(api_response)
      )
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = importer.send(:fetch_via_api, "owner", "repo", "123")

      expect(result).to include(
        number: 123,
        title: "Test Issue",
        state: "open",
        source: "api"
      )
    end

    it "handles 404 errors" do
      response = double(code: "404", body: "")
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = importer.send(:fetch_via_api, "owner", "repo", "123")
      expect(result).to be_nil
      expect(importer).to have_received(:display_message).with(
        "❌ Issue not found (may be private)",
        type: :error
      )
    end

    it "handles rate limit errors" do
      response = double(code: "403", body: "")
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = importer.send(:fetch_via_api, "owner", "repo", "123")
      expect(result).to be_nil
      expect(importer).to have_received(:display_message).with(
        "❌ API rate limit exceeded",
        type: :error
      )
    end

    it "handles network errors" do
      allow(Net::HTTP).to receive(:get_response).and_raise(StandardError.new("Network error"))

      result = importer.send(:fetch_via_api, "owner", "repo", "123")
      expect(result).to be_nil
      expect(importer).to have_received(:display_message).with(
        "❌ Failed to fetch issue: Network error",
        type: :error
      )
    end
  end

  describe "#create_work_loop_prompt" do
    let(:issue_data) do
      {
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug"],
        milestone: "v1.0",
        assignees: ["user1"],
        comments: 5,
        source: "api"
      }
    end

    it "creates PROMPT.md file" do
      importer.send(:create_work_loop_prompt, issue_data)

      expect(File.exist?("PROMPT.md")).to be true
      content = File.read("PROMPT.md")

      expect(content).to include("# Work Loop: GitHub Issue #123")
      expect(content).to include("Test Issue")
      expect(content).to include("Test description")
      expect(content).to include("STATUS: COMPLETE")
    end

    it "displays success message" do
      importer.send(:create_work_loop_prompt, issue_data)

      expect(importer).to have_received(:display_message).with(
        "📄 Created PROMPT.md for work loop",
        type: :success
      )
    end
  end

  describe "#generate_prompt_content" do
    let(:issue_data) do
      {
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug", "priority-high"],
        milestone: "v1.0",
        assignees: ["user1", "user2"],
        comments: 5,
        source: "api"
      }
    end

    it "generates complete prompt content" do
      content = importer.send(:generate_prompt_content, issue_data)

      expect(content).to include("# Work Loop: GitHub Issue #123")
      expect(content).to include("**Issue #123**: Test Issue")
      expect(content).to include("**URL**: https://github.com/owner/repo/issues/123")
      expect(content).to include("**State**: open")
      expect(content).to include("**Labels**: bug, priority-high")
      expect(content).to include("**Milestone**: v1.0")
      expect(content).to include("**Assignees**: user1, user2")
      expect(content).to include("Test description")
      expect(content).to include("STATUS: COMPLETE")
      expect(content).to include("source: api")
    end

    it "handles missing optional fields" do
      minimal_data = {
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: [],
        milestone: nil,
        assignees: [],
        comments: 0,
        source: "api"
      }

      content = importer.send(:generate_prompt_content, minimal_data)

      expect(content).not_to include("**Labels**:")
      expect(content).not_to include("**Milestone**:")
      expect(content).not_to include("**Assignees**:")
    end
  end

  describe "#normalize_gh_cli_data" do
    let(:gh_data) do
      {
        "number" => 123,
        "title" => "Test Issue",
        "body" => "Test description",
        "state" => "OPEN",
        "url" => "https://github.com/owner/repo/issues/123",
        "labels" => [{"name" => "bug"}, {"name" => "enhancement"}],
        "milestone" => {"title" => "v1.0"},
        "assignees" => [{"login" => "user1"}],
        "comments" => [1, 2, 3]
      }
    end

    it "normalizes GitHub CLI response format" do
      result = importer.send(:normalize_gh_cli_data, gh_data)

      expect(result).to eq({
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "OPEN",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug", "enhancement"],
        milestone: "v1.0",
        assignees: ["user1"],
        comments: 3,
        source: "gh_cli"
      })
    end

    it "handles nil values gracefully" do
      minimal_data = {
        "number" => 123,
        "title" => "Test",
        "state" => "OPEN",
        "url" => "https://github.com/owner/repo/issues/123"
      }

      result = importer.send(:normalize_gh_cli_data, minimal_data)

      expect(result[:body]).to eq("")
      expect(result[:labels]).to eq([])
      expect(result[:milestone]).to be_nil
      expect(result[:assignees]).to eq([])
      expect(result[:comments]).to eq(0)
    end
  end

  describe "#normalize_api_data" do
    let(:api_data) do
      {
        "number" => 123,
        "title" => "Test Issue",
        "body" => "Test description",
        "state" => "open",
        "html_url" => "https://github.com/owner/repo/issues/123",
        "labels" => [{"name" => "bug"}, {"name" => "enhancement"}],
        "milestone" => {"title" => "v1.0"},
        "assignees" => [{"login" => "user1"}],
        "comments" => 5
      }
    end

    it "normalizes GitHub API response format" do
      result = importer.send(:normalize_api_data, api_data)

      expect(result).to eq({
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug", "enhancement"],
        milestone: "v1.0",
        assignees: ["user1"],
        comments: 5,
        source: "api"
      })
    end
  end

  describe "#gh_cli_available?" do
    it "returns true when gh command is available" do
      allow(Open3).to receive(:capture3).and_return([
        "gh version 2.0.0",
        "",
        double(success?: true)
      ])

      result = importer.send(:gh_cli_available?)
      expect(result).to be true
    end

    it "returns false when gh command fails" do
      allow(Open3).to receive(:capture3).and_return([
        "",
        "command not found",
        double(success?: false)
      ])

      result = importer.send(:gh_cli_available?)
      expect(result).to be false
    end

    it "returns false when gh command is not found" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      result = importer.send(:gh_cli_available?)
      expect(result).to be false
    end
  end
end
