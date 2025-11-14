# AIDP Development Container

This directory contains the development container configuration for AIDP. The devcontainer provides a sandboxed environment with all necessary tools and strict network access control.

## What's Included

### Base Environment

- **Ruby 3.4.7** with bundler and common development gems
- **Git** with delta for enhanced diffs
- **Zsh** with powerline10k theme and useful plugins
- **Development tools**: vim, nano, fzf, yamllint

### Network Security

- **Strict firewall** with allowlisted domains only
- Access limited to:
  - GitHub and Git repositories
  - Ruby/Gem repositories (rubygems.org)
  - AI provider APIs (Anthropic, OpenAI, Google, OpenRouter)
  - VS Code services
  - Local network

### VS Code Extensions

- **Ruby Development**: Shopify Ruby LSP, StandardRB
- **Git Tools**: GitLens, Git Graph
- **YAML Support**: RedHat YAML extension
- **General**: Code Spell Checker, EditorConfig

### Persistent Storage

- Bash history
- AIDP configuration (~/.aidp)
- Bundler cache (vendor/bundle)

## Usage

### Prerequisites

- [VS Code](https://code.visualstudio.com/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

### Opening in Container

1. Open this project in VS Code
2. Press `F1` or `Cmd+Shift+P` (Mac) / `Ctrl+Shift+P` (Windows/Linux)
3. Select "Dev Containers: Reopen in Container"
4. Wait for the container to build (first time only)

The container will:

1. Build from the Dockerfile
2. Install Ruby dependencies (`bundle install`)
3. Initialize the firewall with allowlisted domains
4. Mount persistent volumes for history and cache

### Working in the Container

Once inside the container:

```bash
# Run tests
bundle exec rspec

# Run AIDP
bundle exec aidp

# Install dependencies
bundle install

# Format code
bundle exec standardrb --fix

# Access git (pre-configured)
git status
```

### Rebuilding the Container

If you modify the Dockerfile or devcontainer.json:

1. Press `F1` or `Cmd+Shift+P`
2. Select "Dev Containers: Rebuild Container"

## Security Features

### Firewall Configuration

The container implements strict outbound network filtering:

- **Default Policy**: DROP all traffic
- **Allowed**: Only explicitly allowlisted domains
- **DNS**: Unrestricted (port 53)
- **SSH**: Allowed (port 22)
- **HTTP/HTTPS**: Only to allowlisted IPs

### Provider Domain Coverage

The allowlist intentionally includes domains needed for authentication and runtime API access for each supported AI provider CLI:

| Provider | Core Domains |
|----------|--------------|
| Anthropic (Claude) | `api.anthropic.com`, `claude.ai`, `console.anthropic.com` |
| OpenAI / Codex | `api.openai.com`, `auth.openai.com`, `openai.com`, `chat.openai.com`, `chatgpt.com`, `cdn.openai.com`, `oaiusercontent.com` |
| Google Gemini | `generativelanguage.googleapis.com`, `oauth2.googleapis.com`, `accounts.google.com`, `www.googleapis.com` |
| GitHub Copilot | `github.com`, `api.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `gist.githubusercontent.com`, `cloud.githubusercontent.com`, `copilot-proxy.githubusercontent.com` |
| Cursor | `api.cursor.sh`, `cursor.sh`, `app.cursor.sh`, `www.cursor.sh` |
| OpenCode | `api.opencode.ai`, `auth.opencode.ai` |
| OpenRouter | `openrouter.ai` |

Additional supporting domains: package registries (`rubygems.org`, `registry.npmjs.org`), VS Code services (updates / marketplace), and a general CDN (`cdn.jsdelivr.net`).

If a provider introduces new endpoints (e.g., beta subdomains), add them in `init-firewall.sh` under the appropriate section.

### Enabling Blocked Domain Logging

Blocked outbound connections can be logged for diagnostics. Logging is disabled by default to avoid noise.

Enable it by setting an environment variable before (re)building the container:

```jsonc
// devcontainer.json
"containerEnv": {
  "AIDP_ENV": "development",
  "AIDP_FIREWALL_LOG": "1"
}
```

Or at runtime (requires container restart of firewall script to take effect):

```bash
docker exec -it <container> bash -lc 'export AIDP_FIREWALL_LOG=1 && sudo /usr/local/bin/init-firewall.sh'
```

When enabled, the script:

1. Creates a custom chain `AIDP_BLOCK_LOG`.
2. Rate-limits logs to `10/min` with a burst of 20.
3. Logs with prefix `AIDP-FW-BLOCK` at kernel log level 4.
4. Drops the packet after logging.

### Inspecting Block Logs

Inside the container:

```bash
sudo dmesg | grep AIDP-FW-BLOCK
# or if journalctl is available
sudo journalctl -k | grep AIDP-FW-BLOCK
```

Each line will include source IP, destination IP, and port. Example:

```text
[12345.678901] AIDP-FW-BLOCK IN=eth0 OUT= MAC=... SRC=172.18.0.5 DST=93.184.216.34 LEN=60 ... DPT=443
```

### Promoting a Blocked Domain to Allowlist

1. Reverse-resolve the destination IP (optional):

  ```bash
  dig -x <IP>
  ```

1. Add an `add_domain "example.com"` line to `init-firewall.sh` in the correct section.

1. Re-run the firewall script or rebuild the container:

  ```bash
  sudo /usr/local/bin/init-firewall.sh
  ```

### Quick Verification of Firewall Health

```bash
# Should succeed
curl -I https://api.openai.com 2>/dev/null | head -n1
curl -I https://api.anthropic.com 2>/dev/null | head -n1

# Should fail (not allowlisted)
timeout 3 curl -I https://example.org || echo "Blocked as expected"
```

### Design Principles

- Fail closed (default DROP) rather than fail open.
- Resolve domains at startup (DNS A records) and build an IP set.
- Keep script idempotent and safe if dependencies (iptables/ipset) are missing.
- Provide optional observability (logging) without overwhelming logs.

### Custom Internal CA Certificates

If your organization performs TLS interception or uses private PKI, you can trust internal root/intermediate CAs by placing PEM files (never committed) in `.devcontainer/custom-ca/` (directory is gitignored). During build these are copied into `/usr/local/share/ca-certificates/` and `update-ca-certificates` runs.

Steps:

1. Obtain PEM-encoded cert(s); convert DER if needed:

  ```bash
  openssl x509 -inform DER -in internal-root.der -out internal-root.pem
  ```

1. Drop `*.pem` files into `.devcontainer/custom-ca/`.
1. Rebuild the container (`Dev Containers: Rebuild Container`).
1. Verify installation:

  ```bash
  grep subject /etc/ssl/certs/*.pem | grep -i 'Internal Root' || echo 'Check installed cert names'
  ```

Node tooling:

If a Node CLI still errors with `self signed certificate in certificate chain`, set:

```jsonc
"containerEnv": {
  "NODE_EXTRA_CA_CERTS": "/etc/ssl/certs/ca-certificates.crt"
}
```

TLS debugging helpers:

```bash
openssl s_client -connect api.openai.com:443 -showcerts </dev/null | head
npm config get cafile
npm config get strict-ssl
```

Temporary (single-command) bypass (avoid committing or scripting):

```bash
NODE_TLS_REJECT_UNAUTHORIZED=0 some_node_cli_command
```

Keep scope narrow; remove after diagnosing.

### Allowlisted Domains

- GitHub (api.github.com, raw.githubusercontent.com, etc.)
- RubyGems (rubygems.org, api.rubygems.org)
- AI Providers (api.anthropic.com, api.openai.com, generativelanguage.googleapis.com)
- VS Code services
- npm registry
- Sentry (error tracking)

See "Provider Domain Coverage" above for the current canonical list. The README list may occasionally drift; `init-firewall.sh` is the source of truth.

### Adding New Domains

To add a new domain to the allowlist:

1. Edit `.devcontainer/init-firewall.sh`
2. Add `add_domain "your.domain.com"` in the appropriate section
3. Rebuild the container

## Customization

### Ruby Version

Edit `devcontainer.json` and change the `RUBY_VERSION` build arg:

```json
"build": {
  "args": {
    "RUBY_VERSION": "3.3.0"
  }
}
```

### Timezone

Set your timezone in `devcontainer.json`:

```json
"build": {
  "args": {
    "TZ": "America/New_York"
  }
}
```

### VS Code Extensions

Add extensions to `devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "publisher.extension-name"
    ]
  }
}
```

## Troubleshooting

### Container Won't Build

- Check Docker is running
- Try "Dev Containers: Rebuild Container Without Cache"
- Check Docker logs for errors

### Network Issues

- Verify firewall initialized: Check container startup logs
- Test with `curl https://rubygems.org`
- If a site is blocked, add it to `init-firewall.sh`

### Permission Errors

- The container runs as user `aidp` (UID 1000)
- Use `sudo` for system-level operations
- Firewall script has sudo access without password

### Slow Performance

- Increase Docker resource limits in Docker Desktop settings
- Consider using Docker volumes instead of bind mounts for better performance

## Development Workflow

### Recommended Workflow

1. Open project in devcontainer
2. Make changes in VS Code
3. Run tests: `bundle exec rspec`
4. Format code: `bundle exec standardrb --fix`
5. Commit changes (git pre-configured)
6. Push to GitHub

### Running AIDP

The container is pre-configured for development:

```bash
# Initialize AIDP in a project
bundle exec aidp init

# Run in analyze mode
bundle exec aidp --mode analyze

# Run in execute mode
bundle exec aidp --mode execute
```

## Benefits of Using Devcontainer

1. **Consistent Environment**: Same setup across all developers
2. **Sandboxed**: Isolated from host system
3. **Network Security**: Strict firewall prevents data exfiltration
4. **Quick Setup**: One command to get started
5. **Reproducible**: Version-controlled configuration
6. **Safe Testing**: Test dangerous operations safely

## Support

For issues or questions about the devcontainer setup:

- Check this README
- Open an issue on GitHub
- Check VS Code's Dev Containers documentation

## Related Documentation

- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Docker Documentation](https://docs.docker.com/)
- [AIDP Documentation](../README.md)
