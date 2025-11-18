# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates MVP scope definition using AI to analyze features
      # Determines must-have vs nice-to-have features for MVP
      # Uses Zero Framework Cognition (ZFC) - NO heuristics, pure AI decisions
      class MVPScopeGenerator
        def initialize(ai_decision_engine:, prompt: nil, config: nil)
          @ai_decision_engine = ai_decision_engine
          @prompt = prompt || TTY::Prompt.new
          @config = config || Aidp::Config.agile_config
        end

        # Generate MVP scope from PRD and user priorities
        # @param prd [Hash] Parsed PRD document
        # @param user_priorities [Array<String>] User-specified priorities (optional)
        # @return [Hash] MVP scope with must-have and nice-to-have features
        def generate(prd:, user_priorities: nil)
          Aidp.log_debug("mvp_scope_generator", "generate", has_prd: !prd.nil?)

          # Collect user priorities if not provided
          priorities = user_priorities || collect_user_priorities(prd)

          Aidp.log_debug("mvp_scope_generator", "analyzing_features", priority_count: priorities.size)

          # Use AI to analyze features and determine MVP viability
          mvp_analysis = analyze_features_with_ai(prd, priorities)

          {
            mvp_features: mvp_analysis[:must_have],
            deferred_features: mvp_analysis[:nice_to_have],
            out_of_scope: mvp_analysis[:out_of_scope],
            success_criteria: mvp_analysis[:success_criteria],
            assumptions: mvp_analysis[:assumptions],
            risks: mvp_analysis[:risks],
            metadata: {
              generated_at: Time.now.iso8601,
              mvp_feature_count: mvp_analysis[:must_have].size,
              deferred_feature_count: mvp_analysis[:nice_to_have].size,
              out_of_scope_count: mvp_analysis[:out_of_scope].size,
              user_priorities: priorities
            }
          }
        end

        # Format MVP scope as markdown
        # @param mvp_scope [Hash] MVP scope structure
        # @return [String] Markdown formatted MVP scope
        def format_as_markdown(mvp_scope)
          Aidp.log_debug("mvp_scope_generator", "format_as_markdown")

          output = ["# MVP Scope Definition", ""]
          output << "**Generated:** #{mvp_scope[:metadata][:generated_at]}"
          output << "**MVP Features:** #{mvp_scope[:metadata][:mvp_feature_count]}"
          output << "**Deferred Features:** #{mvp_scope[:metadata][:deferred_feature_count]}"
          output << ""

          output << "## Overview"
          output << ""
          output << "This document defines the Minimum Viable Product (MVP) scope, distinguishing between must-have features for initial release and nice-to-have features that can be deferred to later iterations."
          output << ""

          output << "## User Priorities"
          output << ""
          mvp_scope[:metadata][:user_priorities].each_with_index do |priority, idx|
            output << "#{idx + 1}. #{priority}"
          end
          output << ""

          output << "## MVP Features (Must-Have)"
          output << ""
          output << "These features are essential for the MVP and must be included in the first release:"
          output << ""
          mvp_scope[:mvp_features].each_with_index do |feature, idx|
            output << "### #{idx + 1}. #{feature[:name]}"
            output << ""
            output << feature[:description] if feature[:description]
            output << ""
            output << "**Rationale:** #{feature[:rationale]}" if feature[:rationale]
            output << ""
            output << "**Acceptance Criteria:**"
            (feature[:acceptance_criteria] || []).each do |criterion|
              output << "- #{criterion}"
            end
            output << ""
          end

          output << "## Deferred Features (Nice-to-Have)"
          output << ""
          output << "These features can be implemented in future iterations:"
          output << ""
          mvp_scope[:deferred_features].each_with_index do |feature, idx|
            output << "### #{idx + 1}. #{feature[:name]}"
            output << ""
            output << feature[:description] if feature[:description]
            output << ""
            output << "**Deferral Reason:** #{feature[:deferral_reason]}" if feature[:deferral_reason]
            output << ""
          end

          output << "## Out of Scope"
          output << ""
          output << "These items are explicitly out of scope for the MVP:"
          output << ""
          mvp_scope[:out_of_scope].each do |item|
            output << "- #{item}"
          end
          output << ""

          output << "## Success Criteria"
          output << ""
          output << "The MVP will be considered successful if:"
          output << ""
          mvp_scope[:success_criteria].each do |criterion|
            output << "- #{criterion}"
          end
          output << ""

          output << "## Assumptions"
          output << ""
          mvp_scope[:assumptions].each do |assumption|
            output << "- #{assumption}"
          end
          output << ""

          output << "## Risks"
          output << ""
          mvp_scope[:risks].each_with_index do |risk, idx|
            output << "#{idx + 1}. **#{risk[:title]}**"
            output << "   - **Impact:** #{risk[:impact]}"
            output << "   - **Mitigation:** #{risk[:mitigation]}"
            output << ""
          end

          output.join("\n")
        end

        private

        # Collect user priorities interactively
        def collect_user_priorities(prd)
          Aidp.log_debug("mvp_scope_generator", "collect_user_priorities")

          @prompt.say("Let's define your MVP priorities.")
          @prompt.say("")

          priorities = []

          # Ask about key priorities
          priorities << @prompt.ask("What is the primary goal of this MVP?", required: true)
          priorities << @prompt.ask("What is the main problem you're solving?", required: true)

          # Ask about target users
          target_users = @prompt.ask("Who are your target users?", required: true)
          priorities << "Target users: #{target_users}"

          # Ask about timeline
          timeline = @prompt.ask("What is your target timeline for MVP launch? (e.g., 3 months)", required: true)
          priorities << "Timeline: #{timeline}"

          # Ask about constraints
          if @prompt.yes?("Do you have any resource or technical constraints?")
            constraints = @prompt.ask("What constraints should we consider?")
            priorities << "Constraints: #{constraints}"
          end

          Aidp.log_debug("mvp_scope_generator", "priorities_collected", count: priorities.size)
          priorities
        end

        # Use AI Decision Engine to analyze features and determine MVP scope
        # This is ZFC - semantic analysis goes to AI, not code
        def analyze_features_with_ai(prd, priorities)
          Aidp.log_debug("mvp_scope_generator", "analyze_features_with_ai")

          # Build prompt for AI analysis
          prompt = build_mvp_analysis_prompt(prd, priorities)

          # Define schema for structured output
          schema = {
            type: "object",
            properties: {
              must_have: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    rationale: {type: "string"},
                    acceptance_criteria: {type: "array", items: {type: "string"}}
                  },
                  required: ["name", "description", "rationale"]
                }
              },
              nice_to_have: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    deferral_reason: {type: "string"}
                  },
                  required: ["name", "description", "deferral_reason"]
                }
              },
              out_of_scope: {
                type: "array",
                items: {type: "string"}
              },
              success_criteria: {
                type: "array",
                items: {type: "string"}
              },
              assumptions: {
                type: "array",
                items: {type: "string"}
              },
              risks: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    impact: {type: "string"},
                    mitigation: {type: "string"}
                  }
                }
              }
            },
            required: ["must_have", "nice_to_have", "success_criteria"]
          }

          # Call AI Decision Engine
          decision = @ai_decision_engine.decide(
            context: "mvp_scope_analysis",
            prompt: prompt,
            data: {
              prd: prd,
              priorities: priorities
            },
            schema: schema
          )

          Aidp.log_debug("mvp_scope_generator", "ai_analysis_complete",
            must_have: decision[:must_have].size,
            nice_to_have: decision[:nice_to_have].size)

          decision
        end

        def build_mvp_analysis_prompt(prd, priorities)
          <<~PROMPT
            Analyze the following Product Requirements Document (PRD) and user priorities to determine the Minimum Viable Product (MVP) scope.

            USER PRIORITIES:
            #{priorities.map.with_index { |p, i| "#{i + 1}. #{p}" }.join("\n")}

            PRD SUMMARY:
            #{prd[:content] || prd.inspect}

            TASK:
            1. Identify MUST-HAVE features that are absolutely essential for the MVP
               - These should address the primary goal and solve the main problem
               - Consider the target users and timeline
               - Focus on core functionality that delivers value

            2. Identify NICE-TO-HAVE features that can be deferred to future iterations
               - These are valuable but not critical for initial release
               - Explain why each can be deferred

            3. Identify items that are OUT OF SCOPE for the MVP
               - Features that don't align with MVP goals
               - Advanced features that can wait

            4. Define SUCCESS CRITERIA for the MVP
               - Measurable outcomes
               - User satisfaction metrics
               - Technical performance targets

            5. List ASSUMPTIONS
               - What are we assuming about users, technology, or resources?

            6. Identify RISKS
               - What could prevent MVP success?
               - What's the impact and mitigation strategy?

            For each must-have feature, provide:
            - Clear name
            - Description
            - Rationale (why it's essential for MVP)
            - Acceptance criteria (how we know it's done)

            For each nice-to-have feature, provide:
            - Clear name
            - Description
            - Deferral reason (why it can wait)

            Be pragmatic and focus on delivering value quickly while managing scope.
          PROMPT
        end
      end
    end
  end
end
