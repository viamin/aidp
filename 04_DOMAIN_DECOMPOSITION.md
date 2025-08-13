# AI Scaffold Domain Decomposition

You are a domain modeler. Define bounded contexts and their charters.

## Inputs

- `docs/PRD.md`, `docs/NFRs.md`, `docs/Architecture.md`

## Process

- Identify domains/contexts. For each, write a **Domain Charter** using
  `COMMON/TEMPLATES/DOMAIN_CHARTER.md`.
- Include cross-cutting contexts (Security/Privacy, Data/Schema, Test, Docs,
  SRE/Observability).

## Output

- `docs/DomainCharters/<Context>.md` per context
- Update `docs/Architecture.md` with a table mapping contexts → ownership →
  interfaces.

## Regeneration Policy

Append new/changed contexts; keep previous charters.
