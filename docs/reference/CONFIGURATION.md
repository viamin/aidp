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
    name: anthropic          # anthropic|openai|google|azure|aider|custom
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

### Available Providers

AIDP supports multiple LLM providers:

- **anthropic**: Claude models via Anthropic API or Claude CLI
- **openai**: GPT models via OpenAI API or Codex CLI
- **google**: Gemini models via Google API or Gemini CLI
- **azure**: Azure OpenAI Service
- **aider**: Aider CLI (supports multiple models via OpenRouter)
- **custom**: Custom provider implementations

#### Aider Provider

Aider is a versatile coding assistant that supports multiple models through OpenRouter. To use Aider:

1. **Installation**: In the devcontainer, Aider is automatically installed. Outside the devcontainer, install with:

   ```bash
   curl -fsSL https://aider.chat/install.sh | bash
   ```

   Or using pipx (recommended for Python-based installation):

   ```bash
   pipx install aider-chat
   ```

2. **Configuration**: Aider manages its own configuration (models, API keys, etc.) through its configuration file `~/.aider/`. Configure Aider before using it with AIDP:

   ```bash
   aider --model <your-model> --openrouter-api-key <your-key>
   ```

3. **Usage**: Set `name: aider` in your provider configuration. AIDP will use Aider in non-interactive mode with the `--yes-always` flag (equivalent to Claude's `--dangerously-skip-permissions`) for automated operation.

4. **Git Commits**: By default, AIDP disables Aider's automatic commits (`--no-auto-commits`) and instead respects AIDP's `work_loop.version_control.behavior` configuration. This ensures consistent commit behavior across all providers. If you need Aider to handle its own commits, you can enable this in provider-specific options.

5. **Firewall**: The devcontainer firewall automatically allows access to:
   - `aider.chat` (for updates)
   - `openrouter.ai` and `api.openrouter.ai` (for API access)
   - `pypi.org` (for version checking)

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
          failure: diagnose_failures
      - name: run_lint
        command: bundle exec standardrb
        min_interval_seconds: 300
        next:
          success: agentic
          failure: diagnose_failures
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
  task_completion_required: true  # Enforce mandatory task tracking (default: true)
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

### Task Completion Tracking

The `task_completion_required` option (default: `true`) enforces mandatory task tracking for work loops. When enabled:

- **If no tasks exist**: Work can complete without tasks (supports workflows without planning phase)
- **If tasks exist**: All project tasks must be completed or abandoned before work loop can finish
- **Abandoned tasks require a reason** for better accountability

**Important**: Tasks are **project-scoped**, not session-scoped. This means:

- Tasks created during planning phases (e.g., with `aidp-plan` label) persist and must be completed during build phases (e.g., with `aidp-build` label)
- Tasks from any work loop session remain active until completed or abandoned
- The system checks for incomplete tasks across the entire project

This feature ensures that work is properly decomposed into trackable tasks, preventing scope creep and maintaining clear records of what was accomplished or abandoned.

**Task Creation:**
Agents create tasks using file signals:

```text
File task: "Implement authentication" priority: high tags: security,auth
File task: "Add tests" priority: medium tags: testing
```

**Task Status Updates:**
Agents update task status during work:

```text
Update task: task_123_abc status: in_progress
Update task: task_123_abc status: done
Update task: task_456_def status: abandoned reason: "Requirements changed"
```

**Valid Statuses:**

- `pending` - Not started (initial state)
- `in_progress` - Currently being worked on
- `done` - Completed successfully
- `abandoned` - Not doing this (requires reason)

**Task Storage:**
Tasks are stored in `.aidp/tasklist.jsonl` using append-only JSONL format for git-friendly tracking across sessions.

**Disabling Task Tracking:**
To disable mandatory task tracking:

```yaml
harness:
  work_loop:
    task_completion_required: false
```

See [WORK_LOOPS_GUIDE.md](WORK_LOOPS_GUIDE.md#task-tracking-requirements) for detailed workflow examples.

### Work Loop Templates

- `templates/work_loop/decide_whats_next.md` renders the lightweight decision prompt that chooses the next unit after deterministic runs.
- `templates/work_loop/diagnose_failures.md` summarizes failing deterministic units and captures the rationale for the next action.
- Watch mode queues extra units by writing to `.aidp/work_loop/initial_units.txt` inside the active worktree. The scheduler consumes and clears that file on the next harness run.

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
| ------ | -------------- |
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

## Auto-Update

```yaml
auto_update:
  enabled: false                  # Master switch for auto-update
  policy: off                     # off|exact|patch|minor|major
  allow_prerelease: false         # Allow prerelease versions (alpha/beta/rc)
  check_interval_seconds: 3600    # How often to check for updates (min: 300, max: 86400)
  supervisor: none                # Supervisor type: supervisord|s6|runit|none
  max_consecutive_failures: 3     # Restart loop protection (min: 1, max: 10)
```

**Auto-update enables Aidp to update itself automatically when running in watch mode.** This is designed for devcontainer environments where Aidp runs continuously.

### Update Policies

| Policy | Description | Example |
| -------- | ------------- | --------- |
| `off` | No automatic updates | Always stay on current version |
| `exact` | Only exact version matches | 1.2.3 → 1.2.3 (no updates) |
| `patch` | Allow patch updates | 1.2.3 → 1.2.4 ✓, 1.2.3 → 1.3.0 ✗ |
| `minor` | Allow minor + patch updates | 1.2.3 → 1.3.0 ✓, 1.2.3 → 2.0.0 ✗ |
| `major` | Allow all updates | 1.2.3 → 2.0.0 ✓ |

**Recommended**: Use `minor` for automatic updates or `patch` for conservative environments.

### Supervisor Integration

Auto-update requires a process supervisor to handle restarts. Supported supervisors:

- **supervisord** - Recommended, widely used
- **s6** - Lightweight, fast startup
- **runit** - Simple, reliable
- **none** - Disables supervisor integration (auto-update won't restart)

See [SELF_UPDATE.md](SELF_UPDATE.md) for complete setup instructions and supervisor configuration.

### How It Works

1. **Check**: Aidp checks for updates every `check_interval_seconds` while running in watch mode
2. **Checkpoint**: If an allowed update is available, Aidp saves current state to `.aidp/checkpoints/`
3. **Exit**: Aidp exits with code 75, signaling the supervisor to update
4. **Update**: Supervisor runs `bundle update aidp`
5. **Restart**: Supervisor restarts Aidp
6. **Restore**: Aidp restores from checkpoint and resumes watch mode

### CLI Commands

Manage auto-update settings via CLI:

```bash
# Show current status
aidp settings auto-update status

# Enable/disable
aidp settings auto-update on
aidp settings auto-update off

# Set policy
aidp settings auto-update policy minor

# Toggle prerelease
aidp settings auto-update prerelease
```

### Example Configurations

**Conservative (patch updates only):**

```yaml
auto_update:
  enabled: true
  policy: patch
  allow_prerelease: false
  check_interval_seconds: 7200  # Check every 2 hours
  supervisor: supervisord
  max_consecutive_failures: 2
```

**Aggressive (all updates):**

```yaml
auto_update:
  enabled: true
  policy: major
  allow_prerelease: true
  check_interval_seconds: 1800  # Check every 30 minutes
  supervisor: supervisord
  max_consecutive_failures: 3
```

**Disabled:**

```yaml
auto_update:
  enabled: false
  policy: off
  # Other settings ignored when disabled
```

### Logs and Monitoring

Auto-update maintains comprehensive logs:

- **Update log**: `.aidp/logs/updates.log` (JSON Lines format)
- **Wrapper log**: `.aidp/logs/wrapper.log` (supervisor wrapper)
- **Checkpoints**: `.aidp/checkpoints/` (state snapshots)

```bash
# View recent updates
cat .aidp/logs/updates.log | jq 'select(.event=="success")'

# Monitor in real-time
tail -f .aidp/logs/wrapper.log
```

### Security and Safety

- **Opt-in by default**: Auto-update is disabled unless explicitly enabled
- **Bundler respects Gemfile.lock**: Only updates aidp gem according to version constraints
- **Restart loop protection**: Disables auto-update after max_consecutive_failures
- **Checksum validation**: Checkpoints verified before restoration
- **Audit trail**: All update attempts logged

See [SELF_UPDATE.md](SELF_UPDATE.md) for complete documentation, troubleshooting, and security considerations.

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

## Watch Mode Configuration

Configure Watch Mode behavior for automated issue and PR processing.

### Basic Watch Settings

```yaml
watch:
  labels:
    auto_trigger: "aidp-auto"
    plan_trigger: "aidp-plan"
    build_trigger: "aidp-build"
    review_trigger: "aidp-review"
    ci_fix_trigger: "aidp-fix-ci"
    request_changes_trigger: "aidp-request-changes"

  safety:
    author_allowlist:
      - "username1"
      - "org/team-name"
    require_allowlist: true

  processing:
    poll_interval_seconds: 30
    max_iterations: 20
```

### GitHub Projects V2 Integration

Enable GitHub Projects V2 for hierarchical issue management:

```yaml
watch:
  projects:
    enabled: true
    project_id: "PVT_kwDOA..."       # Required: Your Project V2 ID
    hierarchical_planning: true       # Break large issues into sub-issues
    field_mappings:                   # Map AIDP fields to project fields
      status: "Status"
      priority: "Priority"
      blocking: "Blocking"
    auto_create_fields: true          # Create fields if they don't exist
```

**Finding Your Project ID:**

```bash
# List your organization's projects
gh api graphql -f query='
  query { organization(login: "YOUR_ORG") {
    projectsV2(first: 10) { nodes { id title } }
  }
}'

# List your user projects
gh api graphql -f query='
  query { viewer {
    projectsV2(first: 10) { nodes { id title } }
  }
}'
```

### Auto-Merge Configuration

Configure automatic merging for sub-issue PRs:

```yaml
watch:
  auto_merge:
    enabled: true
    sub_issue_prs_only: true          # Only auto-merge sub-issue PRs (safety)
    require_ci_success: true          # Wait for CI to pass
    require_reviews: 0                # Minimum required reviews (0 = none)
    merge_method: "squash"            # squash, merge, or rebase
    delete_branch: true               # Delete branch after merge
```

**Safety Features:**

- Parent PRs are **never** auto-merged (always require human review)
- Only PRs with `aidp-sub-pr` label are eligible (when `sub_issue_prs_only: true`)
- CI must pass before merge (when `require_ci_success: true`)
- Merge conflicts prevent auto-merge

For complete documentation, see [GITHUB_PROJECTS.md](GITHUB_PROJECTS.md).

## Devcontainer Configuration

AIDP can automatically generate and manage your `.devcontainer/devcontainer.json` configuration based on your project settings.

```yaml
devcontainer:
  manage: true
  custom_ports:
    - number: 8080
      label: "Application Server"
    - number: 5432
      label: "PostgreSQL Database"
  last_generated: "2025-01-04T12:34:56Z"
```

**Configuration Options**:

- `manage` (boolean): Whether AIDP should generate/update the devcontainer configuration
- `custom_ports` (array): Additional ports to expose in the devcontainer
  - `number` (integer): Port number
  - `label` (string): Human-readable description of the port
- `last_generated` (string): ISO 8601 timestamp of last generation (auto-managed)

**Behavior**:

- Ports are auto-detected from your project configuration (test frameworks, web servers, databases)
- Existing devcontainer customizations are preserved during updates
- Automatic backups are created before modifications
- Use `aidp devcontainer diff` to preview changes
- Use `aidp devcontainer apply` to generate/update the configuration

For more details, see the devcontainer documentation in `docs/devcontainer/`.

## Updating the Configuration

- Run `aidp config --interactive` to re-open the wizard.
- Use `--dry-run` to preview changes without writing.
- Manual edits are honoured: the wizard uses existing values as defaults and
  only updates what you change.

For a tour of the wizard itself, see [SETUP_WIZARD.md](SETUP_WIZARD.md).
