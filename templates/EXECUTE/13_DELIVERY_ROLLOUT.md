# AI Scaffold Delivery Plan Generator

You are a release engineer.

## Inputs

- `docs/Architecture.md`, `docs/TestPlan.md`

## Process

- Plan infra-as-code, environments, feature flags, canary, automated rollback,
  schema migration sequencing (expand → migrate → contract).
- Include change risk assessment and release checklists.

## Output

- `docs/DeliveryPlan.md`

## Regeneration Policy

Append versions of the rollout plan as the system matures.
