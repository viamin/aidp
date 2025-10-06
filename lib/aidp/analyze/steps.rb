# frozen_string_literal: true

module Aidp
  module Analyze
    module Steps
      # Analysis step specifications
      # Templates are organized by purpose and named with action verbs
      SPEC = {
        "01_REPOSITORY_ANALYSIS" => {
          "templates" => ["analysis/analyze_repository.md"],
          "description" => "Initial code-maat based repository mining",
          "outs" => ["docs/analysis/repository_analysis.md"],
          "gate" => false
        },
        "02_ARCHITECTURE_ANALYSIS" => {
          "templates" => ["analysis/analyze_architecture.md"],
          "description" => "Identify architectural patterns, dependencies, and violations",
          "outs" => ["docs/analysis/architecture_analysis.md"],
          "gate" => true
        },
        "03_TEST_ANALYSIS" => {
          "templates" => ["analysis/analyze_tests.md"],
          "description" => "Analyze existing test coverage and identify gaps",
          "outs" => ["docs/analysis/test_analysis.md"],
          "gate" => false
        },
        "04_FUNCTIONALITY_ANALYSIS" => {
          "templates" => ["analysis/analyze_functionality.md"],
          "description" => "Map features, identify dead code, analyze complexity",
          "outs" => ["docs/analysis/functionality_analysis.md"],
          "gate" => false
        },
        "05_DOCUMENTATION_ANALYSIS" => {
          "templates" => ["analysis/analyze_documentation.md"],
          "description" => "Identify missing documentation and generate what's needed",
          "outs" => ["docs/analysis/documentation_analysis.md"],
          "gate" => false
        },
        "06_STATIC_ANALYSIS" => {
          "templates" => ["analysis/analyze_static_code.md"],
          "description" => "Check for existing tools and recommend improvements",
          "outs" => ["docs/analysis/static_analysis.md"],
          "gate" => false
        },
        "06A_TREE_SITTER_SCAN" => {
          "templates" => ["analysis/scan_with_tree_sitter.md"],
          "description" => "Tree-sitter powered static analysis to build knowledge base",
          "outs" => [".aidp/kb/symbols.json", ".aidp/kb/seams.json", ".aidp/kb/hotspots.json"],
          "gate" => false
        },
        "07_REFACTORING_RECOMMENDATIONS" => {
          "templates" => ["analysis/recommend_refactoring.md"],
          "description" => "Provide actionable refactoring guidance",
          "outs" => ["docs/analysis/refactoring_recommendations.md"],
          "gate" => true
        }
      }.freeze
    end
  end
end
