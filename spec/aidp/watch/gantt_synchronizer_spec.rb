# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::GanttSynchronizer do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:state_store) { instance_double(Aidp::Watch::StateStore) }
  let(:project_id) { "PVT_123" }
  let(:field_mappings) do
    {
      start_date: "Start Date",
      target_date: "Target Date",
      dependencies: "Dependencies",
      critical_path: "Critical Path"
    }
  end
  let(:parser_class) { class_double(Aidp::Watch::PrdParser) }
  let(:parser) { instance_double(Aidp::Watch::PrdParser) }

  subject(:synchronizer) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      project_id: project_id,
      field_mappings: field_mappings,
      parser_class: parser_class
    )
  end

  describe "#sync_from_prd" do
    let(:parsed) do
      {
        format: :mermaid,
        tasks: [
          {id: "task1", issue_number: 101, start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 7, 2), duration_days: 2, dependency_ids: [], critical: false},
          {id: "task2", issue_number: 102, start_date: Date.new(2026, 7, 3), end_date: Date.new(2026, 7, 5), duration_days: 3, dependency_ids: ["task1"], critical: true}
        ]
      }
    end

    before do
      allow(parser_class).to receive(:new).and_return(parser)
      allow(parser).to receive(:parse).and_return(parsed)
      allow(state_store).to receive(:project_item_id).with(101).and_return("PVTI_101")
      allow(state_store).to receive(:project_item_id).with(102).and_return(nil)
      allow(state_store).to receive(:record_project_item_id)
      allow(state_store).to receive(:record_project_sync)
      allow(repository_client).to receive(:link_issue_to_project).with(project_id, 102).and_return("PVTI_102")
      allow(repository_client).to receive(:fetch_project_fields).and_return([
        {name: "Start Date", id: "start"},
        {name: "Target Date", id: "target"},
        {name: "Dependencies", id: "deps"},
        {name: "Critical Path", id: "crit", options: [{name: "Yes", id: "yes"}, {name: "No", id: "no"}]}
      ])
      allow(repository_client).to receive(:update_project_item_field)
    end

    it "updates project timeline fields and dependency summaries" do
      result = synchronizer.sync_from_prd(prd_path: "/tmp/GANTT.md")

      expect(result[:synced]).to eq(2)
      expect(repository_client).to have_received(:link_issue_to_project).with(project_id, 102)
      expect(repository_client).to have_received(:update_project_item_field).with("PVTI_102", "deps", {project_id: project_id, text: "#101"})
      expect(repository_client).to have_received(:update_project_item_field).with("PVTI_102", "crit", {project_id: project_id, option_id: "yes"})
    end

    it "falls back to title-based issue mapping when Mermaid tasks omit issue numbers" do
      parsed_without_issue_refs = {
        format: :mermaid,
        tasks: [
          {id: "task1", name: "API slice", issue_number: nil, start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 7, 2), duration_days: 2, dependency_ids: [], critical: false},
          {id: "task2", name: "Worker slice", issue_number: nil, start_date: Date.new(2026, 7, 3), end_date: Date.new(2026, 7, 5), duration_days: 3, dependency_ids: ["task1"], critical: true}
        ]
      }
      allow(parser).to receive(:parse).and_return(parsed_without_issue_refs)
      allow(state_store).to receive(:project_item_id).with(201).and_return("PVTI_201")
      allow(state_store).to receive(:project_item_id).with(202).and_return("PVTI_202")

      result = synchronizer.sync_from_prd(
        prd_path: "/tmp/GANTT.md",
        issue_numbers_by_title: {
          "api slice" => 201,
          "worker slice" => 202
        }
      )

      expect(result[:synced]).to eq(2)
      expect(result[:skipped]).to eq(0)
      expect(repository_client).to have_received(:update_project_item_field).with("PVTI_202", "deps", {project_id: project_id, text: "#201"})
      expect(state_store).to have_received(:record_project_sync).with(201, hash_including(gantt_task_id: "task1"))
      expect(state_store).to have_received(:record_project_sync).with(202, hash_including(gantt_task_id: "task2"))
    end
  end

  describe "#sync_issue_status_to_gantt" do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:file) { File.join(tmp_dir, "GANTT.md") }
    let(:real_synchronizer) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_id: project_id,
        field_mappings: field_mappings
      )
    end

    before do
      File.write(file, <<~MARKDOWN)
        Overview mentions issue #102 before the chart.

        ```mermaid
        gantt
            section Build
            Implement sync (#102) :task2, after task1, 3d
        ```
      MARKDOWN
    end

    after do
      FileUtils.rm_rf(tmp_dir)
    end

    it "rewrites Mermaid task status markers for completed issues" do
      expect(
        real_synchronizer.sync_issue_status_to_gantt(
          prd_path: file,
          issue_number: 102,
          status: "Done"
        )
      ).to be true

      expect(File.read(file)).to include("Overview mentions issue #102 before the chart.")
      expect(File.read(file)).to include("Implement sync (#102) :done, task2, after task1, 3d")
    end
  end
end
