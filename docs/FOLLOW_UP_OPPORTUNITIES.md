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
- [x] Expand model family list (e.g., gemini, llama, deepseek) with descriptions.
- [ ] Introduce provider capability hints (reasoning, coding, long-context) displayed during selection.
- [ ] Provide an optional "quick setup" path that skips advanced provider editing questions.
- [ ] Add environment variable hinting for each provider (auto-generate export commands in next steps).

## Test Infrastructure

- [ ] Helper factory for common provider selection sequences using `TestPrompt` (reducing duplicated response maps).
- [x] Negative specs: no fallbacks selected, editing declined, additional fallback loop exercised.
- [x] Spec covering removal of a provider (delete feature now exists).
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
- [x] Detect and auto-correct inconsistent capitalization in stored model family values.
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

## Tool Configuration Expansion (Issue #150) - MVP Complete, Enhancements Pending

- [ ] Fix /tools REPL command tests (9 failing tests need config fixes in spec/aidp/execute/repl_macros_spec.rb:655-928)
- [ ] Update CONFIGURATION.md with coverage tools section, VCS behavior section, interactive testing section, and model family section
- [ ] Update INTERACTIVE_REPL.md with /tools command reference and examples
- [ ] Work loop integration: Execute coverage commands and parse reports
- [ ] Work loop integration: Execute interactive tests (MCP tools, expect scripts, AppleScript)
- [ ] Work loop integration: Apply VCS behavior (staging, committing, conventional commits)
- [ ] Work loop integration: Use model_family field for provider selection and fallback logic

## Skills System - Complete, Optional Enhancements Available

- [ ] --open-editor option to open skill content in $EDITOR (low priority, TTY::Prompt already provides editor integration)
- [ ] Harness integration for automatic skill selection during workflow execution
- [ ] REPL integration with /skill commands for interactive skill management
- [ ] Init integration to offer skill creation during project setup (aidp init)
- [ ] Tab completion for shell autocompletion of skill commands
- [ ] Telemetry for skill usage tracking (optional, privacy considerations)

## Thinking Depth System - MVP Complete, Advanced Features Pending

### Phase 2: Intelligent Coordinator Integration
- [ ] Implement ComplexityEstimator for task analysis
- [ ] Coordinator tier selection based on complexity estimation
- [ ] Escalation & backoff policy (escalate on N failures, de-escalate on success)
- [ ] Provider switching for tier (switch provider if current doesn't support required tier)

### Phase 3: Advanced Features
- [ ] Per-skill/template tier overrides in configuration
- [ ] Permission modes by tier (safe/tools/dangerous permissions based on tier)
- [ ] Plain language control for tier selection (parse user messages for tier hints)
- [ ] Timeline & evidence pack integration (log tier changes to work_loop.jsonl)

### Testing & Validation
- [ ] Performance benchmarks (latency impact of tier switching)
- [ ] Real-world cost tracking in production usage

## Parallel Workstreams - Core Complete, Polish Pending

### Testing
- [ ] Integration tests for end-to-end parallel execution
- [ ] System tests for resource monitoring and performance benchmarks
- [ ] Failure recovery scenario testing

### Documentation
- [ ] User guide with parallel execution examples
- [ ] Performance tuning guide (optimal concurrency settings)
- [ ] Troubleshooting guide for parallel execution issues
- [ ] Best practices document for parallel workflows

### Future Enhancements
- [ ] Priority queue for workstream scheduling (high/normal/low priorities)
- [ ] Real-time progress dashboard with live status for all running workstreams
- [ ] Dependency management (declare workstream dependencies, automatic ordering)
- [ ] Smart scheduling based on resource requirements and availability

## Zero Framework Cognition (ZFC) - Phase 1 Foundation Complete, Phases 2-4 Pending

### Phase 1 Remaining Items
- [ ] Performance benchmarks for ZFC decision-making latency
- [ ] Real-world cost tracking (requires production deployment with ZFC enabled)

### Phase 2: Decision Logic (Core ZFC)
- [ ] AI-driven provider selection (replace load calculation formula with AI decision)
- [ ] AI-driven tier escalation (replace heuristic thresholds with AI judgment)
- [ ] AI-based workflow routing (replace pattern matching with AI selection)
- [ ] Integration testing for Phase 2 features
- [ ] Documentation updates for AI decision-making

### Phase 3: Quality Judgments (Polish)
- [ ] AI-driven health assessment (replace scoring formula with AI evaluation)
- [ ] AI-based project analysis (replace pattern matching with AI analysis)
- [ ] Testing & refinement for Phase 3 features

### Phase 4: Documentation & Governance
- [ ] Create ZFC_GUIDELINES.md with compliant vs violated pattern examples
- [ ] Update STYLE_GUIDE.md with ZFC section
- [ ] Update LLM_STYLE_GUIDE.md with ZFC section
- [ ] Create scripts/check_zfc_compliance.rb for automated ZFC violation detection
- [ ] Add CI check for ZFC compliance in new PRs
- [ ] Add to pre-commit hooks (optional)

---
Last Updated: 2025-11-11
