# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/planning/builders/project_plan_builder"

RSpec.describe Aidp::Planning::Builders::ProjectPlanBuilder do
  let(:mock_ai_engine) { double("AIDecisionEngine") }
  let(:mock_doc_parser) { double("DocumentParser") }
  let(:mock_wbs_generator) { double("WBSGenerator") }
  let(:mock_gantt_generator) { double("GanttGenerator") }
  let(:mock_persona_mapper) { double("PersonaMapper") }

  let(:builder) do
    described_class.new(
      ai_decision_engine: mock_ai_engine,
      document_parser: mock_doc_parser,
      wbs_generator: mock_wbs_generator,
      gantt_generator: mock_gantt_generator,
      persona_mapper: mock_persona_mapper
    )
  end

  let(:sample_prd) do
    {
      type: :prd,
      sections: {"problem_statement" => "Build a feature", "goals" => "Deliver value"},
      raw_content: "Full PRD content"
    }
  end

  let(:sample_tech_design) do
    {
      type: :design,
      sections: {"architecture" => "Microservices", "components" => "API, DB"},
      raw_content: "Full design content"
    }
  end

  let(:sample_wbs) do
    {
      phases: [{name: "Implementation", tasks: [{name: "Build", effort: "5"}]}],
      metadata: {phase_count: 1, total_tasks: 1}
    }
  end

  let(:sample_gantt) do
    {
      tasks: [{id: "task1", name: "Build", duration: 3}],
      critical_path: ["task1"],
      mermaid: "gantt\n  task1 :task1, 3d",
      metadata: {critical_path_length: 1}
    }
  end

  let(:sample_persona_assignments) do
    {
      assignments: {"task1" => {persona: "senior_developer", task: "Build"}},
      metadata: {personas_used: ["senior_developer"]}
    }
  end

  describe "#build_from_ingestion" do
    let(:temp_dir) { Dir.mktmpdir }

    before do
      # Create sample docs
      File.write(File.join(temp_dir, "prd.md"), "# PRD\nProblem statement")
      File.write(File.join(temp_dir, "design.md"), "# Design\nArchitecture")

      # Mock parser
      allow(mock_doc_parser).to receive(:parse_directory).and_return([sample_prd, sample_tech_design])

      # Mock generators
      allow(mock_wbs_generator).to receive(:generate).and_return(sample_wbs)
      allow(mock_wbs_generator).to receive(:format_as_markdown).and_return("# WBS\n...")
      allow(mock_gantt_generator).to receive(:generate).and_return(sample_gantt)
      allow(mock_persona_mapper).to receive(:assign_personas).and_return(sample_persona_assignments)
    end

    after { FileUtils.rm_rf(temp_dir) }

    it "parses documentation from directory" do
      builder.build_from_ingestion(temp_dir)

      expect(mock_doc_parser).to have_received(:parse_directory).with(temp_dir)
    end

    it "generates WBS from parsed docs" do
      builder.build_from_ingestion(temp_dir)

      expect(mock_wbs_generator).to have_received(:generate).with(hash_including(prd: sample_prd))
    end

    it "generates Gantt chart from WBS" do
      builder.build_from_ingestion(temp_dir)

      expect(mock_gantt_generator).to have_received(:generate).with(hash_including(wbs: sample_wbs))
    end

    it "assigns personas to tasks" do
      builder.build_from_ingestion(temp_dir)

      expect(mock_persona_mapper).to have_received(:assign_personas).with(sample_gantt[:tasks])
    end

    it "returns complete plan components" do
      result = builder.build_from_ingestion(temp_dir)

      expect(result).to be_a(Hash)
      expect(result[:prd]).to eq(sample_prd)
      expect(result[:tech_design]).to eq(sample_tech_design)
      expect(result[:wbs]).to eq(sample_wbs)
      expect(result[:gantt]).to eq(sample_gantt)
      expect(result[:persona_assignments]).to eq(sample_persona_assignments)
    end

    it "includes formatted outputs" do
      result = builder.build_from_ingestion(temp_dir)

      expect(result[:wbs_markdown]).to be_a(String)
      expect(result[:gantt_mermaid]).to be_a(String)
      expect(result[:critical_path]).to be_an(Array)
    end
  end

  describe "#build_from_scratch" do
    let(:requirements) do
      {
        problem: "Need to build feature X",
        goals: "Deliver high quality solution",
        success_criteria: "Users can complete workflow"
      }
    end

    before do
      allow(mock_wbs_generator).to receive(:generate).and_return(sample_wbs)
      allow(mock_wbs_generator).to receive(:format_as_markdown).and_return("# WBS\n...")
      allow(mock_gantt_generator).to receive(:generate).and_return(sample_gantt)
      allow(mock_persona_mapper).to receive(:assign_personas).and_return(sample_persona_assignments)
    end

    it "structures requirements as PRD" do
      result = builder.build_from_scratch(requirements)

      expect(result[:prd]).to be_a(Hash)
      expect(result[:prd][:type]).to eq(:prd)
      expect(result[:prd][:sections]).to be_a(Hash)
    end

    it "generates complete plan from requirements" do
      result = builder.build_from_scratch(requirements)

      expect(result[:wbs]).to eq(sample_wbs)
      expect(result[:gantt]).to eq(sample_gantt)
      expect(result[:persona_assignments]).to eq(sample_persona_assignments)
    end

    it "handles nil tech_design" do
      result = builder.build_from_scratch(requirements)

      # Should still generate WBS even without tech design
      expect(result[:tech_design]).to be_nil
      expect(result[:wbs]).not_to be_nil
    end
  end

  describe "#assemble_project_plan" do
    let(:components) do
      {
        prd: sample_prd,
        tech_design: sample_tech_design,
        wbs: sample_wbs,
        wbs_markdown: "# WBS\n\n## Phase: Implementation\n...",
        gantt: sample_gantt,
        gantt_mermaid: "gantt\n  Build :task1, 3d",
        critical_path: ["task1"],
        persona_assignments: sample_persona_assignments
      }
    end

    it "generates complete PROJECT_PLAN.md" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to be_a(String)
      expect(plan).to include("# Project Plan")
    end

    it "includes executive summary" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Executive Summary")
    end

    it "includes WBS section" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Work Breakdown Structure")
      expect(plan).to include(components[:wbs_markdown])
    end

    it "includes Gantt chart with Mermaid" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Timeline and Gantt Chart")
      expect(plan).to include("```mermaid")
      expect(plan).to include(components[:gantt_mermaid])
      expect(plan).to include("```")
    end

    it "includes critical path" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Critical Path")
      expect(plan).to include("task1")
    end

    it "includes persona assignments summary" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Persona Assignments")
      expect(plan).to include("senior_developer")
    end

    it "includes metadata" do
      plan = builder.assemble_project_plan(components)

      expect(plan).to include("## Metadata")
      expect(plan).to include("Total Phases")
      expect(plan).to include("Total Tasks")
      expect(plan).to include("Critical Path Length")
    end

    it "groups tasks by persona" do
      plan = builder.assemble_project_plan(components)

      # Should have persona sections
      expect(plan).to include("### senior_developer")
    end
  end

  describe "initialization" do
    it "creates default components if not provided" do
      minimal_builder = described_class.new(ai_decision_engine: mock_ai_engine)

      expect(minimal_builder).to be_a(described_class)
    end

    it "uses provided components" do
      custom_builder = described_class.new(
        ai_decision_engine: mock_ai_engine,
        document_parser: mock_doc_parser
      )

      expect(custom_builder).to be_a(described_class)
    end
  end

  describe "dependency injection" do
    it "allows testing with mock components" do
      # This test verifies that dependency injection works correctly
      custom_wbs = {phases: [], metadata: {}}
      allow(mock_wbs_generator).to receive(:generate).and_return(custom_wbs)
      allow(mock_wbs_generator).to receive(:format_as_markdown).and_return("")

      builder.build_from_scratch({problem: "test"})

      expect(mock_wbs_generator).to have_received(:generate)
    end
  end
end
