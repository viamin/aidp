# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/workflows/waterfall/wbs_generator"

RSpec.describe Aidp::Workflows::Waterfall::WBSGenerator do
  let(:generator) { described_class.new }
  let(:sample_prd) do
    {
      type: :prd,
      sections: {
        "problem_statement" => "Need to build a feature",
        "goals" => "Deliver high quality feature"
      }
    }
  end
  let(:sample_design) do
    {
      type: :design,
      sections: {
        "architecture" => "Microservices architecture",
        "components" => "API, Database, Frontend"
      }
    }
  end

  describe "#generate" do
    it "generates WBS structure with phases" do
      result = generator.generate(prd: sample_prd, tech_design: sample_design)

      expect(result).to be_a(Hash)
      expect(result[:phases]).to be_an(Array)
      expect(result[:metadata]).to be_a(Hash)
    end

    it "includes all default phases" do
      result = generator.generate(prd: sample_prd)

      phase_names = result[:phases].map { |p| p[:name] }
      expect(phase_names).to include("Requirements")
      expect(phase_names).to include("Design")
      expect(phase_names).to include("Implementation")
      expect(phase_names).to include("Testing")
      expect(phase_names).to include("Deployment")
    end

    it "generates tasks for each phase" do
      result = generator.generate(prd: sample_prd, tech_design: sample_design)

      result[:phases].each do |phase|
        expect(phase[:tasks]).to be_an(Array)
        expect(phase[:tasks]).not_to be_empty
      end
    end

    it "includes metadata with timestamps and counts" do
      result = generator.generate(prd: sample_prd)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:phase_count]).to eq(5)
      expect(result[:metadata][:total_tasks]).to be > 0
    end

    context "with custom phases" do
      let(:custom_generator) { described_class.new(phases: ["Planning", "Execution"]) }

      it "uses custom phases" do
        result = custom_generator.generate(prd: sample_prd)

        phase_names = result[:phases].map { |p| p[:name] }
        expect(phase_names).to eq(["Planning", "Execution"])
      end
    end
  end

  describe "#format_as_markdown" do
    let(:wbs) { generator.generate(prd: sample_prd, tech_design: sample_design) }

    it "generates valid markdown" do
      markdown = generator.format_as_markdown(wbs)

      expect(markdown).to be_a(String)
      expect(markdown).to include("# Work Breakdown Structure")
      expect(markdown).to include("## Phase:")
    end

    it "includes metadata in output" do
      markdown = generator.format_as_markdown(wbs)

      expect(markdown).to include("Total Phases:")
      expect(markdown).to include("Total Tasks:")
      expect(markdown).to include("Generated:")
    end

    it "includes task details" do
      markdown = generator.format_as_markdown(wbs)

      expect(markdown).to include("**Dependencies:**")
      expect(markdown).to include("**Effort:**")
    end

    it "includes subtasks when present" do
      markdown = generator.format_as_markdown(wbs)

      # Implementation phase should have subtasks
      expect(markdown).to match(/- Feature module/)
    end
  end

  describe "task generation" do
    let(:wbs) { generator.generate(prd: sample_prd, tech_design: sample_design) }

    it "generates requirements tasks" do
      requirements_phase = wbs[:phases].find { |p| p[:name] == "Requirements" }

      expect(requirements_phase[:tasks]).not_to be_empty
      expect(requirements_phase[:tasks].first[:name]).to include("functional requirements")
    end

    it "generates design tasks with dependencies" do
      design_phase = wbs[:phases].find { |p| p[:name] == "Design" }
      data_model_task = design_phase[:tasks].find { |t| t[:name].include?("data models") }

      expect(data_model_task[:dependencies]).not_to be_empty
    end

    it "generates implementation tasks with subtasks" do
      impl_phase = wbs[:phases].find { |p| p[:name] == "Implementation" }
      core_features_task = impl_phase[:tasks].find { |t| t[:name].include?("core features") }

      expect(core_features_task[:subtasks]).not_to be_empty
    end

    it "generates testing tasks" do
      testing_phase = wbs[:phases].find { |p| p[:name] == "Testing" }

      expect(testing_phase[:tasks]).not_to be_empty
      task_names = testing_phase[:tasks].map { |t| t[:name] }
      expect(task_names).to include(match(/unit tests/))
    end

    it "generates deployment tasks" do
      deployment_phase = wbs[:phases].find { |p| p[:name] == "Deployment" }

      expect(deployment_phase[:tasks]).not_to be_empty
      expect(deployment_phase[:tasks].first[:name]).to include("production")
    end
  end
end
