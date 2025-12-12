# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::ProjectsProcessor do
  let(:repository_client) { instance_double("Aidp::Watch::RepositoryClient") }
  let(:state_store) { instance_double("Aidp::Watch::StateStore") }
  let(:project_id) { "PVT_123456" }
  let(:config) { {field_mappings: {status: "Status", blocking: "Blocking"}, auto_create_fields: true} }

  subject(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      project_id: project_id,
      config: config
    )
  end

  describe "#sync_issue_to_project" do
    let(:issue_number) { 42 }

    context "when issue is not yet linked to project" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return(nil)
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: false, blockers: []})
        allow(state_store).to receive(:record_project_item_id)
        allow(state_store).to receive(:record_project_sync)
        allow(repository_client).to receive(:link_issue_to_project).and_return("PVTI_abc123")
      end

      it "links the issue to the project" do
        expect(repository_client).to receive(:link_issue_to_project).with(project_id, issue_number)
        processor.sync_issue_to_project(issue_number)
      end

      it "records the project item id" do
        expect(state_store).to receive(:record_project_item_id).with(issue_number, "PVTI_abc123")
        processor.sync_issue_to_project(issue_number)
      end

      it "returns true on success" do
        expect(processor.sync_issue_to_project(issue_number)).to be true
      end
    end

    context "when issue is already linked to project" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_existing")
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: false, blockers: []})
        allow(state_store).to receive(:record_project_sync)
      end

      it "does not re-link the issue" do
        expect(repository_client).not_to receive(:link_issue_to_project)
        processor.sync_issue_to_project(issue_number)
      end
    end

    context "when linking fails" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return(nil)
        allow(repository_client).to receive(:link_issue_to_project).and_raise(StandardError, "API error")
      end

      it "returns false" do
        expect(processor.sync_issue_to_project(issue_number)).to be false
      end
    end
  end

  describe "#check_blocking_dependencies" do
    let(:issue_number) { 42 }

    context "when issue has no sub-issues" do
      before do
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: false, blockers: []})
      end

      it "returns not blocked" do
        result = processor.check_blocking_dependencies(issue_number)
        expect(result[:blocked]).to be false
      end
    end

    context "when issue has open sub-issues" do
      before do
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: true, blockers: [43, 44]})
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_issue).with(43).and_return({state: "open"})
        allow(repository_client).to receive(:fetch_issue).with(44).and_return({state: "open"})
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Blocking", id: "PVTSSF_blocking", options: []}
        ])
        allow(repository_client).to receive(:update_project_item_field)
      end

      it "returns blocked with blockers list" do
        result = processor.check_blocking_dependencies(issue_number)
        expect(result[:blocked]).to be true
        expect(result[:blockers]).to eq([43, 44])
      end
    end

    context "when all sub-issues are closed" do
      before do
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: true, blockers: [43]})
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_issue).with(43).and_return({state: "closed"})
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: [{name: "Todo", id: "opt_todo"}]},
          {name: "Blocking", id: "PVTSSF_blocking", options: []}
        ])
        allow(repository_client).to receive(:update_project_item_field)
      end

      it "returns not blocked" do
        result = processor.check_blocking_dependencies(issue_number)
        expect(result[:blocked]).to be false
      end
    end
  end

  describe "#sync_all_issues" do
    let(:issues) { [{number: 1}, {number: 2}, {number: 3}] }

    before do
      allow(processor).to receive(:sync_issue_to_project).and_return(true)
    end

    it "syncs each issue" do
      expect(processor).to receive(:sync_issue_to_project).exactly(3).times
      processor.sync_all_issues(issues)
    end

    it "returns summary of results" do
      result = processor.sync_all_issues(issues)
      expect(result[:synced]).to eq(3)
      expect(result[:failed]).to eq(0)
    end
  end
end
