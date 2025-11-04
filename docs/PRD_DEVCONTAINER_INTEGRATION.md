# PRD: Devcontainer Integration for AIDP Setup Wizard

**Issue:** [#213](https://github.com/viamin/aidp/issues/213)
**Status:** In Development
**Version:** 1.0
**Last Updated:** 2025-01-03

---

## Executive Summary

Extend the AIDP interactive configuration wizard (`aidp config --interactive`) to manage devcontainer configuration. The wizard will import existing devcontainer settings, present them as defaults, and generate or enhance `.devcontainer/devcontainer.json` based on user selections. This creates a unified, idempotent configuration experience where AIDP settings and development environment stay synchronized.

---

## Goals

### Primary Goals

1. **Unified Configuration**: Single wizard for both AIDP and devcontainer setup
2. **Import Existing Settings**: Parse existing devcontainer to pre-fill wizard defaults
3. **Intelligent Generation**: Create devcontainer from wizard selections
4. **Port Management**: Configure firewall rules and port forwarding based on selected services
5. **Safety & Backups**: Non-destructive updates with automatic backups
6. **ZFC Integration**: Use Zero Framework Cognition for intelligent devcontainer generation

### Non-Goals

- Direct editing of devcontainer.json through a specialized UI
- Support for docker-compose.yml (focus on devcontainer.json only)
- Management of Dockerfile content (only devcontainer.json features/settings)
- Complex multi-container orchestration

---

## User Personas

### Primary: Solo Developer

- Wants quick setup without manual devcontainer configuration
- Needs their development environment to match AIDP's expectations
- Values automatic port forwarding for preview/debugging

### Secondary: Team Lead

- Setting up standardized devcontainers across team
- Wants to version control complete development environment
- Needs documentation for onboarding

---

## User Stories

### Story 1: First-Time Setup

**As a** new AIDP user
**I want** the wizard to create a complete devcontainer for me
**So that** I can start developing without manual environment setup

**Acceptance Criteria:**

- Wizard detects no existing devcontainer
- Offers to create one based on wizard selections
- Generates working devcontainer.json with appropriate features
- Ports are forwarded based on selected tools

### Story 2: Importing Existing Configuration

**As an** existing devcontainer user
**I want** AIDP wizard to recognize my current devcontainer settings
**So that** I don't have to re-enter information I've already configured

**Acceptance Criteria:**

- Wizard detects `.devcontainer/devcontainer.json`
- Extracts ports, features, environment variables
- Pre-fills wizard questions with detected values
- Offers to enhance (not replace) existing configuration

### Story 3: Re-running the Wizard

**As a** developer updating their setup
**I want** to safely update my devcontainer through the wizard
**So that** my environment stays in sync with AIDP configuration

**Acceptance Criteria:**

- Wizard creates backup of existing devcontainer
- Shows diff of proposed changes
- Merges new settings without clobbering manual edits
- Preserves custom features/mounts not managed by AIDP

---

## Technical Architecture

### Module Structure

```text
lib/aidp/
  setup/
    wizard.rb                          # Extended with devcontainer flow
    devcontainer/
      parser.rb                        # Parse existing devcontainer.json
      generator.rb                     # Generate/update devcontainer.json
      port_manager.rb                  # Manage port configurations
      backup_manager.rb                # Handle backups
      feature_mapper.rb                # Map wizard choices to devcontainer features
```text

### Data Flow

```text
┌─────────────────────────────────────────────────────────────────┐
│ 1. Wizard Start                                                 │
│    - Load aidp.yml (existing config)                           │
│    - Detect .devcontainer/devcontainer.json                    │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Import Phase (if devcontainer exists)                       │
│    - Parse devcontainer.json                                   │
│    - Extract: ports, features, env, mounts, shell, user       │
│    - Pre-fill wizard defaults                                 │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Wizard Questions (standard + devcontainer-specific)         │
│    - Provider selection → env vars needed                      │
│    - Test commands → postCreateCommand hooks                   │
│    - Interactive tools → features (playwright, chrome)         │
│    - Work loop options → supervisor scripts                    │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Port Configuration                                           │
│    - Analyze selected services                                 │
│    - Build ports matrix                                        │
│    - Generate PORTS.md documentation                           │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Generate/Enhance Devcontainer                               │
│    - Create backup (if exists)                                 │
│    - Generate new devcontainer.json                            │
│    - Show diff                                                 │
│    - Prompt for confirmation                                   │
│    - Write files                                               │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Save Configuration                                           │
│    - Update aidp.yml with devcontainer metadata               │
│    - Write ZFC recipe (future: for re-application)            │
└─────────────────────────────────────────────────────────────────┘
```text

### Configuration Schema (aidp.yml)

```yaml
devcontainer:
  manage: true                    # AIDP manages devcontainer
  path: .devcontainer             # Path to devcontainer directory
  last_generated: 2025-01-03T10:00:00Z

  ports:
    # Automatically opened ports based on wizard selections
    - number: 3000
      label: "Web Preview"
      protocol: "http"
    - number: 7681
      label: "Remote Terminal"
      protocol: "http"

  features:
    # Devcontainer features enabled
    - ghcr.io/devcontainers/features/github-cli:1
    - ghcr.io/devcontainers/features/node:1

  env:
    # Environment variables to set (no secrets)
    AIDP_LOG_LEVEL: info
    AIDP_ENV: development

  custom_settings:
    # User's manual additions (preserved on updates)
    remoteUser: vscode
    customizations:
      vscode:
        extensions:
          - eamodio.gitlens
```text

---

## Feature Specifications

### 1. Devcontainer Parser

**Purpose:** Read and parse existing `.devcontainer/devcontainer.json` or `devcontainer.json`

**Methods:**

- `detect_devcontainer()` - Find devcontainer.json in standard locations
- `parse()` - Parse JSON and extract relevant fields
- `extract_ports()` - Get forwardPorts and portsAttributes
- `extract_features()` - Get features array
- `extract_env()` - Get containerEnv
- `extract_post_commands()` - Get postCreateCommand, postStartCommand
- `extract_customizations()` - Get vscode extensions, settings

**Error Handling:**

- Invalid JSON → warn user, proceed with defaults
- Missing file → silently proceed with creation flow
- Partial config → extract what's available, use defaults for rest

### 2. Devcontainer Generator

**Purpose:** Create or update devcontainer.json based on wizard selections

**Methods:**

- `generate(config, existing = nil)` - Generate complete devcontainer.json
- `merge_with_existing(new_config, existing)` - Intelligently merge configurations
- `build_features_list(wizard_config)` - Map wizard selections to devcontainer features
- `build_post_commands(wizard_config)` - Generate postCreate/postStart scripts

**Mapping Rules:**

| Wizard Selection | Devcontainer Feature/Setting |
|------------------|------------------------------|
| Provider: Any | Add gh CLI feature |
| Test: RSpec | Ensure Ruby feature with correct version |
| Test: Jest/Playwright | Ensure Node feature |
| Interactive: Playwright MCP | Add playwright feature |
| Interactive: Chrome DevTools | Add chromium/puppeteer |
| Interactive: Expect | Add expect package |
| Lint: StandardRB | Add rubocop to postCreate |
| Lint: ESLint | Add eslint to postCreate |

### 3. Port Manager

**Purpose:** Configure port forwarding and firewall rules

**Methods:**

- `detect_required_ports(wizard_config)` - Analyze config for port needs
- `generate_ports_config()` - Build forwardPorts array
- `generate_ports_attributes()` - Build portsAttributes with labels
- `generate_ports_documentation()` - Create PORTS.md

**Port Rules:**

| Service/Tool | Port | Label | Auto-open? |
|--------------|------|-------|------------|
| Web app preview | 3000 | "Application" | Yes |
| Playwright debug | 9222 | "Playwright Debug" | No |
| Remote terminal | 7681 | "ttyd Terminal" | No |
| MCP server | 8080 | "MCP Server" | No |

### 4. Backup Manager

**Purpose:** Safely backup existing devcontainer before modifications

**Methods:**

- `create_backup(source_path)` - Copy to `.aidp/backups/devcontainer-<timestamp>.json`
- `list_backups()` - List available backups
- `restore_backup(backup_path)` - Restore from backup (manual command)

---

## Wizard Flow Changes

### New Section: Devcontainer Configuration

**Position:** After "Operational modes" section, before final preview

**Questions:**

1. **Detect Existing** (automatic, informational only)

   ```text
   📦 Devcontainer Configuration
   ────────────────────────────────
   ✓ Found existing devcontainer at .devcontainer/devcontainer.json
   Importing settings...
   ```

1. **Manage Devcontainer?**

   ```text
   Would you like AIDP to manage your devcontainer configuration?
   [Yes] / No

   Benefits:
   - Auto-configure ports for selected tools
   - Install required features (gh CLI, language runtimes)
   - Keep environment in sync with AIDP settings
   ```

1. **Port Configuration** (if manage = yes)

   ```text
   Configure port forwarding?
   [Yes] / No

   The following ports will be configured:
   • 3000 (Web Preview) - based on your app type
   • 7681 (Remote Terminal) - if watch mode enabled

   Additional ports? (comma-separated, or press Enter to skip)
   [8080, 5432]
   ```

1. **Features Selection** (if manage = yes)

   ```text
   Additional devcontainer features? (multi-select)
   ◯ Docker-in-Docker
   ◯ AWS CLI
   ◯ Azure CLI
   ◯ Terraform
   ◯ None
   ```

1. **Action Selection**

   ```text
   Devcontainer action:
   • Create new devcontainer (no existing found)
   • Enhance existing devcontainer (merge with current)
   • Skip devcontainer setup

   [Enhance existing]
   ```

1. **Preview & Confirm**

   ```text
   📄 Devcontainer Changes Preview
   ════════════════════════════════

   Added Features:
   + ghcr.io/devcontainers/features/github-cli:1
   + ghcr.io/devcontainers/features/ruby:1

   Added Ports:
   + 3000 (Web Preview)

   Modified Settings:
   ~ postCreateCommand: "bundle install && npm install"

   Apply these changes?
   [Yes] / No / Show diff
   ```

---

## CLI Commands

### `aidp devcontainer diff`

**Purpose:** Show diff between current and proposed devcontainer

```bash
aidp devcontainer diff [--proposed-config=path/to/config.json]
```text

**Output:**

```text
Devcontainer Changes
━━━━━━━━━━━━━━━━━━━━

Features:
  + ghcr.io/devcontainers/features/github-cli:1
  + ghcr.io/devcontainers/features/ruby:1

Ports:
  + 3000 (forwardPorts)
  ~ 7681 (changed label: "Terminal" → "Remote Terminal")

Environment:
  + AIDP_LOG_LEVEL=info
```text

### `aidp devcontainer apply`

**Purpose:** Apply devcontainer configuration from aidp.yml

```bash
aidp devcontainer apply [--dry-run] [--force] [--backup]
```text

**Flags:**

- `--dry-run` - Show what would be changed
- `--force` - Skip confirmation prompts
- `--backup` - Create backup even if auto-backup is disabled

---

## Testing Strategy

### Unit Tests

**DevcontainerParser:**

- Parse valid devcontainer.json
- Handle malformed JSON gracefully
- Extract all supported fields
- Handle missing fields with defaults

**DevcontainerGenerator:**

- Generate from scratch (no existing)
- Merge with existing (preserve custom fields)
- Map wizard config to features correctly
- Generate valid JSON output

**PortManager:**

- Detect ports from wizard config
- Generate proper portsAttributes
- Create readable PORTS.md

### Integration Tests

**Wizard Flow:**

- Complete wizard with devcontainer creation
- Complete wizard with devcontainer enhancement
- Wizard with no devcontainer (creation flow)
- Wizard with existing devcontainer (import + enhance)

### Manual Testing Checklist

- [ ] Run wizard in empty project → creates devcontainer
- [ ] Run wizard in project with existing devcontainer → imports settings
- [ ] Run wizard twice → second run preserves manual edits
- [ ] Open in VS Code Dev Container → verify it works
- [ ] Ports forward correctly
- [ ] PostCreate commands execute
- [ ] Features install properly

---

## Documentation Plan

### docs/SETUP_WIZARD.md

**Updates:**

- Add section on devcontainer integration
- Screenshots of new wizard questions
- Example configurations

### docs/DEVELOPMENT_CONTAINER.md (NEW)

**Contents:**

- Overview of AIDP's devcontainer management
- File structure explanation
- Port configuration reference
- Feature mapping table
- Backup/restore procedures
- Troubleshooting

### docs/CONFIGURATION.md

**Updates:**

- Document `devcontainer:` section in aidp.yml
- Configuration options reference
- Examples for common setups

### docs/PORTS.md (NEW)

**Contents:**

- Auto-generated list of configured ports
- Purpose of each port
- Security considerations
- How to add custom ports

---

## Rollout Plan

### Phase 1: Core Infrastructure (Session 1)

- [ ] Create module structure
- [ ] Implement DevcontainerParser
- [ ] Implement DevcontainerGenerator (basic)
- [ ] Unit tests for both modules

### Phase 2: Port Management (Session 2)

- [ ] Implement PortManager
- [ ] Port detection logic
- [ ] PORTS.md generation
- [ ] Unit tests

### Phase 3: Wizard Integration (Session 3)

- [ ] Add devcontainer section to wizard
- [ ] Import flow
- [ ] Preview/diff display
- [ ] Integration tests

### Phase 4: CLI Commands (Session 4)

- [ ] Implement `devcontainer diff`
- [ ] Implement `devcontainer apply`
- [ ] Command tests

### Phase 5: Documentation (Session 5)

- [ ] Write DEVELOPMENT_CONTAINER.md
- [ ] Update SETUP_WIZARD.md
- [ ] Update CONFIGURATION.md
- [ ] Generate PORTS.md template

---

## Success Metrics

### Adoption

- % of new users who enable devcontainer management in wizard
- % of existing users who re-run wizard to add devcontainer

### Quality

- Zero failed devcontainer builds
- < 5% of users manually editing devcontainer after wizard
- All tests passing

### Documentation

- < 10% of users asking "how do I set up devcontainer" in issues

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing devcontainers | High | Always backup, show diff, require confirmation |
| ZFC not available yet | Medium | Phase ZFC integration separately; use template-based generation first |
| Complex merge logic | Medium | Start with simple additive merge; enhance iteratively |
| User confusion | Medium | Clear wizard prompts, good documentation, examples |

---

## Open Questions

1. **ZFC Integration Timeline**: When will ZFC be available? If not soon, proceed with template-based approach?
   - **Decision:** Start with template-based, design for ZFC integration later

2. **Docker Compose Support**: Should we support docker-compose.yml?
   - **Decision:** No, out of scope for v1. Focus on devcontainer.json only

3. **Multi-container Setups**: Support for multiple services (db, redis, etc)?
   - **Decision:** Not in v1. Document workarounds for now

4. **VS Code Extensions**: Should wizard manage recommended extensions?
   - **Decision:** Yes, but minimal set. Allow customization in devcontainer.json

---

## Appendix: Example Generated Devcontainer

```json
{
  "name": "AIDP Development",
  "image": "mcr.microsoft.com/devcontainers/ruby:3.2",

  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {
      "version": "lts"
    }
  },

  "forwardPorts": [3000, 7681],

  "portsAttributes": {
    "3000": {
      "label": "Application",
      "onAutoForward": "notify"
    },
    "7681": {
      "label": "Remote Terminal",
      "onAutoForward": "silent"
    }
  },

  "containerEnv": {
    "AIDP_LOG_LEVEL": "info",
    "AIDP_ENV": "development"
  },

  "postCreateCommand": "bundle install && .aidp/devcontainer/postCreate.sh",

  "customizations": {
    "vscode": {
      "extensions": [
        "shopify.ruby-lsp",
        "GitHub.copilot"
      ]
    }
  },

  "remoteUser": "vscode",

  "_aidp": {
    "managed": true,
    "version": "0.20.0",
    "generated_at": "2025-01-03T10:00:00Z"
  }
}
```text

---

**END OF PRD**
