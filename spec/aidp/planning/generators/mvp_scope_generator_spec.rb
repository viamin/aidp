# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/generators/mvp_scope_generator"

RSpec.describe Aidp::Planning::Generators::MVPScopeGenerator do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:prompt) { double("TTY::Prompt") }
  let(:config) { {} }

  subject(:generator) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      prompt: prompt,
      config: config
    )
  end

  describe "#generate" do
    let(:prd) do
      {
        content: "Sample PRD content",
        type: :prd
      }
    end

    let(:user_priorities) do
      [
        "Primary goal: Launch quickly",
        "Main problem: User confusion",
        "Target users: Developers",
        "Timeline: 3 months"
      ]
    end

    let(:ai_response) do
      {
        must_have: [
          {
            name: "Core Feature",
            description: "Essential functionality",
            rationale: "Solves main user problem",
            acceptance_criteria: ["Works for basic use case"]
          }
        ],
        nice_to_have: [
          {
            name: "Enhancement",
            description: "Nice improvement",
            deferral_reason: "Can wait for v2"
          }
        ],
        out_of_scope: ["Advanced analytics"],
        success_criteria: ["User adoption > 100"],
        assumptions: ["Users have internet"],
        risks: [
          {
            title: "Technical complexity",
            impact: "high",
            mitigation: "Start simple"
          }
        ]
      }
    end

    it "generates MVP scope with user priorities" do
      expect(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = generator.generate(prd: prd, user_priorities: user_priorities)

      expect(result[:mvp_features]).to eq(ai_response[:must_have])
      expect(result[:deferred_features]).to eq(ai_response[:nice_to_have])
      expect(result[:out_of_scope]).to eq(ai_response[:out_of_scope])
      expect(result[:success_criteria]).to eq(ai_response[:success_criteria])
      expect(result[:metadata][:mvp_feature_count]).to eq(1)
      expect(result[:metadata][:deferred_feature_count]).to eq(1)
    end

    it "collects user priorities interactively when not provided" do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ask).and_return(
        "Quick launch",
        "User confusion",
        "Developers",
        "3 months"
      )
      allow(prompt).to receive(:yes?).and_return(false)

      expect(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = generator.generate(prd: prd)

      expect(result[:mvp_features]).to be_an(Array)
      expect(result[:metadata][:user_priorities]).to be_an(Array)
    end
  end

  describe "#format_as_markdown" do
    let(:mvp_scope) do
      {
        mvp_features: [
          {
            name: "Feature 1",
            description: "Description",
            rationale: "Important",
            acceptance_criteria: ["Criterion 1"]
          }
        ],
        deferred_features: [
          {
            name: "Feature 2",
            description: "Later",
            deferral_reason: "Not critical"
          }
        ],
        out_of_scope: ["Feature 3"],
        success_criteria: ["Metric 1"],
        assumptions: ["Assumption 1"],
        risks: [
          {
            title: "Risk 1",
            impact: "medium",
            mitigation: "Plan A"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          mvp_feature_count: 1,
          deferred_feature_count: 1,
          user_priorities: ["Priority 1"]
        }
      }
    end

    it "formats MVP scope as markdown" do
      markdown = generator.format_as_markdown(mvp_scope)

      expect(markdown).to include("# MVP Scope Definition")
      expect(markdown).to include("## MVP Features (Must-Have)")
      expect(markdown).to include("Feature 1")
      expect(markdown).to include("## Deferred Features (Nice-to-Have)")
      expect(markdown).to include("Feature 2")
      expect(markdown).to include("## Out of Scope")
      expect(markdown).to include("Feature 3")
      expect(markdown).to include("## Success Criteria")
      expect(markdown).to include("## Assumptions")
      expect(markdown).to include("## Risks")
    end
  end
end
