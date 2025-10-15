# frozen_string_literal: true

module Aidp
  module Execute
    module Steps
      # Simplified step specifications with fewer gates
      # Templates are now organized by purpose (planning/, analysis/, implementation/)
      # and named with action verbs for clarity
      SPEC = {
        "00_LLM_STYLE_GUIDE" => {
          "templates" => ["planning/generate_llm_style_guide.md"],
          "description" => "Generate project-specific LLM Style Guide",
          "outs" => ["docs/LLM_STYLE_GUIDE.md"],
          "gate" => false,
          "interactive" => false
        },
        "00_PRD" => {
          "templates" => ["planning/create_prd.md"],
          "description" => "Generate Product Requirements Document",
          "outs" => ["docs/prd.md"],
          "gate" => false, # Now auto-generated from user input
          "interactive" => true # Uses collected user input
        },
        "01_NFRS" => {
          "templates" => ["planning/define_nfrs.md"],
          "description" => "Define Non-Functional Requirements",
          "outs" => ["docs/nfrs.md"],
          "gate" => false # Auto-generated
        },
        "02_ARCHITECTURE" => {
          "templates" => ["planning/design_architecture.md"],
          "description" => "Design System Architecture",
          "outs" => ["docs/architecture.md"],
          "gate" => false # Auto-generated
        },
        "02A_ARCH_GATE_QUESTIONS" => {
          "templates" => ["planning/ask_architecture_questions.md"],
          "description" => "Architecture Gate Questions",
          "outs" => ["docs/arch_gate_questions.md"],
          "gate" => true
        },
        "03_ADR_FACTORY" => {
          "templates" => ["planning/generate_adrs.md"],
          "description" => "Generate Architecture Decision Records",
          "outs" => ["docs/adr/*.md"],
          "gate" => false
        },
        "04_DOMAIN_DECOMPOSITION" => {
          "templates" => ["planning/decompose_domain.md"],
          "description" => "Decompose Domain into Components",
          "outs" => ["docs/domain_decomposition.md"],
          "gate" => false # Auto-generated
        },
        "05_API_DESIGN" => {
          "templates" => ["planning/design_apis.md"],
          "description" => "Design APIs and Interfaces",
          "outs" => ["docs/api_design.md"],
          "gate" => false # Auto-generated
        },
        "06_DATA_MODEL" => {
          "templates" => ["planning/design_data_model.md"],
          "description" => "Design Data Model",
          "outs" => ["docs/data_model.md"],
          "gate" => true
        },
        "07_SECURITY_REVIEW" => {
          "templates" => ["planning/plan_testing.md"],
          "description" => "Security Review and Threat Model",
          "outs" => ["docs/security_review.md"],
          "gate" => true
        },
        "08_PERFORMANCE_REVIEW" => {
          "templates" => ["planning/create_tasks.md"],
          "description" => "Performance Review and Optimization",
          "outs" => ["docs/performance_review.md"],
          "gate" => true
        },
        "09_RELIABILITY_REVIEW" => {
          "templates" => ["implementation/setup_scaffolding.md"],
          "description" => "Reliability Review and SLOs",
          "outs" => ["docs/reliability_review.md"],
          "gate" => true
        },
        "10_TESTING_STRATEGY" => {
          "templates" => ["implementation/implement_features.md"],
          "description" => "Define Testing Strategy",
          "outs" => ["docs/testing_strategy.md"],
          "gate" => false # Auto-generated
        },
        "11_STATIC_ANALYSIS" => {
          "templates" => ["implementation/configure_static_analysis.md"],
          "description" => "Static Code Analysis",
          "outs" => ["docs/static_analysis.md"],
          "gate" => false
        },
        "12_OBSERVABILITY_SLOS" => {
          "templates" => ["planning/plan_observability.md"],
          "description" => "Define Observability and SLOs",
          "outs" => ["docs/observability_slos.md"],
          "gate" => true
        },
        "13_DELIVERY_ROLLOUT" => {
          "templates" => ["implementation/plan_delivery.md"],
          "description" => "Plan Delivery and Rollout",
          "outs" => ["docs/delivery_rollout.md"],
          "gate" => true
        },
        "14_DOCS_PORTAL" => {
          "templates" => ["implementation/create_documentation_portal.md"],
          "description" => "Documentation Portal",
          "outs" => ["docs/docs_portal.md"],
          "gate" => false
        },
        "15_POST_RELEASE" => {
          "templates" => ["implementation/review_post_release.md"],
          "description" => "Post-Release Review",
          "outs" => ["docs/post_release.md"],
          "gate" => false # Auto-generated
        },
        # New implementation step for actual development work
        "16_IMPLEMENTATION" => {
          "templates" => ["implementation/implement_features.md"], # Reuse existing implementation template
          "description" => "Execute Implementation Tasks",
          "outs" => ["implementation_log.md"],
          "gate" => false,
          "implementation" => true # Special step that runs development tasks
        },
        # Simple task execution - for one-off commands and simple fixes
        "99_SIMPLE_TASK" => {
          "templates" => ["implementation/simple_task.md"],
          "description" => "Execute Simple Task (one-off commands, quick fixes, linting; emit NEXT_UNIT when more tooling is needed)",
          "outs" => [],
          "gate" => false,
          "simple" => true # Special step for simple, focused tasks
        }
      }.freeze
    end
  end
end
