# frozen_string_literal: true

module Aidp
  module Execute
    module Steps
      # Simplified step specifications with fewer gates
      SPEC = {
        "00_PRD" => {
          "templates" => ["00_PRD.md"],
          "description" => "Generate Product Requirements Document",
          "outs" => ["docs/prd.md"],
          "gate" => false,  # Now auto-generated from user input
          "interactive" => true  # Uses collected user input
        },
        "01_NFRS" => {
          "templates" => ["01_NFRS.md"],
          "description" => "Define Non-Functional Requirements",
          "outs" => ["docs/nfrs.md"],
          "gate" => false  # Auto-generated
        },
        "02_ARCHITECTURE" => {
          "templates" => ["02_ARCHITECTURE.md"],
          "description" => "Design System Architecture",
          "outs" => ["docs/architecture.md"],
          "gate" => false  # Auto-generated
        },
        "02A_ARCH_GATE_QUESTIONS" => {
          "templates" => ["02A_ARCH_GATE_QUESTIONS.md"],
          "description" => "Architecture Gate Questions",
          "outs" => ["docs/arch_gate_questions.md"],
          "gate" => true
        },
        "03_ADR_FACTORY" => {
          "templates" => ["03_ADR_FACTORY.md"],
          "description" => "Generate Architecture Decision Records",
          "outs" => ["docs/adr/*.md"],
          "gate" => false
        },
        "04_DOMAIN_DECOMPOSITION" => {
          "templates" => ["04_DOMAIN_DECOMPOSITION.md"],
          "description" => "Decompose Domain into Components",
          "outs" => ["docs/domain_decomposition.md"],
          "gate" => false  # Auto-generated
        },
        "05_API_DESIGN" => {
          "templates" => ["05_CONTRACTS.md"],
          "description" => "Design APIs and Interfaces",
          "outs" => ["docs/api_design.md"],
          "gate" => false  # Auto-generated
        },
        "06_DATA_MODEL" => {
          "templates" => ["06_THREAT_MODEL.md"],
          "description" => "Design Data Model",
          "outs" => ["docs/data_model.md"],
          "gate" => true
        },
        "07_SECURITY_REVIEW" => {
          "templates" => ["07_TEST_PLAN.md"],
          "description" => "Security Review and Threat Model",
          "outs" => ["docs/security_review.md"],
          "gate" => true
        },
        "08_PERFORMANCE_REVIEW" => {
          "templates" => ["08_TASKS.md"],
          "description" => "Performance Review and Optimization",
          "outs" => ["docs/performance_review.md"],
          "gate" => true
        },
        "09_RELIABILITY_REVIEW" => {
          "templates" => ["09_SCAFFOLDING_DEVEX.md"],
          "description" => "Reliability Review and SLOs",
          "outs" => ["docs/reliability_review.md"],
          "gate" => true
        },
        "10_TESTING_STRATEGY" => {
          "templates" => ["10_IMPLEMENTATION_AGENT.md"],
          "description" => "Define Testing Strategy",
          "outs" => ["docs/testing_strategy.md"],
          "gate" => false  # Auto-generated
        },
        "11_STATIC_ANALYSIS" => {
          "templates" => ["11_STATIC_ANALYSIS.md"],
          "description" => "Static Code Analysis",
          "outs" => ["docs/static_analysis.md"],
          "gate" => false
        },
        "12_OBSERVABILITY_SLOS" => {
          "templates" => ["12_OBSERVABILITY_SLOS.md"],
          "description" => "Define Observability and SLOs",
          "outs" => ["docs/observability_slos.md"],
          "gate" => true
        },
        "13_DELIVERY_ROLLOUT" => {
          "templates" => ["13_DELIVERY_ROLLOUT.md"],
          "description" => "Plan Delivery and Rollout",
          "outs" => ["docs/delivery_rollout.md"],
          "gate" => true
        },
        "14_DOCS_PORTAL" => {
          "templates" => ["14_DOCS_PORTAL.md"],
          "description" => "Documentation Portal",
          "outs" => ["docs/docs_portal.md"],
          "gate" => false
        },
        "15_POST_RELEASE" => {
          "templates" => ["15_POST_RELEASE.md"],
          "description" => "Post-Release Review",
          "outs" => ["docs/post_release.md"],
          "gate" => false  # Auto-generated
        },
        # New implementation step for actual development work
        "16_IMPLEMENTATION" => {
          "templates" => ["10_IMPLEMENTATION_AGENT.md"],  # Reuse existing implementation template
          "description" => "Execute Implementation Tasks",
          "outs" => ["implementation_log.md"],
          "gate" => false,
          "implementation" => true  # Special step that runs development tasks
        }
      }.freeze
    end
  end
end
