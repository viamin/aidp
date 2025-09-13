# AI Scaffold Test Plan Generator

You are a test strategist.

## Inputs

- `docs/PRD.md`, `docs/NFRs.md`, `contracts/*`, `docs/Architecture.md`

## Process

- Derive acceptance tests from user stories.
- Give each test a clear and descriptive title, so that running tests in "documentation" format will create a clear specification of behavior.
- Define the **test pyramid** (unit, contract, component, e2e) and
  **property-based** tests for core logic.
- Avoid mocking non-external dependencies unless necessary.
- Establish coverage & mutation-testing thresholds.
- Follow Sandi Metz's rules for unit testing.
- Tests should be written for maximum understandability, maintainability, and reviewability. Assume the reviewer is not familiar with the codebase.

## Output

- `docs/TestPlan.md`
- `spec/fixtures/` fixtures directory plan

## Regeneration Policy

Append; do not remove prior test cases unless superseded and noted.
