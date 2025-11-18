# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/generators/marketing_report_generator"

RSpec.describe Aidp::Planning::Generators::MarketingReportGenerator do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:config) { {} }

  subject(:generator) do
    described_class.new(
      ai_decision_engine: ai_decision_engine,
      config: config
    )
  end

  describe "#generate" do
    let(:mvp_scope) do
      {
        mvp_features: [
          {
            name: "Fast Search",
            description: "Lightning-fast search engine"
          }
        ],
        success_criteria: ["User adoption > 1000"]
      }
    end

    let(:ai_response) do
      {
        overview: "Marketing strategy for MVP launch",
        value_proposition: {
          headline: "Search at Lightning Speed",
          subheadline: "Find what you need in milliseconds",
          core_benefits: ["Save time", "Increase productivity", "Better results"]
        },
        key_messages: [
          {
            title: "Speed",
            description: "Fastest search in the market",
            supporting_points: ["10x faster than competitors", "Sub-second results"]
          }
        ],
        differentiators: [
          {
            title: "Performance",
            description: "Unmatched speed",
            advantage: "10x faster than alternatives"
          }
        ],
        target_audience: [
          {
            name: "Developers",
            description: "Software engineers",
            pain_points: ["Slow searches", "Poor results"],
            our_solution: ["Fast results", "Accurate matching"]
          }
        ],
        positioning: {
          category: "Developer Tools",
          statement: "For developers who need fast search, our tool provides instant results",
          tagline: "Search Faster, Code Better"
        },
        success_metrics: [
          {
            name: "Sign-ups",
            target: "1000 in first month",
            measurement: "Track registrations"
          }
        ],
        messaging_framework: [
          {
            audience: "Developers",
            message: "Save time with fast search",
            channel: "Twitter",
            cta: "Try it free"
          }
        ],
        launch_checklist: [
          {
            task: "Create landing page",
            owner: "Marketing",
            timeline: "Week 1"
          }
        ]
      }
    end

    it "generates marketing report from MVP scope" do
      expect(ai_decision_engine).to receive(:decide)
        .with(hash_including(
          context: "marketing_report_generation"
        ))
        .and_return(ai_response)

      result = generator.generate(mvp_scope: mvp_scope)

      expect(result[:overview]).to eq(ai_response[:overview])
      expect(result[:value_proposition]).to eq(ai_response[:value_proposition])
      expect(result[:key_messages]).to eq(ai_response[:key_messages])
      expect(result[:differentiators]).to eq(ai_response[:differentiators])
      expect(result[:target_audience]).to eq(ai_response[:target_audience])
      expect(result[:positioning]).to eq(ai_response[:positioning])
    end

    it "includes feedback analysis when provided" do
      feedback_analysis = {
        findings: [
          {title: "Users love speed", description: "Fast performance praised"}
        ]
      }

      expect(ai_decision_engine).to receive(:decide) do |args|
        data = args[:data]
        expect(data[:feedback_analysis]).to eq(feedback_analysis)
        ai_response
      end

      generator.generate(mvp_scope: mvp_scope, feedback_analysis: feedback_analysis)
    end

    it "includes metadata in result" do
      allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = generator.generate(mvp_scope: mvp_scope)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:key_message_count]).to eq(1)
      expect(result[:metadata][:differentiator_count]).to eq(1)
    end
  end

  describe "#format_as_markdown" do
    let(:report) do
      {
        overview: "Launch strategy",
        value_proposition: {
          headline: "Best Tool Ever",
          subheadline: "Makes your life easier",
          core_benefits: ["Save time", "Make money"]
        },
        key_messages: [
          {
            title: "Efficiency",
            description: "Work faster",
            supporting_points: ["Automated workflows"]
          }
        ],
        differentiators: [
          {
            title: "Speed",
            description: "Fastest tool",
            advantage: "10x faster"
          }
        ],
        target_audience: [
          {
            name: "Professionals",
            description: "Business users",
            pain_points: ["Slow tools"],
            our_solution: ["Fast performance"]
          }
        ],
        positioning: {
          category: "Productivity",
          statement: "For busy professionals",
          tagline: "Work Smarter"
        },
        success_metrics: [
          {
            name: "Users",
            target: "1000",
            measurement: "Count sign-ups"
          }
        ],
        messaging_framework: [
          {
            audience: "Professionals",
            message: "Save time",
            channel: "LinkedIn",
            cta: "Sign up"
          }
        ],
        launch_checklist: [
          {
            task: "Website",
            owner: "Marketing",
            timeline: "Week 1"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          key_message_count: 1,
          differentiator_count: 1
        }
      }
    end

    it "formats report as markdown" do
      markdown = generator.format_as_markdown(report)

      expect(markdown).to include("# Marketing Report")
      expect(markdown).to include("## Overview")
      expect(markdown).to include("## Value Proposition")
      expect(markdown).to include("## Key Messages")
      expect(markdown).to include("## Differentiators")
      expect(markdown).to include("## Target Audience")
      expect(markdown).to include("## Positioning")
      expect(markdown).to include("## Success Metrics")
      expect(markdown).to include("## Messaging Framework")
      expect(markdown).to include("## Launch Checklist")
    end

    it "formats messaging framework as table" do
      markdown = generator.format_as_markdown(report)

      expect(markdown).to include("| Audience | Message | Channel | Call to Action |")
      expect(markdown).to include("| Professionals | Save time | LinkedIn | Sign up |")
    end
  end
end
