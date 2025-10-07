# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Workflows::Definitions do
  describe "ANALYZE_WORKFLOWS" do
    let(:workflows) { described_class::ANALYZE_WORKFLOWS }

    it "defines analyze workflows" do
      expect(workflows).to be_a(Hash)
      expect(workflows).not_to be_empty
    end

    it "includes expected analyze workflow types" do
      expect(workflows.keys).to include(
        :quick_overview,
        :style_guide,
        :architecture_review,
        :quality_assessment,
        :deep_analysis,
        :custom
      )
    end

    describe "workflow structure" do
      it "has required fields for each workflow" do
        workflows.each do |key, workflow|
          expect(workflow).to have_key(:name)
          expect(workflow).to have_key(:description)
          expect(workflow).to have_key(:icon)
          expect(workflow).to have_key(:details)
          expect(workflow).to have_key(:steps)
        end
      end

      it "has array of strings for details" do
        workflows.each do |key, workflow|
          next if key == :custom
          expect(workflow[:details]).to be_an(Array)
          expect(workflow[:details].first).to be_a(String)
        end
      end

      it "has valid steps (array or :custom symbol)" do
        workflows.each do |key, workflow|
          if key == :custom
            expect(workflow[:steps]).to eq(:custom)
          else
            expect(workflow[:steps]).to be_an(Array)
            expect(workflow[:steps]).not_to be_empty
          end
        end
      end
    end

    describe "quick_overview workflow" do
      let(:workflow) { workflows[:quick_overview] }

      it "has surface-level analysis steps" do
        expect(workflow[:steps]).to include(
          "01_REPOSITORY_ANALYSIS",
          "04_FUNCTIONALITY_ANALYSIS",
          "05_DOCUMENTATION_ANALYSIS"
        )
      end

      it "has appropriate name and description" do
        expect(workflow[:name]).to eq("Quick Overview")
        expect(workflow[:description]).to include("Surface-level")
      end
    end

    describe "deep_analysis workflow" do
      let(:workflow) { workflows[:deep_analysis] }

      it "includes all analysis steps" do
        expect(workflow[:steps]).to include(
          "01_REPOSITORY_ANALYSIS",
          "02_ARCHITECTURE_ANALYSIS",
          "03_TEST_ANALYSIS",
          "04_FUNCTIONALITY_ANALYSIS",
          "05_DOCUMENTATION_ANALYSIS",
          "06_STATIC_ANALYSIS",
          "06A_TREE_SITTER_SCAN",
          "07_REFACTORING_RECOMMENDATIONS"
        )
      end

      it "has comprehensive description" do
        expect(workflow[:description]).to include("Complete analysis")
      end
    end

    describe "style_guide workflow" do
      let(:workflow) { workflows[:style_guide] }

      it "focuses on code patterns and style" do
        expect(workflow[:steps]).to include(
          "01_REPOSITORY_ANALYSIS",
          "06_STATIC_ANALYSIS",
          "06A_TREE_SITTER_SCAN"
        )
      end
    end
  end

  describe "EXECUTE_WORKFLOWS" do
    let(:workflows) { described_class::EXECUTE_WORKFLOWS }

    it "defines execute workflows" do
      expect(workflows).to be_a(Hash)
      expect(workflows).not_to be_empty
    end

    it "includes expected execute workflow types" do
      expect(workflows.keys).to include(
        :quick_prototype,
        :exploration,
        :feature_development,
        :production_ready,
        :full_enterprise,
        :custom
      )
    end

    describe "quick_prototype workflow" do
      let(:workflow) { workflows[:quick_prototype] }

      it "has minimal planning steps" do
        expect(workflow[:steps]).to eq([
          "00_PRD",
          "10_TESTING_STRATEGY",
          "16_IMPLEMENTATION"
        ])
      end

      it "indicates speed focus" do
        expect(workflow[:description]).to include("Rapid")
        expect(workflow[:description]).to include("minimal")
      end
    end

    describe "exploration workflow" do
      let(:workflow) { workflows[:exploration] }

      it "includes basic quality checks" do
        expect(workflow[:steps]).to include(
          "00_PRD",
          "10_TESTING_STRATEGY",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        )
      end
    end

    describe "production_ready workflow" do
      let(:workflow) { workflows[:production_ready] }

      it "includes enterprise-grade steps" do
        expect(workflow[:steps]).to include(
          "00_PRD",
          "01_NFRS",
          "02_ARCHITECTURE",
          "07_SECURITY_REVIEW",
          "08_PERFORMANCE_REVIEW",
          "10_TESTING_STRATEGY",
          "12_OBSERVABILITY_SLOS",
          "16_IMPLEMENTATION"
        )
      end

      it "has enterprise focus" do
        expect(workflow[:description]).to include("Enterprise-grade")
      end
    end

    describe "full_enterprise workflow" do
      let(:workflow) { workflows[:full_enterprise] }

      it "includes all governance steps" do
        expect(workflow[:steps]).to include(
          "00_PRD",
          "01_NFRS",
          "02_ARCHITECTURE",
          "03_ADR_FACTORY",
          "04_DOMAIN_DECOMPOSITION",
          "05_API_DESIGN",
          "07_SECURITY_REVIEW",
          "14_DOCS_PORTAL",
          "16_IMPLEMENTATION"
        )
      end

      it "is the most comprehensive workflow" do
        # Should have more steps than production_ready
        production_steps = workflows[:production_ready][:steps].size
        enterprise_steps = workflow[:steps].size
        expect(enterprise_steps).to be > production_steps
      end
    end
  end

  describe "HYBRID_WORKFLOWS" do
    let(:workflows) { described_class::HYBRID_WORKFLOWS }

    it "defines hybrid workflows" do
      expect(workflows).to be_a(Hash)
      expect(workflows).not_to be_empty
    end

    it "includes expected hybrid workflow types" do
      expect(workflows.keys).to include(
        :legacy_modernization,
        :style_guide_enforcement,
        :test_coverage_improvement,
        :custom_hybrid
      )
    end

    describe "legacy_modernization workflow" do
      let(:workflow) { workflows[:legacy_modernization] }

      it "mixes analyze and execute steps" do
        analyze_steps = %w[01_REPOSITORY_ANALYSIS 02_ARCHITECTURE_ANALYSIS 06A_TREE_SITTER_SCAN 07_REFACTORING_RECOMMENDATIONS]
        execute_steps = %w[00_PRD 02_ARCHITECTURE 16_IMPLEMENTATION]

        analyze_steps.each do |step|
          expect(workflow[:steps]).to include(step)
        end

        execute_steps.each do |step|
          expect(workflow[:steps]).to include(step)
        end
      end
    end

    describe "style_guide_enforcement workflow" do
      let(:workflow) { workflows[:style_guide_enforcement] }

      it "analyzes then enforces patterns" do
        expect(workflow[:steps]).to include(
          "01_REPOSITORY_ANALYSIS",
          "06_STATIC_ANALYSIS",
          "00_LLM_STYLE_GUIDE",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        )
      end
    end

    describe "test_coverage_improvement workflow" do
      let(:workflow) { workflows[:test_coverage_improvement] }

      it "analyzes gaps then implements tests" do
        expect(workflow[:steps]).to include(
          "03_TEST_ANALYSIS",
          "04_FUNCTIONALITY_ANALYSIS",
          "10_TESTING_STRATEGY",
          "16_IMPLEMENTATION"
        )
      end
    end
  end

  describe ".all_available_steps" do
    let(:all_steps) { described_class.all_available_steps }

    it "returns array of step definitions" do
      expect(all_steps).to be_an(Array)
      expect(all_steps).not_to be_empty
    end

    it "includes both analyze and execute steps" do
      modes = all_steps.map { |s| s[:mode] }.uniq
      expect(modes).to include(:analyze)
      expect(modes).to include(:execute)
    end

    it "has required fields for each step" do
      all_steps.each do |step|
        expect(step).to have_key(:step)
        expect(step).to have_key(:mode)
        expect(step).to have_key(:description)
      end
    end

    it "returns sorted steps" do
      step_names = all_steps.map { |s| s[:step] }
      expect(step_names).to eq(step_names.sort)
    end

    it "includes analyze steps from Analyze::Steps::SPEC" do
      analyze_count = all_steps.count { |s| s[:mode] == :analyze }
      expect(analyze_count).to eq(Aidp::Analyze::Steps::SPEC.size)
    end

    it "includes execute steps from Execute::Steps::SPEC" do
      execute_count = all_steps.count { |s| s[:mode] == :execute }
      expect(execute_count).to eq(Aidp::Execute::Steps::SPEC.size)
    end
  end

  describe ".get_workflow" do
    it "returns analyze workflow by key" do
      workflow = described_class.get_workflow(:analyze, :quick_overview)
      expect(workflow).to eq(described_class::ANALYZE_WORKFLOWS[:quick_overview])
    end

    it "returns execute workflow by key" do
      workflow = described_class.get_workflow(:execute, :exploration)
      expect(workflow).to eq(described_class::EXECUTE_WORKFLOWS[:exploration])
    end

    it "returns hybrid workflow by key" do
      workflow = described_class.get_workflow(:hybrid, :legacy_modernization)
      expect(workflow).to eq(described_class::HYBRID_WORKFLOWS[:legacy_modernization])
    end

    it "returns nil for unknown workflow" do
      workflow = described_class.get_workflow(:analyze, :nonexistent)
      expect(workflow).to be_nil
    end
  end

  describe ".workflows_for_mode" do
    it "returns analyze workflows for :analyze mode" do
      workflows = described_class.workflows_for_mode(:analyze)
      expect(workflows).to eq(described_class::ANALYZE_WORKFLOWS)
    end

    it "returns execute workflows for :execute mode" do
      workflows = described_class.workflows_for_mode(:execute)
      expect(workflows).to eq(described_class::EXECUTE_WORKFLOWS)
    end

    it "returns hybrid workflows for :hybrid mode" do
      workflows = described_class.workflows_for_mode(:hybrid)
      expect(workflows).to eq(described_class::HYBRID_WORKFLOWS)
    end

    it "returns nil for unknown mode" do
      workflows = described_class.workflows_for_mode(:unknown)
      expect(workflows).to be_nil
    end
  end

  describe "workflow consistency" do
    it "all non-custom workflows reference valid analyze steps" do
      described_class::ANALYZE_WORKFLOWS.each do |key, workflow|
        next if key == :custom

        workflow[:steps].each do |step|
          expect(Aidp::Analyze::Steps::SPEC).to have_key(step),
            "Workflow #{key} references non-existent analyze step: #{step}"
        end
      end
    end

    it "all non-custom execute workflows reference valid execute steps" do
      described_class::EXECUTE_WORKFLOWS.each do |key, workflow|
        next if key == :custom

        workflow[:steps].each do |step|
          expect(Aidp::Execute::Steps::SPEC).to have_key(step),
            "Workflow #{key} references non-existent execute step: #{step}"
        end
      end
    end

    it "hybrid workflows reference valid steps from both modes" do
      all_valid_steps = Aidp::Analyze::Steps::SPEC.keys + Aidp::Execute::Steps::SPEC.keys

      described_class::HYBRID_WORKFLOWS.each do |key, workflow|
        next if key == :custom_hybrid

        workflow[:steps].each do |step|
          expect(all_valid_steps).to include(step),
            "Hybrid workflow #{key} references non-existent step: #{step}"
        end
      end
    end
  end
end
