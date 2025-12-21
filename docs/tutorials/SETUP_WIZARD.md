# Setup Wizard

The AIDP setup wizard provides an interactive flow for capturing everything the
framework needs inside `.aidp/aidp.yml`. It runs automatically the first time
you execute `aidp` in a repository, and you can launch it manually at any time.

```bash
# Re-run the wizard manually
aidp config --interactive

# Preview changes without writing to disk
aidp config --interactive --dry-run
```

## What the wizard collects

### Providers

- Primary LLM provider, model, temperature, token limits, and retry policy
- MCP tool configuration (Git, shell, filesystem, browser, GitHub, or custom)
- Inline guidance for exporting API keys to environment variables (no secrets
  are stored in the YAML file)

### Work Loop Settings

- Unit / integration / end-to-end test commands
- Lint and formatter commands (with optional autofix)
- Deterministic unit catalog (commands, wait policies, and fallbacks)
- Guard rails (include/exclude patterns, protected paths, confirmation rules,
  max lines per commit)
- Watch patterns for test reruns and default timeouts
- Branching strategy (prefix, slug template, checkpoint tags)
- Artifact directories for evidence packs, logs, and screenshots
- Version control behavior (tool, commit behavior, commit message style, PR creation)

### Non-Functional Requirements (NFRs)

- Performance, security, reliability, accessibility, and i18n guidance
- Preferred libraries and tools by stack (Rails, Node.js, Python, or custom)
- Optional environment-specific overrides (dev/test/prod)

### Logging & Modes

- Log level, JSON formatting, rotation sizes/backups
- Defaults for background/quick/watch modes used by automation features

### Devcontainer Configuration

- Automatic generation and management of `.devcontainer/devcontainer.json`
- Auto-detection of required ports based on project type and services
- Custom port configuration with labels
- Intelligent merging that preserves user customizations
- Automatic backups before modifications

## Preview & Diff

Before writing, the wizard prints the generated YAML along with a unified diff
against the existing configuration (if present). Use the diff to check which
values changed. When the wizard runs with `--dry-run`, the diff and preview are
shown but nothing is written to disk.

## Schema Version & Metadata

The generated file includes:

```yaml
schema_version: 1        # Tracks config migrations
generated_by: aidp setup wizard vX.Y.Z
generated_at: 2024-05-01T12:34:56Z
```

These fields help future migrations understand the format that was written.

## Idempotency & Preservation

- Existing values serve as defaults; press Enter to keep them.
- Type `clear` to remove a value.
- Sections you skip are left untouched in the YAML, allowing manual edits to
  survive subsequent runs.

## Where the file lives

The wizard writes `.aidp/aidp.yml`. The directory is created automatically if
missing. Manual edits are fine—just re-run the wizard when you need to adjust
settings or use `--dry-run` to preview changes first.

For a full schema reference, see [CONFIGURATION.md](../reference/CONFIGURATION.md).
