# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::SubIssueCreator do
  let(:repository_client) { instance_double("Aidp::Watch::RepositoryClient") }
  let(:state_store) { instance_double("Aidp::Watch::StateStore") }
  let(:project_id) { "PVT_123456" }

  subject(:creator) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      project_id: project_id
    )
  end

  describe "#create_sub_issues" do
    let(:parent_issue) { {number: 42, title: "Parent Issue", url: "https://github.com/test/repo/issues/42"} }
    let(:sub_issues_data) do
      [
        {
          title: "Sub task 1",
          description: "First sub task",
          tasks: ["Task 1", "Task 2"],
          skills: ["Ruby", "Rails"],
          personas: ["Backend Developer"],
          dependencies: ["#40"]
        }
      ]
    end

    before do
      allow(repository_client).to receive(:create_issue).and_return({number: 43, url: "https://github.com/test/repo/issues/43"})
      allow(repository_client).to receive(:link_issue_to_project).and_return("PVTI_abc")
      allow(repository_client).to receive(:post_comment)
      allow(state_store).to receive(:record_project_item_id)
      allow(state_store).to receive(:record_sub_issues)
    end

    it "creates sub-issues with correct attributes" do
      expect(repository_client).to receive(:create_issue).with(
        hash_including(
          title: "Sub task 1",
          labels: include("aidp-auto")
        )
      )
      creator.create_sub_issues(parent_issue, sub_issues_data)
    end

    it "records sub-issues in state store" do
      expect(state_store).to receive(:record_sub_issues).with(42, [43])
      creator.create_sub_issues(parent_issue, sub_issues_data)
    end

    it "links issues to project when project_id is set" do
      expect(repository_client).to receive(:link_issue_to_project).with(project_id, 42)
      expect(repository_client).to receive(:link_issue_to_project).with(project_id, 43)
      creator.create_sub_issues(parent_issue, sub_issues_data)
    end

    it "posts summary comment on parent" do
      expect(repository_client).to receive(:post_comment).with(42, anything)
      creator.create_sub_issues(parent_issue, sub_issues_data)
    end

    context "when issue creation fails" do
      before do
        allow(repository_client).to receive(:create_issue).and_raise(StandardError, "API error")
      end

      it "continues with other sub-issues" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result).to eq([])
      end
    end

    context "when project linking fails" do
      before do
        allow(repository_client).to receive(:link_issue_to_project).and_raise(StandardError, "Project error")
      end

      it "continues processing" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.size).to eq(1)
      end
    end

    context "when comment posting fails" do
      before do
        allow(repository_client).to receive(:post_comment).and_raise(StandardError, "Comment error")
      end

      it "still returns created issues" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.size).to eq(1)
      end
    end

    context "when no sub-issues are created" do
      before do
        allow(repository_client).to receive(:create_issue).and_raise(StandardError, "Failed")
      end

      it "does not try to link to project" do
        expect(repository_client).not_to receive(:link_issue_to_project)
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "without project_id" do
      let(:project_id) { nil }

      it "skips project linking" do
        expect(repository_client).not_to receive(:link_issue_to_project)
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with empty sub-issue title" do
      let(:sub_issues_data) { [{title: "", description: "No title"}] }

      it "generates default title from parent" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(title: "Parent Issue - Part 1")
        )
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with optional fields missing" do
      let(:sub_issues_data) { [{title: "Simple task"}] }

      it "creates issue without optional fields" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(title: "Simple task")
        )
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.size).to eq(1)
      end
    end
  end
end
