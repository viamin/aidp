# aidp init — Project Bootstrapping

`aidp init` scans the current repository and produces a set of baseline
documents that prepare the codebase for autonomous work loops.

```bash
aidp init
```

## What the command does

1. **Analyze project structure**
   - Detects languages, frameworks, key directories, and repository statistics.
   - Enumerates configuration files and testing frameworks.
   - Documents available quality tooling (linters, formatters, static analyzers).

2. **Generate foundational documents**
   - `docs/LLM_STYLE_GUIDE.md`: project-aware guidance derived from the
     `planning/generate_llm_style_guide.md` template.
   - `docs/PROJECT_ANALYSIS.md`: structural snapshot, language breakdown, and
     repository metrics inspired by `analysis/analyze_repository.md`.
   - `docs/CODE_QUALITY_PLAN.md`: quality roadmap, including the detected
     toolchain and recommended actions.

3. **Collect preferences**
   - Optionally adopt stricter conventions, enforce linting upgrades, or plan
     migrations to the new style guide. Preferences are baked into the generated
     plan so future work loops inherit the decisions.

4. **Prepare for autonomous loops**
   - Ensures style guidance lives in `docs/` where work loops automatically look
     for it.
   - Highlights quality tooling so fix-forward loops can run linters and tests
     consistently.

## Customizing the output

- Re-run `aidp init` after major refactors to refresh documentation.
- Edit any of the generated files directly—subsequent runs will overwrite them,
  so check the diff into version control.
- When adding new linters or frameworks, append notes to
  `docs/PROJECT_ANALYSIS.md` so the automation stays aligned with the latest
  tooling.
- Use the [Setup Wizard](SETUP_WIZARD.md) to keep `.aidp/aidp.yml` in sync with
  the conventions discovered by `aidp init` (tests, lint commands, guards, etc.).
- After the first run, review `harness.work_loop.units` to register deterministic
  commands (full test suites, lint passes, or wait strategies) so future loops
  can pivot between tooling and agentic work automatically.

## Relationship to Work Loops

The generated documents are used by the fix-forward work loop engine as shared
context. See [Work Loops Guide](WORK_LOOPS_GUIDE.md) (Pre-Loop Setup) for how
the style guide and analysis docs are consumed by subsequent automation.
