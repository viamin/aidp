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

      def initialize(project_dir = Dir.pwd, prompt: TTY::Prompt.new, analyzer: nil, doc_generator: nil)
        @project_dir = project_dir
        @prompt = prompt
        @analyzer = analyzer || ProjectAnalyzer.new(project_dir)
        @doc_generator = doc_generator || DocGenerator.new(project_dir)
      end

      def run
        display_message("🔍 Running aidp init project analysis...", type: :info)
        analysis = @analyzer.analyze
        display_summary(analysis)

        preferences = gather_preferences

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

        display_message("\n📊 Repository Snapshot", type: :highlight)
        display_message("  Languages: #{languages.empty? ? "Unknown" : languages.join(", ")}", type: :info)
        display_message("  Frameworks: #{frameworks.empty? ? "None detected" : frameworks.join(", ")}", type: :info)
        display_message("  Test suites: #{tests.empty? ? "Not found" : tests.join(", ")}", type: :info)
        display_message("  Config files: #{config_files.empty? ? "None detected" : config_files.join(", ")}", type: :info)
      end

      def gather_preferences
        display_message("\n⚙️  Customise bootstrap plans (press Enter to accept defaults):", type: :info)

        {
          adopt_new_conventions: ask_yes_no("Adopt the newly generated conventions as canonical defaults?", default: true),
          stricter_linters: ask_yes_no("Enforce stricter linting based on detected tools?", default: false),
          migrate_styles: ask_yes_no("Plan migrations to align legacy files with the new style guide?", default: false)
        }
      end

      def ask_yes_no(question, default:)
        @prompt.yes?(question) do |q|
          q.default default ? "yes" : "no"
        end
      rescue NoMethodError
        # Compatibility with simplified prompts in tests (e.g. TestPrompt)
        default
      end
    end
  end
end
