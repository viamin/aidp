# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates next iteration plan based on user feedback
      # Creates actionable tasks to address feedback and improve product
      # Uses Zero Framework Cognition (ZFC) for priority and task generation
      class IterationPlanGenerator
        def initialize(ai_decision_engine:, wbs_generator: nil, config: nil)
          @ai_decision_engine = ai_decision_engine
          @wbs_generator = wbs_generator
          @config = config || Aidp::Config.agile_config
        end

        # Generate iteration plan from feedback analysis
        # @param feedback_analysis [Hash] Analyzed feedback data
        # @param current_mvp [Hash] Current MVP scope (optional)
        # @return [Hash] Iteration plan structure
        def generate(feedback_analysis:, current_mvp: nil)
          Aidp.log_debug("iteration_plan_generator", "generate",
            recommendations: feedback_analysis[:recommendations]&.size || 0)

          # Use AI to generate iteration plan
          iteration_plan = generate_plan_with_ai(feedback_analysis, current_mvp)

          {
            overview: iteration_plan[:overview],
            goals: iteration_plan[:goals],
            improvements: iteration_plan[:improvements],
            new_features: iteration_plan[:new_features],
            bug_fixes: iteration_plan[:bug_fixes],
            technical_debt: iteration_plan[:technical_debt],
            tasks: iteration_plan[:tasks],
            success_metrics: iteration_plan[:success_metrics],
            risks: iteration_plan[:risks],
            timeline: iteration_plan[:timeline],
            metadata: {
              generated_at: Time.now.iso8601,
              improvement_count: iteration_plan[:improvements]&.size || 0,
              new_feature_count: iteration_plan[:new_features]&.size || 0,
              task_count: iteration_plan[:tasks]&.size || 0,
              based_on_feedback: !feedback_analysis.nil?
            }
          }
        end

        # Format iteration plan as markdown
        # @param plan [Hash] Iteration plan structure
        # @return [String] Markdown formatted iteration plan
        def format_as_markdown(plan)
          Aidp.log_debug("iteration_plan_generator", "format_as_markdown")

          output = ["# Next Iteration Plan", ""]
          output << "**Generated:** #{plan[:metadata][:generated_at]}"
          output << "**Improvements:** #{plan[:metadata][:improvement_count]}"
          output << "**New Features:** #{plan[:metadata][:new_feature_count]}"
          output << "**Total Tasks:** #{plan[:metadata][:task_count]}"
          output << ""

          output << "## Overview"
          output << ""
          output << plan[:overview]
          output << ""

          output << "## Iteration Goals"
          output << ""
          plan[:goals].each_with_index do |goal, idx|
            output << "#{idx + 1}. #{goal}"
          end
          output << ""

          output << "## Feature Improvements"
          output << ""
          output << "Based on user feedback, these existing features will be improved:"
          output << ""
          plan[:improvements].each_with_index do |improvement, idx|
            output << "### #{idx + 1}. #{improvement[:feature_name]}"
            output << ""
            output << "**Current Issue:** #{improvement[:issue]}"
            output << ""
            output << "**Proposed Improvement:** #{improvement[:improvement]}"
            output << ""
            output << "**User Impact:** #{improvement[:impact]}"
            output << ""
            output << "**Effort:** #{improvement[:effort]}"
            output << ""
            output << "**Priority:** #{improvement[:priority]}"
            output << ""
          end

          output << "## New Features"
          output << ""
          output << "New features to be added based on user requests:"
          output << ""
          plan[:new_features].each_with_index do |feature, idx|
            output << "### #{idx + 1}. #{feature[:name]}"
            output << ""
            output << feature[:description]
            output << ""
            output << "**Rationale:** #{feature[:rationale]}"
            output << ""
            output << "**Acceptance Criteria:**"
            (feature[:acceptance_criteria] || []).each do |criterion|
              output << "- #{criterion}"
            end
            output << ""
            output << "**Effort:** #{feature[:effort]}"
            output << ""
          end

          output << "## Bug Fixes"
          output << ""
          plan[:bug_fixes].each_with_index do |bug, idx|
            output << "#{idx + 1}. **#{bug[:title]}** (Priority: #{bug[:priority]})"
            output << "   - Description: #{bug[:description]}"
            output << "   - Affected Users: #{bug[:affected_users]}"
            output << ""
          end

          output << "## Technical Debt"
          output << ""
          output << "Technical improvements to be addressed:"
          output << ""
          plan[:technical_debt].each do |debt|
            output << "- **#{debt[:title]}:** #{debt[:description]} (Effort: #{debt[:effort]})"
          end
          output << ""

          output << "## Task Breakdown"
          output << ""
          plan[:tasks].each_with_index do |task, idx|
            output << "### Task #{idx + 1}: #{task[:name]}"
            output << ""
            output << "**Description:** #{task[:description]}"
            output << ""
            output << "**Category:** #{task[:category]}"
            output << ""
            output << "**Priority:** #{task[:priority]}"
            output << ""
            output << "**Estimated Effort:** #{task[:effort]}"
            output << ""
            output << "**Dependencies:** #{task[:dependencies]&.join(", ") || "None"}"
            output << ""
            output << "**Success Criteria:**"
            (task[:success_criteria] || []).each do |criterion|
              output << "- #{criterion}"
            end
            output << ""
          end

          output << "## Success Metrics"
          output << ""
          output << "How we'll measure success of this iteration:"
          output << ""
          plan[:success_metrics].each do |metric|
            output << "- **#{metric[:name]}:** #{metric[:target]}"
            output << ""
          end

          output << "## Risks and Mitigation"
          output << ""
          plan[:risks].each_with_index do |risk, idx|
            output << "#{idx + 1}. **#{risk[:title]}**"
            output << "   - Probability: #{risk[:probability]}"
            output << "   - Impact: #{risk[:impact]}"
            output << "   - Mitigation: #{risk[:mitigation]}"
            output << ""
          end

          output << "## Timeline"
          output << ""
          plan[:timeline].each do |phase|
            output << "- **#{phase[:phase]}:** #{phase[:duration]} (#{phase[:activities]})"
          end
          output << ""

          output.join("\n")
        end

        private

        def generate_plan_with_ai(feedback_analysis, current_mvp)
          Aidp.log_debug("iteration_plan_generator", "generate_plan_with_ai")

          prompt = build_iteration_prompt(feedback_analysis, current_mvp)

          schema = {
            type: "object",
            properties: {
              overview: {type: "string"},
              goals: {type: "array", items: {type: "string"}},
              improvements: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    feature_name: {type: "string"},
                    issue: {type: "string"},
                    improvement: {type: "string"},
                    impact: {type: "string"},
                    effort: {type: "string"},
                    priority: {type: "string"}
                  }
                }
              },
              new_features: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    rationale: {type: "string"},
                    acceptance_criteria: {type: "array", items: {type: "string"}},
                    effort: {type: "string"}
                  }
                }
              },
              bug_fixes: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    priority: {type: "string"},
                    affected_users: {type: "string"}
                  }
                }
              },
              technical_debt: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    effort: {type: "string"}
                  }
                }
              },
              tasks: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    category: {type: "string"},
                    priority: {type: "string"},
                    effort: {type: "string"},
                    dependencies: {type: "array", items: {type: "string"}},
                    success_criteria: {type: "array", items: {type: "string"}}
                  }
                }
              },
              success_metrics: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    target: {type: "string"}
                  }
                }
              },
              risks: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    probability: {type: "string"},
                    impact: {type: "string"},
                    mitigation: {type: "string"}
                  }
                }
              },
              timeline: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    phase: {type: "string"},
                    duration: {type: "string"},
                    activities: {type: "string"}
                  }
                }
              }
            },
            required: ["overview", "goals", "improvements", "tasks"]
          }

          decision = @ai_decision_engine.decide(
            context: "iteration_plan_generation",
            prompt: prompt,
            data: {
              feedback_analysis: feedback_analysis,
              current_mvp: current_mvp
            },
            schema: schema
          )

          Aidp.log_debug("iteration_plan_generator", "ai_plan_generated",
            tasks: decision[:tasks]&.size || 0,
            improvements: decision[:improvements]&.size || 0)

          decision
        end

        def build_iteration_prompt(feedback_analysis, current_mvp)
          mvp_context = if current_mvp
            <<~CONTEXT
              CURRENT MVP FEATURES:
              #{current_mvp[:mvp_features]&.map { |f| "- #{f[:name]}: #{f[:description]}" }&.join("\n") || "No features"}
            CONTEXT
          else
            ""
          end

          <<~PROMPT
            Generate a detailed iteration plan based on user feedback analysis.

            FEEDBACK SUMMARY:
            #{feedback_analysis[:summary]}

            KEY FINDINGS:
            #{feedback_analysis[:findings]&.map { |f| "- #{f[:title]}: #{f[:description]}" }&.join("\n") || "No findings"}

            RECOMMENDATIONS:
            #{feedback_analysis[:recommendations]&.map { |r| "- #{r[:title]}: #{r[:description]}" }&.join("\n") || "No recommendations"}

            PRIORITY ISSUES:
            #{feedback_analysis[:priority_issues]&.map { |i| "- #{i[:title]} (#{i[:priority]})" }&.join("\n") || "No priority issues"}

            #{mvp_context}

            TASK:
            Create a comprehensive iteration plan:

            1. OVERVIEW
               - What is the focus of this iteration?
               - Why these priorities?

            2. ITERATION GOALS (3-5 goals)
               - Clear, measurable goals for this iteration

            3. FEATURE IMPROVEMENTS
               - For existing features that need enhancement
               - Current issue, proposed improvement, user impact, effort, priority

            4. NEW FEATURES
               - Features to add based on user requests
               - Description, rationale, acceptance criteria, effort estimate

            5. BUG FIXES
               - Critical and high-priority bugs from feedback
               - Priority, description, affected users

            6. TECHNICAL DEBT
               - Technical improvements needed
               - Performance, scalability, maintainability issues

            7. TASK BREAKDOWN
               - Specific, actionable tasks
               - For each: description, category, priority, effort, dependencies, success criteria
               - Categories: feature, improvement, bug_fix, tech_debt, testing, documentation

            8. SUCCESS METRICS
               - How to measure iteration success
               - Specific targets

            9. RISKS AND MITIGATION
               - What could go wrong?
               - Probability (low/medium/high)
               - Impact (low/medium/high)
               - Mitigation strategy

            10. TIMELINE
               - Phases of the iteration
               - Duration and key activities

            Prioritize based on user impact, effort, and dependencies. Be specific and actionable.
          PROMPT
        end
      end
    end
  end
end
