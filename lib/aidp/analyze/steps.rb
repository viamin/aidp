# frozen_string_literal: true

module Aidp
  module Analyze
    # Defines the steps, templates, outputs, and associated AI agents for analyze mode
    class Steps
      SPEC = {
        "01_REPOSITORY_ANALYSIS" => {
          "templates" => ["01_REPOSITORY_ANALYSIS.md"],
          "outs" => ["01_REPOSITORY_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Repository Analyst"
        },
        "02_ARCHITECTURE_ANALYSIS" => {
          "templates" => ["02_ARCHITECTURE_ANALYSIS.md"],
          "outs" => ["02_ARCHITECTURE_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Architecture Analyst"
        },
        "03_TEST_ANALYSIS" => {
          "templates" => ["03_TEST_ANALYSIS.md"],
          "outs" => ["03_TEST_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Test Analyst"
        },
        "04_FUNCTIONALITY_ANALYSIS" => {
          "templates" => ["04_FUNCTIONALITY_ANALYSIS.md"],
          "outs" => ["04_FUNCTIONALITY_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Functionality Analyst"
        },
        "05_DOCUMENTATION_ANALYSIS" => {
          "templates" => ["05_DOCUMENTATION_ANALYSIS.md"],
          "outs" => ["05_DOCUMENTATION_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Documentation Analyst"
        },
        "06_STATIC_ANALYSIS" => {
          "templates" => ["06_STATIC_ANALYSIS.md"],
          "outs" => ["06_STATIC_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Static Analysis Expert"
        },
        "07_REFACTORING_RECOMMENDATIONS" => {
          "templates" => ["07_REFACTORING_RECOMMENDATIONS.md"],
          "outs" => ["07_REFACTORING_RECOMMENDATIONS.md"],
          "gate" => false,
          "agent" => "Refactoring Specialist"
        }
      }.freeze
    end
  end
end
