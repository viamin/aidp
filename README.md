# AI Dev Pipeline (aidp) - Ruby Gem

This repository contains both the **AI Dev Pipeline Ruby gem** and the **markdown prompts/instructions** that power it.

## The Gem: `aidp`

A portable CLI that runs a markdown-only AI dev workflow using your existing IDE assistants:

- **Prefers Cursor CLI** (`cursor-agent`)
- **Falls back to Claude** (`claude`/`claude-code`) or **Gemini** (`gemini`/`gemini-cli`)
- **Last resort: macOS UI automation** (AppleScript) to paste into Cursor chat

### Installation

```bash
# Build and install the gem
gem build aidp.gemspec
gem install aidp-*.gem

# Or install directly from this directory
gem install .
```

### Usage

```bash
cd /your/project
aidp steps                    # see available steps
aidp detect                   # see which provider will be used
aidp execute prd              # run PRD step
aidp sync prd                 # copy generated files
aidp execute_all              # run all steps sequentially
```

### Override Provider

```bash
AIDP_PROVIDER=anthropic aidp execute prd
AIDP_LLM_CMD=/usr/local/bin/claude aidp execute nfrs
```

### Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Build gem
bundle exec rake build
```

## The Workflow: Markdown-Only, Tool/Stack Agnostic

The gem packages **markdown prompts/instructions** that you can also use directly with Cursor (or any LLM) **step-by-step** to go from an idea → Product Requirements Document → Non-Functional Requirements → Architecture → Domain decomposition → Contracts → Threat model → Test plan → Tasks → Scaffolding hints → Implementation guidance → Static analysis → Observability → Delivery → Docs → Post-release.

- Style: inspired by `snarktank/ai-dev-tasks`. Every file is **self-contained**,
  designed to be pasted or referenced by your LLM agent/editor.
- **Human-in-the-loop gates**: The process pauses and asks the user for missing
  info at **two stages only**: Product Requirements Document and Architecture.
- Everything is **stack-agnostic**. The LLM should ask the user for frameworks/languages
  appropriate for the project requirements and constraints.

## How to use with Cursor / your LLM

1. Start with `00_PRD.md`. Paste your high-level idea/prompt where indicated and
   run the instructions.
2. If the LLM needs additional info, it must ask questions **only** at PRD and
   Architecture steps, per the prompts.
3. Proceed to the next file in numeric order. Each step reads **previous
   artifacts** from disk if available (or the chat buffer), and produces new
   artifacts in Markdown/YAML/Mermaid.
4. You can re-run any step; outputs are **idempotent** and instruct the LLM to
   append under a `## Regenerated on YYYY-MM-DD` section rather than overwrite
   manual edits.

## Directory map

- `00_PRD.md` → Prompt → Product Requirements Document (PRD)
- `01_NFRS.md` → Non-Functional Requirements (NFRs) / Quality Attributes
- `02_ARCHITECTURE.md` → Architecture analysis + Mermaid + Architecture Decision Records (ADRs) suggestions
  (**Gate #2**)
- `02A_ARCH_GATE_QUESTIONS.md` → Explicit questions to ask at the architecture
  gate
- `03_ADR_FACTORY.md` → Turn suggestions into concrete ADRs
- `04_DOMAIN_DECOMPOSITION.md` → Bounded contexts + charters
- `05_CONTRACTS.md` → API/Event/Schema contracts (consumer-driven)
- `06_THREAT_MODEL.md` → STRIDE/LINDDUN, data classification
- `07_TEST_PLAN.md` → Acceptance tests, pyramid, golden cases
- `08_TASKS.md` → Tasks per domain/cross-cutting
- `09_SCAFFOLDING_DEVEX.md` → Repo structure guidance (language-agnostic)
- `10_IMPLEMENTATION_AGENT.md` → SOLID, GoF, DDD, hexagonal; composition-first
- `11_STATIC_ANALYSIS.md` → Linters, SAST, SBOM, secrets, licenses
- `12_OBSERVABILITY_SLOS.md` → Telemetry, Service Level Objectives (SLOs), dashboards, runbooks
- `13_DELIVERY_ROLLOUT.md` → Feature flags, canary, rollback
- `14_DOCS_PORTAL.md` → Living docs / developer portal
- `15_POST_RELEASE.md` → Telemetry review, error budgets, iterate/optimize

Common templates & checklists live under `COMMON/`.
