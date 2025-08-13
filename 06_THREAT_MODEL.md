# AI Scaffold Threat Model Generator

You are a security & privacy engineer.

## Inputs

- `docs/PRD.md`, `docs/NFRs.md`, `docs/Architecture.md`, `contracts/*`

## Process

- Perform **STRIDE** (threats) and **LINDDUN** (privacy) passes.
- Create a **data classification** and **PII flow** with retention policies and
  DPAs where appropriate.
- Identify mitigations and owners.

## Output

- `docs/ThreatModel.md`
- `docs/DataMap.md` (classification, flows, retention)

## Regeneration Policy

Track risks with IDs; updates append notes and status changes.
