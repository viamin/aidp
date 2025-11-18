# frozen_string_literal: true

module Aidp
  module Workflows
    # Centralized workflow definitions for both Analyze and Execute modes
    # Provides pre-configured workflows at various levels of depth/complexity
    module Definitions
      # Analyze mode workflows - from surface-level to deep analysis
      ANALYZE_WORKFLOWS = {
        quick_overview: {
          name: "Quick Overview",
          description: "Surface-level understanding - What does this project do?",
          icon: "🔍",
          details: [
            "Repository structure scan",
            "High-level functionality mapping",
            "Quick documentation review"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "04_FUNCTIONALITY_ANALYSIS",
            "05_DOCUMENTATION_ANALYSIS"
          ]
        },

        style_guide: {
          name: "Style & Patterns",
          description: "Identify coding patterns and create style guide",
          icon: "📐",
          details: [
            "Code pattern analysis",
            "Style consistency review",
            "Generate project style guide"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "06_STATIC_ANALYSIS",
            "06A_TREE_SITTER_SCAN"
          ]
        },

        architecture_review: {
          name: "Architecture Review",
          description: "Understand system architecture and dependencies",
          icon: "🏗️",
          details: [
            "Architecture pattern analysis",
            "Dependency mapping",
            "Component relationships",
            "Design principles review"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "02_ARCHITECTURE_ANALYSIS",
            "06A_TREE_SITTER_SCAN"
          ]
        },

        quality_assessment: {
          name: "Quality Assessment",
          description: "Comprehensive code quality and test coverage analysis",
          icon: "✅",
          details: [
            "Test coverage analysis",
            "Code quality metrics",
            "Static analysis review",
            "Refactoring opportunities"
          ],
          steps: [
            "03_TEST_ANALYSIS",
            "06_STATIC_ANALYSIS",
            "06A_TREE_SITTER_SCAN",
            "07_REFACTORING_RECOMMENDATIONS"
          ]
        },

        deep_analysis: {
          name: "Deep Analysis",
          description: "Complete analysis for extension/refactoring",
          icon: "🔬",
          details: [
            "Full repository analysis",
            "Architecture deep dive",
            "Complete test coverage analysis",
            "Functionality mapping",
            "Documentation review",
            "Static analysis",
            "Tree-sitter knowledge base",
            "Refactoring recommendations"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "02_ARCHITECTURE_ANALYSIS",
            "03_TEST_ANALYSIS",
            "04_FUNCTIONALITY_ANALYSIS",
            "05_DOCUMENTATION_ANALYSIS",
            "06_STATIC_ANALYSIS",
            "06A_TREE_SITTER_SCAN",
            "07_REFACTORING_RECOMMENDATIONS"
          ]
        },

        custom: {
          name: "Custom Analysis",
          description: "Choose specific analysis steps",
          icon: "⚙️",
          details: ["Select exactly which analysis steps you need"],
          steps: :custom # Will be populated by user selection
        }
      }.freeze

      # Execute mode workflows - from quick prototype to enterprise-grade
      EXECUTE_WORKFLOWS = {
        quick_prototype: {
          name: "Quick Prototype",
          description: "Rapid prototype - minimal planning, fast iteration",
          icon: "⚡",
          details: [
            "Minimal PRD",
            "Basic testing strategy",
            "Direct to implementation"
          ],
          steps: [
            "00_PRD",
            "10_TESTING_STRATEGY",
            "16_IMPLEMENTATION"
          ]
        },

        exploration: {
          name: "Exploration/Experiment",
          description: "Proof of concept with basic quality checks",
          icon: "🔬",
          details: [
            "Quick PRD generation",
            "Testing strategy",
            "Static analysis setup",
            "Implementation with work loops"
          ],
          steps: [
            "00_PRD",
            "10_TESTING_STRATEGY",
            "11_STATIC_ANALYSIS",
            "16_IMPLEMENTATION"
          ]
        },

        feature_development: {
          name: "Feature Development",
          description: "Standard feature with architecture and testing",
          icon: "🚀",
          details: [
            "Product requirements",
            "Architecture design",
            "Testing strategy",
            "Static analysis",
            "Implementation"
          ],
          steps: [
            "00_PRD",
            "02_ARCHITECTURE",
            "10_TESTING_STRATEGY",
            "11_STATIC_ANALYSIS",
            "16_IMPLEMENTATION"
          ]
        },

        tdd_feature_development: {
          name: "TDD Feature Development",
          description: "Test-driven development with tests written first",
          icon: "🧪",
          details: [
            "Product requirements",
            "Architecture design",
            "TDD test specifications (write tests FIRST)",
            "RED: Tests fail initially",
            "GREEN: Implement to pass tests",
            "REFACTOR: Improve with confidence"
          ],
          steps: [
            "00_PRD",
            "02_ARCHITECTURE",
            "17_TDD_SPECIFICATION",
            "16_IMPLEMENTATION"
          ]
        },

        production_ready: {
          name: "Production-Ready",
          description: "Enterprise-grade with NFRs and compliance",
          icon: "🏗️",
          details: [
            "Comprehensive PRD",
            "Non-functional requirements",
            "System architecture",
            "Security review",
            "Performance planning",
            "Testing strategy",
            "Observability & SLOs",
            "Delivery planning",
            "Implementation"
          ],
          steps: [
            "00_PRD",
            "01_NFRS",
            "02_ARCHITECTURE",
            "07_SECURITY_REVIEW",
            "08_PERFORMANCE_REVIEW",
            "10_TESTING_STRATEGY",
            "11_STATIC_ANALYSIS",
            "12_OBSERVABILITY_SLOS",
            "13_DELIVERY_ROLLOUT",
            "16_IMPLEMENTATION"
          ]
        },

        full_enterprise: {
          name: "Full Enterprise",
          description: "Complete enterprise workflow with all governance",
          icon: "🏢",
          details: [
            "All planning documents",
            "Architecture decision records",
            "Domain decomposition",
            "API design",
            "Security & performance reviews",
            "Reliability planning",
            "Complete observability",
            "Documentation portal"
          ],
          steps: [
            "00_PRD",
            "01_NFRS",
            "02_ARCHITECTURE",
            "03_ADR_FACTORY",
            "04_DOMAIN_DECOMPOSITION",
            "05_API_DESIGN",
            "07_SECURITY_REVIEW",
            "08_PERFORMANCE_REVIEW",
            "09_RELIABILITY_REVIEW",
            "10_TESTING_STRATEGY",
            "11_STATIC_ANALYSIS",
            "12_OBSERVABILITY_SLOS",
            "13_DELIVERY_ROLLOUT",
            "14_DOCS_PORTAL",
            "16_IMPLEMENTATION"
          ]
        },

        waterfall_standard: {
          name: "Waterfall Planning",
          description: "Structured project planning with WBS and Gantt charts",
          icon: "📊",
          details: [
            "Documentation ingestion or generation",
            "Work breakdown structure (WBS)",
            "Gantt chart with critical path",
            "Task dependencies and milestones",
            "Persona/agent assignment",
            "Complete project plan"
          ],
          steps: [
            "20_WATERFALL_INIT",
            "21_WATERFALL_PRD",
            "22_WATERFALL_TECH_DESIGN",
            "23_WATERFALL_WBS",
            "24_WATERFALL_GANTT",
            "25_WATERFALL_TASKS",
            "26_WATERFALL_PERSONAS",
            "16_IMPLEMENTATION"
          ]
        },

        waterfall_minimal: {
          name: "Waterfall Planning (Minimal)",
          description: "Quick waterfall planning without full enterprise features",
          icon: "📋",
          details: [
            "Essential documentation",
            "Basic work breakdown",
            "Simple Gantt chart",
            "Task list with dependencies"
          ],
          steps: [
            "20_WATERFALL_INIT",
            "21_WATERFALL_PRD",
            "23_WATERFALL_WBS",
            "25_WATERFALL_TASKS",
            "16_IMPLEMENTATION"
          ]
        },

        waterfall_tdd: {
          name: "Waterfall Planning with TDD",
          description: "Waterfall planning with test-driven development",
          icon: "📊🧪",
          details: [
            "Complete waterfall planning",
            "Work breakdown structure",
            "Gantt chart with critical path",
            "TDD test specifications (write tests first)",
            "Test-driven implementation",
            "Persona assignments"
          ],
          steps: [
            "20_WATERFALL_INIT",
            "21_WATERFALL_PRD",
            "22_WATERFALL_TECH_DESIGN",
            "23_WATERFALL_WBS",
            "24_WATERFALL_GANTT",
            "25_WATERFALL_TASKS",
            "17_TDD_SPECIFICATION",
            "26_WATERFALL_PERSONAS",
            "27_WATERFALL_PROJECT_PLAN",
            "16_IMPLEMENTATION"
          ]
        },

        custom: {
          name: "Custom Workflow",
          description: "Choose specific planning and implementation steps",
          icon: "⚙️",
          details: ["Select exactly which steps you need"],
          steps: :custom # Will be populated by user selection
        }
      }.freeze

      # Hybrid workflows - mix of analyze and execute steps
      HYBRID_WORKFLOWS = {
        legacy_modernization: {
          name: "Legacy Modernization",
          description: "Analyze existing code then plan modernization",
          icon: "♻️",
          details: [
            "Deep code analysis",
            "Refactoring recommendations",
            "Architecture design for new system",
            "Migration planning",
            "Implementation"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "02_ARCHITECTURE_ANALYSIS",
            "06A_TREE_SITTER_SCAN",
            "07_REFACTORING_RECOMMENDATIONS",
            "00_PRD",
            "02_ARCHITECTURE",
            "16_IMPLEMENTATION"
          ]
        },

        style_guide_enforcement: {
          name: "Style Guide Enforcement",
          description: "Extract patterns then enforce them",
          icon: "📏",
          details: [
            "Analyze existing patterns",
            "Generate LLM style guide",
            "Configure static analysis",
            "Implement enforcement"
          ],
          steps: [
            "01_REPOSITORY_ANALYSIS",
            "06_STATIC_ANALYSIS",
            "06A_TREE_SITTER_SCAN",
            "00_LLM_STYLE_GUIDE",
            "11_STATIC_ANALYSIS",
            "16_IMPLEMENTATION"
          ]
        },

        test_coverage_improvement: {
          name: "Test Coverage Improvement",
          description: "Analyze gaps then implement comprehensive tests",
          icon: "🧪",
          details: [
            "Test coverage analysis",
            "Functionality mapping",
            "Testing strategy design",
            "Test implementation"
          ],
          steps: [
            "03_TEST_ANALYSIS",
            "04_FUNCTIONALITY_ANALYSIS",
            "06A_TREE_SITTER_SCAN",
            "10_TESTING_STRATEGY",
            "16_IMPLEMENTATION"
          ]
        },

        custom_hybrid: {
          name: "Custom Hybrid",
          description: "Mix analyze and execute steps",
          icon: "🔀",
          details: ["Choose from both analyze and execute steps"],
          steps: :custom # Will be populated by user selection
        }
      }.freeze

      # Get all available steps for custom selection
      def self.all_available_steps
        analyze_steps = Aidp::Analyze::Steps::SPEC.keys.map do |step|
          {
            step: step,
            mode: :analyze,
            description: Aidp::Analyze::Steps::SPEC[step]["description"]
          }
        end

        execute_steps = Aidp::Execute::Steps::SPEC.keys.map do |step|
          {
            step: step,
            mode: :execute,
            description: Aidp::Execute::Steps::SPEC[step]["description"]
          }
        end

        (analyze_steps + execute_steps).sort_by { |s| s[:step] }
      end

      # Get workflow definition by key
      def self.get_workflow(mode, workflow_key)
        case mode
        when :analyze
          ANALYZE_WORKFLOWS[workflow_key]
        when :execute
          EXECUTE_WORKFLOWS[workflow_key]
        when :hybrid
          HYBRID_WORKFLOWS[workflow_key]
        end
      end

      # Get all workflows for a mode
      def self.workflows_for_mode(mode)
        case mode
        when :analyze
          ANALYZE_WORKFLOWS
        when :execute
          EXECUTE_WORKFLOWS
        when :hybrid
          HYBRID_WORKFLOWS
        end
      end
    end
  end
end
