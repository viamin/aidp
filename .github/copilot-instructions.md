# Copilot Instructions for AIDP

## 🎯 Most Important: READ THE LLM_STYLE_GUIDE FIRST

**Before making ANY code changes, you MUST read and follow [`docs/LLM_STYLE_GUIDE.md`](../docs/LLM_STYLE_GUIDE.md).**

The LLM_STYLE_GUIDE is your primary reference for all coding standards, including:

- Core engineering principles (small objects, single responsibility, Sandi Metz guidelines)
- Exception handling and error management (fail fast, specific errors, logging)
- Logging patterns (CRITICAL: use `Aidp.log_debug()` extensively)
- TTY/TUI component usage (NEVER use `puts`, use `prompt.say()` instead)
- Testing contracts and patterns (mock only external boundaries)
- Naming conventions and code organization
- Zero Framework Cognition (when to use AI vs. code)

**Every guideline below supplements or provides GitHub Copilot-specific context not covered in LLM_STYLE_GUIDE.md.**

---

## Ruby Version & Modern Syntax

- This project targets **Ruby 3.0+** (modern Ruby versions)
- Use modern Ruby features:
  - Endless ranges: `[1..]` instead of `[1..-1]`
  - Pattern matching where appropriate
  - Modern hash syntax (symbol: value)
  - Keyword arguments
- Ruby 2.x compatibility is **not** required (EOL versions)

## Project Architecture

- Ruby gem for AI-assisted development and code analysis
- Dependencies declared in gemspec should be assumed available (no `if defined?` checks needed)
- Tree-sitter is used for AST parsing with graceful fallbacks to regex-based parsing
- Knowledge base (KB) files are JSON-based outputs for analysis results

## Key Dependencies

- **TTY Toolkit** - All terminal UI components (see LLM_STYLE_GUIDE.md for usage)
- **Concurrent-ruby** - Available for parallel processing
- **Tree-sitter parsers** - May not be available for all languages (graceful fallbacks required)

## Performance Context

- File processing should use parallel execution where possible
- Caching is implemented for parsed file results
- Large codebases are a primary use case

## File Organization

- **Do NOT create summary documents at the project root** including:
  - IMPLEMENTATION_SUMMARY.md
  - SESSION_SUMMARY.md
  - PROMPT.md
  - Or any similar files
- Work summaries and implementation docs should go in `docs/` with descriptive names
- Temporary working files should go in `.aidp/` directory
- Use git commit messages for implementation tracking instead of summary files
- Name documentation files descriptively based on the feature/issue, not generically
