# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/analyzers/feedback_analyzer"

RSpec.describe Aidp::Planning::Analyzers::FeedbackAnalyzer do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:config) { {} }

  subject(:analyzer) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      config: config
    )
  end

  describe "#analyze" do
    let(:feedback_data) do
      {
        format: :csv,
        source_file: "feedback.csv",
        parsed_at: "2025-01-15T10:00:00Z",
        response_count: 3,
        responses: [
          {
            respondent_id: "user1",
            timestamp: "2025-01-15",
            rating: 5,
            feedback_text: "Great product!",
            feature: "dashboard",
            sentiment: "positive",
            tags: ["usability", "design"],
            raw_data: {}
          },
          {
            respondent_id: "user2",
            timestamp: "2025-01-16",
            rating: 3,
            feedback_text: "Needs improvement",
            feature: "search",
            sentiment: "neutral",
            tags: ["performance"],
            raw_data: {}
          },
          {
            respondent_id: "user3",
            timestamp: "2025-01-17",
            rating: 2,
            feedback_text: "Confusing interface",
            feature: "dashboard",
            sentiment: "negative",
            tags: ["usability"],
            raw_data: {}
          }
        ],
        metadata: {
          total_rows: 3,
          columns: ["id", "timestamp", "rating", "feedback"],
          has_timestamps: true,
          has_ratings: true
        }
      }
    end

    let(:ai_response) do
      {
        summary: "Overall feedback is mixed with usability concerns",
        findings: [
          {
            title: "Usability Issues",
            description: "Users find dashboard confusing",
            evidence: ["Confusing interface", "Great product!"],
            impact: "high"
          }
        ],
        trends: [
          {
            title: "Dashboard Concerns",
            description: "Mixed feedback on dashboard",
            frequency: "2 mentions",
            implication: "Needs redesign"
          }
        ],
        insights: [
          {
            category: "usability",
            description: "Dashboard needs simplification"
          }
        ],
        sentiment_breakdown: [
          {type: "positive", count: 1, percentage: 33.3},
          {type: "neutral", count: 1, percentage: 33.3},
          {type: "negative", count: 1, percentage: 33.3}
        ],
        feature_feedback: [
          {
            feature_name: "dashboard",
            sentiment: "mixed",
            positive: ["Great product!"],
            negative: ["Confusing interface"],
            improvements: ["Simplify layout"]
          }
        ],
        recommendations: [
          {
            title: "Redesign Dashboard",
            description: "Simplify dashboard layout",
            rationale: "Multiple users confused",
            effort: "medium",
            impact: "high"
          }
        ],
        priority_issues: [
          {
            title: "Dashboard Usability",
            priority: "high",
            impact: "Affects user experience",
            affected_users: "66%",
            action: "Redesign with user testing"
          }
        ],
        positive_highlights: [
          "Users appreciate the design"
        ]
      }
    end

    it "analyzes feedback data using AI decision engine" do
      expect(ai_decision_engine).to receive(:decide)
        .with(hash_including(
          context: "feedback_analysis",
          data: feedback_data
        ))
        .and_return(ai_response)

      result = analyzer.analyze(feedback_data)

      expect(result[:summary]).to eq(ai_response[:summary])
      expect(result[:findings]).to eq(ai_response[:findings])
      expect(result[:trends]).to eq(ai_response[:trends])
      expect(result[:insights]).to eq(ai_response[:insights])
      expect(result[:sentiment_breakdown]).to eq(ai_response[:sentiment_breakdown])
      expect(result[:feature_feedback]).to eq(ai_response[:feature_feedback])
      expect(result[:recommendations]).to eq(ai_response[:recommendations])
      expect(result[:priority_issues]).to eq(ai_response[:priority_issues])
      expect(result[:positive_highlights]).to eq(ai_response[:positive_highlights])
    end

    it "includes metadata in analysis result" do
      allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = analyzer.analyze(feedback_data)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:responses_analyzed]).to eq(3)
      expect(result[:metadata][:source_file]).to eq("feedback.csv")
      expect(result[:metadata][:source_format]).to eq(:csv)
    end

    it "uses structured schema for AI decision" do
      expect(ai_decision_engine).to receive(:decide) do |args|
        schema = args[:schema]
        expect(schema[:type]).to eq("object")
        expect(schema[:properties]).to have_key(:summary)
        expect(schema[:properties]).to have_key(:findings)
        expect(schema[:properties]).to have_key(:recommendations)
        expect(schema[:required]).to include("summary", "findings", "recommendations")
        ai_response
      end

      analyzer.analyze(feedback_data)
    end
  end

  describe "#format_as_markdown" do
    let(:analysis) do
      {
        summary: "Overall positive feedback",
        sentiment_breakdown: [
          {type: "positive", count: 5, percentage: 83.3},
          {type: "negative", count: 1, percentage: 16.7}
        ],
        findings: [
          {
            title: "Feature Request",
            description: "Users want dark mode",
            evidence: ["Please add dark mode", "Dark mode needed"],
            impact: "medium"
          }
        ],
        trends: [
          {
            title: "UI Preferences",
            description: "Users prefer dark themes",
            frequency: "3 mentions",
            implication: "Consider dark mode"
          }
        ],
        insights: [
          {
            category: "features",
            description: "Dark mode is highly requested"
          }
        ],
        feature_feedback: [
          {
            feature_name: "Settings",
            sentiment: "positive",
            positive: ["Easy to use"],
            negative: ["Missing dark mode"],
            improvements: ["Add dark mode toggle"]
          }
        ],
        priority_issues: [
          {
            title: "No Dark Mode",
            priority: "medium",
            impact: "User preference",
            affected_users: "50%",
            action: "Add to backlog"
          }
        ],
        positive_highlights: [
          "Clean interface",
          "Fast performance"
        ],
        recommendations: [
          {
            title: "Add Dark Mode",
            description: "Implement dark theme option",
            rationale: "Highly requested by users",
            effort: "medium",
            impact: "high"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          responses_analyzed: 6,
          source_file: "feedback.csv",
          source_format: :csv
        }
      }
    end

    it "formats analysis as markdown with all sections" do
      markdown = analyzer.format_as_markdown(analysis)

      expect(markdown).to include("# User Feedback Analysis")
      expect(markdown).to include("## Executive Summary")
      expect(markdown).to include("Overall positive feedback")
      expect(markdown).to include("## Sentiment Breakdown")
      expect(markdown).to include("## Key Findings")
      expect(markdown).to include("Feature Request")
      expect(markdown).to include("## Trends and Patterns")
      expect(markdown).to include("## Insights")
      expect(markdown).to include("## Feature-Specific Feedback")
      expect(markdown).to include("## Priority Issues")
      expect(markdown).to include("## Positive Highlights")
      expect(markdown).to include("## Recommendations")
    end

    it "includes metadata in markdown" do
      markdown = analyzer.format_as_markdown(analysis)

      expect(markdown).to include("**Generated:** 2025-01-15T10:00:00Z")
      expect(markdown).to include("**Responses Analyzed:** 6")
      expect(markdown).to include("**Source:** feedback.csv")
    end

    it "formats sentiment breakdown as table" do
      markdown = analyzer.format_as_markdown(analysis)

      expect(markdown).to include("| Sentiment | Count | Percentage |")
      expect(markdown).to include("| positive | 5 | 83.3% |")
      expect(markdown).to include("| negative | 1 | 16.7% |")
    end
  end
end
