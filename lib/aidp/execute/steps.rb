# frozen_string_literal: true

module Aidp
  module Execute
    # Defines the steps, templates, outputs, and associated AI agents for execute mode
    class Steps
      SPEC = {
        "00_PRD" => {
          "templates" => ["00_PRD.md"],
          "outs" => ["00_PRD.md"],
          "gate" => false,
          "agent" => "Product Manager"
        },
        "01_NFRS" => {
          "templates" => ["01_NFRS.md"],
          "outs" => ["01_NFRS.md"],
          "gate" => false,
          "agent" => "Architect"
        },
        "02_ARCHITECTURE" => {
          "templates" => ["02_ARCHITECTURE.md"],
          "outs" => ["02_ARCHITECTURE.md"],
          "gate" => false,
          "agent" => "Architect"
        },
        "02A_ARCH_GATE_QUESTIONS" => {
          "templates" => ["02A_ARCH_GATE_QUESTIONS.md"],
          "outs" => ["02A_ARCH_GATE_QUESTIONS.md"],
          "gate" => true,
          "agent" => "Architect"
        },
        "03_ADR_FACTORY" => {
          "templates" => ["03_ADR_FACTORY.md"],
          "outs" => ["03_ADR_FACTORY.md"],
          "gate" => false,
          "agent" => "Architect"
        },
        "04_DOMAIN_DECOMPOSITION" => {
          "templates" => ["04_DOMAIN_DECOMPOSITION.md"],
          "outs" => ["04_DOMAIN_DECOMPOSITION.md"],
          "gate" => false,
          "agent" => "Architect"
        },
        "05_CONTRACTS" => {
          "templates" => ["05_CONTRACTS.md"],
          "outs" => ["05_CONTRACTS.md"],
          "gate" => false,
          "agent" => "Architect"
        },
        "06_THREAT_MODEL" => {
          "templates" => ["06_THREAT_MODEL.md"],
          "outs" => ["06_THREAT_MODEL.md"],
          "gate" => false,
          "agent" => "Security Expert"
        },
        "07_TEST_PLAN" => {
          "templates" => ["07_TEST_PLAN.md"],
          "outs" => ["07_TEST_PLAN.md"],
          "gate" => false,
          "agent" => "Test Engineer"
        },
        "08_TASKS" => {
          "templates" => ["08_TASKS.md"],
          "outs" => ["08_TASKS.md"],
          "gate" => false,
          "agent" => "Project Manager"
        },
        "09_SCAFFOLDING_DEVEX" => {
          "templates" => ["09_SCAFFOLDING_DEVEX.md"],
          "outs" => ["09_SCAFFOLDING_DEVEX.md"],
          "gate" => false,
          "agent" => "DevOps Engineer"
        },
        "10_IMPLEMENTATION_AGENT" => {
          "templates" => ["10_IMPLEMENTATION_AGENT.md"],
          "outs" => ["10_IMPLEMENTATION_AGENT.md"],
          "gate" => false,
          "agent" => "Implementation Specialist"
        },
        "11_STATIC_ANALYSIS" => {
          "templates" => ["11_STATIC_ANALYSIS.md"],
          "outs" => ["11_STATIC_ANALYSIS.md"],
          "gate" => false,
          "agent" => "Code Quality Expert"
        },
        "12_OBSERVABILITY_SLOS" => {
          "templates" => ["12_OBSERVABILITY_SLOS.md"],
          "outs" => ["12_OBSERVABILITY_SLOS.md"],
          "gate" => false,
          "agent" => "SRE Engineer"
        },
        "13_DELIVERY_ROLLOUT" => {
          "templates" => ["13_DELIVERY_ROLLOUT.md"],
          "outs" => ["13_DELIVERY_ROLLOUT.md"],
          "gate" => false,
          "agent" => "DevOps Engineer"
        },
        "14_DOCS_PORTAL" => {
          "templates" => ["14_DOCS_PORTAL.md"],
          "outs" => ["14_DOCS_PORTAL.md"],
          "gate" => false,
          "agent" => "Technical Writer"
        },
        "15_POST_RELEASE" => {
          "templates" => ["15_POST_RELEASE.md"],
          "outs" => ["15_POST_RELEASE.md"],
          "gate" => false,
          "agent" => "Project Manager"
        }
      }.freeze
    end
  end
end
