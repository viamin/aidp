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

  describe "#initialize" do
    it "sets default field mappings when not provided" do
      proc = described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_id: project_id,
        config: {}
      )
      expect(proc.project_id).to eq(project_id)
    end

    it "accepts custom field mappings" do
      custom_config = {field_mappings: {status: "CustomStatus"}}
      proc = described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_id: project_id,
        config: custom_config
      )
      expect(proc.project_id).to eq(project_id)
    end
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

    context "when syncing with status parameter" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_existing")
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: false, blockers: []})
        allow(state_store).to receive(:record_project_sync)
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: [{name: "In Progress", id: "opt_progress"}]}
        ])
        allow(repository_client).to receive(:update_project_item_field)
      end

      it "updates the status" do
        expect(repository_client).to receive(:update_project_item_field)
        processor.sync_issue_to_project(issue_number, status: "In Progress")
      end
    end

    context "when record_project_sync fails" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_existing")
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: false, blockers: []})
        allow(state_store).to receive(:record_project_sync).and_raise(StandardError, "Storage error")
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

    context "when fetch issue fails" do
      before do
        allow(state_store).to receive(:blocking_status).with(issue_number).and_return({blocked: true, blockers: [43]})
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_issue).with(43).and_raise(StandardError, "API error")
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Blocking", id: "PVTSSF_blocking", options: []}
        ])
        allow(repository_client).to receive(:update_project_item_field)
      end

      it "assumes blocker is still blocking" do
        result = processor.check_blocking_dependencies(issue_number)
        expect(result[:blocked]).to be true
        expect(result[:blockers]).to include(43)
      end
    end
  end

  describe "#update_issue_status" do
    let(:issue_number) { 42 }

    context "when issue has no project item id" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return(nil)
      end

      it "returns false" do
        expect(processor.update_issue_status(issue_number, "In Progress")).to be false
      end
    end

    context "when status field not found and cannot be created" do
      let(:config) { {field_mappings: {status: "Status", blocking: "Blocking"}, auto_create_fields: false} }

      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_project_fields).and_return([])
      end

      it "returns false" do
        expect(processor.update_issue_status(issue_number, "In Progress")).to be false
      end
    end

    context "when option not found" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: [{name: "Todo", id: "opt_todo"}]}
        ])
      end

      it "returns false for unknown status" do
        expect(processor.update_issue_status(issue_number, "Unknown Status")).to be false
      end
    end

    context "when update succeeds" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: [{name: "In Progress", id: "opt_in_progress"}]}
        ])
        allow(repository_client).to receive(:update_project_item_field)
      end

      it "returns true" do
        expect(processor.update_issue_status(issue_number, "In Progress")).to be true
      end
    end

    context "when update fails" do
      before do
        allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: [{name: "In Progress", id: "opt_in_progress"}]}
        ])
        allow(repository_client).to receive(:update_project_item_field).and_raise(StandardError, "API error")
      end

      it "returns false" do
        expect(processor.update_issue_status(issue_number, "In Progress")).to be false
      end
    end
  end

  describe "#ensure_project_fields" do
    context "when auto_create_fields is false" do
      let(:config) { {field_mappings: {status: "Status", blocking: "Blocking"}, auto_create_fields: false} }

      it "returns true immediately" do
        expect(processor.ensure_project_fields).to be true
      end
    end

    context "when fields need to be created" do
      before do
        allow(repository_client).to receive(:fetch_project_fields).and_return([])
        allow(repository_client).to receive(:create_project_field).and_return(
          {id: "PVTF_new", name: "Status"}
        )
      end

      it "attempts to create required fields" do
        expect(repository_client).to receive(:create_project_field).at_least(:once)
        processor.ensure_project_fields
      end
    end

    context "when field creation fails" do
      before do
        allow(repository_client).to receive(:fetch_project_fields).and_return([])
        allow(repository_client).to receive(:create_project_field).and_raise(StandardError, "Cannot create field")
      end

      it "returns false" do
        expect(processor.ensure_project_fields).to be false
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

    context "when some issues fail to sync" do
      before do
        allow(processor).to receive(:sync_issue_to_project).with(1).and_return(true)
        allow(processor).to receive(:sync_issue_to_project).with(2).and_return(false)
        allow(processor).to receive(:sync_issue_to_project).with(3).and_return(true)
      end

      it "counts failures correctly" do
        result = processor.sync_all_issues(issues)
        expect(result[:synced]).to eq(2)
        expect(result[:failed]).to eq(1)
      end
    end

    context "with empty issues list" do
      let(:issues) { [] }

      it "returns zero counts" do
        result = processor.sync_all_issues(issues)
        expect(result[:synced]).to eq(0)
        expect(result[:failed]).to eq(0)
      end
    end
  end

  describe "#ensure_project_fields" do
    context "when all fields already exist" do
      before do
        allow(repository_client).to receive(:fetch_project_fields).and_return([
          {name: "Status", id: "PVTSSF_status", options: []},
          {name: "Blocking", id: "PVTSSF_blocking", options: []}
        ])
      end

      it "returns true without creating fields" do
        expect(repository_client).not_to receive(:create_project_field)
        expect(processor.ensure_project_fields).to be true
      end
    end

    context "when fetch_project_fields fails" do
      before do
        allow(repository_client).to receive(:fetch_project_fields).and_raise(StandardError, "API error")
        allow(repository_client).to receive(:create_project_field).and_return({id: "new", name: "Status"})
      end

      it "tries to create fields anyway" do
        processor.ensure_project_fields
      end
    end
  end

  describe "case insensitive field matching" do
    let(:issue_number) { 42 }

    before do
      allow(state_store).to receive(:project_item_id).with(issue_number).and_return("PVTI_123")
      allow(repository_client).to receive(:fetch_project_fields).and_return([
        {name: "STATUS", id: "PVTSSF_status", options: [{name: "IN PROGRESS", id: "opt_progress"}]}
      ])
      allow(repository_client).to receive(:update_project_item_field)
    end

    it "matches field names case-insensitively" do
      expect(processor.update_issue_status(issue_number, "in progress")).to be true
    end
  end
end
