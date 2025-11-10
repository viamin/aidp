# Follow-up Opportunities

This document tracks potential future enhancements and refactors identified during recent provider configuration and wizard improvements. These are not scheduled immediately but can be pulled into upcoming work streams.

## Provider & Wizard Enhancements

- [x] Summary table of configured providers (primary + fallbacks) before save, with billing type and model family.
- [x] Validation warning for duplicate fallback providers with identical billing/model characteristics (redundancy detection).
- [x] Ability to remove (delete) a provider configuration from the edit loop.
- [x] Real-time provider metrics tracking (LastUsed, token usage, rate-limit reset times) (#242)
- [x] Persist provider metrics to disk for dashboard visibility across CLI invocations (#242)
- [x] Extract rate-limit reset times from provider error messages (especially Claude) (#242)
- [ ] Reorder fallback providers interactively to express priority.
- [ ] Persist provider priority metadata for advanced fallback heuristics.
- [x] Add guard against selecting a primary provider also listed as a fallback (auto-remove or prevent).
- [ ] Expand model family list (e.g., gemini, llama, deepseek) with descriptions.
- [ ] Introduce provider capability hints (reasoning, coding, long-context) displayed during selection.
- [ ] Provide an optional "quick setup" path that skips advanced provider editing questions.
- [ ] Add environment variable hinting for each provider (auto-generate export commands in next steps).

## Test Infrastructure

- [ ] Helper factory for common provider selection sequences using `TestPrompt` (reducing duplicated response maps).
- [ ] Negative specs: no fallbacks selected, editing declined, additional fallback loop exercised.
- [ ] Spec covering removal of a provider (delete feature now exists).
- [ ] Property-based test (e.g., generating random provider lists) to ensure normalization and ordering stability.
- [ ] Snapshot test of YAML output for complex multi-provider configuration.

## Prompt / UX Improvements

- [ ] Colorize key wizard sections consistently (providers, work loop, logging) with standardized palette.
- [ ] Contextual help toggle (press 'h') to show inline tips for current step.
- [ ] Accessibility review: ensure prompts can be navigated with minimal cognitive load.
- [ ] Internationalization readiness: extract user-facing strings for future i18n.

## Configuration & Normalization

- [x] Centralize provider metadata (billing types, model families) in a single registry module.
- [ ] Add migration utility to upgrade older config versions (schema_version checks beyond v1).
- [ ] Detect and auto-correct inconsistent capitalization in stored model family values.
- [ ] Introduce config validation command (`aidp config --validate`) to list warnings without running wizard.

## Performance / Internal

- [ ] Cache discovered providers across wizard invocations within a session.
- [ ] Parallelize provider capability probing (if introspection added).
- [ ] Lazy-load provider metadata only when editing loop entered.

## Code TODOs

- [ ] Add default selection back to wizard once TTY-Prompt default validation issue is resolved ([lib/aidp/setup/wizard.rb:143](lib/aidp/setup/wizard.rb#L143))
- [ ] Integrate error handler with actual provider execution ([lib/aidp/harness/error_handler.rb:429](lib/aidp/harness/error_handler.rb#L429))
- [ ] Implement actual AST analysis for seam detection ([lib/aidp/analyze/seams.rb:139](lib/aidp/analyze/seams.rb#L139))
- [ ] Implement interactive confirmation via REPL for guard policy in work loop ([lib/aidp/execute/work_loop_runner.rb](lib/aidp/execute/work_loop_runner.rb))
- [ ] Enhance WorkLoopRunner to accept iteration callbacks for async monitoring ([lib/aidp/execute/async_work_loop_runner.rb:168](lib/aidp/execute/async_work_loop_runner.rb#L168))

## Documentation

- [ ] Add `CONFIGURATION_PROVIDER_GUIDE.md` explaining billing types and model families.
- [ ] Update `CONTRIBUTING.md` with guidance on using `TestPrompt` for interactive specs.
- [ ] Record a troubleshooting section for common wizard issues (missing provider, unexpected defaults).

## CLI & Integration

- [ ] Add non-interactive flags to configure providers directly (e.g., `--provider cursor --fallback github_copilot`).
- [ ] Support exporting current provider setup as JSON for external tooling.
- [ ] Integrate with an analytics module to track provider switching frequency (for future automated suggestions).

---
Generated on: #{Time.now.utc.iso8601}
