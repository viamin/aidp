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
        # Simple task execution - for one-off commands and simple fixes
        "99_SIMPLE_TASK" => {
          "templates" => ["implementation/simple_task.md"],
          "description" => "Execute Simple Task (one-off commands, quick fixes, linting; emit NEXT_UNIT when more tooling is needed)",
          "outs" => [],
          "gate" => false,
          "simple" => true # Special step for simple, focused tasks
        },
        # Waterfall planning mode steps
        "20_WATERFALL_INIT" => {
          "templates" => ["waterfall/initialize_planning.md"],
          "description" => "Initialize waterfall planning (ingestion vs generation)",
          "outs" => [".aidp/docs/.waterfall_mode"],
          "gate" => true,
          "interactive" => true
        },
        "21_WATERFALL_PRD" => {
          "skill" => "product_strategist",
          "templates" => ["waterfall/generate_prd.md"],
          "description" => "Generate or enhance Product Requirements Document",
          "outs" => [".aidp/docs/PRD.md"],
          "gate" => false,
          "interactive" => true
        },
        "22_WATERFALL_TECH_DESIGN" => {
          "skill" => "architect",
          "templates" => ["waterfall/generate_tech_design.md"],
          "description" => "Generate Technical Design Document",
          "outs" => [".aidp/docs/TECH_DESIGN.md"],
          "gate" => false
        },
        "23_WATERFALL_WBS" => {
          "templates" => ["waterfall/generate_wbs.md"],
          "description" => "Generate Work Breakdown Structure",
          "outs" => [".aidp/docs/WBS.md"],
          "gate" => false
        },
        "24_WATERFALL_GANTT" => {
          "templates" => ["waterfall/generate_gantt.md"],
          "description" => "Generate Gantt chart and critical path analysis",
          "outs" => [".aidp/docs/GANTT.md"],
          "gate" => false
        },
        "25_WATERFALL_TASKS" => {
          "templates" => ["waterfall/generate_task_list.md"],
          "description" => "Generate detailed task list with dependencies",
          "outs" => [".aidp/docs/TASK_LIST.md"],
          "gate" => false
        },
        "26_WATERFALL_PERSONAS" => {
          "templates" => ["waterfall/assign_personas.md"],
          "description" => "Assign tasks to personas using ZFC",
          "outs" => [".aidp/docs/persona_map.yml"],
          "gate" => false
        },
        "27_WATERFALL_PROJECT_PLAN" => {
          "templates" => ["waterfall/assemble_project_plan.md"],
          "description" => "Assemble complete project plan with all artifacts",
          "outs" => [".aidp/docs/PROJECT_PLAN.md"],
          "gate" => false
        }
      }.freeze
    end
  end
end
