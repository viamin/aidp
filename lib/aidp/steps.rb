# frozen_string_literal: true

module Aidp
  class Steps
    # Map step name -> template(s) and default outputs
    SPEC = {
      "prd" => {templates: ["00_PRD.md"], outs: ["docs/PRD.md", "PRD_QUESTIONS.md"], gate: true},
      "nfrs" => {templates: ["01_NFRS.md"], outs: ["docs/NFRs.md"]},
      "arch" => {templates: ["02_ARCHITECTURE.md", "02A_ARCH_GATE_QUESTIONS.md"],
                 outs: ["docs/Architecture.md", "docs/architecture.mmd", "ARCH_QUESTIONS.md"], gate: true},
      "adrs" => {templates: ["03_ADR_FACTORY.md"], outs: ["docs/adr/001-sample.md"]},
      "domains" => {templates: ["04_DOMAIN_DECOMPOSITION.md"], outs: ["docs/DomainCharters/README.md"]},
      "contracts" => {templates: ["05_CONTRACTS.md"], outs: ["contracts/README.md"]},
      "threat" => {templates: ["06_THREAT_MODEL.md"], outs: ["docs/ThreatModel.md", "docs/DataMap.md"]},
      "tests" => {templates: ["07_TEST_PLAN.md"], outs: ["docs/TestPlan.md"]},
      "tasks" => {templates: ["08_TASKS.md"], outs: ["tasks/backlog.yaml", "TASKS_QUESTIONS.md"], gate: true},
      "scaffold" => {templates: ["09_SCAFFOLDING_DEVEX.md"], outs: ["docs/ScaffoldingGuide.md"]},
      "impl" => {templates: ["10_IMPLEMENTATION_AGENT.md"], outs: ["docs/ImplementationGuide.md", "IMPL_QUESTIONS.md"],
                 gate: true},
      "static" => {templates: ["11_STATIC_ANALYSIS.md"], outs: ["docs/StaticAnalysis.md"]},
      "obs" => {templates: ["12_OBSERVABILITY_SLOS.md"], outs: ["docs/Observability.md"]},
      "delivery" => {templates: ["13_DELIVERY_ROLLOUT.md"], outs: ["docs/DeliveryPlan.md"]},
      "docsportal" => {templates: ["14_DOCS_PORTAL.md"], outs: ["docs/DocsPortalPlan.md"]},
      "post" => {templates: ["15_POST_RELEASE.md"], outs: ["docs/PostReleaseReport.md"]}
    }.freeze

    def self.list
      SPEC.keys
    end

    def self.for(name)
      SPEC[name] or raise "Unknown step #{name.inspect}"
    end
  end
end
