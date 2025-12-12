# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/prompt_evaluator"

RSpec.describe Aidp::Execute::PromptEvaluator do
  let(:config) do
    instance_double("Configuration",
      default_provider: "anthropic")
  end

  let(:ai_decision_engine) { instance_double("Aidp::Harness::AIDecisionEngine") }

  describe "#initialize" do
    context "when ai_decision_engine is provided" do
      it "uses the provided engine" do
        evaluator = described_class.new(config, ai_decision_engine: ai_decision_engine)
        expect(evaluator.instance_variable_get(:@ai_decision_engine)).to eq(ai_decision_engine)
      end
    end

    context "when config doesn't support default_provider" do
      let(:limited_config) { double("LimitedConfig") }

      it "sets ai_decision_engine to nil" do
        evaluator = described_class.new(limited_config)
        expect(evaluator.instance_variable_get(:@ai_decision_engine)).to be_nil
      end
    end
  end

  describe "#should_evaluate?" do
    let(:evaluator) { described_class.new(config, ai_decision_engine: ai_decision_engine) }

    it "returns false when iteration count is below threshold" do
      expect(evaluator.should_evaluate?(5)).to be false
      expect(evaluator.should_evaluate?(9)).to be false
    end

    it "returns true at the threshold" do
      expect(evaluator.should_evaluate?(10)).to be true
    end

    it "returns true at intervals after threshold" do
      expect(evaluator.should_evaluate?(15)).to be true
      expect(evaluator.should_evaluate?(20)).to be true
      expect(evaluator.should_evaluate?(25)).to be true
    end

    it "returns false between intervals" do
      expect(evaluator.should_evaluate?(11)).to be false
      expect(evaluator.should_evaluate?(12)).to be false
      expect(evaluator.should_evaluate?(13)).to be false
      expect(evaluator.should_evaluate?(14)).to be false
    end
  end

  describe "#evaluate" do
    let(:evaluator) { described_class.new(config, ai_decision_engine: ai_decision_engine) }
    let(:prompt_content) { "# Test Prompt\n\nImplement feature X" }
    let(:task_summary) { {total: 2, done: 1, pending: 1, in_progress: 0, abandoned: 0} }
    let(:recent_failures) do
      {
        tests: {success: false, failures: ["test_foo failed"]},
        lints: {success: true, failures: []}
      }
    end

    context "when ai_decision_engine is not available" do
      # Use limited_config which doesn't respond to default_provider, so no AI engine is created
      let(:limited_config) { double("LimitedConfig") }
      let(:evaluator) { described_class.new(limited_config) }

      it "returns a skipped result" do
        result = evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: task_summary,
          recent_failures: recent_failures
        )

        expect(result[:effective]).to be true
        expect(result[:skipped]).to be true
        expect(result[:skip_reason]).to include("AI decision engine not available")
        expect(result[:issues]).to eq([])
        expect(result[:suggestions]).to eq([])
      end
    end

    context "when ai_decision_engine is available" do
      let(:ai_response) do
        {
          effective: false,
          issues: ["Unclear completion criteria"],
          suggestions: ["Add specific acceptance criteria"],
          likely_blockers: ["Missing context"],
          confidence: 0.85
        }
      end

      before do
        allow(ai_decision_engine).to receive(:decide).and_return(ai_response)
      end

      it "calls ai_decision_engine with correct parameters" do
        expect(ai_decision_engine).to receive(:decide).with(
          :prompt_evaluation,
          context: hash_including(:prompt),
          schema: anything,
          tier: :mini,
          cache_ttl: nil
        )

        evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: task_summary,
          recent_failures: recent_failures
        )
      end

      it "returns the AI decision result" do
        result = evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: task_summary,
          recent_failures: recent_failures
        )

        expect(result[:effective]).to be false
        expect(result[:issues]).to include("Unclear completion criteria")
        expect(result[:confidence]).to eq(0.85)
      end
    end

    context "when AI call raises an error" do
      before do
        allow(ai_decision_engine).to receive(:decide).and_raise(StandardError.new("API error"))
      end

      it "returns a fallback result" do
        result = evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: task_summary,
          recent_failures: recent_failures
        )

        expect(result[:effective]).to be_nil
        expect(result[:issues]).to include(a_string_matching(/Unable to evaluate/))
        expect(result[:confidence]).to eq(0.0)
      end
    end

    context "with nil prompt content" do
      it "handles nil gracefully" do
        allow(ai_decision_engine).to receive(:decide).and_return({
          effective: true,
          issues: [],
          suggestions: [],
          confidence: 0.5
        })

        result = evaluator.evaluate(
          prompt_content: nil,
          iteration_count: 10,
          task_summary: {},
          recent_failures: {}
        )

        expect(result).to be_a(Hash)
      end
    end

    context "with empty task summary" do
      it "formats empty summary correctly" do
        allow(ai_decision_engine).to receive(:decide).and_return({
          effective: true,
          issues: [],
          suggestions: [],
          confidence: 0.5
        })

        result = evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: {},
          recent_failures: {}
        )

        expect(result[:effective]).to be true
      end
    end

    context "with string task summary" do
      it "handles string summary" do
        allow(ai_decision_engine).to receive(:decide).and_return({
          effective: true,
          issues: [],
          suggestions: [],
          confidence: 0.5
        })

        result = evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: 10,
          task_summary: "Some tasks in progress",
          recent_failures: {}
        )

        expect(result[:effective]).to be true
      end
    end
  end

  describe "#generate_template_improvements" do
    let(:evaluator) { described_class.new(config, ai_decision_engine: ai_decision_engine) }
    let(:evaluation_result) do
      {
        effective: false,
        issues: ["Unclear goals"],
        suggestions: ["Be more specific"]
      }
    end
    let(:original_template) { "# Template\n\n{{task_description}}" }

    context "when ai_decision_engine is nil" do
      # Use limited_config which doesn't respond to default_provider, so no AI engine is created
      let(:limited_config) { double("LimitedConfig") }
      let(:evaluator) { described_class.new(limited_config) }

      it "returns nil" do
        result = evaluator.generate_template_improvements(
          evaluation_result: evaluation_result,
          original_template: original_template
        )

        expect(result).to be_nil
      end
    end

    context "when ai_decision_engine is available" do
      let(:improvement_response) do
        {
          improved_sections: [
            {section_name: "Goals", original: "...", improved: "...", rationale: "..."}
          ],
          additional_sections: [],
          completion_criteria_improvements: ["Add specific exit criteria"]
        }
      end

      before do
        allow(ai_decision_engine).to receive(:decide).and_return(improvement_response)
      end

      it "returns template improvements" do
        result = evaluator.generate_template_improvements(
          evaluation_result: evaluation_result,
          original_template: original_template
        )

        expect(result[:improved_sections]).to be_an(Array)
        expect(result[:completion_criteria_improvements]).to include("Add specific exit criteria")
      end
    end

    context "when AI call fails" do
      before do
        allow(ai_decision_engine).to receive(:decide).and_raise(StandardError.new("API error"))
      end

      it "returns nil" do
        result = evaluator.generate_template_improvements(
          evaluation_result: evaluation_result,
          original_template: original_template
        )

        expect(result).to be_nil
      end
    end
  end
end
