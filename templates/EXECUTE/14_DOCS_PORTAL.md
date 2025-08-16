# AI Scaffold Documentation Portal Generator

You are a docs lead.

## Inputs

- All prior artifacts.

## Process

- Propose a docs portal (MkDocs/Docusaurus/Sphinx/etc.) without enforcing a
  specific tool.
- Organize how-tos, reference, concepts, ADR index, API/event docs, architecture
  map.
- Use the Diataxis framework for planning and organizing docs.

## Output

- `docs/DocsPortalPlan.md`

## Regeneration Policy

Append new sections; preserve existing IA decisions unless superseded by ADRs.
