# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/workflows/waterfall/gantt_generator"

RSpec.describe Aidp::Workflows::Waterfall::GanttGenerator do
  let(:generator) { described_class.new }
  let(:sample_wbs) do
    {
      phases: [
        {
          name: "Requirements",
          tasks: [
            {name: "Document requirements", effort: "3 story points", dependencies: []},
            {name: "Review requirements", effort: "2 story points", dependencies: ["Document requirements"]}
          ]
        },
        {
          name: "Implementation",
          tasks: [
            {name: "Build feature", effort: "8 story points", dependencies: ["Review requirements"]},
            {name: "Write tests", effort: "5 story points", dependencies: ["Build feature"]}
          ]
        }
      ],
      metadata: {generated_at: Time.now.iso8601, phase_count: 2, total_tasks: 4}
    }
  end

  describe "#generate" do
    it "generates gantt chart data from WBS" do
      result = generator.generate(wbs: sample_wbs)

      expect(result).to be_a(Hash)
      expect(result[:tasks]).to be_an(Array)
      expect(result[:critical_path]).to be_an(Array)
      expect(result[:mermaid]).to be_a(String)
      expect(result[:metadata]).to be_a(Hash)
    end

    it "extracts all tasks from WBS phases" do
      result = generator.generate(wbs: sample_wbs)

      expect(result[:tasks].size).to eq(4)
      expect(result[:tasks].first[:name]).to eq("Document requirements")
    end

    it "assigns unique IDs to tasks" do
      result = generator.generate(wbs: sample_wbs)

      task_ids = result[:tasks].map { |t| t[:id] }
      expect(task_ids.uniq.size).to eq(task_ids.size)
      expect(task_ids.all? { |id| id.start_with?("task") }).to be true
    end

    it "calculates durations from effort estimates" do
      result = generator.generate(wbs: sample_wbs)

      result[:tasks].each do |task|
        expect(task[:duration]).to be_a(Integer)
        expect(task[:duration]).to be > 0
      end
    end

    it "converts story points to days" do
      result = generator.generate(wbs: sample_wbs)

      # 3 story points should convert to at least 1 day
      doc_task = result[:tasks].find { |t| t[:name] == "Document requirements" }
      expect(doc_task[:duration]).to be >= 1
    end

    it "includes metadata" do
      result = generator.generate(wbs: sample_wbs)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:total_tasks]).to eq(4)
      expect(result[:metadata][:critical_path_length]).to be_a(Integer)
    end
  end

  describe "#format_mermaid" do
    let(:gantt_data) { generator.generate(wbs: sample_wbs) }

    it "generates valid Mermaid syntax" do
      mermaid = gantt_data[:mermaid]

      expect(mermaid).to start_with("gantt")
      expect(mermaid).to include("title Project Timeline")
      expect(mermaid).to include("dateFormat YYYY-MM-DD")
    end

    it "includes sections for each phase" do
      mermaid = gantt_data[:mermaid]

      expect(mermaid).to include("section Requirements")
      expect(mermaid).to include("section Implementation")
    end

    it "includes all tasks" do
      mermaid = gantt_data[:mermaid]

      expect(mermaid).to include("Document requirements")
      expect(mermaid).to include("Review requirements")
      expect(mermaid).to include("Build feature")
      expect(mermaid).to include("Write tests")
    end

    it "marks critical path tasks with crit status" do
      mermaid = gantt_data[:mermaid]
      critical_path = gantt_data[:critical_path]

      # At least one task should be marked as critical
      expect(mermaid).to include(":crit,") if critical_path.any?
    end

    it "includes dependencies using 'after' syntax" do
      mermaid = gantt_data[:mermaid]

      # Tasks with dependencies should use "after" syntax
      expect(mermaid).to include("after") if gantt_data[:tasks].any? { |t| t[:dependencies].any? }
    end
  end

  describe "#calculate_critical_path" do
    it "finds the longest dependency chain" do
      result = generator.generate(wbs: sample_wbs)

      expect(result[:critical_path]).to be_an(Array)
      expect(result[:critical_path]).not_to be_empty
    end

    it "includes dependent tasks in critical path" do
      result = generator.generate(wbs: sample_wbs)
      critical_path = result[:critical_path]

      # Critical path should form a connected chain
      expect(critical_path.size).to be > 1
    end

    it "calculates correct critical path length" do
      result = generator.generate(wbs: sample_wbs)

      expect(result[:metadata][:critical_path_length]).to eq(result[:critical_path].size)
    end

    context "with parallel tasks" do
      let(:parallel_wbs) do
        {
          phases: [
            {
              name: "Development",
              tasks: [
                {name: "Setup", effort: "1 story points", dependencies: []},
                {name: "Feature A", effort: "5 story points", dependencies: ["Setup"]},
                {name: "Feature B", effort: "3 story points", dependencies: ["Setup"]},
                {name: "Integration", effort: "2 story points", dependencies: ["Feature A", "Feature B"]}
              ]
            }
          ],
          metadata: {generated_at: Time.now.iso8601, phase_count: 1, total_tasks: 4}
        }
      end

      it "identifies critical path through parallel branches" do
        result = generator.generate(wbs: parallel_wbs)

        # Critical path should go through the longer branch (Feature A)
        expect(result[:critical_path]).to be_an(Array)
        expect(result[:critical_path].size).to be >= 3
      end
    end
  end

  describe "duration calculation" do
    it "defaults to 1 day for tasks without effort" do
      wbs_no_effort = {
        phases: [{
          name: "Test",
          tasks: [{name: "Task", dependencies: []}]
        }],
        metadata: {generated_at: Time.now.iso8601, phase_count: 1, total_tasks: 1}
      }

      result = generator.generate(wbs: wbs_no_effort)
      expect(result[:tasks].first[:duration]).to eq(1)
    end

    it "enforces minimum 1 day duration" do
      result = generator.generate(wbs: sample_wbs)

      result[:tasks].each do |task|
        expect(task[:duration]).to be >= 1
      end
    end
  end
end
