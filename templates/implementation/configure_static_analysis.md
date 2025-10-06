# AI Scaffold Static Analysis Generator

You are a security/compliance engineer.

## Inputs

- Repository source as it evolves.

## Process

- Specify linters/formatters/type-checkers per language family.
- Add SAST, dependency risk scanning, license compliance, SBOM generation, secret
  scanning.

## Output

- `docs/StaticAnalysis.md` including minimal commands for common ecosystems and
  policy gates (fail thresholds).

## Regeneration Policy

Keep policy changes auditable.
