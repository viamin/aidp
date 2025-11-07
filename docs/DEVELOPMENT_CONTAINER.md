# Development Containers with AIDP

AIDP can automatically generate and manage your `.devcontainer/devcontainer.json` configuration, providing a consistent development environment across your team.

## Quick Start

### Using the Interactive Wizard

The easiest way to set up devcontainer management is through the interactive wizard:

```bash
aidp config --interactive
```

During the wizard, you'll be asked:

- Whether you want AIDP to manage your devcontainer configuration
- If you want to add any custom ports beyond the auto-detected ones

The wizard will:

1. Detect existing `.devcontainer/devcontainer.json` if present
2. Auto-detect required ports based on your project type (Rails, Sinatra, Node.js, etc.)
3. Show you the detected ports
4. Allow you to add custom ports with labels
5. Generate the devcontainer configuration when you save

### Manual Configuration

Add to your `.aidp/aidp.yml`:

```yaml
devcontainer:
  manage: true
  custom_ports:
    - number: 3000
      label: "Rails Server"
    - number: 5432
      label: "PostgreSQL"
```

Then generate the devcontainer:

```bash
aidp devcontainer apply
```

## CLI Commands

AIDP provides several commands for managing your devcontainer configuration:

### `aidp devcontainer diff`

Show the differences between your current devcontainer.json and what AIDP would generate:

```bash
aidp devcontainer diff
```

This is useful for previewing changes before applying them.

### `aidp devcontainer apply`

Generate or update your `.devcontainer/devcontainer.json` based on your AIDP configuration:

```bash
# Interactive mode (asks for confirmation)
aidp devcontainer apply

# Dry run (preview without writing)
aidp devcontainer apply --dry-run

# Force mode (skip confirmation)
aidp devcontainer apply --force

# Skip backup creation
aidp devcontainer apply --no-backup
```

### `aidp devcontainer list-backups`

List all available backups of your devcontainer.json:

```bash
aidp devcontainer list-backups
# or
aidp devcontainer backups
```

Backups are created automatically before AIDP modifies your devcontainer.json.

### `aidp devcontainer restore`

Restore your devcontainer.json from a backup:

```bash
# Restore from backup at index 0 (most recent)
aidp devcontainer restore 0

# Restore with confirmation
aidp devcontainer restore 0

# Force restore without confirmation
aidp devcontainer restore 0 --force

# Restore without creating a backup of current file
aidp devcontainer restore 0 --no-backup
```

## How It Works

### Auto-Detection

AIDP automatically detects required ports based on wizard configuration:

**Project Type**:

- Web applications (Rails, Sinatra, Express) → Port 3000 (default)
- Custom application port can be specified via `app_port` setting
- CLI tools → No web ports

**Watch Mode**:

- When watch mode is enabled → Port 7681 (Remote Terminal via ttyd)

**Interactive Tools**:

- Playwright → Port 9222 (Chrome DevTools Protocol for debugging)
- MCP Server → Port 8080 (Model Context Protocol, if enabled)

**Custom Services**:

- PostgreSQL → Port 5432
- Redis → Port 6379
- MySQL → Port 3306
- Custom ports defined in `devcontainer.custom_ports`

**Features**:

- Test frameworks (RSpec, Jest, Playwright) → Adds corresponding language features
- Linters (StandardRB, ESLint) → Adds language-specific features
- GitHub CLI → Added for all provider selections

### Intelligent Merging

When you have an existing `.devcontainer/devcontainer.json`, AIDP preserves your customizations:

**Preserved**:

- Custom name
- User-added VS Code extensions
- User-added features
- Custom environment variables
- User-defined settings
- Manually added ports

**Updated**:

- AIDP-managed ports (based on your configuration)
- AIDP-managed features (based on your test frameworks)
- AIDP metadata

**Example**: If you manually added the GitHub Copilot extension, AIDP will keep it while adding/updating its own managed features.

### Backups

AIDP automatically creates timestamped backups before modifying your devcontainer.json:

```text
.aidp/
  backups/
    devcontainer/
      devcontainer.json.20250104_123456
      devcontainer.json.20250104_145530
      metadata/
        devcontainer.json.20250104_123456.json
        devcontainer.json.20250104_145530.json
```

Backups include metadata about why they were created:

- `wizard_update` - Created by the interactive wizard
- `cli_apply` - Created by `aidp devcontainer apply`
- `manual_test` - Created manually for testing

## Port Configuration

### Standard Ports

AIDP uses standard ports for common services:

| Service | Port | Label |
|---------|------|-------|
| Web Application | 3000 | Application (default) |
| Remote Terminal | 7681 | Remote Terminal (ttyd) |
| Playwright Debug | 9222 | Playwright Debug |
| MCP Server | 8080 | MCP Server |
| PostgreSQL | 5432 | PostgreSQL |
| Redis | 6379 | Redis |
| MySQL | 3306 | MySQL |

### Custom Ports

Add custom ports in your `.aidp/aidp.yml`:

```yaml
devcontainer:
  manage: true
  custom_ports:
    - number: 8080
      label: "API Server"
    - number: 9200
      label: "Elasticsearch"
    - number: 3306
      label: "MySQL Database"
```

### Port Attributes

All ports are configured with:

- **Label**: Human-readable description
- **Protocol**: HTTP (default for web servers)
- **Forward automatically**: Yes (ports are forwarded when container starts)

## Features

AIDP automatically adds devcontainer features based on your configuration:

**Test Frameworks**:

- RSpec → `ghcr.io/devcontainers/features/ruby`
- Playwright → `ghcr.io/devcontainers/features/playwright`

**Linters**:

- StandardRB → Ruby feature
- ESLint → Node.js feature

You can add custom features by manually editing the generated devcontainer.json - AIDP will preserve them on subsequent updates.

## Workflow Example

Here's a typical workflow for setting up and managing your devcontainer:

```bash
# 1. Initial setup via wizard
aidp config --interactive
# Answer questions, including devcontainer setup
# Wizard creates .devcontainer/devcontainer.json

# 2. Preview changes before applying
aidp devcontainer diff

# 3. Make changes to aidp.yml
vim .aidp/aidp.yml
# Add custom port for your new microservice

# 4. Preview what would change
aidp devcontainer apply --dry-run

# 5. Apply the changes
aidp devcontainer apply

# 6. If something goes wrong, restore from backup
aidp devcontainer list-backups
aidp devcontainer restore 0
```

## Troubleshooting

### "No configuration found in aidp.yml"

Make sure your `.aidp/aidp.yml` has a `devcontainer` section with `manage: true`:

```yaml
devcontainer:
  manage: true
```

Run `aidp config --interactive` if you haven't set this up yet.

### "Devcontainer.json already exists"

AIDP will automatically merge with your existing configuration. Use `aidp devcontainer diff` to see what would change before applying.

### Custom settings not preserved

AIDP preserves most customizations. If something specific isn't being preserved, please open an issue on GitHub.

### Ports not being detected

Port detection is based on:

- Project file analysis (config.ru, config/routes.rb, etc.)
- Configuration in aidp.yml (test_commands, services, etc.)

You can always add ports manually via `custom_ports` in your configuration.

## Advanced Usage

### Disable Devcontainer Management

To stop AIDP from managing your devcontainer:

```yaml
devcontainer:
  manage: false
```

Or remove the `devcontainer` section entirely from your `aidp.yml`.

### Manual Devcontainer Editing

You can freely edit the generated `.devcontainer/devcontainer.json`. AIDP's intelligent merging will preserve your changes when it updates the file. Just be aware that certain AIDP-managed sections (like port lists) will be updated to match your `aidp.yml` configuration.

### Using with VS Code

Once your `.devcontainer/devcontainer.json` is generated:

1. Open the repository in VS Code
2. VS Code will detect the devcontainer and prompt you to "Reopen in Container"
3. Click "Reopen in Container" to build and start your development environment
4. All ports, features, and settings will be automatically configured

### CI/CD Integration

The devcontainer can also be used in CI/CD:

```bash
# In your CI pipeline
devcontainer build .
devcontainer run-user-commands .
```

## Container Detection

AIDP automatically detects when it's running inside a devcontainer using multiple heuristics:

- **Environment Variables**: `REMOTE_CONTAINERS`, `VSCODE_REMOTE_CONTAINERS`, `CODESPACES`
- **Filesystem Markers**: `/.dockerenv`, `/run/.containerenv`
- **Cgroup Information**: Checks for Docker, Podman, containerd in `/proc/1/cgroup`
- **Hostname Patterns**: Container-specific hostname formats

This detection allows AIDP to adjust its behavior when running in containerized environments. The detection logic is implemented in `lib/aidp/utils/devcontainer_detector.rb`.

## Implementation Details

AIDP's devcontainer management consists of two systems:

1. **Legacy System** (`lib/aidp/init/devcontainer_generator.rb`):
   - Used by early `aidp init` commands
   - Copies template files from AIDP's own `.devcontainer/`
   - Generates static Dockerfile, firewall scripts, and README

2. **Modern System** (`lib/aidp/setup/devcontainer/`):
   - Used by `aidp config --interactive` wizard
   - Generates `devcontainer.json` based on project analysis
   - Supports intelligent merging with existing configurations
   - Provides backup/restore functionality
   - Uses wizard configuration to detect required features and ports

The modern system is recommended for all new projects. See the code in:

- `lib/aidp/setup/devcontainer/generator.rb` - Configuration generation
- `lib/aidp/setup/devcontainer/parser.rb` - Parsing existing configs
- `lib/aidp/setup/devcontainer/port_manager.rb` - Port detection and management
- `lib/aidp/setup/devcontainer/backup_manager.rb` - Backup/restore functionality
- `lib/aidp/cli/devcontainer_commands.rb` - CLI command implementation

## See Also

- [Configuration Reference](CONFIGURATION.md) - Full aidp.yml schema
- [Setup Wizard](SETUP_WIZARD.md) - Interactive configuration guide
- [Devcontainer Specification](https://containers.dev) - Official devcontainer docs
