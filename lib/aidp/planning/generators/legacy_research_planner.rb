# frozen_string_literal: true

require_relative "../../logger"
require "find"

module Aidp
  module Planning
    module Generators
      # Generates user research plan for existing/legacy codebases
      # Analyzes code structure to identify features and suggest research priorities
      # Uses Zero Framework Cognition (ZFC) for research question generation
      class LegacyResearchPlanner
        def initialize(ai_decision_engine:, prompt: nil, config: nil)
          @ai_decision_engine = ai_decision_engine
          @prompt = prompt || TTY::Prompt.new
          @config = config || Aidp::Config.agile_config
        end

        # Generate legacy research plan from codebase analysis
        # @param codebase_path [String] Path to codebase directory
        # @param language [String] Primary language/framework (optional)
        # @param known_users [String] Known user segments (optional)
        # @return [Hash] Research plan structure
        def generate(codebase_path:, language: nil, known_users: nil)
          Aidp.log_debug("legacy_research_planner", "generate",
            codebase_path: codebase_path,
            language: language)

          # Analyze codebase structure
          codebase_analysis = analyze_codebase(codebase_path, language)

          Aidp.log_debug("legacy_research_planner", "codebase_analyzed",
            features: codebase_analysis[:features].size,
            files: codebase_analysis[:file_count])

          # Use AI to generate research plan
          research_plan = generate_research_plan_with_ai(codebase_analysis, known_users)

          {
            overview: research_plan[:overview],
            current_features: research_plan[:current_features],
            research_questions: research_plan[:research_questions],
            research_methods: research_plan[:research_methods],
            testing_priorities: research_plan[:testing_priorities],
            user_segments: research_plan[:user_segments],
            improvement_opportunities: research_plan[:improvement_opportunities],
            timeline: research_plan[:timeline],
            codebase_summary: codebase_analysis[:summary],
            metadata: {
              generated_at: Time.now.iso8601,
              codebase_path: codebase_path,
              language: language,
              feature_count: research_plan[:current_features]&.size || 0,
              file_count: codebase_analysis[:file_count],
              research_question_count: research_plan[:research_questions]&.size || 0
            }
          }
        end

        # Format research plan as markdown
        # @param plan [Hash] Research plan structure
        # @return [String] Markdown formatted research plan
        def format_as_markdown(plan)
          Aidp.log_debug("legacy_research_planner", "format_as_markdown")

          output = ["# Legacy User Research Plan", ""]
          output << "**Generated:** #{plan[:metadata][:generated_at]}"
          output << "**Codebase:** #{plan[:metadata][:codebase_path]}"
          output << "**Features Identified:** #{plan[:metadata][:feature_count]}"
          output << "**Files Analyzed:** #{plan[:metadata][:file_count]}"
          output << ""

          output << "## Overview"
          output << ""
          output << plan[:overview]
          output << ""

          output << "## Codebase Summary"
          output << ""
          output << plan[:codebase_summary]
          output << ""

          output << "## Current Features"
          output << ""
          output << "Features identified in the codebase:"
          output << ""
          plan[:current_features].each_with_index do |feature, idx|
            output << "### #{idx + 1}. #{feature[:name]}"
            output << ""
            output << "**Description:** #{feature[:description]}"
            output << ""
            output << "**Entry Points:** #{feature[:entry_points]&.join(", ") || "Unknown"}"
            output << ""
            output << "**Status:** #{feature[:status]}"
            output << ""
          end

          output << "## Research Questions"
          output << ""
          output << "Key questions to answer about user experience:"
          output << ""
          plan[:research_questions].each_with_index do |question, idx|
            output << "#{idx + 1}. #{question[:question]}"
            output << "   - **Category:** #{question[:category]}"
            output << "   - **Priority:** #{question[:priority]}"
            output << ""
          end

          output << "## Recommended Research Methods"
          output << ""
          plan[:research_methods].each do |method|
            output << "### #{method[:name]}"
            output << ""
            output << method[:description]
            output << ""
            output << "**When to Use:** #{method[:when_to_use]}"
            output << ""
            output << "**Expected Insights:** #{method[:expected_insights]}"
            output << ""
          end

          output << "## Testing Priorities"
          output << ""
          output << "Features/flows to focus on first:"
          output << ""
          plan[:testing_priorities].each_with_index do |priority, idx|
            output << "#{idx + 1}. **#{priority[:feature]}** (Priority: #{priority[:priority]})"
            output << "   - Rationale: #{priority[:rationale]}"
            output << "   - Focus Areas: #{priority[:focus_areas]&.join(", ")}"
            output << ""
          end

          output << "## User Segments"
          output << ""
          plan[:user_segments].each do |segment|
            output << "### #{segment[:name]}"
            output << ""
            output << segment[:description]
            output << ""
            output << "**Research Focus:** #{segment[:research_focus]}"
            output << ""
          end

          output << "## Improvement Opportunities"
          output << ""
          output << "Based on codebase analysis:"
          output << ""
          plan[:improvement_opportunities].each_with_index do |opportunity, idx|
            output << "#{idx + 1}. **#{opportunity[:title]}**"
            output << "   - Description: #{opportunity[:description]}"
            output << "   - Impact: #{opportunity[:impact]}"
            output << "   - Effort: #{opportunity[:effort]}"
            output << ""
          end

          output << "## Research Timeline"
          output << ""
          plan[:timeline].each do |phase|
            output << "- **#{phase[:phase]}:** #{phase[:duration]}"
          end
          output << ""

          output.join("\n")
        end

        private

        # Analyze codebase structure to extract features and patterns
        def analyze_codebase(codebase_path, language)
          Aidp.log_debug("legacy_research_planner", "analyze_codebase", path: codebase_path)

          unless Dir.exist?(codebase_path)
            raise ArgumentError, "Codebase path does not exist: #{codebase_path}"
          end

          # Collect basic codebase information
          files = []
          directories = []
          readme_content = nil

          Find.find(codebase_path) do |path|
            # Skip common ignore patterns
            if File.basename(path).start_with?(".") ||
                path.include?("node_modules") ||
                path.include?("vendor") ||
                path.include?(".git")
              Find.prune
            end

            if File.directory?(path)
              directories << path
            elsif File.file?(path)
              files << path
              # Try to read README for context
              if File.basename(path).match?(/^README/i)
                readme_content = File.read(path) rescue nil
              end
            end
          end

          # Extract feature hints from directory structure and file names
          features = extract_features_from_structure(files, directories, codebase_path)

          {
            features: features,
            file_count: files.size,
            directory_count: directories.size,
            readme_content: readme_content,
            language: language || detect_language(files),
            summary: "Analyzed #{files.size} files in #{directories.size} directories. " \
                     "Identified #{features.size} potential features based on code structure."
          }
        end

        # Extract potential features from codebase structure
        def extract_features_from_structure(files, directories, base_path)
          features = []

          # Look for common patterns in directory names
          directories.each do |dir|
            dir_name = File.basename(dir)
            relative_path = dir.sub("#{base_path}/", "")

            # Skip common infrastructure directories
            next if %w[lib spec test config bin vendor node_modules].include?(dir_name)

            # Directories that might represent features
            if relative_path.match?(/features?|components?|modules?|pages?|views?|controllers?|services?/i)
              features << {
                name: dir_name.gsub(/[-_]/, " ").capitalize,
                type: :directory_based,
                path: relative_path,
                description: "Feature identified from directory: #{relative_path}"
              }
            end
          end

          # Look for controller/route files that indicate features
          files.each do |file|
            file_name = File.basename(file, ".*")
            relative_path = file.sub("#{base_path}/", "")

            if file.match?(/controller|router|routes|handler/i)
              features << {
                name: file_name.gsub(/[-_](controller|router|routes|handler)/, "").gsub(/[-_]/, " ").capitalize,
                type: :route_based,
                path: relative_path,
                description: "Feature identified from routing/controller file: #{File.basename(file)}"
              }
            end
          end

          # Deduplicate by name
          features.uniq { |f| f[:name].downcase }.take(20) # Limit to 20 features
        end

        # Detect primary language from file extensions
        def detect_language(files)
          extensions = files.map { |f| File.extname(f) }.compact
          ext_counts = extensions.each_with_object(Hash.new(0)) { |ext, counts| counts[ext] += 1 }

          language_map = {
            ".rb" => "Ruby",
            ".js" => "JavaScript",
            ".ts" => "TypeScript",
            ".py" => "Python",
            ".go" => "Go",
            ".java" => "Java",
            ".cs" => "C#",
            ".php" => "PHP",
            ".swift" => "Swift",
            ".kt" => "Kotlin"
          }

          most_common_ext = ext_counts.max_by { |_, count| count }&.first
          language_map[most_common_ext] || "Unknown"
        end

        def generate_research_plan_with_ai(codebase_analysis, known_users)
          Aidp.log_debug("legacy_research_planner", "generate_research_plan_with_ai")

          prompt = build_research_plan_prompt(codebase_analysis, known_users)

          schema = {
            type: "object",
            properties: {
              overview: {type: "string"},
              current_features: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    entry_points: {type: "array", items: {type: "string"}},
                    status: {type: "string"}
                  }
                }
              },
              research_questions: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    question: {type: "string"},
                    category: {type: "string"},
                    priority: {type: "string"}
                  }
                }
              },
              research_methods: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    when_to_use: {type: "string"},
                    expected_insights: {type: "string"}
                  }
                }
              },
              testing_priorities: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    feature: {type: "string"},
                    priority: {type: "string"},
                    rationale: {type: "string"},
                    focus_areas: {type: "array", items: {type: "string"}}
                  }
                }
              },
              user_segments: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    name: {type: "string"},
                    description: {type: "string"},
                    research_focus: {type: "string"}
                  }
                }
              },
              improvement_opportunities: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    title: {type: "string"},
                    description: {type: "string"},
                    impact: {type: "string"},
                    effort: {type: "string"}
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
            required: ["overview", "current_features", "research_questions", "testing_priorities"]
          }

          decision = @ai_decision_engine.decide(
            context: "legacy_research_plan_generation",
            prompt: prompt,
            data: {
              codebase_analysis: codebase_analysis,
              known_users: known_users
            },
            schema: schema
          )

          Aidp.log_debug("legacy_research_planner", "ai_plan_generated",
            features: decision[:current_features]&.size || 0,
            questions: decision[:research_questions]&.size || 0)

          decision
        end

        def build_research_plan_prompt(codebase_analysis, known_users)
          features_text = codebase_analysis[:features].map { |f|
            "- #{f[:name]} (#{f[:type]}, #{f[:path]})"
          }.join("\n")

          readme_context = if codebase_analysis[:readme_content]
            <<~README
              README CONTENT (for context):
              #{codebase_analysis[:readme_content][0..2000]}
            README
          else
            ""
          end

          <<~PROMPT
            Generate a comprehensive user research plan for an existing/legacy codebase.

            CODEBASE ANALYSIS:
            Language: #{codebase_analysis[:language]}
            Files: #{codebase_analysis[:file_count]}
            Directories: #{codebase_analysis[:directory_count]}

            POTENTIAL FEATURES IDENTIFIED:
            #{features_text}

            #{readme_context}

            KNOWN USER SEGMENTS:
            #{known_users || "Not specified - suggest based on codebase"}

            TASK:
            Create a user research plan to understand how users experience this existing product:

            1. OVERVIEW
               - Why user research is needed for this product
               - What we hope to learn

            2. CURRENT FEATURES
               - For each feature identified, provide:
                 - Clear name and description
                 - Likely entry points (how users access it)
                 - Status (active, deprecated, experimental)

            3. RESEARCH QUESTIONS (8-12 questions)
               - Questions about user experience with current features
               - Category (usability, value, workflow, pain_points, missing_features)
               - Priority (high/medium/low)

            4. RECOMMENDED RESEARCH METHODS (3-4 methods)
               - Method name (e.g., User Interviews, Surveys, Analytics Analysis)
               - Description of the method
               - When to use it
               - Expected insights

            5. TESTING PRIORITIES
               - Which features/flows to focus on first
               - Priority level (critical/high/medium)
               - Rationale for prioritization
               - Focus areas for each

            6. USER SEGMENTS (2-3 segments)
               - Different types of users to study
               - Description of each segment
               - Research focus for that segment

            7. IMPROVEMENT OPPORTUNITIES
               - Based on code structure, what might need improvement
               - Impact (high/medium/low)
               - Effort estimate (low/medium/high)

            8. TIMELINE
               - Research phases with duration estimates
               - Codebase analysis, recruitment, data collection, analysis, reporting

            Focus on understanding existing user experience and identifying improvement opportunities.
          PROMPT
        end
      end
    end
  end
end
