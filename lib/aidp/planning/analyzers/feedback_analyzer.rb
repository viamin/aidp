# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Analyzers
      # Analyzes user feedback using AI to extract insights and recommendations
      # Uses Zero Framework Cognition (ZFC) - NO regex, heuristics, or keyword matching
      # All semantic analysis delegated to AI Decision Engine
      class FeedbackAnalyzer
        def initialize(ai_decision_engine:, config: nil)
          @ai_decision_engine = ai_decision_engine
          @config = config || Aidp::Config.agile_config
        end

        # Analyze feedback data and generate insights
        # @param feedback_data [Hash] Parsed feedback data from FeedbackDataParser
        # @return [Hash] Analysis results with findings and recommendations
        def analyze(feedback_data)
          Aidp.log_debug("feedback_analyzer", "analyze",
            response_count: feedback_data[:response_count],
            format: feedback_data[:format])

          # Use AI to perform semantic analysis
          analysis = analyze_with_ai(feedback_data)

          {
            summary: analysis[:summary],
            findings: analysis[:findings],
            trends: analysis[:trends],
            insights: analysis[:insights],
            sentiment_breakdown: analysis[:sentiment_breakdown],
            feature_feedback: analysis[:feature_feedback],
            recommendations: analysis[:recommendations],
            priority_issues: analysis[:priority_issues],
            positive_highlights: analysis[:positive_highlights],
            metadata: {
              generated_at: Time.now.iso8601,
              responses_analyzed: feedback_data[:response_count],
              source_file: feedback_data[:source_file],
              source_format: feedback_data[:format]
            }
          }
        end

        # Format feedback analysis as markdown
        # @param analysis [Hash] Feedback analysis structure
        # @return [String] Markdown formatted analysis
        def format_as_markdown(analysis)
          Aidp.log_debug("feedback_analyzer", "format_as_markdown")

          output = ["# User Feedback Analysis", ""]
          output << "**Generated:** #{analysis[:metadata][:generated_at]}"
          output << "**Responses Analyzed:** #{analysis[:metadata][:responses_analyzed]}"
          output << "**Source:** #{analysis[:metadata][:source_file]}"
          output << ""

          output << "## Executive Summary"
          output << ""
          output << analysis[:summary]
          output << ""

          output << "## Sentiment Breakdown"
          output << ""
          output << "| Sentiment | Count | Percentage |"
          output << "|-----------|-------|------------|"
          analysis[:sentiment_breakdown].each do |sentiment|
            output << "| #{sentiment[:type]} | #{sentiment[:count]} | #{sentiment[:percentage]}% |"
          end
          output << ""

          output << "## Key Findings"
          output << ""
          analysis[:findings].each_with_index do |finding, idx|
            output << "### #{idx + 1}. #{finding[:title]}"
            output << ""
            output << finding[:description]
            output << ""
            output << "**Evidence:**"
            finding[:evidence].each do |evidence|
              output << "- #{evidence}"
            end
            output << ""
            output << "**Impact:** #{finding[:impact]}"
            output << ""
          end

          output << "## Trends and Patterns"
          output << ""
          analysis[:trends].each_with_index do |trend, idx|
            output << "### #{idx + 1}. #{trend[:title]}"
            output << ""
            output << trend[:description]
            output << ""
            output << "**Frequency:** #{trend[:frequency]}"
            output << ""
            output << "**Implication:** #{trend[:implication]}"
            output << ""
          end

          output << "## Insights"
          output << ""
          analysis[:insights].each do |insight|
            output << "- **#{insight[:category]}:** #{insight[:description]}"
            output << ""
          end

          output << "## Feature-Specific Feedback"
          output << ""
          analysis[:feature_feedback].each do |feedback|
            output << "### #{feedback[:feature_name]}"
            output << ""
            output << "**Overall Sentiment:** #{feedback[:sentiment]}"
            output << ""
            output << "**Positive Feedback:**"
            feedback[:positive].each do |pos|
              output << "- #{pos}"
            end
            output << ""
            output << "**Negative Feedback:**"
            feedback[:negative].each do |neg|
              output << "- #{neg}"
            end
            output << ""
            output << "**Suggested Improvements:**"
            feedback[:improvements].each do |imp|
              output << "- #{imp}"
            end
            output << ""
          end

          output << "## Priority Issues"
          output << ""
          output << "Issues requiring immediate attention:"
          output << ""
          analysis[:priority_issues].each_with_index do |issue, idx|
            output << "#{idx + 1}. **#{issue[:title]}** (Priority: #{issue[:priority]})"
            output << "   - Impact: #{issue[:impact]}"
            output << "   - Affected Users: #{issue[:affected_users]}"
            output << "   - Recommended Action: #{issue[:action]}"
            output << ""
          end

          output << "## Positive Highlights"
          output << ""
          output << "What users loved:"
          output << ""
          analysis[:positive_highlights].each do |highlight|
            output << "- #{highlight}"
          end
          output << ""

          output << "## Recommendations"
          output << ""
          analysis[:recommendations].each_with_index do |rec, idx|
            output << "### #{idx + 1}. #{rec[:title]}"
            output << ""
            output << rec[:description]
            output << ""
            output << "**Rationale:** #{rec[:rationale]}"
            output << ""
            output << "**Effort:** #{rec[:effort]}"
            output << ""
            output << "**Expected Impact:** #{rec[:impact]}"
            output << ""
          end

          output.join("\n")
        end

        private

        def analyze_with_ai(feedback_data)
          Aidp.log_debug("feedback_analyzer", "analyze_with_ai")

          prompt = build_analysis_prompt(feedback_data)

          schema = {
            type: "object",
            properties: {
              summary: {type: "string"},
              findings: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    evidence: {type: "array", items: {type: "string"}},
                    impact: {type: "string"}
                  }
                }
              },
              trends: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    frequency: {type: "string"},
                    implication: {type: "string"}
                  }
                }
              },
              insights: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    category: {type: "string"},
                    description: {type: "string"}
                  }
                }
              },
              sentiment_breakdown: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    type: {type: "string"},
                    count: {type: "integer"},
                    percentage: {type: "number"}
                  }
                }
              },
              feature_feedback: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    feature_name: {type: "string"},
                    sentiment: {type: "string"},
                    positive: {type: "array", items: {type: "string"}},
                    negative: {type: "array", items: {type: "string"}},
                    improvements: {type: "array", items: {type: "string"}}
                  }
                }
              },
              recommendations: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    rationale: {type: "string"},
                    effort: {type: "string"},
                    impact: {type: "string"}
                  }
                }
              },
              priority_issues: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    priority: {type: "string"},
                    impact: {type: "string"},
                    affected_users: {type: "string"},
                    action: {type: "string"}
                  }
                }
              },
              positive_highlights: {
                type: "array",
                items: {type: "string"}
              }
            },
            required: ["summary", "findings", "recommendations"]
          }

          decision = @ai_decision_engine.decide(
            context: "feedback_analysis",
            prompt: prompt,
            data: feedback_data,
            schema: schema
          )

          Aidp.log_debug("feedback_analyzer", "ai_analysis_complete",
            findings: decision[:findings]&.size || 0,
            recommendations: decision[:recommendations]&.size || 0)

          decision
        end

        def build_analysis_prompt(feedback_data)
          # Format response data for AI analysis
          responses_text = feedback_data[:responses]&.map&.with_index { |r, i|
            <<~RESPONSE
              Response #{i + 1}:
              - ID: #{r[:respondent_id]}
              - Timestamp: #{r[:timestamp]}
              - Rating: #{r[:rating]}
              - Feature: #{r[:feature]}
              - Feedback: #{r[:feedback_text]}
              - Sentiment: #{r[:sentiment]}
              - Tags: #{r[:tags]&.join(", ")}
            RESPONSE
          }&.join("\n") || "No responses"

          <<~PROMPT
            Analyze the following user feedback data and extract insights, trends, and recommendations.

            FEEDBACK DATA:
            Total Responses: #{feedback_data[:response_count]}
            Source: #{feedback_data[:source_file]}
            Format: #{feedback_data[:format]}

            RESPONSES:
            #{responses_text}

            TASK:
            Perform comprehensive feedback analysis:

            1. SUMMARY
               - High-level overview of feedback (2-3 paragraphs)
               - Overall sentiment and key themes

            2. KEY FINDINGS (3-5 findings)
               - Important discoveries from the data
               - Evidence supporting each finding
               - Impact assessment (high/medium/low)

            3. TRENDS AND PATTERNS
               - Recurring themes
               - Frequency of occurrence
               - Implications for product development

            4. INSIGHTS
               - Categorized insights (usability, features, performance, etc.)
               - Actionable observations

            5. SENTIMENT BREAKDOWN
               - Distribution of positive, negative, neutral sentiment
               - Counts and percentages

            6. FEATURE-SPECIFIC FEEDBACK
               - For each mentioned feature: sentiment, positive/negative feedback, improvements

            7. PRIORITY ISSUES
               - Critical issues requiring immediate attention
               - Priority level (critical/high/medium)
               - Affected user count
               - Recommended action

            8. POSITIVE HIGHLIGHTS
               - What users loved
               - Strengths to maintain or amplify

            9. RECOMMENDATIONS (4-6 recommendations)
               - Specific, actionable recommendations
               - Rationale based on feedback
               - Effort estimate (low/medium/high)
               - Expected impact

            Use semantic analysis to understand context and meaning. Look beyond keywords to understand user intent and emotion.
          PROMPT
        end
      end
    end
  end
end
