# Project LLM Style Guide

> Generated automatically by `aidp init` on 2025-10-16T14:54:28Z.
>
> Detected languages: Ruby
> Framework hints: Django, Express, FastAPI, Flask, Go Gin, Hanami, Laravel, Next.js, Phoenix, Rails, React, Sinatra, Spring, Vue
> Primary test frameworks: RSpec
> Key directories: lib, spec, scripts, bin, docs, examples

This project has opted to adopt new conventions recommended by aidp init. When in doubt, prefer the rules below over legacy patterns.

## 1. Core Engineering Rules

- Prioritise readability and maintainability; extract objects or modules once business logic exceeds a few branches.
- Co-locate domain objects with their tests under the matching directory (e.g., `lib/` ↔ `spec/`).
- Remove dead code and feature flags that are no longer exercised; keep git history as the source of truth.
- Use small, composable services rather than bloated classes.

## 2. Naming & Structure

- Follow idiomatic naming for the detected languages (Ruby); align files under lib, spec, scripts, bin, docs, examples.
- Ensure top-level namespaces mirror the directory structure (e.g., `Aidp::Init` lives in `lib/aidp/init/`).
- Keep public APIs explicit with keyword arguments and descriptive method names.

## 3. Parameters & Data

- Limit positional arguments to three; prefer keyword arguments or value objects beyond that.
- Reuse shared data structures to capture configuration (YAML/JSON) instead of scattered constants.
- Validate incoming data at boundaries; rely on plain objects internally.

## 4. Error Handling

- Raise domain-specific errors; avoid using plain `StandardError` without context.
- Wrap external calls with rescuable adapters and surface actionable error messages.
- Log failures with relevant identifiers only—never entire payloads.

## 5. Testing Contracts

- Mirror production directory structure inside `spec`.
- Keep tests independent; mock external services only at the boundary layers.
- Use the project's native assertions (RSpec) and ensure every bug fix comes with a regression test.

## 6. Framework-Specific Guidelines

- Adopt the idioms of detected frameworks (Django, Express, FastAPI, Flask, Go Gin, Hanami, Laravel, Next.js, Phoenix, Rails, React, Sinatra, Spring, Vue).
- Keep controllers/handlers thin; delegate logic to service objects or interactors.
- Store shared UI or component primitives in a central folder to make reuse easier.

## 7. Dependencies & External Services

- Document every external integration inside `docs/` and keep credentials outside the repo.
- Use dependency injection for clients; avoid global state or singletons.
- When adding new gems or packages, document the rationale in `PROJECT_ANALYSIS.md`.

## 8. Build & Development

- Run linters before committing: Rspec.
- Keep build scripts in `bin/` or `scripts/` and ensure they are idempotent.
- Prefer `mise` or language-specific version managers to keep toolchains aligned.

## 9. Performance

- Measure before optimising; add benchmarks for hotspots.
- Cache expensive computations when they are pure and repeatable.
- Review dependency load time; lazy-load optional components where possible.

## 10. Project-Specific Anti-Patterns

- Avoid sprawling God objects that mix persistence, business logic, and presentation.
- Resist ad-hoc shelling out; prefer library APIs with proper error handling.
- Do not bypass the agreed testing workflow—even for small fixes.

---
Generated from template `planning/generate_llm_style_guide.md` with repository-aware adjustments.
