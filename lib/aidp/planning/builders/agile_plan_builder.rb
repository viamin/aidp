# frozen_string_literal: true

require_relative "../../logger"
require_relative "../parsers/document_parser"
require_relative "../parsers/feedback_data_parser"
require_relative "../generators/mvp_scope_generator"
require_relative "../generators/user_test_plan_generator"
require_relative "../generators/marketing_report_generator"
require_relative "../generators/iteration_plan_generator"
require_relative "../generators/legacy_research_planner"
require_relative "../analyzers/feedback_analyzer"
require_relative "../mappers/persona_mapper"

module Aidp
  module Planning
    module Builders
      # Orchestrates agile planning workflows
      # Coordinates MVP scoping, user testing, feedback analysis, and iteration planning
      class AgilePlanBuilder
        def initialize(
          ai_decision_engine:,
          config: nil,
          prompt: nil,
          document_parser: nil,
          mvp_scope_generator: nil,
          user_test_plan_generator: nil,
          marketing_report_generator: nil,
          feedback_analyzer: nil,
          iteration_plan_generator: nil,
          legacy_research_planner: nil,
          persona_mapper: nil
        )
          @ai_decision_engine = ai_decision_engine
          @config = config || Aidp::Config.agile_config
          @prompt = prompt || TTY::Prompt.new
          @document_parser = document_parser || Parsers::DocumentParser.new(ai_decision_engine: ai_decision_engine)
          @mvp_scope_generator = mvp_scope_generator || Generators::MVPScopeGenerator.new(
            ai_decision_engine: ai_decision_engine,
            prompt: @prompt,
            config: @config
          )
          @user_test_plan_generator = user_test_plan_generator || Generators::UserTestPlanGenerator.new(
            ai_decision_engine: ai_decision_engine,
            config: @config
          )
          @marketing_report_generator = marketing_report_generator || Generators::MarketingReportGenerator.new(
            ai_decision_engine: ai_decision_engine,
            config: @config
          )
          @feedback_analyzer = feedback_analyzer || Analyzers::FeedbackAnalyzer.new(
            ai_decision_engine: ai_decision_engine,
            config: @config
          )
          @iteration_plan_generator = iteration_plan_generator || Generators::IterationPlanGenerator.new(
            ai_decision_engine: ai_decision_engine,
            config: @config
          )
          @legacy_research_planner = legacy_research_planner || Generators::LegacyResearchPlanner.new(
            ai_decision_engine: ai_decision_engine,
            prompt: @prompt,
            config: @config
          )
          @persona_mapper = persona_mapper || Mappers::PersonaMapper.new(
            ai_decision_engine: ai_decision_engine,
            config: @config,
            mode: :agile
          )
        end

        # Build complete MVP plan from PRD
        # @param prd_path [String] Path to PRD document
        # @param user_priorities [Array<String>] Optional user priorities
        # @return [Hash] Complete MVP plan with all artifacts
        def build_mvp_plan(prd_path:, user_priorities: nil)
          Aidp.log_debug("agile_plan_builder", "build_mvp_plan", prd_path: prd_path)

          # Parse PRD
          prd = parse_prd(prd_path)

          # Generate MVP scope
          @prompt.say("Generating MVP scope...")
          mvp_scope = @mvp_scope_generator.generate(prd: prd, user_priorities: user_priorities)
          Aidp.log_debug("agile_plan_builder", "mvp_scope_generated",
            must_have: mvp_scope[:mvp_features].size,
            deferred: mvp_scope[:deferred_features].size)

          # Generate user test plan
          @prompt.say("Creating user testing plan...")
          test_plan = @user_test_plan_generator.generate(mvp_scope: mvp_scope)
          Aidp.log_debug("agile_plan_builder", "test_plan_generated",
            stages: test_plan[:testing_stages].size)

          # Generate marketing report
          @prompt.say("Generating marketing materials...")
          marketing_report = @marketing_report_generator.generate(mvp_scope: mvp_scope)
          Aidp.log_debug("agile_plan_builder", "marketing_report_generated",
            messages: marketing_report[:key_messages].size)

          @prompt.ok("MVP plan complete!")

          {
            mvp_scope: mvp_scope,
            test_plan: test_plan,
            marketing_report: marketing_report,
            metadata: {
              generated_at: Time.now.iso8601,
              workflow: "agile_mvp"
            }
          }
        end

        # Analyze feedback data
        # @param feedback_path [String] Path to feedback data file (CSV/JSON/markdown)
        # @return [Hash] Feedback analysis results
        def analyze_feedback(feedback_path:)
          Aidp.log_debug("agile_plan_builder", "analyze_feedback", feedback_path: feedback_path)

          # Parse feedback data
          @prompt.say("Parsing feedback data...")
          parser = Parsers::FeedbackDataParser.new(file_path: feedback_path)
          feedback_data = parser.parse

          @prompt.say("Analyzing #{feedback_data[:response_count]} responses...")

          # Analyze with AI
          analysis = @feedback_analyzer.analyze(feedback_data)
          Aidp.log_debug("agile_plan_builder", "feedback_analyzed",
            findings: analysis[:findings].size,
            recommendations: analysis[:recommendations].size)

          @prompt.ok("Feedback analysis complete!")

          {
            analysis: analysis,
            metadata: {
              generated_at: Time.now.iso8601,
              workflow: "agile_feedback_analysis"
            }
          }
        end

        # Plan next iteration based on feedback
        # @param feedback_analysis_path [String] Path to feedback analysis document
        # @param current_mvp_path [String] Optional path to current MVP scope
        # @return [Hash] Iteration plan
        def plan_next_iteration(feedback_analysis_path:, current_mvp_path: nil)
          Aidp.log_debug("agile_plan_builder", "plan_next_iteration",
            feedback_path: feedback_analysis_path,
            mvp_path: current_mvp_path)

          # Parse feedback analysis
          @prompt.say("Loading feedback analysis...")
          feedback_analysis = parse_feedback_analysis(feedback_analysis_path)

          # Parse current MVP if provided
          current_mvp = nil
          if current_mvp_path
            @prompt.say("Loading current MVP scope...")
            current_mvp = parse_mvp_scope(current_mvp_path)
          end

          # Generate iteration plan
          @prompt.say("Planning next iteration...")
          iteration_plan = @iteration_plan_generator.generate(
            feedback_analysis: feedback_analysis,
            current_mvp: current_mvp
          )
          Aidp.log_debug("agile_plan_builder", "iteration_plan_generated",
            improvements: iteration_plan[:improvements].size,
            tasks: iteration_plan[:tasks].size)

          @prompt.ok("Iteration plan complete!")

          {
            iteration_plan: iteration_plan,
            metadata: {
              generated_at: Time.now.iso8601,
              workflow: "agile_iteration"
            }
          }
        end

        # Plan user research for existing/legacy codebase
        # @param codebase_path [String] Path to codebase directory
        # @param language [String] Optional primary language
        # @param known_users [String] Optional known user segments
        # @return [Hash] Research plan
        def plan_legacy_research(codebase_path:, language: nil, known_users: nil)
          Aidp.log_debug("agile_plan_builder", "plan_legacy_research",
            codebase_path: codebase_path)

          @prompt.say("Analyzing codebase...")
          research_plan = @legacy_research_planner.generate(
            codebase_path: codebase_path,
            language: language,
            known_users: known_users
          )
          Aidp.log_debug("agile_plan_builder", "research_plan_generated",
            features: research_plan[:current_features].size,
            questions: research_plan[:research_questions].size)

          # Generate user test plan based on research priorities
          @prompt.say("Creating user testing plan...")
          # Create a minimal MVP scope structure for test plan generation
          mvp_scope_for_testing = {
            mvp_features: research_plan[:current_features],
            metadata: {
              user_priorities: ["Understand existing user experience", "Identify pain points", "Discover improvement opportunities"]
            }
          }
          test_plan = @user_test_plan_generator.generate(mvp_scope: mvp_scope_for_testing)

          @prompt.ok("Legacy research plan complete!")

          {
            research_plan: research_plan,
            test_plan: test_plan,
            metadata: {
              generated_at: Time.now.iso8601,
              workflow: "agile_legacy_research"
            }
          }
        end

        # Write all artifacts to files
        # @param plan_data [Hash] Plan data from any workflow
        # @param output_dir [String] Directory to write files
        def write_artifacts(plan_data, output_dir: ".aidp/docs")
          Aidp.log_debug("agile_plan_builder", "write_artifacts", output_dir: output_dir)

          FileUtils.mkdir_p(output_dir)

          artifacts_written = []

          # Write MVP scope if present
          if plan_data[:mvp_scope]
            path = File.join(output_dir, "MVP_SCOPE.md")
            content = @mvp_scope_generator.format_as_markdown(plan_data[:mvp_scope])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "MVP_SCOPE.md")
          end

          # Write test plan if present
          if plan_data[:test_plan]
            path = File.join(output_dir, "USER_TEST_PLAN.md")
            content = @user_test_plan_generator.format_as_markdown(plan_data[:test_plan])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "USER_TEST_PLAN.md")
          end

          # Write marketing report if present
          if plan_data[:marketing_report]
            path = File.join(output_dir, "MARKETING_REPORT.md")
            content = @marketing_report_generator.format_as_markdown(plan_data[:marketing_report])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "MARKETING_REPORT.md")
          end

          # Write feedback analysis if present
          if plan_data[:analysis]
            path = File.join(output_dir, "USER_FEEDBACK_ANALYSIS.md")
            content = @feedback_analyzer.format_as_markdown(plan_data[:analysis])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "USER_FEEDBACK_ANALYSIS.md")
          end

          # Write iteration plan if present
          if plan_data[:iteration_plan]
            path = File.join(output_dir, "NEXT_ITERATION_PLAN.md")
            content = @iteration_plan_generator.format_as_markdown(plan_data[:iteration_plan])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "NEXT_ITERATION_PLAN.md")
          end

          # Write research plan if present
          if plan_data[:research_plan]
            path = File.join(output_dir, "LEGACY_USER_RESEARCH_PLAN.md")
            content = @legacy_research_planner.format_as_markdown(plan_data[:research_plan])
            File.write(path, content)
            artifacts_written << path
            Aidp.log_debug("agile_plan_builder", "wrote_artifact", file: "LEGACY_USER_RESEARCH_PLAN.md")
          end

          @prompt.ok("Wrote #{artifacts_written.size} artifacts to #{output_dir}")
          artifacts_written
        end

        private

        def parse_prd(prd_path)
          Aidp.log_debug("agile_plan_builder", "parse_prd", path: prd_path)

          unless File.exist?(prd_path)
            raise ArgumentError, "PRD file not found: #{prd_path}"
          end

          content = File.read(prd_path)

          # Simple PRD structure extraction
          {
            content: content,
            path: prd_path,
            type: :prd,
            metadata: {
              parsed_at: Time.now.iso8601
            }
          }
        end

        def parse_feedback_analysis(analysis_path)
          Aidp.log_debug("agile_plan_builder", "parse_feedback_analysis", path: analysis_path)

          unless File.exist?(analysis_path)
            raise ArgumentError, "Feedback analysis file not found: #{analysis_path}"
          end

          content = File.read(analysis_path)

          # Extract key sections from markdown
          {
            content: content,
            summary: extract_section(content, "Executive Summary"),
            findings: extract_list_items(content, "Key Findings"),
            recommendations: extract_list_items(content, "Recommendations"),
            priority_issues: extract_list_items(content, "Priority Issues"),
            metadata: {
              parsed_at: Time.now.iso8601
            }
          }
        end

        def parse_mvp_scope(mvp_path)
          Aidp.log_debug("agile_plan_builder", "parse_mvp_scope", path: mvp_path)

          unless File.exist?(mvp_path)
            raise ArgumentError, "MVP scope file not found: #{mvp_path}"
          end

          content = File.read(mvp_path)

          {
            content: content,
            mvp_features: extract_features(content, "MVP Features"),
            deferred_features: extract_features(content, "Deferred Features"),
            metadata: {
              parsed_at: Time.now.iso8601
            }
          }
        end

        def extract_section(content, heading)
          # Simple section extraction
          if content =~ /## #{heading}\s*\n\n(.+?)(\n## |$)/m
            $1.strip
          else
            ""
          end
        end

        def extract_list_items(content, heading)
          section = extract_section(content, heading)
          # Extract bullet points or numbered items
          section.scan(/^[-*]\s+(.+)$/).flatten
        end

        def extract_features(content, heading)
          # Simple feature extraction from markdown headings
          section_start = content.index(/## #{heading}/)
          return [] unless section_start

          section = content[section_start..]
          next_section = section.index(/\n## /, 1)
          section = section[0...next_section] if next_section

          # Extract feature names from h3 headings
          features = section.scan(/### \d+\.\s+(.+)/).flatten
          features.map { |name| {name: name, description: "Feature from #{heading}"} }
        end
      end
    end
  end
end
