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
end
