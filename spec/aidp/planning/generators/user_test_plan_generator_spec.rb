# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/generators/user_test_plan_generator"

RSpec.describe Aidp::Planning::Generators::UserTestPlanGenerator do
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
            name: "User Dashboard",
            description: "Main user interface",
            rationale: "Core functionality"
          },
          {
            name: "Settings",
            description: "User preferences",
            rationale: "Essential for personalization"
          }
        ],
        metadata: {
          user_priorities: ["Target users: Developers", "Timeline: 3 months"]
        }
      }
    end

    let(:ai_response) do
      {
        overview: "This testing plan validates the MVP with real users",
        target_users: [
          {
            name: "Professional Developers",
            description: "Experienced software engineers",
            characteristics: ["5+ years experience", "Use similar tools"],
            sample_size: "10-15 participants"
          }
        ],
        recruitment: {
          screener_questions: [
            {
              question: "How many years of development experience do you have?",
              type: "number",
              qualifying_answer: "5 or more"
            }
          ],
          channels: ["Developer forums", "LinkedIn", "Twitter"],
          incentives: "$50 Amazon gift card"
        },
        testing_stages: [
          {
            name: "Alpha Testing",
            objective: "Validate core functionality",
            duration: "2 weeks",
            participants: "5-10 users",
            activities: ["Feature testing", "Bug reporting"],
            success_criteria: ["No critical bugs", "80% task completion"]
          }
        ],
        survey_questions: {
          likert: [
            "The interface is easy to use",
            "The features meet my needs"
          ],
          multiple_choice: [
            {
              question: "How often would you use this?",
              options: ["Daily", "Weekly", "Monthly", "Rarely"]
            }
          ],
          open_ended: [
            "What did you like most about the product?",
            "What improvements would you suggest?"
          ]
        },
        interview_script: {
          introduction: "Thank you for participating in our user testing",
          main_questions: [
            {
              question: "What was your first impression?",
              follow_ups: ["Why did you feel that way?", "What could improve it?"]
            }
          ],
          closing: "Thank you for your valuable feedback"
        },
        success_metrics: [
          {
            name: "Task Completion Rate",
            description: "Percentage of tasks completed successfully",
            target: "80% or higher"
          }
        ],
        timeline: [
          {
            phase: "Recruitment",
            duration: "1 week"
          },
          {
            phase: "Alpha Testing",
            duration: "2 weeks"
          },
          {
            phase: "Analysis",
            duration: "1 week"
          }
        ]
      }
    end

    it "generates user test plan from MVP scope" do
      expect(ai_decision_engine).to receive(:decide)
        .with(hash_including(
          context: "user_test_plan_generation"
        ))
        .and_return(ai_response)

      result = generator.generate(mvp_scope: mvp_scope)

      expect(result[:overview]).to eq(ai_response[:overview])
      expect(result[:target_users]).to eq(ai_response[:target_users])
      expect(result[:recruitment]).to eq(ai_response[:recruitment])
      expect(result[:testing_stages]).to eq(ai_response[:testing_stages])
      expect(result[:survey_questions]).to eq(ai_response[:survey_questions])
      expect(result[:interview_script]).to eq(ai_response[:interview_script])
      expect(result[:success_metrics]).to eq(ai_response[:success_metrics])
      expect(result[:timeline]).to eq(ai_response[:timeline])
    end

    it "includes metadata in result" do
      allow(ai_decision_engine).to receive(:decide).and_return(ai_response)

      result = generator.generate(mvp_scope: mvp_scope)

      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:mvp_feature_count]).to eq(2)
      expect(result[:metadata][:testing_stage_count]).to eq(1)
      expect(result[:metadata][:survey_question_count]).to eq(3) # likert, multiple_choice, open_ended
    end

    it "passes MVP features to AI for contextual questions" do
      expect(ai_decision_engine).to receive(:decide) do |args|
        prompt = args[:prompt]
        expect(prompt).to include("User Dashboard")
        expect(prompt).to include("Settings")
        ai_response
      end

      generator.generate(mvp_scope: mvp_scope)
    end
  end

  describe "#format_as_markdown" do
    let(:test_plan) do
      {
        overview: "Comprehensive testing plan",
        target_users: [
          {
            name: "Power Users",
            description: "Advanced users",
            characteristics: ["Expert level", "Daily usage"],
            sample_size: "10"
          }
        ],
        recruitment: {
          screener_questions: [
            {
              question: "Are you an expert user?",
              type: "yes/no",
              qualifying_answer: "yes"
            }
          ],
          channels: ["Forums"],
          incentives: "Gift card"
        },
        testing_stages: [
          {
            name: "Beta",
            objective: "Test at scale",
            duration: "1 month",
            participants: "50",
            activities: ["Real-world usage"],
            success_criteria: ["Positive feedback"]
          }
        ],
        survey_questions: {
          likert: ["I am satisfied"],
          multiple_choice: [
            {
              question: "Frequency?",
              options: ["Daily", "Weekly"]
            }
          ],
          open_ended: ["Suggestions?"]
        },
        interview_script: {
          introduction: "Welcome",
          main_questions: [
            {
              question: "Your thoughts?",
              follow_ups: ["Why?"]
            }
          ],
          closing: "Thanks"
        },
        success_metrics: [
          {
            name: "NPS",
            description: "Net Promoter Score",
            target: "50+"
          }
        ],
        timeline: [
          {
            phase: "Testing",
            duration: "2 weeks"
          }
        ],
        metadata: {
          generated_at: "2025-01-15T10:00:00Z",
          mvp_feature_count: 2,
          testing_stage_count: 1,
          survey_question_count: 1
        }
      }
    end

    it "formats test plan as markdown" do
      markdown = generator.format_as_markdown(test_plan)

      expect(markdown).to include("# User Testing Plan")
      expect(markdown).to include("## Overview")
      expect(markdown).to include("## Target Users")
      expect(markdown).to include("## Recruitment Criteria")
      expect(markdown).to include("## Testing Stages")
      expect(markdown).to include("## Survey Questions")
      expect(markdown).to include("## Interview Script")
      expect(markdown).to include("## Success Metrics")
      expect(markdown).to include("## Timeline")
    end

    it "includes all question types" do
      markdown = generator.format_as_markdown(test_plan)

      expect(markdown).to include("### Likert Scale Questions")
      expect(markdown).to include("### Multiple Choice Questions")
      expect(markdown).to include("### Open-Ended Questions")
    end
  end
end
