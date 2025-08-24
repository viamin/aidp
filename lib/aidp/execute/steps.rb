# frozen_string_literal: true

module Aidp
  module Execute
    module Steps
      SPEC = {
        "00_PRD" => {
          "templates" => ["prd.md"],
          "description" => "Generate Product Requirements Document",
          "outs" => ["docs/prd.md"],
          "gate" => true
        },
        "01_NFRS" => {
          "templates" => ["nfrs.md"],
          "description" => "Define Non-Functional Requirements",
          "outs" => ["docs/nfrs.md"],
          "gate" => true
        },
        "02_ARCHITECTURE" => {
          "templates" => ["architecture.md"],
          "description" => "Design System Architecture",
          "outs" => ["docs/architecture.md"],
          "gate" => true
        },
        "02A_ARCH_GATE_QUESTIONS" => {
          "templates" => ["arch_gate_questions.md"],
          "description" => "Architecture Gate Questions",
          "outs" => ["docs/arch_gate_questions.md"],
          "gate" => true
        },
        "03_ADR_FACTORY" => {
          "templates" => ["adr_factory.md"],
          "description" => "Generate Architecture Decision Records",
          "outs" => ["docs/adr/*.md"],
          "gate" => false
        },
        "04_DOMAIN_DECOMPOSITION" => {
          "templates" => ["domain_decomposition.md"],
          "description" => "Decompose Domain into Components",
          "outs" => ["docs/domain_decomposition.md"],
          "gate" => true
        },
        "05_API_DESIGN" => {
          "templates" => ["api_design.md"],
          "description" => "Design APIs and Interfaces",
          "outs" => ["docs/api_design.md"],
          "gate" => true
        },
        "06_DATA_MODEL" => {
          "templates" => ["data_model.md"],
          "description" => "Design Data Model",
          "outs" => ["docs/data_model.md"],
          "gate" => true
        },
        "07_SECURITY_REVIEW" => {
          "templates" => ["security_review.md"],
          "description" => "Security Review and Threat Model",
          "outs" => ["docs/security_review.md"],
          "gate" => true
        },
        "08_PERFORMANCE_REVIEW" => {
          "templates" => ["performance_review.md"],
          "description" => "Performance Review and Optimization",
          "outs" => ["docs/performance_review.md"],
          "gate" => true
        },
        "09_RELIABILITY_REVIEW" => {
          "templates" => ["reliability_review.md"],
          "description" => "Reliability Review and SLOs",
          "outs" => ["docs/reliability_review.md"],
          "gate" => true
        },
        "10_TESTING_STRATEGY" => {
          "templates" => ["testing_strategy.md"],
          "description" => "Define Testing Strategy",
          "outs" => ["docs/testing_strategy.md"],
          "gate" => true
        },
        "11_STATIC_ANALYSIS" => {
          "templates" => ["static_analysis.md"],
          "description" => "Static Code Analysis",
          "outs" => ["docs/static_analysis.md"],
          "gate" => false
        },
        "12_OBSERVABILITY_SLOS" => {
          "templates" => ["observability_slos.md"],
          "description" => "Define Observability and SLOs",
          "outs" => ["docs/observability_slos.md"],
          "gate" => true
        },
        "13_DELIVERY_ROLLOUT" => {
          "templates" => ["delivery_rollout.md"],
          "description" => "Plan Delivery and Rollout",
          "outs" => ["docs/delivery_rollout.md"],
          "gate" => true
        },
        "14_DOCS_PORTAL" => {
          "templates" => ["docs_portal.md"],
          "description" => "Documentation Portal",
          "outs" => ["docs/docs_portal.md"],
          "gate" => false
        },
        "15_POST_RELEASE" => {
          "templates" => ["post_release.md"],
          "description" => "Post-Release Review",
          "outs" => ["docs/post_release.md"],
          "gate" => true
        }
      }.freeze
    end
  end
end
