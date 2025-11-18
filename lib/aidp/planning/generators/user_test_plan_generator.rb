# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates user testing plan with recruitment criteria and survey templates
      # Uses AI to create contextual testing questions based on feature set
      # Follows Zero Framework Cognition (ZFC) pattern
      class UserTestPlanGenerator
        def initialize(ai_decision_engine:, config: nil)
          @ai_decision_engine = ai_decision_engine
          @config = config || Aidp::Config.agile_config
        end

        # Generate user test plan from MVP scope
        # @param mvp_scope [Hash] MVP scope definition
        # @param target_users [String] Description of target users (optional)
        # @return [Hash] User test plan structure
        def generate(mvp_scope:, target_users: nil)
          Aidp.log_debug("user_test_plan_generator", "generate",
            feature_count: mvp_scope[:mvp_features]&.size || 0)

          # Use AI to generate contextual testing plan
          test_plan = generate_test_plan_with_ai(mvp_scope, target_users)

          {
            overview: test_plan[:overview],
            target_users: test_plan[:target_users],
            recruitment: test_plan[:recruitment],
            testing_stages: test_plan[:testing_stages],
            survey_questions: test_plan[:survey_questions],
            interview_script: test_plan[:interview_script],
            success_metrics: test_plan[:success_metrics],
            timeline: test_plan[:timeline],
            metadata: {
              generated_at: Time.now.iso8601,
              mvp_feature_count: mvp_scope[:mvp_features]&.size || 0,
              testing_stage_count: test_plan[:testing_stages]&.size || 0,
              survey_question_count: test_plan[:survey_questions]&.size || 0
            }
          }
        end

        # Format user test plan as markdown
        # @param test_plan [Hash] User test plan structure
        # @return [String] Markdown formatted test plan
        def format_as_markdown(test_plan)
          Aidp.log_debug("user_test_plan_generator", "format_as_markdown")

          output = ["# User Testing Plan", ""]
          output << "**Generated:** #{test_plan[:metadata][:generated_at]}"
          output << "**Features to Test:** #{test_plan[:metadata][:mvp_feature_count]}"
          output << "**Testing Stages:** #{test_plan[:metadata][:testing_stage_count]}"
          output << ""

          output << "## Overview"
          output << ""
          output << test_plan[:overview]
          output << ""

          output << "## Target Users"
          output << ""
          test_plan[:target_users].each do |segment|
            output << "### #{segment[:name]}"
            output << ""
            output << "**Description:** #{segment[:description]}"
            output << ""
            output << "**Characteristics:**"
            segment[:characteristics].each do |char|
              output << "- #{char}"
            end
            output << ""
            output << "**Sample Size:** #{segment[:sample_size]}"
            output << ""
          end

          output << "## Recruitment Criteria"
          output << ""
          output << "### Screener Questions"
          output << ""
          test_plan[:recruitment][:screener_questions].each_with_index do |q, idx|
            output << "#{idx + 1}. **#{q[:question]}**"
            output << "   - Type: #{q[:type]}"
            output << "   - Qualifying Answer: #{q[:qualifying_answer]}" if q[:qualifying_answer]
            output << ""
          end

          output << "### Recruitment Channels"
          output << ""
          test_plan[:recruitment][:channels].each do |channel|
            output << "- #{channel}"
          end
          output << ""

          output << "### Incentives"
          output << ""
          output << test_plan[:recruitment][:incentives]
          output << ""

          output << "## Testing Stages"
          output << ""
          test_plan[:testing_stages].each_with_index do |stage, idx|
            output << "### Stage #{idx + 1}: #{stage[:name]}"
            output << ""
            output << "**Objective:** #{stage[:objective]}"
            output << ""
            output << "**Duration:** #{stage[:duration]}"
            output << ""
            output << "**Participants:** #{stage[:participants]}"
            output << ""
            output << "**Activities:**"
            stage[:activities].each do |activity|
              output << "- #{activity}"
            end
            output << ""
            output << "**Success Criteria:**"
            stage[:success_criteria].each do |criterion|
              output << "- #{criterion}"
            end
            output << ""
          end

          output << "## Survey Questions"
          output << ""
          output << "### Likert Scale Questions (1-5: Strongly Disagree to Strongly Agree)"
          output << ""
          test_plan[:survey_questions][:likert].each_with_index do |q, idx|
            output << "#{idx + 1}. #{q}"
          end
          output << ""

          output << "### Multiple Choice Questions"
          output << ""
          test_plan[:survey_questions][:multiple_choice].each_with_index do |q, idx|
            output << "#{idx + 1}. **#{q[:question]}**"
            q[:options].each_with_index do |opt, oidx|
              output << "   #{("a".."z").to_a[oidx]}. #{opt}"
            end
            output << ""
          end

          output << "### Open-Ended Questions"
          output << ""
          test_plan[:survey_questions][:open_ended].each_with_index do |q, idx|
            output << "#{idx + 1}. #{q}"
          end
          output << ""

          output << "## Interview Script"
          output << ""
          output << "### Introduction"
          output << ""
          output << test_plan[:interview_script][:introduction]
          output << ""

          output << "### Main Questions"
          output << ""
          test_plan[:interview_script][:main_questions].each_with_index do |q, idx|
            output << "#{idx + 1}. #{q[:question]}"
            output << "   - **Follow-ups:** #{q[:follow_ups].join(", ")}" if q[:follow_ups]&.any?
            output << ""
          end

          output << "### Closing"
          output << ""
          output << test_plan[:interview_script][:closing]
          output << ""

          output << "## Success Metrics"
          output << ""
          test_plan[:success_metrics].each do |metric|
            output << "- **#{metric[:name]}:** #{metric[:description]}"
            output << "  - Target: #{metric[:target]}"
            output << ""
          end

          output << "## Timeline"
          output << ""
          test_plan[:timeline].each do |phase|
            output << "- **#{phase[:phase]}:** #{phase[:duration]}"
          end
          output << ""

          output.join("\n")
        end

        private

        def generate_test_plan_with_ai(mvp_scope, target_users)
          Aidp.log_debug("user_test_plan_generator", "generate_test_plan_with_ai")

          prompt = build_test_plan_prompt(mvp_scope, target_users)

          schema = {
            type: "object",
            properties: {
              overview: {type: "string"},
              target_users: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    characteristics: {type: "array", items: {type: "string"}},
                    sample_size: {type: "string"}
                  }
                }
              },
              recruitment: {
                type: "object",
                properties: {
                  screener_questions: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        question: {type: "string"},
                        type: {type: "string"},
                        qualifying_answer: {type: "string"}
                      }
                    }
                  },
                  channels: {type: "array", items: {type: "string"}},
                  incentives: {type: "string"}
                }
              },
              testing_stages: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    objective: {type: "string"},
                    duration: {type: "string"},
                    participants: {type: "string"},
                    activities: {type: "array", items: {type: "string"}},
                    success_criteria: {type: "array", items: {type: "string"}}
                  }
                }
              },
              survey_questions: {
                type: "object",
                properties: {
                  likert: {type: "array", items: {type: "string"}},
                  multiple_choice: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        question: {type: "string"},
                        options: {type: "array", items: {type: "string"}}
                      }
                    }
                  },
                  open_ended: {type: "array", items: {type: "string"}}
                }
              },
              interview_script: {
                type: "object",
                properties: {
                  introduction: {type: "string"},
                  main_questions: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        question: {type: "string"},
                        follow_ups: {type: "array", items: {type: "string"}}
                      }
                    }
                  },
                  closing: {type: "string"}
                }
              },
              success_metrics: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    target: {type: "string"}
                  }
                }
              },
              timeline: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    phase: {type: "string"},
                    duration: {type: "string"}
                  }
                }
              }
            },
            required: ["overview", "target_users", "recruitment", "testing_stages", "survey_questions"]
          }

          decision = @ai_decision_engine.decide(
            context: "user_test_plan_generation",
            prompt: prompt,
            data: {
              mvp_scope: mvp_scope,
              target_users: target_users
            },
            schema: schema
          )

          Aidp.log_debug("user_test_plan_generator", "ai_plan_generated",
            stages: decision[:testing_stages]&.size || 0,
            questions: decision[:survey_questions][:likert]&.size || 0)

          decision
        end

        def build_test_plan_prompt(mvp_scope, target_users)
          <<~PROMPT
            Generate a comprehensive user testing plan for the following MVP scope.

            MVP FEATURES:
            #{mvp_scope[:mvp_features]&.map { |f| "- #{f[:name]}: #{f[:description]}" }&.join("\n") || "No features provided"}

            TARGET USERS:
            #{target_users || mvp_scope.dig(:metadata, :user_priorities)&.find { |p| p.start_with?("Target users:") } || "General users"}

            TASK:
            Create a detailed user testing plan that includes:

            1. OVERVIEW
               - Brief description of testing goals
               - Why user testing is important for this MVP

            2. TARGET USERS (segments)
               - Define 2-3 user segments to test
               - For each: name, description, characteristics, recommended sample size

            3. RECRUITMENT
               - Screener questions to qualify participants
               - Recruitment channels (where to find users)
               - Suggested incentives

            4. TESTING STAGES
               - Define 3-4 testing stages (e.g., Alpha, Beta, Launch)
               - For each stage: objective, duration, number of participants, activities, success criteria

            5. SURVEY QUESTIONS
               - 5-7 Likert scale questions (1-5 scale)
               - 3-5 multiple choice questions with options
               - 3-5 open-ended questions

            6. INTERVIEW SCRIPT
               - Introduction text
               - 5-7 main interview questions with follow-ups
               - Closing text

            7. SUCCESS METRICS
               - Quantitative and qualitative metrics
               - Target values for each metric

            8. TIMELINE
               - Estimated duration for each phase (recruitment, testing, analysis)

            Make questions specific to the MVP features. Focus on usability, value proposition, and user satisfaction.
          PROMPT
        end
      end
    end
  end
end
