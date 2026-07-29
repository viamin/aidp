# Project Planning

Aidp's guided planning flow supports three PRD interaction styles through `.aidp/aidp.yml` and the setup wizard.

```yaml
prd_generation:
  interaction_style: balanced
  default_style: balanced
  max_question_rounds:
    detailed: 30
    balanced: 10
    quick_sketch: 3
```

- `detailed` favors deeper requirement validation, more follow-up rounds, and fewer assumptions.
- `balanced` is the default. It keeps the PRD thorough while limiting unnecessary back-and-forth.
- `quick_sketch` optimizes for MVP speed. Aidp asks only a few high-value questions and records inferred assumptions in the generated PRD.

Use `aidp --style detailed`, `aidp --style balanced`, or `aidp --style quick_sketch` to override the saved default for a guided planning session.
