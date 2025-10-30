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
  - AI provider APIs (Anthropic, OpenAI, Google)
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

### Allowlisted Domains

- GitHub (api.github.com, raw.githubusercontent.com, etc.)
- RubyGems (rubygems.org, api.rubygems.org)
- AI Providers (api.anthropic.com, api.openai.com, generativelanguage.googleapis.com)
- VS Code services
- npm registry
- Sentry (error tracking)

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
