# frozen_string_literal: true

require "tty-prompt"
require_relative "../message_display"
require_relative "project_analyzer"
require_relative "doc_generator"

module Aidp
  module Init
    # High-level coordinator for `aidp init`. Handles analysis, optional user
    # preferences, and documentation generation.
    class Runner
      include Aidp::MessageDisplay

      def initialize(project_dir = Dir.pwd, prompt: TTY::Prompt.new, analyzer: nil, doc_generator: nil, options: {})
        @project_dir = project_dir
        @prompt = prompt
        @analyzer = analyzer || ProjectAnalyzer.new(project_dir)
        @doc_generator = doc_generator || DocGenerator.new(project_dir)
        @options = options
      end

      def run
        display_message("🔍 Running aidp init project analysis...", type: :info)
        analysis = @analyzer.analyze(explain_detection: @options[:explain_detection])

        if @options[:explain_detection]
          display_detailed_analysis(analysis)
        else
          display_summary(analysis)
        end

        # Dry run: skip preferences and generation
        if @options[:dry_run]
          display_message("\n🔍 Dry run mode - no files will be written.", type: :info)
          return {
            analysis: analysis,
            preferences: {},
            generated_files: []
          }
        end

        preferences = gather_preferences

        # Offer preview before writing
        if @options[:preview] || ask_yes_no_with_context(
          "Preview generated files before saving?",
          context: "Shows a summary of what will be written to docs/",
          default: false
        )
          preview_generated_docs(analysis, preferences)

          unless ask_yes_no("Proceed with writing these files?", default: true)
            display_message("\n❌ Cancelled. No files were written.", type: :info)
            return {
              analysis: analysis,
              preferences: preferences,
              generated_files: []
            }
          end
        end

        @doc_generator.generate(analysis: analysis, preferences: preferences)

        display_message("\n📄 Generated documentation:", type: :info)
        display_message("  - docs/LLM_STYLE_GUIDE.md", type: :success)
        display_message("  - docs/PROJECT_ANALYSIS.md", type: :success)
        display_message("  - docs/CODE_QUALITY_PLAN.md", type: :success)
        display_message("\n✅ aidp init complete.", type: :success)

        {
          analysis: analysis,
          preferences: preferences,
          generated_files: [
            "docs/LLM_STYLE_GUIDE.md",
            "docs/PROJECT_ANALYSIS.md",
            "docs/CODE_QUALITY_PLAN.md"
          ]
        }
      end

      private

      def display_summary(analysis)
        languages = analysis[:languages].keys
        frameworks = analysis[:frameworks]
        tests = analysis[:test_frameworks]
        config_files = analysis[:config_files]
        tooling = analysis[:tooling]

        # Extract high-confidence frameworks (>= 0.7)
        confident_frameworks = frameworks.select { |f| f[:confidence] >= 0.7 }.map { |f| f[:name] }
        uncertain_frameworks = frameworks.select { |f| f[:confidence] < 0.7 }

        # Extract high-confidence test frameworks (>= 0.7)
        confident_tests = tests.select { |t| t[:confidence] >= 0.7 }.map { |t| t[:name] }

        # Extract high-confidence tooling (>= 0.7)
        confident_tooling = tooling.select { |t| t[:confidence] >= 0.7 }.map { |t| format_tool(t[:tool]) }

        display_message("\n📊 Repository Snapshot", type: :highlight)
        display_message("  Languages: #{languages.empty? ? "Unknown" : languages.join(", ")}", type: :info)

        if confident_frameworks.any?
          display_message("  Frameworks: #{confident_frameworks.join(", ")}", type: :info)
        else
          display_message("  Frameworks: None confidently detected", type: :info)
        end

        if uncertain_frameworks.any?
          uncertain_list = uncertain_frameworks.map { |f| "#{f[:name]} (#{(f[:confidence] * 100).round}%)" }.join(", ")
          display_message("  Possible frameworks: #{uncertain_list}", type: :info)
        end

        if confident_tests.any?
          display_message("  Test suites: #{confident_tests.join(", ")}", type: :info)
        else
          display_message("  Test suites: Not found", type: :info)
        end

        if confident_tooling.any?
          display_message("  Quality tools: #{confident_tooling.join(", ")}", type: :info)
        end

        display_message("  Config files: #{config_files.empty? ? "None detected" : config_files.size} found", type: :info)
      end

      def display_detailed_analysis(analysis)
        display_message("\n🔍 Detailed Detection Analysis", type: :highlight)
        display_message("=" * 60, type: :info)

        # Languages
        display_message("\n📝 Languages (by file size):", type: :highlight)
        if analysis[:languages].any?
          total_size = analysis[:languages].values.sum
          analysis[:languages].each do |lang, size|
            percentage = ((size.to_f / total_size) * 100).round(1)
            display_message("  • #{lang}: #{percentage}%", type: :info)
          end
        else
          display_message("  None detected", type: :info)
        end

        # Frameworks
        display_message("\n🎯 Frameworks:", type: :highlight)
        if analysis[:frameworks].any?
          analysis[:frameworks].each do |fw|
            confidence_pct = (fw[:confidence] * 100).round
            display_message("  • #{fw[:name]} (#{confidence_pct}% confidence):", type: :info)
            fw[:evidence].each do |evidence|
              display_message("    - #{evidence}", type: :info)
            end
          end
        else
          display_message("  None detected", type: :info)
        end

        # Test Frameworks
        display_message("\n🧪 Test Frameworks:", type: :highlight)
        if analysis[:test_frameworks].any?
          analysis[:test_frameworks].each do |test|
            confidence_pct = (test[:confidence] * 100).round
            display_message("  • #{test[:name]} (#{confidence_pct}% confidence):", type: :info)
            test[:evidence].each do |evidence|
              display_message("    - #{evidence}", type: :info)
            end
          end
        else
          display_message("  None detected", type: :info)
        end

        # Tooling
        display_message("\n🔧 Quality Tooling:", type: :highlight)
        if analysis[:tooling].any?
          analysis[:tooling].each do |tool_data|
            tool_name = format_tool(tool_data[:tool])
            confidence_pct = (tool_data[:confidence] * 100).round
            display_message("  • #{tool_name} (#{confidence_pct}% confidence):", type: :info)
            tool_data[:evidence].each do |evidence|
              display_message("    - #{evidence}", type: :info)
            end
          end
        else
          display_message("  None detected", type: :info)
        end

        # Key Directories
        display_message("\n📁 Key Directories:", type: :highlight)
        if analysis[:key_directories].any?
          analysis[:key_directories].each do |dir|
            display_message("  • #{dir}", type: :info)
          end
        else
          display_message("  None detected", type: :info)
        end

        # Config Files
        display_message("\n⚙️  Configuration Files:", type: :highlight)
        if analysis[:config_files].any?
          analysis[:config_files].each do |file|
            display_message("  • #{file}", type: :info)
          end
        else
          display_message("  None detected", type: :info)
        end

        # Repository Stats
        display_message("\n📈 Repository Stats:", type: :highlight)
        stats = analysis[:repo_stats]
        display_message("  • Total files: #{stats[:total_files]}", type: :info)
        display_message("  • Total directories: #{stats[:total_directories]}", type: :info)
        display_message("  • Documentation: #{stats[:docs_present] ? "Present" : "Not found"}", type: :info)
        display_message("  • CI/CD config: #{stats[:has_ci_config] ? "Present" : "Not found"}", type: :info)
        display_message("  • Containerization: #{stats[:has_containerization] ? "Present" : "Not found"}", type: :info)

        display_message("\n" + "=" * 60, type: :info)
      end

      def format_tool(tool)
        tool.to_s.split("_").map(&:capitalize).join(" ")
      end

      def gather_preferences
        display_message("\n⚙️  Configuration Options", type: :highlight)
        display_message("The following questions will help customize the generated documentation.", type: :info)
        display_message("Press Enter to accept defaults shown in brackets.\n", type: :info)

        {
          adopt_new_conventions: ask_yes_no_with_context(
            "Make these conventions official for this repository?",
            context: "This saves the detected patterns to LLM_STYLE_GUIDE.md and guides future AI-assisted work.",
            default: true
          ),
          stricter_linters: ask_yes_no_with_context(
            "Enable stricter linting rules in the quality plan?",
            context: "Recommends failing CI on linting violations for better code quality.",
            default: false
          ),
          migrate_styles: ask_yes_no_with_context(
            "Plan gradual migration of legacy code to new style guide?",
            context: "Adds migration tasks to CODE_QUALITY_PLAN.md for incremental improvements.",
            default: false
          )
        }
      end

      def ask_yes_no_with_context(question, context:, default:)
        display_message("\n#{question}", type: :info)
        display_message("  ℹ️  #{context}", type: :info)
        ask_yes_no(question, default: default)
      end

      def ask_yes_no(question, default:)
        @prompt.yes?(question) do |q|
          q.default default ? "yes" : "no"
        end
      rescue NoMethodError
        # Compatibility with simplified prompts in tests (e.g. TestPrompt)
        default
      end

      def preview_generated_docs(analysis, preferences)
        display_message("\n📄 Preview of Generated Documentation", type: :highlight)
        display_message("=" * 60, type: :info)

        # LLM_STYLE_GUIDE summary
        display_message("\n1. docs/LLM_STYLE_GUIDE.md", type: :highlight)
        confident_frameworks = analysis[:frameworks].select { |f| f[:confidence] >= 0.7 }.map { |f| f[:name] }
        display_message("   - Detected frameworks: #{confident_frameworks.any? ? confident_frameworks.join(", ") : "None"}", type: :info)
        display_message("   - Adoption status: #{preferences[:adopt_new_conventions] ? "Official conventions" : "Optional reference"}", type: :info)

        # PROJECT_ANALYSIS summary
        display_message("\n2. docs/PROJECT_ANALYSIS.md", type: :highlight)
        display_message("   - Languages: #{analysis[:languages].keys.join(", ")}", type: :info)
        display_message("   - Total frameworks detected: #{analysis[:frameworks].size}", type: :info)
        display_message("   - Test frameworks: #{analysis[:test_frameworks].map { |t| t[:name] }.join(", ") || "None"}", type: :info)

        # CODE_QUALITY_PLAN summary
        display_message("\n3. docs/CODE_QUALITY_PLAN.md", type: :highlight)
        tooling_count = analysis[:tooling].select { |t| t[:confidence] >= 0.7 }.size
        display_message("   - Quality tools detected: #{tooling_count}", type: :info)
        display_message("   - Stricter linting: #{preferences[:stricter_linters] ? "Yes" : "No"}", type: :info)
        display_message("   - Migration planning: #{preferences[:migrate_styles] ? "Yes" : "No"}", type: :info)

        # Validation warnings
        validate_tooling(analysis)

        display_message("\n" + "=" * 60, type: :info)
      end

      def validate_tooling(analysis)
        display_message("\n🔍 Validation", type: :highlight)

        warnings = []

        # Check if detected tools actually exist
        analysis[:tooling].select { |t| t[:confidence] >= 0.7 }.each do |tool_data|
          tool_name = tool_data[:tool].to_s

          # Try to find the tool command
          tool_command = case tool_name
          when "rubocop", "standardrb", "eslint", "prettier", "stylelint", "flake8", "black", "pytest", "jest"
            tool_name
          when "cargo_fmt"
            "cargo"
          when "gofmt"
            "gofmt"
          else
            nil
          end

          next unless tool_command

          # Check if command exists
          unless system("which #{tool_command} > /dev/null 2>&1")
            warnings << "   ⚠️  #{format_tool(tool_data[:tool])} detected but command '#{tool_command}' not found in PATH"
          end
        end

        # Check if test commands can be inferred
        if analysis[:test_frameworks].empty?
          warnings << "   ⚠️  No test framework detected - consider adding one for better quality assurance"
        end

        # Check for CI configuration
        unless analysis[:repo_stats][:has_ci_config]
          warnings << "   ℹ️  No CI configuration detected - consider adding GitHub Actions or similar"
        end

        if warnings.any?
          warnings.each { |warning| display_message(warning, type: :info) }
        else
          display_message("   ✅ All detected tools validated successfully", type: :success)
        end
      end
    end
  end
end
