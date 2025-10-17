# AIDP LLM Style Cheat Sheet

> Ultra‑concise rules for automated coding agents. Use this as the *source of truth* for generation. For nuance or rationale, see `STYLE_GUIDE.md`.

## 1. Core Engineering Rules

- Small objects, clear roles. Avoid god classes.
- Methods: do one thing; extract early.
- Prefer composition over inheritance.
- No commented‑out or dead code.
- No introducing TODO without issue reference.
- When removing code, delete it cleanly without explanatory comments.
- **CRITICAL: Use `Aidp.log_debug()` extensively** to instrument important code paths (see Section 4).

### Sandi Metz Guidelines

- Classes ~100 lines; Methods ~5 lines; Max 4 parameters.
- **These are guidelines, not hard limits** - exceptions allowed when appropriate (complex algorithms, data structures).
- Break rules consciously when needed, but consider refactoring first.

## 2. Naming & Structure

- Classes: `PascalCase`; methods/files: `snake_case`; constants: `SCREAMING_SNAKE_CASE`.
- Keep public APIs intention‑revealing (avoid abbreviations unless ubiquitous).
- One responsibility per file when practical.
- **Ruby Method Naming**: Avoid `get_*` and `set_*` prefixes - use Ruby's idiomatic style:
  - ❌ `get_name`, `set_name(value)`
  - ✅ `name`, `name=(value)` or `name(value)`
  - ❌ `get_provider_config`, `get_status`
  - ✅ `provider_config`, `status`
- **Requires**: Prefer `require_relative` over `require` for local files.

## 3. Parameters & Data

- Max ~4 params; use keyword args or an options hash beyond that.
- Avoid boolean flag parameters that branch behavior; split methods.

## 4. Error Handling & Logging

- Raise specific errors; never silently rescue.
- Let internal logic errors surface (fail fast).
- Only rescue to: wrap external failures, add context, clean up resources.
- No `rescue Exception`; prefer `rescue SpecificError`.
- **Always log rescued errors**: `Aidp.log_error("component", "msg", error: e.message)`

### Logging (CRITICAL)

**Instrument all important code paths with `Aidp.log_debug()` for readable traces.**

```ruby
# Log: method entries, state changes, external calls, decisions
Aidp.log_debug("component", "Action verb", key: value, id: id)
Aidp.log_info("component", "Completed", result: status)
Aidp.log_warn("component", "Degraded", error: e.message)
Aidp.log_error("component", "Failed", error: e.message)
```

**When to log:** Method entries, state transitions, external API calls, file ops, decision points, loop iterations (w/ identifiers).

**Include:** IDs/slugs, counts, statuses, filenames. **Avoid:** Secrets (auto-redacted), full payloads, tight loops.

**Style:** Present tense verbs ("Executing"), metadata hash (not interpolation), consistent component names.

## 5. TTY / TUI

- Always use TTY Toolkit components (prompt, progressbar, spinner, table).
- Never re‑implement progress bars, selectors, or tables.
- **Never use `puts`, `print`, or `$stdout.puts`** - use `prompt.say()` instead.

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

## 6. Testing Contracts

- Test public behavior; don't mock internal private methods.
- Mock ONLY external boundaries (network, filesystem, user input, provider APIs).
- Keep failing regressions visible — do **not** mark them pending.
- **NEVER put mock methods in production code** - use dependency injection instead.
- **Test Descriptions**: Use clear, behavior-focused titles (e.g., "enqueues email after validation", not "works").

### Interactive & External Service Testing

- **Use constructor dependency injection** for TTY::Prompt, HTTP clients, file I/O.
- **Pattern**: `def initialize(prompt: TTY::Prompt.new)` → inject test doubles in specs.
- **Create test doubles** that implement the same interface as real dependencies.
- **Shared test utilities** for common mocks (e.g., `TestPrompt` in `spec/support/`).

### Integration Testing with expect Scripts

- **AI agents cannot** test by running `bundle exec aidp` (requires live user interaction).
- **Use expect scripts** for integration testing of interactive TUI flows.
- **Example**: `spawn bundle exec aidp`, `expect "Choose mode"`, `send "\r"`, `expect eof`.
- See STYLE_GUIDE.md for detailed expect script patterns and examples.

### Testing Rules (Sandi Metz)

- **Test incoming queries**: Assert what they return.
- **Test incoming commands**: Assert direct public side effects.
- **Don't test**: Private methods, outgoing queries, implementation details.
- **Mock strategy**: Command messages → mock; Query messages → stub.

### Pending Specs Policy (Strict)

| Case | Allowed? | Notes |
|------|----------|-------|
| Regression (was green) | ❌ | Fix or remove feature |
| Planned future work | ✅ | Must include reason + issue ref |
| Spike / prototype | ✅ | Temporary; track issue |
| Flaky external dependency | ⚠️ | Issue + retry/backoff plan |

Every `pending` MUST have: short reason + tracking reference.

## 7. Concurrency & Threads

- Join or stop threads in `ensure` / cleanup.
- Avoid global mutable state without synchronization.
- Keep intervals & sleeps configurable for tests.

## 8. Performance

- Avoid O(n^2) over large codebases (batch I/O, stream where possible).
- Cache repeated expensive parsing (e.g., tree-sitter results) via existing cache utilities.

## 9. Progress / Status Output

- UI rendering logic separated from business logic.
- Inject I/O (stdout/prompt) for testability.

## 10. Security & Safety

- Never execute untrusted code.
- Validate file paths; avoid shell interpolation without sanitization.
- Don’t leak secrets into logs.

## 11. Implementation Do / Don’t

| Do | Don’t |
|----|-------|
| Extract small PORO service objects | Add conditionals everywhere in core loops |
| Use keyword args for clarity | Pass long ordered arg lists |
| Use symbols for internal states | Use magic strings inline |
| Provide explicit error classes | Raise generic RuntimeError silently |
| Log context (ids, counts) | Log giant raw payloads |

## 12. Quick Review Checklist

- [ ] Single responsibility kept
- [ ] Public API clear & documented inline
- [ ] No broad rescues or hidden failures
- [ ] Tests updated / added
- [ ] Pending specs policy respected
- [ ] TTY components (no custom terminal hacks)
- [ ] Style: StandardRB clean

## 13. Error Class Pattern

```ruby
module Aidp
  module Errors
    class ConfigurationError < StandardError; end
    class ProviderError      < StandardError; end
    class ValidationError    < StandardError; end
    class StateError         < StandardError; end
    class UserError          < StandardError; end
  end
end
```

## 14. Anti‑Patterns (Reject in PRs)

- Pending or skipped *regressions*
- Copy/paste ANSI / cursor escape spaghetti
- Mega-methods controlling flow + formatting + persistence
- Hidden sleeps / magic timeouts
- Silent swallowed exceptions
- **Mock methods in production code** (use dependency injection instead)

## 15. Ruby Version Management

- **ALWAYS use mise** for Ruby version management in this project
- Commands running Ruby or Bundler MUST use `mise exec` to ensure correct versions
- Examples: `mise exec -- ruby script.rb`, `mise exec -- bundle install`, `mise exec -- bundle exec rspec`
- Never use system Ruby directly - always go through mise

## 16. Commit Hygiene

- One logical change per commit (or tightly coupled set)
- Include rationale when refactoring behavior
- Reference issue IDs for non-trivial changes

---
**Use this cheat sheet for generation; consult `STYLE_GUIDE.md` when context or rationale is needed.**
