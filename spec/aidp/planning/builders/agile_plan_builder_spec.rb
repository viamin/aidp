# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/builders/agile_plan_builder"
require "tmpdir"

RSpec.describe Aidp::Planning::Builders::AgilePlanBuilder do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:prompt) { double("TTY::Prompt") }
  let(:config) { {} }
  let(:document_parser) { double("DocumentParser") }
  let(:mvp_scope_generator) { double("MVPScopeGenerator") }
  let(:user_test_plan_generator) { double("UserTestPlanGenerator") }
  let(:marketing_report_generator) { double("MarketingReportGenerator") }
  let(:feedback_analyzer) { double("FeedbackAnalyzer") }
  let(:iteration_plan_generator) { double("IterationPlanGenerator") }
  let(:legacy_research_planner) { double("LegacyResearchPlanner") }
  let(:persona_mapper) { double("PersonaMapper") }

  subject(:builder) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      config: config,
      prompt: prompt,
      document_parser: document_parser,
      mvp_scope_generator: mvp_scope_generator,
      user_test_plan_generator: user_test_plan_generator,
      marketing_report_generator: marketing_report_generator,
      feedback_analyzer: feedback_analyzer,
      iteration_plan_generator: iteration_plan_generator,
      legacy_research_planner: legacy_research_planner,
      persona_mapper: persona_mapper
    )
  end

  describe "#build_mvp_plan" do
    let(:prd_content) { "Sample PRD content" }
    let(:prd) { {content: prd_content, type: :prd} }
    let(:mvp_scope) { {mvp_features: [{name: "Feature 1"}], deferred_features: []} }
    let(:test_plan) { {testing_stages: [{name: "Alpha"}]} }
    let(:marketing_report) { {key_messages: [{title: "Message 1"}]} }

    before do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
    end

    it "orchestrates complete MVP planning workflow" do
      Tempfile.create(["prd", ".md"]) do |file|
        file.write(prd_content)
        file.rewind

        expect(mvp_scope_generator).to receive(:generate)
          .with(hash_including(prd: hash_including(content: prd_content)))
          .and_return(mvp_scope)

        expect(user_test_plan_generator).to receive(:generate)
          .with(hash_including(mvp_scope: mvp_scope))
          .and_return(test_plan)

        expect(marketing_report_generator).to receive(:generate)
          .with(hash_including(mvp_scope: mvp_scope))
          .and_return(marketing_report)

        result = builder.build_mvp_plan(prd_path: file.path)

        expect(result[:mvp_scope]).to eq(mvp_scope)
        expect(result[:test_plan]).to eq(test_plan)
        expect(result[:marketing_report]).to eq(marketing_report)
        expect(result[:metadata][:workflow]).to eq("agile_mvp")
      end
    end

    it "accepts user priorities parameter" do
      user_priorities = ["Priority 1", "Priority 2"]

      Tempfile.create(["prd", ".md"]) do |file|
        file.write(prd_content)
        file.rewind

        expect(mvp_scope_generator).to receive(:generate)
          .with(hash_including(user_priorities: user_priorities))
          .and_return(mvp_scope)

        allow(user_test_plan_generator).to receive(:generate).and_return(test_plan)
        allow(marketing_report_generator).to receive(:generate).and_return(marketing_report)

        builder.build_mvp_plan(prd_path: file.path, user_priorities: user_priorities)
      end
    end

    it "provides user feedback via prompt" do
      Tempfile.create(["prd", ".md"]) do |file|
        file.write(prd_content)
        file.rewind

        allow(mvp_scope_generator).to receive(:generate).and_return(mvp_scope)
        allow(user_test_plan_generator).to receive(:generate).and_return(test_plan)
        allow(marketing_report_generator).to receive(:generate).and_return(marketing_report)

        expect(prompt).to receive(:say).with("Generating MVP scope...")
        expect(prompt).to receive(:say).with("Creating user testing plan...")
        expect(prompt).to receive(:say).with("Generating marketing materials...")
        expect(prompt).to receive(:ok).with("MVP plan complete!")

        builder.build_mvp_plan(prd_path: file.path)
      end
    end
  end

  describe "#analyze_feedback" do
    let(:feedback_path) { "feedback.csv" }
    let(:feedback_data) do
      {
        format: :csv,
        response_count: 5,
        responses: []
      }
    end
    let(:analysis) { {findings: [], recommendations: []} }

    before do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
      allow(File).to receive(:exist?).with(feedback_path).and_return(true)
    end

    it "parses and analyzes feedback data" do
      parser = double("FeedbackDataParser")
      allow(Aidp::Planning::Parsers::FeedbackDataParser).to receive(:new)
        .with(file_path: feedback_path)
        .and_return(parser)

      expect(parser).to receive(:parse).and_return(feedback_data)
      expect(feedback_analyzer).to receive(:analyze)
        .with(feedback_data)
        .and_return(analysis)

      result = builder.analyze_feedback(feedback_path: feedback_path)

      expect(result[:analysis]).to eq(analysis)
      expect(result[:metadata][:workflow]).to eq("agile_feedback_analysis")
    end
  end

  describe "#plan_next_iteration" do
    let(:feedback_analysis) do
      {
        summary: "Overall positive",
        findings: [],
        recommendations: []
      }
    end
    let(:iteration_plan) { {improvements: [], tasks: []} }

    before do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
    end

    it "generates iteration plan from feedback analysis" do
      Tempfile.create(["analysis", ".md"]) do |file|
        file.write("## Executive Summary\nPositive feedback")
        file.rewind

        expect(iteration_plan_generator).to receive(:generate)
          .with(hash_including(
            feedback_analysis: hash_including(content: anything),
            current_mvp: nil
          ))
          .and_return(iteration_plan)

        result = builder.plan_next_iteration(feedback_analysis_path: file.path)

        expect(result[:iteration_plan]).to eq(iteration_plan)
        expect(result[:metadata][:workflow]).to eq("agile_iteration")
      end
    end

    it "includes current MVP when provided" do
      Tempfile.create(["analysis", ".md"]) do |analysis_file|
        Tempfile.create(["mvp", ".md"]) do |mvp_file|
          analysis_file.write("## Summary\nGood")
          mvp_file.write("### 1. Feature 1\nDescription")
          analysis_file.rewind
          mvp_file.rewind

          expect(iteration_plan_generator).to receive(:generate) do |args|
            expect(args[:current_mvp]).not_to be_nil
            iteration_plan
          end

          builder.plan_next_iteration(
            feedback_analysis_path: analysis_file.path,
            current_mvp_path: mvp_file.path
          )
        end
      end
    end
  end

  describe "#plan_legacy_research" do
    let(:research_plan) do
      {
        current_features: [{name: "Feature 1"}],
        research_questions: []
      }
    end
    let(:test_plan) { {testing_stages: []} }

    before do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
    end

    it "analyzes codebase and generates research plan" do
      Dir.mktmpdir do |tmpdir|
        expect(legacy_research_planner).to receive(:generate)
          .with(hash_including(
            codebase_path: tmpdir,
            language: "Ruby",
            known_users: nil
          ))
          .and_return(research_plan)

        expect(user_test_plan_generator).to receive(:generate)
          .and_return(test_plan)

        result = builder.plan_legacy_research(
          codebase_path: tmpdir,
          language: "Ruby"
        )

        expect(result[:research_plan]).to eq(research_plan)
        expect(result[:test_plan]).to eq(test_plan)
        expect(result[:metadata][:workflow]).to eq("agile_legacy_research")
      end
    end
  end

  describe "#write_artifacts" do
    let(:mvp_scope) { {mvp_features: [], deferred_features: [], metadata: {}} }
    let(:test_plan) { {testing_stages: [], metadata: {}} }
    let(:marketing_report) { {key_messages: [], metadata: {}} }

    before do
      allow(prompt).to receive(:ok)
      allow(mvp_scope_generator).to receive(:format_as_markdown).and_return("# MVP Scope")
      allow(user_test_plan_generator).to receive(:format_as_markdown).and_return("# Test Plan")
      allow(marketing_report_generator).to receive(:format_as_markdown).and_return("# Marketing")
    end

    it "writes all artifacts to output directory" do
      Dir.mktmpdir do |tmpdir|
        plan_data = {
          mvp_scope: mvp_scope,
          test_plan: test_plan,
          marketing_report: marketing_report
        }

        artifacts = builder.write_artifacts(plan_data, output_dir: tmpdir)

        expect(artifacts).to include(File.join(tmpdir, "MVP_SCOPE.md"))
        expect(artifacts).to include(File.join(tmpdir, "USER_TEST_PLAN.md"))
        expect(artifacts).to include(File.join(tmpdir, "MARKETING_REPORT.md"))

        expect(File.read(File.join(tmpdir, "MVP_SCOPE.md"))).to eq("# MVP Scope")
      end
    end

    it "creates output directory if it doesn't exist" do
      Dir.mktmpdir do |tmpdir|
        output_dir = File.join(tmpdir, "nested", "output")
        plan_data = {mvp_scope: mvp_scope}

        builder.write_artifacts(plan_data, output_dir: output_dir)

        expect(Dir.exist?(output_dir)).to be true
      end
    end
  end
end
