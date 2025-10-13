# AIDP Configuration (`.aidp/aidp.yml`)

The configuration file lives inside the project at `.aidp/aidp.yml`. It is
generated and maintained by the setup wizard, but you can edit it manually when
needed. This page documents every top-level key the wizard writes.

## Header

```yaml
schema_version: 1     # Configuration schema version
generated_by: aidp setup wizard vX.Y.Z
generated_at: 2024-05-01T12:34:56Z
```

Keep `schema_version` intact so future releases can migrate the file.

## Providers

```yaml
providers:
  llm:
    name: anthropic          # anthropic|openai|google|azure|custom
    model: claude-3-5-sonnet-20241022
    temperature: 0.2
    max_tokens: 4096
    rate_limit_per_minute: 60
    retry_policy:
      attempts: 3
      backoff_seconds: 10
  mcp:
    enabled: true
    tools: [git, shell, fs]
    custom_servers: []
```

Secrets such as API keys are never stored here—export them as environment
variables instead.

## Work Loop

```yaml
work_loop:
  test:
    unit: bundle exec rspec
    integration: "npm run test:integration"
    e2e: "npx playwright test"
    timeout_seconds: 1800
    watch:
      patterns: ["spec/**/*_spec.rb", "lib/**/*.rb"]
  lint:
    command: bundle exec rubocop
    format: bundle exec rubocop -A
    autofix: false
  guards:
    include: ["app/**/*", "lib/**/*"]
    exclude: ["node_modules/**", "dist/**"]
    max_lines_changed_per_commit: 300
    protected_paths: ["config/credentials.yml.enc"]
    confirm_protected: true
  branching:
    prefix: aidp
    slug_format: "issue-%{id}-%{title}"
    checkpoint_tag: "aidp-start/%{id}"
  artifacts:
    evidence_dir: .aidp/evidence
    logs_dir: .aidp/logs
    screenshots_dir: .aidp/screenshots
```

## Non-Functional Requirements (NFRs)

```yaml
nfrs:
  performance: "Prefer O(n log n) algorithms; cache where safe."
  security: "Follow Rails security guide; avoid inline SQL."
  reliability: "Idempotent jobs with retry + exponential backoff."
  accessibility: "Adhere to WCAG 2.1 AA for UI work."
  internationalization: "Ensure copy is i18n-ready."
  preferred_libraries:
    rails:
      auth: devise
      authz: pundit
      jobs: sidekiq
      testing: [rspec, factory_bot]
  environment_overrides:
    production: "Benchmark new endpoints; maintain SLO of 99.9%."
```

All values are free-form strings (multi-line is allowed). The planner reads
these when designing features or selecting dependencies.

## Logging

```yaml
logging:
  level: info            # debug|info|error
  json: false
  max_size_mb: 10
  max_backups: 5
```

## Modes

```yaml
modes:
  background_default: false
  watch_enabled: false
  quick_mode_default: false
```

These defaults are consumed by background jobs, watch mode, and quick mode
invocations.

## Updating the Configuration

- Run `aidp config --interactive` to re-open the wizard.
- Use `--dry-run` to preview changes without writing.
- Manual edits are honoured: the wizard uses existing values as defaults and
  only updates what you change.

For a tour of the wizard itself, see [SETUP_WIZARD.md](SETUP_WIZARD.md).
