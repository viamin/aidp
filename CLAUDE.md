# Guide for Claude and AI Assistants

Welcome! This document provides essential context for AI assistants (Claude, GPT, Gemini, etc.) working on the AIDP (AI Dev Pipeline) project.

## 🎯 Most Important: READ THE LLM_STYLE_GUIDE FIRST

**Before making ANY code changes, you MUST read and follow [`docs/LLM_STYLE_GUIDE.md`](docs/LLM_STYLE_GUIDE.md).**

The LLM_STYLE_GUIDE is your primary reference - it contains ultra-concise rules specifically designed for automated coding agents. It covers:

- Core engineering principles (small objects, single responsibility)
- Zero Framework Cognition (ZFC) - when to use AI vs. code
- Naming conventions and structure
- Error handling and logging (CRITICAL: use `Aidp.log_debug()` extensively)
- TTY/TUI component usage (NEVER use `puts`, use `prompt.say()` instead)
- Testing contracts and patterns
- Security and safety guidelines

**Every rule in LLM_STYLE_GUIDE.md includes references to the full STYLE_GUIDE.md for detailed context.**

## About AIDP

AIDP is a portable CLI that automates AI development workflows from idea to implementation. It features:

- **Work Loops** - Iterative execution with automatic validation
- **Background Jobs** - Async workflow execution
- **Devcontainer Support** - Sandboxed AI agent environments
- **Multiple AI Providers** - Claude, Cursor, Gemini, GitHub Copilot, Kilocode, etc.
- **Workstreams** - Parallel task execution with git worktrees
- **Watch Mode** - Automated GitHub issue monitoring and resolution

## Documentation Structure

```text
├── README.md                          # Main project documentation
├── CLAUDE.md                          # This file - AI assistant guide
├── docs/
│   ├── LLM_STYLE_GUIDE.md            # ⭐ PRIMARY REFERENCE for AI agents
│   ├── STYLE_GUIDE.md                # Comprehensive style guide (73KB)
│   ├── README.md                     # Documentation index
│   ├── CLI_USER_GUIDE.md             # Complete CLI reference
│   ├── WORK_LOOPS_GUIDE.md           # Iterative workflow details
│   ├── CONFIGURATION.md              # Configuration reference
│   └── [40+ other documentation files]
```

## Quick Start for AI Assistants

1. **Read [`docs/LLM_STYLE_GUIDE.md`](docs/LLM_STYLE_GUIDE.md)** - Your primary coding reference
2. **Check [`README.md`](README.md)** - Understand project features and architecture
3. **Review [`docs/README.md`](docs/README.md)** - Find relevant documentation for your task
4. **Consult [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md)** - When you need detailed rationale or context

## Key Principles for AI Assistants

### 1. Follow the LLM_STYLE_GUIDE Religiously

Every code generation must adhere to the rules in [`docs/LLM_STYLE_GUIDE.md`](docs/LLM_STYLE_GUIDE.md). This includes:

- Using `Aidp.log_debug()` to instrument code paths
- Using TTY components instead of `puts` or `print`
- Following Sandi Metz guidelines (small classes, small methods)
- Implementing Zero Framework Cognition (ZFC) for semantic decisions
- Proper error handling with specific exceptions
- Testing external boundaries only

### 2. Understand the Ruby Environment

- **Always use `mise`** for Ruby version management
- Commands must use `mise exec -- ruby script.rb` or `mise exec -- bundle exec rspec`
- Never use system Ruby directly

### 3. Testing Philosophy

- Mock ONLY external boundaries (network, filesystem, user input, APIs)
- **NEVER put mock methods in production code** - use dependency injection
- Use `expect` scripts for TUI flows
- Use `tmux` for TUI testing with programmatic verification
- Keep failing regressions visible - do NOT mark pending without issue reference

### 4. Code Organization

- Small objects with clear roles (no god classes)
- Methods do one thing (~5 lines guideline)
- Max ~4 parameters (use keyword args beyond that)
- One responsibility per file when practical
- Prefer composition over inheritance

### 5. Zero Framework Cognition (ZFC)

**FORBIDDEN** (use `AIDecisionEngine.decide(...)` instead):

- Regex for semantic analysis
- Scoring formulas
- Heuristic thresholds
- Keyword matching

Meaning and decisions go to AI. Mechanical and structural tasks go to code.

### 5a. AI-Generated Determinism (AGD)

When AI should run **once during configuration** to generate deterministic code:

- Use for stable input formats (test/lint output)
- AI generates patterns/rules stored in config
- Runtime execution is deterministic (no AI calls)
- Example: `AIFilterFactory` generates `FilterDefinition` during setup

See [`docs/AI_GENERATED_DETERMINISM.md`](docs/AI_GENERATED_DETERMINISM.md) for the full pattern.

### 6. Logging (CRITICAL)

**Instrument ALL important code paths with `Aidp.log_debug()`**

```ruby
Aidp.log_debug("component_name", "action_verb", key: value, id: id)
```

Log at:

- Method entries
- State changes
- External calls
- Decisions
- Error conditions

### 7. TTY Component Usage

**NEVER use `puts`, `print`, or `$stdout.puts`** - use TTY components:

- Single selection: `prompt.select`
- Multi-selection: `prompt.multi_select`
- Text input: `prompt.ask`
- Confirmation: `prompt.yes?`
- Progress: `TTY::ProgressBar`
- Spinner: `TTY::Spinner`
- Tables: `TTY::Table`
- Output: `prompt.say()`

## Common Tasks Reference

### Running Tests

```bash
mise exec -- bundle exec rspec
mise exec -- bundle exec rspec spec/specific_spec.rb
```

### Running Linter

```bash
mise exec -- bundle exec standardrb
mise exec -- bundle exec standardrb --fix
```

### Running AIDP

```bash
mise exec -- bundle exec aidp
mise exec -- bundle exec aidp --help
```

### Development Container

This repository includes devcontainer support for sandboxed development:

```bash
# Open in VS Code
code .
# Press F1 → "Dev Containers: Reopen in Container"
```

## Finding Information

When you need to understand a specific area:

1. Check [`docs/README.md`](docs/README.md) for the documentation index
2. Use the Quick Links at the bottom of docs/README.md
3. Search for relevant markdown files in `docs/`
4. Reference the implementation in `lib/aidp/`

### Key Documentation Files

| Topic | File |
| ----- | ---- |
| CLI Commands | `docs/CLI_USER_GUIDE.md` |
| Work Loops | `docs/WORK_LOOPS_GUIDE.md` |
| Configuration | `docs/CONFIGURATION.md` |
| Devcontainers | `docs/DEVELOPMENT_CONTAINER.md` |
| Testing | `docs/LLM_STYLE_GUIDE.md` (Section 7) |
| ZFC Pattern | `docs/LLM_STYLE_GUIDE.md` (Section 2) |
| AGD Pattern | `docs/AI_GENERATED_DETERMINISM.md` |

## Anti-Patterns to Avoid

From LLM_STYLE_GUIDE.md, these are explicitly forbidden:

- ❌ Pending regressions without fixes
- ❌ Custom ANSI/cursor code (use TTY components)
- ❌ God methods or classes
- ❌ Hidden sleeps/timeouts (make configurable)
- ❌ Silent exceptions (always log rescued errors)
- ❌ Mock methods in production code (use dependency injection)
- ❌ Using `puts` or `print` (use `prompt.say()`)
- ❌ Regex for semantic analysis (use `AIDecisionEngine`)

## Questions or Unclear Requirements?

If you're uncertain about:

1. **Coding standards** → Check [`docs/LLM_STYLE_GUIDE.md`](docs/LLM_STYLE_GUIDE.md) first
2. **Feature behavior** → Read relevant docs or ask for clarification
3. **Architecture decisions** → Look for existing patterns in `lib/aidp/`
4. **Testing approach** → Review `spec/` for similar tests

## Remember

- **LLM_STYLE_GUIDE.md is your primary reference** - read it before every coding session
- Instrument code with `Aidp.log_debug()` extensively
- Use TTY components for all user interaction
- Follow Sandi Metz guidelines (but break them consciously when needed)
- Test external boundaries only
- Apply Zero Framework Cognition for semantic decisions
- Use `mise exec` for all Ruby commands

---

**Quick Links**: [LLM_STYLE_GUIDE.md](docs/LLM_STYLE_GUIDE.md) | [README.md](README.md) | [STYLE_GUIDE.md](docs/STYLE_GUIDE.md) | [docs/README.md](docs/README.md)
