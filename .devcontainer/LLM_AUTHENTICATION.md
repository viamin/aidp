# LLM CLI Authentication and Configuration

This document explains how LLM provider authentication is configured to persist across devcontainer rebuilds, and how dangerous/auto-approve mode is enabled **only inside the devcontainer** while keeping your host machine safe.

## Overview

The devcontainer uses a **dual-layer approach**:

1. **Authentication**: Shared from host via bind mounts (authenticate once on host)
2. **Dangerous Mode**: Enabled only inside container via wrappers and environment variables

## Authentication Persistence Strategy

The devcontainer is configured to persist LLM CLI credentials using bind mounts from your host:

### 1. Host Directory Mounts (Preferred)

These mounts share your host machine's credentials with the container, so you only need to authenticate once on your host:

- **`~/.claude`** → Container: `/home/vscode/.claude`
  - **Provider**: Claude (Anthropic)
  - **Files shared**:
    - `~/.claude/.credentials.json` - Claude CLI OAuth tokens
    - `~/.claude/settings.json` - Claude CLI settings
  - **Benefit**: Authenticate once on host, works in all containers

- **`~/.config`** → Container: `/home/vscode/.config`
  - **Providers**: Gemini, GitHub CLI/Copilot
  - **Paths shared**:
    - `~/.config/gemini/` - Gemini CLI credentials
    - `~/.config/github-cli/` - GitHub Copilot authentication
  - **Benefit**: Authenticate once on host, works in all containers

- **`~/.cursor`** → Container: `/home/vscode/.cursor`
  - **Provider**: Cursor AI
  - **Includes**: `~/.cursor/mcp.json` (MCP server configuration)
  - **Benefit**: Shares Cursor credentials if you have Cursor installed on host

- **`~/.codex`** → Container: `/home/vscode/.codex`
  - **Provider**: Codex CLI (OpenAI)
  - **Files shared**: `~/.codex/config.toml`, `~/.codex/credentials.json`
  - **Benefit**: Authenticate once on host, works in all containers

- **`~/.aider`** → Container: `/home/vscode/.aider`
  - **Provider**: Aider
  - **Files shared**: `~/.aider/.aider.conf.yml`, `~/.aider/.aider.env`
  - **Benefit**: Authenticate once on host, works in all containers

## Dangerous Mode Configuration (Container-Only)

⚠️ **IMPORTANT**: The devcontainer runs LLM CLI tools in **dangerous/auto-approve mode** for unattended operation. This is safe because of the devcontainer's firewall and isolation, but these settings are **NOT applied to your host machine**.

### How Dangerous Mode Works

Three layers enable auto-approve mode inside the container only:

#### 1. Environment Variables ([devcontainer.json](devcontainer.json#L30-L39))

Set in `containerEnv` - these only exist inside the container:

```json
"CODEX_APPROVAL_POLICY": "never",
"CODEX_SANDBOX_MODE": "danger-full-access",
"OPENCODE_PERMISSION": "allow"
```

#### 2. Binary Wrappers ([configure-llm-tools.sh](configure-llm-tools.sh))

The `postCreateCommand` script creates wrapper scripts at `/usr/local/bin/devcontainer-llm-wrappers/` that intercept CLI commands:

- **Codex**: Adds `-a never -s danger-full-access` flags
- **Claude**: Adds `--dangerously-skip-permissions` flag
- **Gemini**: Points to `/etc/gemini-cli/settings.json` with `"autoAccept": true`
- **OpenCode**: Uses `OPENCODE_PERMISSION` environment variable

#### 3. VSCode Extension Settings ([devcontainer.json](devcontainer.json#L118-L121))

Applied only inside the devcontainer:

```json
"claude-code.dangerouslySkipPermissions": true,
"claude-code.useTerminal": false
```

### Why This Is Safe

- ✅ **Host credentials are shared** (authentication works)
- ✅ **Host configs remain safe** (no dangerous mode on host)
- ✅ **Container isolation** (firewall + restricted network)
- ✅ **Easy reset** (rebuild container if anything goes wrong)

## Provider Authentication Methods

| Provider | CLI Tool | Credential Location | Mount Type | Auth Command | Dangerous Mode |
|----------|----------|---------------------|------------|--------------|----------------|
| **Claude** | `claude` | `~/.claude/.credentials.json` | Host mount | `claude /login` | Wrapper + VSCode setting |
| **Gemini** | `gemini` | `~/.config/gemini/` | Host mount | `gemini auth` | `/etc/gemini-cli/settings.json` |
| **GitHub Copilot** | `copilot` | `~/.config/github-cli/` | Host mount | `gh auth login` | N/A |
| **Cursor** | `cursor-agent` | `~/.cursor/` | Host mount | Via Cursor app | N/A |
| **Codex** | `codex` | `~/.codex/` | Host mount | `codex login` | CLI flags via wrapper |
| **OpenCode** | `opencode` | `~/.config/opencode/` | Host mount | `opencode auth` | Env var `OPENCODE_PERMISSION` |
| **Aider** | `aider` | `~/.aider/` | Host mount | `aider --openrouter-api-key <key>` | Wrapper (non-interactive) |

## First-Time Setup

### On Your Host Machine (Recommended)

Authenticate with CLI tools on your host before starting the devcontainer:

```bash
# Claude
claude /login

# Gemini
gemini auth

# GitHub Copilot
gh auth login
# Then authenticate Copilot separately if needed
```

All authentication happens on the host and is automatically available in the container via bind mounts.

## Verifying Authentication

After container startup, verify each tool is authenticated:

```bash
# Claude
claude --version
echo "test" | claude

# Gemini
gemini --version

# GitHub Copilot
copilot --version

# Cursor (if using)
cursor-agent --version

# Codex (if using)
codex --version

# OpenCode (if using)
opencode --version

# Aider (if using)
aider --version
```

## Troubleshooting

### Tool still asks for permissions inside devcontainer

This shouldn't happen with dangerous mode enabled. If it does:

1. Check that wrapper scripts exist:

   ```bash
   ls -la /usr/local/bin/devcontainer-llm-wrappers/
   ```

2. Verify wrappers are being used:

   ```bash
   which codex  # Should show /usr/local/bin/codex
   which claude # Should show /usr/local/bin/claude
   ```

3. Re-run configuration script:

   ```bash
   /workspaces/aidp/.devcontainer/configure-llm-tools.sh
   ```

### "Authentication required" after rebuild

Check that the host mount is working:

```bash
ls -la ~/.claude/.credentials.json
ls -la ~/.config/gemini
ls -la ~/.config/github-cli
ls -la ~/.codex
```

If missing, authenticate on your host machine first.

### "Permission denied" errors

The container runs as user `vscode`. Ensure mounted directories have appropriate permissions:

```bash
# On host
chmod -R u+rwX ~/.claude ~/.config/gemini ~/.cursor
```

### Mount doesn't exist on host

If `~/.claude` or `~/.cursor` doesn't exist on your host and you get mount errors, you can either:

1. Create the directory on host: `mkdir -p ~/.claude ~/.cursor`
2. Remove unused mounts from [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) if you don't use those tools

## Environment Variable Overrides

Some providers support environment variable configuration in addition to CLI authentication:

```bash
# Gemini - API key override (optional)
export AIDP_GEMINI_API_KEY="your-api-key"

# OpenCode - Model selection (optional)
export OPENCODE_MODEL="github-copilot/claude-3.5-sonnet"

# Timeout overrides (optional, defaults to 300s)
export AIDP_ANTHROPIC_TIMEOUT=600
export AIDP_GEMINI_TIMEOUT=600
export AIDP_GITHUB_COPILOT_TIMEOUT=600
```

## MCP Server Configuration

### Cursor MCP Servers

MCP servers are configured in `~/.cursor/mcp.json` and shared via mount:

```json
{
  "mcpServers": {
    "server_name": {
      "command": "npx",
      "args": ["-y", "package-name"],
      "env": {
        "API_KEY": "value"
      }
    }
  }
}
```

### Claude MCP Servers

Claude MCP servers are managed via the Claude CLI:

```bash
claude mcp list
claude mcp add <server-name>
```

Configuration is stored in `~/.config/claude/` and shared via mount.

## Security Considerations

- **Bind mounts** share your host credentials bidirectionally (container changes affect host)
- **Volumes** are isolated to the container (safer but require re-authentication)
- Never commit credentials or tokens to the repository
- The `.gitignore` excludes credential directories automatically

## Additional Resources

- [AIDP Provider Documentation](../../lib/aidp/providers/)
- [Devcontainer Mounts Reference](https://containers.dev/implementors/json_reference/#mounts)
- [Claude CLI Documentation](https://claude.ai/docs/cli)
- [GitHub CLI Documentation](https://cli.github.com/)
