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
  end
end
