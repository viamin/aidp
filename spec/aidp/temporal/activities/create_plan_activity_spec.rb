# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::CreatePlanActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Temporalio::Activity).to receive(:heartbeat)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    let(:base_input) do
      {
        project_dir: project_dir,
        issue_number: 123,
        analysis: {
          issue_number: 123,
          title: "Test Issue",
          requirements: ["Add feature X", "Update component Y"],
          acceptance_criteria: ["Tests pass", "Documentation updated"],
          affected_areas: []
        }
      }
    end

    it "returns success result with plan" do
      result = activity.execute(base_input)

      expect(result[:success]).to be true
      expect(result[:issue_number]).to eq(123)
      expect(result[:result]).to be_a(Hash)
    end

    it "returns step count" do
      result = activity.execute(base_input)

      expect(result[:step_count]).to be > 0
    end

    it "writes plan file to .aidp/plans directory" do
      activity.execute(base_input)

      plan_file = File.join(project_dir, ".aidp", "plans", "issue_123_plan.yml")
      expect(File.exist?(plan_file)).to be true
    end

    context "with affected_areas including tests" do
      let(:input_with_tests) do
        base_input.merge(
          analysis: base_input[:analysis].merge(affected_areas: ["tests"])
        )
      end

      it "includes add_tests step" do
        result = activity.execute(input_with_tests)

        step_names = result[:result][:steps].map { |s| s[:name] }
        expect(step_names).to include("add_tests")
      end
    end

    context "with affected_areas including documentation" do
      let(:input_with_docs) do
        base_input.merge(
          analysis: base_input[:analysis].merge(affected_areas: ["documentation"])
        )
      end

      it "includes update_docs step" do
        result = activity.execute(input_with_docs)

        step_names = result[:result][:steps].map { |s| s[:name] }
        expect(step_names).to include("update_docs")
      end
    end

    context "with both tests and documentation" do
      let(:input_with_both) do
        base_input.merge(
          analysis: base_input[:analysis].merge(affected_areas: ["tests", "documentation"])
        )
      end

      it "includes both add_tests and update_docs steps" do
        result = activity.execute(input_with_both)

        step_names = result[:result][:steps].map { |s| s[:name] }
        expect(step_names).to include("add_tests")
        expect(step_names).to include("update_docs")
      end
    end

    context "with empty requirements" do
      let(:input_no_requirements) do
        base_input.merge(
          analysis: base_input[:analysis].merge(requirements: [])
        )
      end

      it "still creates setup and validate steps" do
        result = activity.execute(input_no_requirements)

        step_names = result[:result][:steps].map { |s| s[:name] }
        expect(step_names).to include("setup")
        expect(step_names).to include("validate")
      end
    end

    context "with nil analysis fields" do
      let(:input_nil_fields) do
        {
          project_dir: project_dir,
          issue_number: 456,
          analysis: {
            issue_number: 456,
            title: "Minimal"
          }
        }
      end

      it "handles nil requirements gracefully" do
        result = activity.execute(input_nil_fields)

        expect(result[:success]).to be true
        expect(result[:result][:requirements]).to eq([])
      end

      it "handles nil acceptance_criteria gracefully" do
        result = activity.execute(input_nil_fields)

        expect(result[:result][:acceptance_criteria]).to eq([])
      end

      it "handles nil affected_areas gracefully" do
        result = activity.execute(input_nil_fields)

        # Should not have tests or docs steps
        step_names = result[:result][:steps].map { |s| s[:name] }
        expect(step_names).not_to include("add_tests")
        expect(step_names).not_to include("update_docs")
      end
    end
  end

  describe "#generate_plan (private)" do
    let(:analysis) do
      {
        issue_number: 1,
        title: "Test",
        requirements: ["Req 1"],
        acceptance_criteria: [],
        affected_areas: []
      }
    end

    it "creates implementation steps for each requirement" do
      plan = activity.send(:generate_plan, project_dir, analysis)

      impl_steps = plan[:steps].select { |s| s[:type] == :implementation }
      expect(impl_steps.length).to eq(1)
    end

    it "calculates total estimated iterations" do
      plan = activity.send(:generate_plan, project_dir, analysis)

      expect(plan[:estimated_total_iterations]).to be > 0
    end

    it "includes created_at timestamp" do
      plan = activity.send(:generate_plan, project_dir, analysis)

      expect(plan[:created_at]).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end

  describe "#write_plan (private)" do
    let(:plan) { {steps: [], requirements: []} }

    it "creates plans directory if not exists" do
      activity.send(:write_plan, project_dir, 789, plan)

      expect(Dir.exist?(File.join(project_dir, ".aidp", "plans"))).to be true
    end

    it "writes plan as YAML" do
      activity.send(:write_plan, project_dir, 789, plan)

      content = File.read(File.join(project_dir, ".aidp", "plans", "issue_789_plan.yml"))
      expect(content).to include("steps:")
    end
  end
end
