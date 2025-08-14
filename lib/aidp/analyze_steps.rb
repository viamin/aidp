# frozen_string_literal: true

module Aidp
  class AnalyzeSteps
    # Map step name -> template(s) and default outputs
    SPEC = {
      "repository" => {
        templates: ["01_REPOSITORY_ANALYSIS.md"],
        outs: ["docs/RepositoryAnalysis.md", "docs/repository_metrics.csv"],
        gate: true,
        agent: "Repository Analyst"
      },
      "architecture" => {
        templates: ["02_ARCHITECTURE_ANALYSIS.md"],
        outs: ["docs/ArchitectureAnalysis.md", "docs/architecture_patterns.md"],
        gate: true,
        agent: "Architecture Analyst"
      },
      "test-coverage" => {
        templates: ["03_TEST_COVERAGE_ANALYSIS.md"],
        outs: ["docs/TestCoverageAnalysis.md", "docs/test_gaps.md"],
        gate: false,
        agent: "Test Analyst"
      },
      "functionality" => {
        templates: ["04_FUNCTIONALITY_ANALYSIS.md"],
        outs: ["docs/FunctionalityAnalysis.md", "docs/feature_map.md"],
        gate: true,
        agent: "Functionality Analyst"
      },
      "documentation" => {
        templates: ["05_DOCUMENTATION_ANALYSIS.md"],
        outs: ["docs/DocumentationAnalysis.md", "docs/missing_docs.md"],
        gate: false,
        agent: "Documentation Analyst"
      },
      "static-analysis" => {
        templates: ["06_STATIC_ANALYSIS.md"],
        outs: ["docs/StaticAnalysisReport.md", "docs/tool_recommendations.md"],
        gate: false,
        agent: "Static Analysis Expert"
      },
      "refactoring" => {
        templates: ["07_REFACTORING_RECOMMENDATIONS.md"],
        outs: ["docs/RefactoringRecommendations.md", "docs/refactoring_plan.md"],
        gate: true,
        agent: "Refactoring Specialist"
      }
    }.freeze

    def self.list
      SPEC.keys
    end

    def self.for(name)
      SPEC[name] or raise "Unknown analyze step #{name.inspect}"
    end

    def self.gate_steps
      SPEC.select { |_, spec| spec[:gate] }.keys
    end

    def self.non_gate_steps
      SPEC.reject { |_, spec| spec[:gate] }.keys
    end
  end
end
