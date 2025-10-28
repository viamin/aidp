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
  units:
    deterministic:
      - name: run_full_tests
        command: bundle exec rake spec
        min_interval_seconds: 300
        next:
          success: agentic
          failure: decide_whats_next
      - name: wait_for_github
        type: wait
        metadata:
          interval_seconds: 60
        next:
          event: agentic
          else: wait_for_github
    defaults:
      initial_unit: agentic
      on_no_next_step: wait_for_github
      fallback_agentic: decide_whats_next
  branching:
    prefix: aidp
    slug_format: "issue-%{id}-%{title}"
    checkpoint_tag: "aidp-start/%{id}"
  artifacts:
    evidence_dir: .aidp/evidence
    logs_dir: .aidp/logs
    screenshots_dir: .aidp/screenshots
  coverage:
    enabled: true
    tool: simplecov
    run_command: "bundle exec rspec"
    report_paths:
      - coverage/index.html
      - coverage/.resultset.json
    fail_on_drop: false
    minimum_coverage: 80.0
  version_control:
    tool: git
    behavior: commit
    conventional_commits: true
  interactive_testing:
    enabled: true
    app_type: web
    tools:
      web:
        playwright_mcp:
          enabled: true
          run: "npx playwright test"
          specs_dir: ".aidp/tests/web"
```

### Coverage Tools

AIDP can track code coverage and integrate with your existing coverage tools.

#### Supported Tools

- **simplecov** (Ruby): SimpleCov integration
- **nyc** (JavaScript): NYC/Istanbul integration
- **istanbul** (JavaScript): Istanbul integration
- **coverage.py** (Python): Coverage.py integration
- **go-cover** (Go): go test -cover integration
- **jest** (JavaScript): Jest coverage integration
- **other**: Custom coverage tool

#### Configuration Options

- **`enabled`** (boolean): Enable/disable coverage tracking
- **`tool`** (string): Coverage tool being used
- **`run_command`** (string): Command to execute coverage
- **`report_paths`** (array): Paths to coverage report files
- **`fail_on_drop`** (boolean): Fail the work loop if coverage decreases
- **`minimum_coverage`** (number): Minimum coverage percentage (0-100)

#### Examples

**Ruby - SimpleCov**:

```yaml
coverage:
  enabled: true
  tool: simplecov
  run_command: "bundle exec rspec"
  report_paths:
    - coverage/index.html
    - coverage/.resultset.json
  minimum_coverage: 80.0
```

**JavaScript - NYC**:

```yaml
coverage:
  enabled: true
  tool: nyc
  run_command: "nyc npm test"
  report_paths:
    - coverage/lcov-report/index.html
    - coverage/lcov.info
```

**Python - Coverage.py**:

```yaml
coverage:
  enabled: true
  tool: coverage.py
  run_command: "coverage run -m pytest"
  report_paths:
    - .coverage
    - htmlcov/index.html
```

**Go - go test -cover**:

```yaml
coverage:
  enabled: true
  tool: go-cover
  run_command: "go test -cover ./..."
  report_paths:
    - coverage.out
```

### Version Control Behavior

Configure how AIDP interacts with your version control system during work loops.

#### Configuration Options

- **`tool`** (string): Version control system (git, svn, or none)
- **`behavior`** (string): What to do with changes in copilot mode:
  - `nothing`: Manual git operations only
  - `stage`: Automatically stage changes (git add)
  - `commit`: Automatically stage and commit changes
- **`conventional_commits`** (boolean): Use [Conventional Commits](https://www.conventionalcommits.org/) format
- **`commit_style`** (string): Conventional commit style (only when `conventional_commits: true`):
  - `default`: Basic conventional format (e.g., `feat: add user authentication`)
  - `angular`: Include scope in parentheses (e.g., `feat(auth): add login`)
  - `emoji`: Add emoji prefix (e.g., `✨ feat: add user authentication`)
- **`co_author_ai`** (boolean): Include "Co-authored-by" attribution with AI provider name (default: true)
- **`auto_create_pr`** (boolean): Automatically create pull requests after successful builds in watch/daemon mode (default: false)
- **`pr_strategy`** (string): How to create pull requests (only when `auto_create_pr: true`):
  - `draft`: Create as draft PR (safe, allows review before merge)
  - `ready`: Create as ready PR (immediately reviewable)
  - `auto_merge`: Create and auto-merge (fully autonomous, requires approval rules)

#### Behavior by Mode

| Mode | VCS Behavior |
|------|--------------|
| **Copilot** | Uses configured `behavior` setting |
| **Watch** | Always commits changes (ignores `behavior`) |
| **Daemon** | Always commits changes (ignores `behavior`) |

#### Examples

**Git with Manual Operations**:

```yaml
version_control:
  tool: git
  behavior: nothing
  conventional_commits: false
```

**Git with Basic Auto-Commit**:

```yaml
version_control:
  tool: git
  behavior: commit
  conventional_commits: true
  commit_style: default
  co_author_ai: true
```

**Git with Angular-Style Commits**:

```yaml
version_control:
  tool: git
  behavior: commit
  conventional_commits: true
  commit_style: angular
  co_author_ai: true
```

**Git with Emoji Commits**:

```yaml
version_control:
  tool: git
  behavior: commit
  conventional_commits: true
  commit_style: emoji
  co_author_ai: true
```

**Fully Autonomous (Watch/Daemon Mode)**:

```yaml
version_control:
  tool: git
  behavior: commit
  conventional_commits: true
  commit_style: emoji
  co_author_ai: true
  auto_create_pr: true
  pr_strategy: draft  # or "ready" or "auto_merge"
```

#### Commit Message Examples

Based on issue #123 "Add feature":

- **Simple (no conventional commits)**:

  ```text
  implement #123 Add feature
  ```

- **Default conventional**:

  ```text
  feat: implement #123 Add feature

  Co-authored-by: Claude <ai@aidp.dev>
  ```

- **Angular style**:

  ```text
  feat(implementation): implement #123 Add feature

  Co-authored-by: Claude <ai@aidp.dev>
  ```

- **Emoji style**:

  ```text
  ✨ feat: implement #123 Add feature

  Co-authored-by: Claude <ai@aidp.dev>
  ```

- **Without co-author attribution**:

  ```text
  feat: implement #123 Add feature
  ```

### Interactive Testing Tools

AIDP can integrate with interactive testing tools for web, CLI, and desktop applications.

#### Application Types

##### Web Applications

**Playwright MCP**:

```yaml
interactive_testing:
  enabled: true
  app_type: web
  tools:
    web:
      playwright_mcp:
        enabled: true
        run: "npx playwright test"
        specs_dir: ".aidp/tests/web"
```

**Chrome DevTools MCP**:

```yaml
interactive_testing:
  enabled: true
  app_type: web
  tools:
    web:
      chrome_devtools_mcp:
        enabled: true
        run: "npm run test:chrome"
        specs_dir: ".aidp/tests/web"
```

##### CLI Applications

**Expect Scripts**:

```yaml
interactive_testing:
  enabled: true
  app_type: cli
  tools:
    cli:
      expect:
        enabled: true
        run: "expect .aidp/tests/cli/smoke.exp"
        specs_dir: ".aidp/tests/cli"
```

##### Desktop Applications

**AppleScript (macOS)**:

```yaml
interactive_testing:
  enabled: true
  app_type: desktop
  tools:
    desktop:
      applescript:
        enabled: true
        run: "osascript .aidp/tests/desktop/smoke.scpt"
        specs_dir: ".aidp/tests/desktop"
```

**Screen Reader Testing**:

```yaml
interactive_testing:
  enabled: true
  app_type: desktop
  tools:
    desktop:
      screen_reader:
        enabled: true
        notes: "VoiceOver scripted checks for accessibility"
```

## Providers

### Model Families

Group providers by model family for better routing and fallback behavior.

```yaml
providers:
  anthropic:
    type: usage_based
    model_family: claude
    max_tokens: 100_000
```

#### Available Families

- **`auto`** (default): Let the provider decide which model to use
- **`openai_o`**: OpenAI o-series reasoning models (o1, o1-mini)
- **`claude`**: Anthropic Claude models (Sonnet, Opus, Haiku)
- **`mistral`**: Mistral AI models (European/open source)
- **`local`**: Self-hosted/local LLMs

#### Examples

**Claude Models**:

```yaml
providers:
  anthropic:
    type: usage_based
    model_family: claude
    models:
      - claude-3-5-sonnet-20241022
      - claude-3-opus-20240229
```

**OpenAI Reasoning Models**:

```yaml
providers:
  openai:
    type: usage_based
    model_family: openai_o
    models:
      - o1-preview
      - o1-mini
```

**Local Models**:

```yaml
providers:
  ollama:
    type: passthrough
    model_family: local
    models:
      - llama2
      - codellama
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

## Thinking Depth

Configure dynamic model selection based on task complexity:

```yaml
thinking:
  default_tier: standard           # Starting tier: mini|standard|thinking|pro|max
  max_tier: pro                   # Maximum allowed tier
  allow_provider_switch: true     # Try other providers if tier unavailable

  escalation:
    on_fail_attempts: 2           # Escalate after N failures
    on_complexity_threshold:      # Escalate based on complexity
      files_changed: 10
      modules_touched: 5

  permissions_by_tier:            # Map tiers to permission modes
    mini: safe
    standard: tools
    pro: dangerous

  overrides:                      # Override tier for specific skills/templates
    skill.security_audit: pro
    template.critical_bugfix: thinking
```

**Tiers**:

- `mini`: Fastest, most cost-effective (claude-3-haiku, gpt-4o-mini)
- `standard`: Balanced performance (claude-3-5-sonnet, gpt-4o)
- `thinking`: Advanced reasoning (o1-preview, o1-mini, o3-mini)
- `pro`: Maximum capability (claude-3-opus, gemini-1.5-pro)
- `max`: Reserved for future flagship models

**Escalation**: AIDP can automatically escalate to higher tiers based on:

- Consecutive failures (`on_fail_attempts`)
- Task complexity thresholds (`on_complexity_threshold`)

**Provider Switching**: If enabled, AIDP will try alternate providers when the current provider doesn't have models at the requested tier.

For detailed documentation, see [THINKING_DEPTH.md](THINKING_DEPTH.md).

## Updating the Configuration

- Run `aidp config --interactive` to re-open the wizard.
- Use `--dry-run` to preview changes without writing.
- Manual edits are honoured: the wizard uses existing values as defaults and
  only updates what you change.

For a tour of the wizard itself, see [SETUP_WIZARD.md](SETUP_WIZARD.md).
