# AIDP LLM Style Cheat Sheet

> Ultra‑concise rules for automated coding agents. Use this as the *source of truth* for generation. For nuance or rationale, see `STYLE_GUIDE.md`.

## 1. Core Engineering Rules

- Small objects, clear roles. Avoid god classes. `STYLE_GUIDE:18-50`
- Methods: do one thing; extract early. `STYLE_GUIDE:108-117`
- Prefer composition over inheritance. `STYLE_GUIDE:97-106`
- No commented‑out or dead code. `STYLE_GUIDE:18-50`
- No introducing TODO without issue reference. `STYLE_GUIDE:1422-1448`
- When removing code, delete it cleanly without explanatory comments. `STYLE_GUIDE:1422-1448`
- **CRITICAL: Use `Aidp.log_debug()` extensively** to instrument important code paths (see Section 4). `STYLE_GUIDE:125-283`
- **NO backward compatibility code**: AIDP is pre-release (v0.x.x) - remove deprecated features immediately. `STYLE_GUIDE:2051-2090`

### Sandi Metz Guidelines

- Classes ~100 lines; Methods ~5 lines; Max 4 parameters. `STYLE_GUIDE:51-96`
- **These are guidelines, not hard limits** - exceptions allowed when appropriate (complex algorithms, data structures).
- Break rules consciously when needed, but consider refactoring first.

## 2. Zero Framework Cognition (ZFC)

**Rule**: Meaning/decisions → AI. Mechanical/structural → code. `STYLE_GUIDE:338-635`

**FORBIDDEN** (use `AIDecisionEngine.decide(...)` instead):

- Regex for semantic analysis
- Scoring formulas
- Heuristic thresholds
- Keyword matching

**Always**: Use `mini` tier • Define schemas • Cache • Feature flags • Mock in tests

See [STYLE_GUIDE.md](STYLE_GUIDE.md#zero-framework-cognition-zfc) for pattern examples. `STYLE_GUIDE:338-635`

## 3. Naming & Structure

- Classes: `PascalCase`; methods/files: `snake_case`; constants: `SCREAMING_SNAKE_CASE`. `STYLE_GUIDE:44-50`
- Keep public APIs intention‑revealing (avoid abbreviations unless ubiquitous). `STYLE_GUIDE:44-50`
- One responsibility per file when practical. `STYLE_GUIDE:29-43`
- **Ruby Method Naming**: Avoid `get_*`/`set_*` prefixes - use `name`/`name=` instead. `STYLE_GUIDE:108-117`
- **Requires**: Prefer `require_relative` over `require` for local files. `STYLE_GUIDE:99-107`
- **Feature Organization**: Organize by PURPOSE (parsers/, generators/, mappers/), NOT by workflow (waterfall/, agile/). Workflows are process containers that sequence generic steps. `STYLE_GUIDE:57-115`

## 4. Parameters & Data

- Max ~4 params; use keyword args or an options hash beyond that. `STYLE_GUIDE:69-75`
- Avoid boolean flag parameters that branch behavior; split methods. `STYLE_GUIDE:108-117`

## 5. Error Handling & Logging

- Raise specific errors; never silently rescue. `STYLE_GUIDE:118-124,1262-1318`
- Let internal logic errors surface (fail fast). `STYLE_GUIDE:1262-1318`
- Only rescue to: wrap external failures, add context, clean up resources. `STYLE_GUIDE:118-124`
- No `rescue Exception`; prefer `rescue SpecificError`. `STYLE_GUIDE:1262-1318,1534-1548`
- **Always log rescued errors**: `Aidp.log_error("component", "msg", error: e.message)` `STYLE_GUIDE:125-283`

### Logging (CRITICAL)

**Instrument all important code paths with `Aidp.log_debug()`** `STYLE_GUIDE:125-283`

- Use: `Aidp.log_{debug|info|warn|error}("component", "verb", key: val)`
- **When**: Method entries, state changes, external calls, decisions
- **Include**: IDs/slugs, counts, statuses, filenames
- **Avoid**: Secrets, full payloads, tight loops
- **Style**: Present tense verbs, metadata hash, consistent component names

## 6. TTY / TUI

- Always use TTY Toolkit components (prompt, progressbar, spinner, table). `STYLE_GUIDE:636-964`
- Never re‑implement progress bars, selectors, or tables. `STYLE_GUIDE:636-964`
- **Never use `puts`, `print`, or `$stdout.puts`** - use `prompt.say()` instead. `STYLE_GUIDE:681-746`

### TTY Component Quick Reference

| Use Case | Component | Example |
|----------|-----------|---------|
| Single selection | `prompt.select` | Mode selection, file picking |
| Multi-selection | `prompt.multi_select` | Template selection, feature flags |
| Text input | `prompt.ask` | Project name, API keys |
| Confirmation | `prompt.yes?` | Destructive operations |
| Progress | `TTY::ProgressBar` | File processing, API calls |
| Spinner | `TTY::Spinner` | Loading states |
| Tables | `TTY::Table` | Results display, status reports |

*Full component reference: `STYLE_GUIDE:636-964`*

## 7. Testing Contracts

- Test public behavior; don't mock private methods. `STYLE_GUIDE:1022-1261`
- Mock ONLY external boundaries (network, filesystem, user input, APIs). `STYLE_GUIDE:1022-1261`
- Keep failing regressions visible — do **not** mark pending. `STYLE_GUIDE:965-1021`
- **NEVER put mock methods in production code** - use dependency injection. `STYLE_GUIDE:1022-1261`
- **Test Descriptions**: Clear, behavior-focused titles. `STYLE_GUIDE:1022-1261`
- One spec file per class; use `context` blocks for variations. `STYLE_GUIDE:1022-1261`

### Interactive & External Service Testing

- **Use constructor dependency injection**: `def initialize(prompt: TTY::Prompt.new)` `STYLE_GUIDE:747-870`
- Create test doubles with same interface as real dependencies
- Use shared test utilities (e.g., `TestPrompt` in `spec/support/`)

### Integration Testing with expect Scripts

- **Use expect scripts** for TUI flows (AI agents can't test interactively). `STYLE_GUIDE:871-964`
- Pattern: `spawn`, `expect "text"`, `send "\r"`, `expect eof`

### Testing with tmux

- **Use tmux for TUI testing**: Capture and verify terminal output programmatically. `STYLE_GUIDE:982-1150`
- **Batch send-keys commands**: Reduce overhead by combining multiple commands with backslash continuation.
- **Long-running processes**: Use tmux sessions for servers/daemons to enable easy interaction and cleanup.
- **Pattern**: `tmux new-session -d -s name`, `tmux send-keys -t name "cmd" Enter`, `tmux capture-pane -t name -p`
- **Always cleanup**: Use `after` hooks or ensure blocks with `tmux kill-session`.

### Testing Rules (Sandi Metz)

- **Test incoming queries**: Assert what they return. `STYLE_GUIDE:1022-1261`
- **Test incoming commands**: Assert direct public side effects. `STYLE_GUIDE:1022-1261`
- **Don't test**: Private methods, outgoing queries, implementation details. `STYLE_GUIDE:1022-1261`
- **Mock strategy**: Command messages → mock; Query messages → stub. `STYLE_GUIDE:1022-1261`

### Pending Specs Policy (Strict)

| Case | Allowed? | Notes |
|------|----------|-------|
| Regression (was green) | ❌ | Fix or remove feature |
| Planned future work | ✅ | Must include reason + issue ref |
| Spike / prototype | ✅ | Temporary; track issue |
| Flaky external dependency | ⚠️ | Issue + retry/backoff plan |

Every `pending` MUST have: short reason + tracking reference. `STYLE_GUIDE:965-1021`

## 8. Test Coverage Patterns

- Target 85%+ coverage for business logic; accept lower for untestable code (forked processes, exec calls). `STYLE_GUIDE:1335-1600`
- **Time-based tests**: Stub `Time.now` instead of `sleep` (avoid flaky tests). `STYLE_GUIDE:1442-1503`
- **Private methods**: Test with `send(:method)` when complex logic needs coverage. `STYLE_GUIDE:1392-1414`
- **Forked processes**: Test orchestration/metadata, not child internals; accept lower coverage. `STYLE_GUIDE:1504-1565`
- **String encoding**: Explicitly convert to UTF-8 before regex/string operations. `STYLE_GUIDE:1566-1600`

## 9. Concurrency & Threads

- Join or stop threads in `ensure` / cleanup. `STYLE_GUIDE:1689-1724`
- Avoid global mutable state without synchronization. `STYLE_GUIDE:1689-1724`
- Keep intervals & sleeps configurable for tests. `STYLE_GUIDE:1689-1724`

## 10. Performance

- Avoid O(n^2) over large codebases (batch I/O, stream where possible). `STYLE_GUIDE:1355-1381`
- Cache repeated expensive parsing (e.g., tree-sitter results) via existing cache utilities. `STYLE_GUIDE:1355-1381`

## 11. Progress / Status Output

- UI rendering logic separated from business logic. `STYLE_GUIDE:636-964`
- Inject I/O (stdout/prompt) for testability. `STYLE_GUIDE:747-870`

## 12. Security & Safety

- Never execute untrusted code. `STYLE_GUIDE:1382-1421`
- Validate file paths; avoid shell interpolation without sanitization. `STYLE_GUIDE:1382-1421`
- Don't leak secrets into logs. `STYLE_GUIDE:272-283,1382-1421`

## 13. Implementation Do / Don't

`STYLE_GUIDE:18-50,108-117,1262-1318`

| Do | Don't |
|----|-------|
| Extract small PORO service objects | Add conditionals in core loops |
| Use keyword args | Pass long ordered arg lists |
| Explicit error classes | Generic RuntimeError |

## 14. Quick Review Checklist

`STYLE_GUIDE:603-635,1458-1468`

- [ ] Single responsibility kept
- [ ] Tests updated / added
- [ ] No broad rescues
- [ ] TTY components used
- [ ] StandardRB clean

## 15. Error Class Pattern

Use custom exception classes. `STYLE_GUIDE:1277-1318,1534-1548`

## 16. Anti‑Patterns (Reject in PRs)

`STYLE_GUIDE:393-402,2029-2090`

- Pending regressions
- Custom ANSI/cursor code
- God methods
- Hidden sleeps/timeouts
- Silent exceptions
- Mock methods in production code
- Backward compatibility wrappers or "legacy" methods
- Deprecated features without immediate removal plan

## 17. Ruby Version Management

- **ALWAYS use mise** for Ruby version management in this project `STYLE_GUIDE:284-337`
- Commands running Ruby or Bundler MUST use `mise exec` to ensure correct versions `STYLE_GUIDE:290-304`
- Examples: `mise exec -- ruby script.rb`, `mise exec -- bundle install`, `mise exec -- bundle exec rspec`
- Never use system Ruby directly - always go through mise `STYLE_GUIDE:284-337`

## 18. Commit Hygiene

- One logical change per commit (or tightly coupled set) `STYLE_GUIDE:1422-1448`
- Include rationale when refactoring behavior `STYLE_GUIDE:1422-1448`
- Reference issue IDs for non-trivial changes `STYLE_GUIDE:1422-1448`

## 19. Task Filing

**Signal**: `File task: "description" priority: high tags: tag1,tag2` `STYLE_GUIDE:1802-1900`

File discovered sub-tasks, tech debt, or future work. Tasks persist in `.aidp/tasklist.jsonl`. See [STYLE_GUIDE.md](STYLE_GUIDE.md#persistent-tasklist-cross-session-task-tracking) for details. `STYLE_GUIDE:1802-1900`

## 20. Prompt Optimization

AIDP uses intelligent fragment selection - you may not see this entire guide in your prompts. The AI selects only relevant sections based on your current task. Use `/prompt explain` to see what was selected. See `STYLE_GUIDE.md` for details on writing fragment-friendly documentation. `STYLE_GUIDE:1469-1490`

---
**Use this cheat sheet for generation; consult `STYLE_GUIDE.md` when context or rationale is needed.**
