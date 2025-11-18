# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates marketing report with key messages and differentiators
      # Uses AI to craft compelling narratives from technical features
      # Follows Zero Framework Cognition (ZFC) pattern
      class MarketingReportGenerator
        def initialize(ai_decision_engine:, config: nil)
          @ai_decision_engine = ai_decision_engine
          @config = config || Aidp::Config.agile_config
        end

        # Generate marketing report from MVP scope and feedback
        # @param mvp_scope [Hash] MVP scope definition
        # @param feedback_analysis [Hash] User feedback analysis (optional)
        # @return [Hash] Marketing report structure
        def generate(mvp_scope:, feedback_analysis: nil)
          Aidp.log_debug("marketing_report_generator", "generate",
            feature_count: mvp_scope[:mvp_features]&.size || 0,
            has_feedback: !feedback_analysis.nil?)

          # Use AI to generate marketing materials
          marketing_report = generate_marketing_with_ai(mvp_scope, feedback_analysis)

          {
            overview: marketing_report[:overview],
            value_proposition: marketing_report[:value_proposition],
            key_messages: marketing_report[:key_messages],
            differentiators: marketing_report[:differentiators],
            target_audience: marketing_report[:target_audience],
            positioning: marketing_report[:positioning],
            success_metrics: marketing_report[:success_metrics],
            launch_checklist: marketing_report[:launch_checklist],
            messaging_framework: marketing_report[:messaging_framework],
            metadata: {
              generated_at: Time.now.iso8601,
              key_message_count: marketing_report[:key_messages]&.size || 0,
              differentiator_count: marketing_report[:differentiators]&.size || 0
            }
          }
        end

        # Format marketing report as markdown
        # @param report [Hash] Marketing report structure
        # @return [String] Markdown formatted marketing report
        def format_as_markdown(report)
          Aidp.log_debug("marketing_report_generator", "format_as_markdown")

          output = ["# Marketing Report", ""]
          output << "**Generated:** #{report[:metadata][:generated_at]}"
          output << "**Key Messages:** #{report[:metadata][:key_message_count]}"
          output << "**Differentiators:** #{report[:metadata][:differentiator_count]}"
          output << ""

          output << "## Overview"
          output << ""
          output << report[:overview]
          output << ""

          output << "## Value Proposition"
          output << ""
          output << "### Headline"
          output << ""
          output << report[:value_proposition][:headline]
          output << ""
          output << "### Subheadline"
          output << ""
          output << report[:value_proposition][:subheadline]
          output << ""
          output << "### Core Benefits"
          output << ""
          report[:value_proposition][:core_benefits].each do |benefit|
            output << "- #{benefit}"
          end
          output << ""

          output << "## Key Messages"
          output << ""
          report[:key_messages].each_with_index do |message, idx|
            output << "### #{idx + 1}. #{message[:title]}"
            output << ""
            output << message[:description]
            output << ""
            output << "**Supporting Points:**"
            message[:supporting_points].each do |point|
              output << "- #{point}"
            end
            output << ""
          end

          output << "## Differentiators"
          output << ""
          output << "What sets us apart from competitors:"
          output << ""
          report[:differentiators].each_with_index do |diff, idx|
            output << "### #{idx + 1}. #{diff[:title]}"
            output << ""
            output << diff[:description]
            output << ""
            output << "**Competitive Advantage:** #{diff[:advantage]}"
            output << ""
          end

          output << "## Target Audience"
          output << ""
          report[:target_audience].each do |segment|
            output << "### #{segment[:name]}"
            output << ""
            output << "**Description:** #{segment[:description]}"
            output << ""
            output << "**Pain Points:**"
            segment[:pain_points].each do |pain|
              output << "- #{pain}"
            end
            output << ""
            output << "**Our Solution:**"
            segment[:our_solution].each do |solution|
              output << "- #{solution}"
            end
            output << ""
          end

          output << "## Positioning"
          output << ""
          output << "**Category:** #{report[:positioning][:category]}"
          output << ""
          output << "**Statement:** #{report[:positioning][:statement]}"
          output << ""
          output << "**Tagline:** #{report[:positioning][:tagline]}"
          output << ""

          output << "## Success Metrics"
          output << ""
          report[:success_metrics].each do |metric|
            output << "- **#{metric[:name]}:** #{metric[:target]}"
            output << "  - Measurement: #{metric[:measurement]}"
            output << ""
          end

          output << "## Messaging Framework"
          output << ""
          output << "| Audience | Message | Channel | Call to Action |"
          output << "|----------|---------|---------|----------------|"
          report[:messaging_framework].each do |msg|
            output << "| #{msg[:audience]} | #{msg[:message]} | #{msg[:channel]} | #{msg[:cta]} |"
          end
          output << ""

          output << "## Launch Checklist"
          output << ""
          report[:launch_checklist].each_with_index do |item, idx|
            output << "- [ ] **#{item[:task]}**"
            output << "  - Owner: #{item[:owner]}"
            output << "  - Timeline: #{item[:timeline]}"
            output << ""
          end

          output.join("\n")
        end

        private

        def generate_marketing_with_ai(mvp_scope, feedback_analysis)
          Aidp.log_debug("marketing_report_generator", "generate_marketing_with_ai")

          prompt = build_marketing_prompt(mvp_scope, feedback_analysis)

          schema = {
            type: "object",
            properties: {
              overview: {type: "string"},
              value_proposition: {
                type: "object",
                properties: {
                  headline: {type: "string"},
                  subheadline: {type: "string"},
                  core_benefits: {type: "array", items: {type: "string"}}
                }
              },
              key_messages: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    supporting_points: {type: "array", items: {type: "string"}}
                  }
                }
              },
              differentiators: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    advantage: {type: "string"}
                  }
                }
              },
              target_audience: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    pain_points: {type: "array", items: {type: "string"}},
                    our_solution: {type: "array", items: {type: "string"}}
                  }
                }
              },
              positioning: {
                type: "object",
                properties: {
                  category: {type: "string"},
                  statement: {type: "string"},
                  tagline: {type: "string"}
                }
              },
              success_metrics: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    target: {type: "string"},
                    measurement: {type: "string"}
                  }
                }
              },
              messaging_framework: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    audience: {type: "string"},
                    message: {type: "string"},
                    channel: {type: "string"},
                    cta: {type: "string"}
                  }
                }
              },
              launch_checklist: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    task: {type: "string"},
                    owner: {type: "string"},
                    timeline: {type: "string"}
                  }
                }
              }
            },
            required: ["overview", "value_proposition", "key_messages", "differentiators"]
          }

          decision = @ai_decision_engine.decide(
            context: "marketing_report_generation",
            prompt: prompt,
            data: {
              mvp_scope: mvp_scope,
              feedback_analysis: feedback_analysis
            },
            schema: schema
          )

          Aidp.log_debug("marketing_report_generator", "ai_report_generated",
            messages: decision[:key_messages]&.size || 0)

          decision
        end

        def build_marketing_prompt(mvp_scope, feedback_analysis)
          feedback_insights = if feedback_analysis
            <<~INSIGHTS
              USER FEEDBACK INSIGHTS:
              #{feedback_analysis[:findings]&.map { |f| "- #{f}" }&.join("\n") || "No insights"}
            INSIGHTS
          else
            ""
          end

          <<~PROMPT
            Generate a comprehensive marketing report for the following MVP.

            MVP FEATURES:
            #{mvp_scope[:mvp_features]&.map { |f| "- #{f[:name]}: #{f[:description]}" }&.join("\n") || "No features"}

            SUCCESS CRITERIA:
            #{mvp_scope[:success_criteria]&.map { |c| "- #{c}" }&.join("\n") || "No criteria"}

            #{feedback_insights}

            TASK:
            Create marketing materials that translate technical features into compelling value propositions:

            1. OVERVIEW
               - Brief summary of the marketing strategy

            2. VALUE PROPOSITION
               - Compelling headline (10-15 words)
               - Supporting subheadline (15-25 words)
               - 3-5 core benefits

            3. KEY MESSAGES (3-5 messages)
               - For each: title, description, 3-5 supporting points
               - Focus on customer value, not technical features

            4. DIFFERENTIATORS (2-4 items)
               - What makes this unique?
               - Competitive advantages
               - Why choose us over alternatives?

            5. TARGET AUDIENCE (2-3 segments)
               - Name and description
               - Pain points they experience
               - How our solution addresses their needs

            6. POSITIONING
               - Category (what market/space are we in?)
               - Positioning statement (who, what, value, differentiation)
               - Tagline (memorable 3-7 words)

            7. SUCCESS METRICS
               - 4-6 measurable metrics for launch success
               - Targets and how to measure

            8. MESSAGING FRAMEWORK
               - For each audience: specific message, channel, call to action

            9. LAUNCH CHECKLIST
               - 8-12 pre-launch tasks
               - Owner and timeline for each

            Make it compelling, customer-focused, and actionable. Avoid jargon.
          PROMPT
        end
      end
    end
  end
end
