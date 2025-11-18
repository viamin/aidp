# frozen_string_literal: true

module Aidp
  module Execute
    module Steps
      # Simplified step specifications with fewer gates
      # Templates are now organized by purpose (planning/, analysis/, implementation/)
      # and named with action verbs for clarity
      # Skills define WHO the agent is, templates define WHAT task to do
      SPEC = {
        "00_LLM_STYLE_GUIDE" => {
          "templates" => ["planning/generate_llm_style_guide.md"],
          "description" => "Generate project-specific LLM Style Guide",
          "outs" => ["docs/LLM_STYLE_GUIDE.md"],
          "gate" => false,
          "interactive" => false
        },
        "00_PRD" => {
          "skill" => "product_strategist",
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
        # Test-Driven Development (TDD) - Optional step for any workflow
        "17_TDD_SPECIFICATION" => {
          "templates" => ["implementation/generate_tdd_specs.md"],
          "description" => "Generate TDD test specifications (write tests first)",
          "outs" => ["docs/tdd_specifications.md", "spec/**/*_spec.rb"],
          "gate" => false,
          "interactive" => false
        },
        # Simple task execution - for one-off commands and simple fixes
        "99_SIMPLE_TASK" => {
          "templates" => ["implementation/simple_task.md"],
          "description" => "Execute Simple Task (one-off commands, quick fixes, linting; emit NEXT_UNIT when more tooling is needed)",
          "outs" => [],
          "gate" => false,
          "simple" => true # Special step for simple, focused tasks
        },
        # Generic planning and project management steps (usable in any workflow)
        "18_WBS" => {
          "templates" => ["planning/generate_wbs.md"],
          "description" => "Generate Work Breakdown Structure with phases and tasks",
          "outs" => [".aidp/docs/WBS.md"],
          "gate" => false
        },
        "19_GANTT_CHART" => {
          "templates" => ["planning/generate_gantt.md"],
          "description" => "Generate Gantt chart with timeline and critical path",
          "outs" => [".aidp/docs/GANTT.md"],
          "gate" => false
        },
        "20_PERSONA_ASSIGNMENT" => {
          "templates" => ["planning/assign_personas.md"],
          "description" => "Assign tasks to personas/roles using AI (ZFC)",
          "outs" => [".aidp/docs/persona_map.yml"],
          "gate" => false
        },
        "21_PROJECT_PLAN_ASSEMBLY" => {
          "templates" => ["planning/assemble_project_plan.md"],
          "description" => "Assemble complete project plan from all artifacts",
          "outs" => [".aidp/docs/PROJECT_PLAN.md"],
          "gate" => false
        },
        # Planning mode initialization (supports ingestion vs generation workflows)
        "22_PLANNING_MODE_INIT" => {
          "templates" => ["planning/initialize_planning_mode.md"],
          "description" => "Initialize planning mode (ingestion of existing docs vs generation from scratch)",
          "outs" => [".aidp/docs/.planning_mode"],
          "gate" => true,
          "interactive" => true
        },
        # Agile planning steps
        "23_MVP_SCOPE" => {
          "skill" => "product_manager",
          "templates" => ["planning/agile/generate_mvp_scope.md"],
          "description" => "Define MVP scope with must-have and nice-to-have features",
          "outs" => [".aidp/docs/MVP_SCOPE.md"],
          "gate" => false,
          "interactive" => true
        },
        "24_USER_TEST_PLAN" => {
          "skill" => "ux_researcher",
          "templates" => ["planning/agile/generate_user_test_plan.md"],
          "description" => "Generate user testing plan with recruitment and survey templates",
          "outs" => [".aidp/docs/USER_TEST_PLAN.md"],
          "gate" => false
        },
        "25_MARKETING_REPORT" => {
          "skill" => "marketing_strategist",
          "templates" => ["planning/agile/generate_marketing_report.md"],
          "description" => "Generate marketing report with key messages and differentiators",
          "outs" => [".aidp/docs/MARKETING_REPORT.md"],
          "gate" => false
        },
        "26_INGEST_FEEDBACK" => {
          "skill" => "ux_researcher",
          "templates" => ["planning/agile/ingest_feedback.md"],
          "description" => "Ingest user feedback data (CSV, JSON, markdown)",
          "outs" => [".aidp/docs/feedback_data.json"],
          "gate" => false,
          "interactive" => true
        },
        "27_ANALYZE_FEEDBACK" => {
          "skill" => "ux_researcher",
          "templates" => ["planning/agile/analyze_feedback.md"],
          "description" => "Analyze user feedback with AI-powered insights",
          "outs" => [".aidp/docs/USER_FEEDBACK_ANALYSIS.md"],
          "gate" => false
        },
        "28_ITERATION_PLAN" => {
          "skill" => "product_manager",
          "templates" => ["planning/agile/generate_iteration_plan.md"],
          "description" => "Generate next iteration plan based on feedback",
          "outs" => [".aidp/docs/NEXT_ITERATION_PLAN.md"],
          "gate" => false
        },
        "29_LEGACY_RESEARCH_PLAN" => {
          "skill" => "ux_researcher",
          "templates" => ["planning/agile/generate_legacy_research_plan.md"],
          "description" => "Generate user research plan for existing codebase",
          "outs" => [".aidp/docs/LEGACY_USER_RESEARCH_PLAN.md"],
          "gate" => false
        }
      }.freeze
    end
  end
end
