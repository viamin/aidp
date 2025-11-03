# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/repository_safety_checker"
require "aidp/watch/repository_client"

RSpec.describe Aidp::Watch::RepositorySafetyChecker do
  let(:repository_client) do
    instance_double(Aidp::Watch::RepositoryClient,
      full_repo: "owner/repo",
      gh_available?: true)
  end
  let(:config) { {} }
  let(:checker) { described_class.new(repository_client: repository_client, config: config) }

  describe "#validate_watch_mode_safety!" do
    context "with force flag" do
      it "bypasses all safety checks" do
        expect(checker.validate_watch_mode_safety!(force: true)).to be true
      end
    end

    context "with private repository" do
      before do
        allow(checker).to receive(:repository_private?).and_return(true)
      end

      it "allows watch mode" do
        expect(checker.validate_watch_mode_safety!).to be true
      end
    end

    context "with public repository" do
      before do
        allow(checker).to receive(:repository_private?).and_return(false)
      end

      context "when public repos not allowed" do
        let(:config) { {safety: {allow_public_repos: false}} }

        it "raises UnsafeRepositoryError" do
          expect {
            checker.validate_watch_mode_safety!
          }.to raise_error(Aidp::Watch::RepositorySafetyChecker::UnsafeRepositoryError)
        end

        it "includes helpful error message" do
          expect {
            checker.validate_watch_mode_safety!
          }.to raise_error do |error|
            expect(error.message).to include("DISABLED for public repositories")
            expect(error.message).to include("allow_public_repos: true")
            expect(error.message).to include("author_allowlist")
          end
        end
      end

      context "when public repos allowed" do
        let(:config) { {safety: {allow_public_repos: true}} }

        it "allows watch mode with warning" do
          expect(checker.validate_watch_mode_safety!).to be true
        end
      end
    end
  end

  describe "#author_authorized?" do
    let(:issue) { {author: "alice", number: 123} }

    context "with no allowlist configured" do
      let(:config) { {} }

      it "allows all authors (backward compatible)" do
        expect(checker.author_authorized?(issue)).to be true
      end
    end

    context "with allowlist configured" do
      let(:config) { {safety: {author_allowlist: ["alice", "bob"]}} }

      it "allows authors in allowlist" do
        expect(checker.author_authorized?(author: "alice")).to be true
        expect(checker.author_authorized?(author: "bob")).to be true
      end

      it "rejects authors not in allowlist" do
        expect(checker.author_authorized?(author: "eve")).to be false
      end

      it "handles nil author" do
        expect(checker.author_authorized?(author: nil)).to be false
      end

      it "extracts author from assignees if no author field" do
        issue_with_assignees = {assignees: ["alice"], number: 123}
        expect(checker.author_authorized?(issue_with_assignees)).to be true
      end
    end
  end

  describe "#should_process_issue?" do
    let(:issue) { {author: "alice", number: 123} }

    context "with authorized author" do
      let(:config) { {safety: {author_allowlist: ["alice"]}} }

      it "returns true" do
        expect(checker.should_process_issue?(issue)).to be true
      end
    end

    context "with unauthorized author" do
      let(:config) { {safety: {author_allowlist: ["bob"]}} }

      context "with enforce: true" do
        it "raises UnauthorizedAuthorError" do
          expect {
            checker.should_process_issue?(issue, enforce: true)
          }.to raise_error(Aidp::Watch::RepositorySafetyChecker::UnauthorizedAuthorError) do |error|
            expect(error.message).to include("Issue #123")
            expect(error.message).to include("alice")
            expect(error.message).to include("not in allowlist")
          end
        end
      end

      context "with enforce: false" do
        it "returns false without raising" do
          expect(checker.should_process_issue?(issue, enforce: false)).to be false
        end
      end
    end
  end

  describe "repository visibility detection" do
    describe "via GitHub CLI" do
      before do
        allow(repository_client).to receive(:gh_available?).and_return(true)
      end

      it "detects private repository" do
        allow(Open3).to receive(:capture3).with("gh", "repo", "view", "owner/repo", "--json", "visibility")
          .and_return(['{"visibility":"private"}', "", instance_double(Process::Status, success?: true)])

        expect(checker.send(:repository_private?)).to be true
      end

      it "detects public repository" do
        allow(Open3).to receive(:capture3).with("gh", "repo", "view", "owner/repo", "--json", "visibility")
          .and_return(['{"visibility":"public"}', "", instance_double(Process::Status, success?: true)])

        expect(checker.send(:repository_private?)).to be false
      end

      it "assumes public on error (safer default)" do
        allow(Open3).to receive(:capture3).with("gh", "repo", "view", "owner/repo", "--json", "visibility")
          .and_return(["", "error", instance_double(Process::Status, success?: false)])

        expect(checker.send(:repository_private?)).to be false
      end
    end

    describe "via API" do
      before do
        allow(repository_client).to receive(:gh_available?).and_return(false)
      end

      it "detects private repository" do
        response = instance_double(Net::HTTPResponse, code: "200", body: '{"private":true}')
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect(checker.send(:repository_private?)).to be true
      end

      it "detects public repository" do
        response = instance_double(Net::HTTPResponse, code: "200", body: '{"private":false}')
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect(checker.send(:repository_private?)).to be false
      end

      it "assumes public on error" do
        response = instance_double(Net::HTTPResponse, code: "500")
        allow(Net::HTTP).to receive(:get_response).and_return(response)

        expect(checker.send(:repository_private?)).to be false
      end
    end

    it "caches visibility check results" do
      allow(repository_client).to receive(:gh_available?).and_return(true)
      allow(Open3).to receive(:capture3).once
        .and_return(['{"visibility":"private"}', "", instance_double(Process::Status, success?: true)])

      # First call
      checker.send(:repository_private?)
      # Second call should use cache
      checker.send(:repository_private?)
    end
  end

  describe "environment safety checks" do
    it "detects Docker container" do
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(true)
      expect(checker.send(:in_container?)).to be true
    end

    it "detects Podman container" do
      allow(File).to receive(:exist?).with("/.dockerenv").and_return(false)
      allow(File).to receive(:exist?).with("/run/.containerenv").and_return(true)
      expect(checker.send(:in_container?)).to be true
    end

    it "detects devcontainer" do
      allow(File).to receive(:exist?).and_return(false)
      allow(ENV).to receive(:[]).with("AIDP_ENV").and_return("development")
      expect(checker.send(:in_container?)).to be true
    end

    it "detects non-container environment" do
      allow(File).to receive(:exist?).and_return(false)
      allow(ENV).to receive(:[]).with("AIDP_ENV").and_return(nil)
      expect(checker.send(:in_container?)).to be false
    end
  end

  describe "author extraction" do
    it "extracts from author field" do
      issue = {author: "alice"}
      expect(checker.send(:extract_author, issue)).to eq("alice")
    end

    it "falls back to first assignee" do
      issue = {assignees: ["bob", "charlie"]}
      expect(checker.send(:extract_author, issue)).to eq("bob")
    end

    it "handles string keys" do
      issue = {"author" => "alice"}
      expect(checker.send(:extract_author, issue)).to eq("alice")
    end

    it "returns nil for empty issue" do
      expect(checker.send(:extract_author, {})).to be_nil
    end
  end
end
