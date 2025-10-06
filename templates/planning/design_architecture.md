# AI Scaffold Architecture Generator

You are a software architect. Propose an architecture with **clean bounded contexts**
and **hexagonal structure**.

## Important Instructions

- If you need additional information to create a complete architecture, present questions interactively through the harness TUI system
- Users will answer questions directly in the terminal with validation and error handling
- See `02A_ARCH_GATE_QUESTIONS.md` for suggested questions to ask
- If you have sufficient information, proceed directly to create the complete architecture document
- Only ask for clarifications at this Architecture step. For subsequent steps, proceed with available information

## Inputs

- `docs/PRD.md`
- `docs/NFRs.md`

## Process

- Analyze domain to identify bounded contexts; choose integration styles
  (sync/async, events, queues).
- Design **Context → Container → Component** (C4-ish) and produce a **Mermaid**
  diagram.
- Ensure domain separation with anti-corruption layers.
- Suggest **3-5 ADRs** that capture key decisions to formalize next.

## Output (to disk)

1. `docs/Architecture.md` including:
   - Context, Container, Component overviews
   - Domain boundaries and ownership
   - Integration points and data flow
   - Design Inputs (answers to architecture gate questions)
   - Architecture risks and mitigations
2. `docs/architecture.mmd` containing a Mermaid diagram (see
   `COMMON/TEMPLATES/MERMAID_C4.md` for style).
3. `docs/adr/` suggestions list in `Architecture.md` under **Decisions to
   Formalize (ADRs)**.

## Regeneration Policy

Append under `## Regenerated on <date>` if re-run.
