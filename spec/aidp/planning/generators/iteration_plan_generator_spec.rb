# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/generators/iteration_plan_generator"

RSpec.describe Aidp::Planning::Generators::IterationPlanGenerator do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:wbs_generator) { nil }
  let(:config) { {} }

  subject(:generator) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      wbs_generator: wbs_generator,
      config: config
    )
  end

  describe "#generate" do
    let(:feedback_analysis) do
      {
        summary: "Users want dark mode and better performance",
        findings: [
          {
            title: "Dark Mode Request",
            description: "Multiple users requested dark mode",
            evidence: ["Please add dark mode", "Dark mode needed"],
            impact: "high"
          }
        ],
        recommendations: [
          {
            title: "Add Dark Mode",
            description: "Implement dark theme",
            rationale: "Highly requested",
            effort: "medium",
            impact: "high"
          }
        ],
        priority_issues: [
          {
            title: "Slow Load Times",
            priority: "high",
            impact: "User frustration",
            affected_users: "30%"
          }
        ]
      }
    end

    let(:ai_response) do
      {
        overview: "This iteration focuses on user feedback priorities",
        goals: ["Add dark mode", "Improve performance", "Fix critical bugs"],
        improvements: [
          {
            feature_name: "Dashboard",
            issue: "Slow loading",
            improvement: "Optimize queries",
            impact: "Better UX",
            effort: "medium",
            priority: "high"
          }
        ],
        new_features: [
          {
            name: "Dark Mode",
            description: "Dark theme option",
            rationale: "User demand",
            acceptance_criteria: ["Toggle in settings", "All pages support dark mode"],
            effort: "medium"
          }
        ],
        bug_fixes: [
          {
            title: "Search Crash",
            description: "App crashes on special characters",
            priority: "critical",
            affected_users: "15%"
          }
        ],
        technical_debt: [
          {
            title: "Update Dependencies",
            description: "Upgrade outdated packages",
            effort: "low"
          }
        ],
        tasks: [
          {
            name: "Implement dark mode toggle",
            description: "Add toggle in settings",
            category: "feature",
            priority: "high",
            effort: "medium",
            dependencies: [],
            success_criteria: ["Toggle works", "Persists preference"]
          }
        ],
        success_metrics: [
          {
            name: "User Satisfaction",
            target: "4.5/5 rating"
          }
        ],
        risks: [
          {
            title: "Technical Complexity",
            probability: "medium",
            impact: "medium",
            mitigation: "Start with prototype"
          }
        ],
        timeline: [
          {
            phase: "Development",
            duration: "2 weeks",
            activities: "Build features"
          }
        ]
      }
    end

    it "generates iteration plan from feedback analysis" do
      expect(ai_decision_engine).to receive(:decide)
        .with(hash_including(
          context: "iteration_plan_generation"
        ))
        .and_return(ai_response)

      result = generator.generate(feedback_analysis: feedback_analysis)

      expect(result[:overview]).to eq(ai_response[:overview])
      expect(result[:goals]).to eq(ai_response[:goals])
      expect(result[:improvements]).to eq(ai_response[:improvements])
      expect(result[:new_features]).to eq(ai_response[:new_features])
      expect(result[:bug_fixes]).to eq(ai_response[:bug_fixes])
      expect(result[:technical_debt]).to eq(ai_response[:technical_debt])
      expect(result[:tasks]).to eq(ai_response[:tasks])
    end

    it "includes current MVP context when provided" do
      current_mvp = {
        mvp_features: [
          {name: "Dashboard", description: "Main UI"}
        ]
      }

      expect(ai_decision_engine).to receive(:decide) do |args|
        data = args[:data]
        expect(data[:current_mvp]).to eq(current_mvp)
        ai_response
      end

      generator.generate(feedback_analysis: feedback_analysis, current_mvp: current_mvp)
    end

    it "includes metadata in result" do
      allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = generator.generate(feedback_analysis: feedback_analysis)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:improvement_count]).to eq(1)
      expect(result[:metadata][:new_feature_count]).to eq(1)
      expect(result[:metadata][:task_count]).to eq(1)
      expect(result[:metadata][:based_on_feedback]).to be true
    end
  end

  describe "#format_as_markdown" do
    let(:plan) do
      {
        overview: "Next iteration plan",
        goals: ["Goal 1", "Goal 2"],
        improvements: [
          {
            feature_name: "Search",
            issue: "Too slow",
            improvement: "Add caching",
            impact: "Faster searches",
            effort: "low",
            priority: "high"
          }
        ],
        new_features: [
          {
            name: "Export",
            description: "Export to CSV",
            rationale: "User request",
            acceptance_criteria: ["Downloads CSV", "Includes all data"],
            effort: "low"
          }
        ],
        bug_fixes: [
          {
            title: "Login Bug",
            description: "Users can't log in",
            priority: "critical",
            affected_users: "All"
          }
        ],
        technical_debt: [
          {
            title: "Refactor Auth",
            description: "Simplify authentication",
            effort: "medium"
          }
        ],
        tasks: [
          {
            name: "Fix login",
            description: "Fix authentication bug",
            category: "bug_fix",
            priority: "critical",
            effort: "high",
            dependencies: [],
            success_criteria: ["Users can log in"]
          }
        ],
        success_metrics: [
          {
            name: "Bug Count",
            target: "0 critical bugs"
          }
        ],
        risks: [
          {
            title: "Scope Creep",
            probability: "low",
            impact: "high",
            mitigation: "Stick to plan"
          }
        ],
        timeline: [
          {
            phase: "Planning",
            duration: "1 week",
            activities: "Design solutions"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          improvement_count: 1,
          new_feature_count: 1,
          task_count: 1
        }
      }
    end

    it "formats iteration plan as markdown" do
      markdown = generator.format_as_markdown(plan)

      expect(markdown).to include("# Next Iteration Plan")
      expect(markdown).to include("## Overview")
      expect(markdown).to include("## Iteration Goals")
      expect(markdown).to include("## Feature Improvements")
      expect(markdown).to include("## New Features")
      expect(markdown).to include("## Bug Fixes")
      expect(markdown).to include("## Technical Debt")
      expect(markdown).to include("## Task Breakdown")
      expect(markdown).to include("## Success Metrics")
      expect(markdown).to include("## Risks and Mitigation")
      expect(markdown).to include("## Timeline")
    end

    it "includes task details with categories" do
      markdown = generator.format_as_markdown(plan)

      expect(markdown).to include("**Category:** bug_fix")
      expect(markdown).to include("**Priority:** critical")
      expect(markdown).to include("**Estimated Effort:** high")
    end
  end
end
