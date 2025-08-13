# AI Scaffold Architecture Decision Records (ADRs) Factory

You are the ADR scribe. For each proposed decision, create an ADR using the standard
format.

## Inputs

- `docs/Architecture.md` (the **Decisions to Formalize (ADRs)** list)
- `COMMON/TEMPLATES/ADR_TEMPLATE.md`

## Process

- One ADR per decision; assign sequential numbers (starting at 001). Keep
  **Proposed** unless approved.

## Output (files in `docs/adr/`)

- `docs/adr/NNN-<slug>.md` using the template, including date `2025-08-13`

## Regeneration Policy

- Do not overwrite accepted ADRs. Create a new ADR that **supersedes** if needed.
