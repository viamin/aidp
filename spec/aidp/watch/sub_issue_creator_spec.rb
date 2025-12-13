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

    context "with multiple sub-issues" do
      let(:sub_issues_data) do
        [
          {title: "Task 1", description: "First"},
          {title: "Task 2", description: "Second"},
          {title: "Task 3", description: "Third"}
        ]
      end

      before do
        allow(repository_client).to receive(:create_issue).and_return(
          {number: 43, url: "https://github.com/test/repo/issues/43"},
          {number: 44, url: "https://github.com/test/repo/issues/44"},
          {number: 45, url: "https://github.com/test/repo/issues/45"}
        )
      end

      it "creates all sub-issues" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.size).to eq(3)
      end

      it "records all sub-issues in state store" do
        expect(state_store).to receive(:record_sub_issues).with(42, [43, 44, 45])
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with custom labels" do
      let(:sub_issues_data) { [{title: "Task", labels: ["custom-label", "priority-high"]}] }

      it "includes custom labels along with aidp-auto" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(labels: include("aidp-auto", "custom-label", "priority-high"))
        )
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with assignees" do
      let(:sub_issues_data) { [{title: "Task", assignees: ["user1", "user2"]}] }

      it "passes assignees to create_issue" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(assignees: ["user1", "user2"])
        )
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with only skills metadata" do
      let(:sub_issues_data) { [{title: "Task", skills: ["Ruby", "PostgreSQL"]}] }

      it "includes skills in the created issue data" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.first[:skills]).to eq(["Ruby", "PostgreSQL"])
      end
    end

    context "with only personas metadata" do
      let(:sub_issues_data) { [{title: "Task", personas: ["DevOps Engineer"]}] }

      it "includes personas in the created issue data" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.first[:personas]).to eq(["DevOps Engineer"])
      end
    end

    context "with only dependencies metadata" do
      let(:sub_issues_data) { [{title: "Task", dependencies: ["#10", "#11"]}] }

      it "includes dependencies in the created issue data" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.first[:dependencies]).to eq(["#10", "#11"])
      end
    end

    context "with whitespace-only title" do
      let(:sub_issues_data) { [{title: "   "}] }

      it "generates default title" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(title: "Parent Issue - Part 1")
        )
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "with nil title" do
      let(:sub_issues_data) { [{title: nil}] }

      it "generates default title" do
        expect(repository_client).to receive(:create_issue).with(
          hash_including(title: "Parent Issue - Part 1")
        )
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end

    context "when parent linking fails but sub-issue linking succeeds" do
      before do
        call_count = 0
        allow(repository_client).to receive(:link_issue_to_project) do |_proj, issue_num|
          call_count += 1
          raise StandardError, "Parent link failed" if call_count == 1
          "PVTI_sub"
        end
      end

      it "continues to link sub-issues" do
        result = creator.create_sub_issues(parent_issue, sub_issues_data)
        expect(result.size).to eq(1)
      end
    end

    context "with empty sub_issues_data" do
      let(:sub_issues_data) { [] }

      it "does not try to post comment" do
        expect(repository_client).not_to receive(:post_comment)
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end

      it "records empty sub-issues array" do
        expect(state_store).to receive(:record_sub_issues).with(42, [])
        creator.create_sub_issues(parent_issue, sub_issues_data)
      end
    end
  end

  describe "#initialize" do
    it "sets attributes correctly" do
      expect(creator.repository_client).to eq(repository_client)
      expect(creator.state_store).to eq(state_store)
      expect(creator.project_id).to eq(project_id)
    end

    context "without project_id" do
      subject(:creator_no_project) do
        described_class.new(
          repository_client: repository_client,
          state_store: state_store
        )
      end

      it "sets project_id to nil" do
        expect(creator_no_project.project_id).to be_nil
      end
    end
  end
end
