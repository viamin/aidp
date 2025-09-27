# frozen_string_literal: true

module Aidp
  module Analyze
    module Steps
      SPEC = {
        "01_REPOSITORY_ANALYSIS" => {
          "templates" => ["01_REPOSITORY_ANALYSIS.md"],
          "description" => "Initial code-maat based repository mining",
          "outs" => ["docs/analysis/repository_analysis.md"],
          "gate" => false
        },
        "02_ARCHITECTURE_ANALYSIS" => {
          "templates" => ["02_ARCHITECTURE_ANALYSIS.md"],
          "description" => "Identify architectural patterns, dependencies, and violations",
          "outs" => ["docs/analysis/architecture_analysis.md"],
          "gate" => true
        },
        "03_TEST_ANALYSIS" => {
          "templates" => ["03_TEST_ANALYSIS.md"],
          "description" => "Analyze existing test coverage and identify gaps",
          "outs" => ["docs/analysis/test_analysis.md"],
          "gate" => false
        },
        "04_FUNCTIONALITY_ANALYSIS" => {
          "templates" => ["04_FUNCTIONALITY_ANALYSIS.md"],
          "description" => "Map features, identify dead code, analyze complexity",
          "outs" => ["docs/analysis/functionality_analysis.md"],
          "gate" => false
        },
        "05_DOCUMENTATION_ANALYSIS" => {
          "templates" => ["05_DOCUMENTATION_ANALYSIS.md"],
          "description" => "Identify missing documentation and generate what's needed",
          "outs" => ["docs/analysis/documentation_analysis.md"],
          "gate" => false
        },
        "06_STATIC_ANALYSIS" => {
          "templates" => ["06_STATIC_ANALYSIS.md"],
          "description" => "Check for existing tools and recommend improvements",
          "outs" => ["docs/analysis/static_analysis.md"],
          "gate" => false
        },
        "06A_TREE_SITTER_SCAN" => {
          "templates" => ["06a_tree_sitter_scan.md"],
          "description" => "Tree-sitter powered static analysis to build knowledge base",
          "outs" => [".aidp/kb/symbols.json", ".aidp/kb/seams.json", ".aidp/kb/hotspots.json"],
          "gate" => false
        },
        "07_REFACTORING_RECOMMENDATIONS" => {
          "templates" => ["07_REFACTORING_RECOMMENDATIONS.md"],
          "description" => "Provide actionable refactoring guidance",
          "outs" => ["docs/analysis/refactoring_recommendations.md"],
          "gate" => true
        }
      }.freeze
    end
  end
end
