# Firewall Configuration Guide

This document explains how the AIDP devcontainer firewall configuration works and how to manage firewall allowlists.

## Overview

The AIDP devcontainer implements strict network access control using a YAML-based configuration file that defines allowed domains and IP ranges. This approach:

- Provides centralized configuration management
- Enables provider classes to declare their firewall requirements
- Supports automatic collection and deduplication of requirements
- Allows fallback mode when YAML parsing is unavailable

## Architecture

### Components

1. **YAML Configuration** (`.aidp/firewall-allowlist.yml`)
   - Single source of truth for firewall rules
   - Defines static IP ranges, Azure ranges, core domains, and provider domains
   - Used by `init-firewall.sh` at container startup

2. **Provider Requirements** (`lib/aidp/providers/*.rb`)
   - Each provider class defines its firewall requirements via `firewall_requirements` class method
   - Returns hash with `:domains` and `:ip_ranges` keys

3. **Requirements Collector** (`lib/aidp/firewall/provider_requirements_collector.rb`)
   - Collects requirements from all provider classes
   - Deduplicates and merges requirements
   - Updates YAML configuration file

4. **Firewall Script** (`.devcontainer/init-firewall.sh`)
   - Reads YAML configuration using `yq`
   - Resolves domains to IPs at runtime
   - Configures iptables and ipset
   - Falls back to essential domains if YAML unavailable

## Configuration File Structure

```yaml
version: 1

# Static IP ranges (always allowed)
static_ip_ranges:
  - cidr: "140.82.112.0/20"
    comment: "GitHub main infrastructure"
  - cidr: "127.0.0.0/8"
    comment: "Localhost"

# Azure IP ranges (for GitHub Copilot and VS Code)
azure_ip_ranges:
  - cidr: "20.189.0.0/16"
    comment: "Azure WestUS2 (broad range due to dynamic IP allocation)"

# Core infrastructure domains
core_domains:
  ruby:
    - "rubygems.org"
    - "api.rubygems.org"
  github:
    - "github.com"
    - "api.github.com"
  # ... other categories

# Provider-specific domains (auto-generated)
provider_domains:
  anthropic:
    - "api.anthropic.com"
    - "claude.ai"
  # ... other providers

# Dynamic IP sources
dynamic_sources:
  github_meta_api:
    url: "https://api.github.com/meta"
    fields: ["git"]
    comment: "GitHub Git protocol IP ranges (dynamically fetched)"
```

## Adding Firewall Requirements

### Option 1: Provider-Specific Domains

For domains required by a specific AI provider:

1. Edit the provider class (e.g., `lib/aidp/providers/anthropic.rb`):

```ruby
# Get firewall requirements for Anthropic provider
def self.firewall_requirements
  {
    domains: [
      "api.anthropic.com",
      "claude.ai",
      "console.anthropic.com",
      "new.domain.com"  # Add new domain
    ],
    ip_ranges: []  # Add IP ranges if needed
  }
end
```

2. Regenerate the configuration:

```bash
bundle exec bin/update-firewall-config
```

3. Verify the update:

```bash
bundle exec bin/update-firewall-config --report
```

### Option 2: Core Infrastructure Domains

For domains not tied to a specific provider (package managers, CDNs, etc.):

1. Edit `.aidp/firewall-allowlist.yml`
2. Add domains under the appropriate category:

```yaml
core_domains:
  package_managers:
    - "existing.domain.com"
    - "new.domain.com"  # Add here
```

3. No regeneration needed for core domains

### Option 3: Static IP Ranges

For IP ranges that should always be allowed:

1. Edit `.aidp/firewall-allowlist.yml`
2. Add to `static_ip_ranges` or `azure_ip_ranges`:

```yaml
static_ip_ranges:
  - cidr: "10.0.0.0/8"
    comment: "Private network range"
```

## Managing Provider Requirements

### Viewing Current Requirements

Generate a report of all provider firewall requirements:

```bash
bundle exec bin/update-firewall-config --report
```

Output example:

```
Firewall Provider Requirements Summary
==================================================

Total Providers: 7
Total Unique Domains: 35
Total Unique IP Ranges: 0

By Provider:
--------------------------------------------------

Anthropic:
  Domains (3):
    - api.anthropic.com
    - claude.ai
    - console.anthropic.com

Cursor:
  Domains (7):
    - api.cursor.sh
    - app.cursor.sh
    - cursor.com
    - cursor.sh
    - downloads.cursor.com
    - www.cursor.com
    - www.cursor.sh

...
```

### Updating Configuration

After modifying provider requirements, update the YAML:

```bash
# Dry run (show what would change)
bundle exec bin/update-firewall-config --dry-run

# Actually update the file
bundle exec bin/update-firewall-config
```

## Firewall Script Operation

The `init-firewall.sh` script:

1. **Checks prerequisites**: Verifies `iptables`, `ipset`, and optionally `yq` are available
2. **Loads configuration**: Reads `.aidp/firewall-allowlist.yml` or falls back to essential domains
3. **Adds IP ranges**: Processes static and Azure IP ranges
4. **Resolves domains**: Uses DNS to resolve domain names to IPs
5. **Fetches GitHub IPs**: Dynamically fetches GitHub's IP ranges from their Meta API
6. **Configures iptables**: Sets up firewall rules with default DROP policy
7. **Verifies**: Tests that allowed domains are accessible and blocked domains are blocked

### Environment Variables

- `FIREWALL_CONFIG`: Path to YAML config (default: `/workspaces/aidp/.aidp/firewall-allowlist.yml`)
- `AIDP_FIREWALL_LOG`: Set to `1` to enable logging of blocked connections

## Troubleshooting

### Firewall Not Working

Check if firewall initialized successfully:

```bash
# In devcontainer
sudo dmesg | grep -i firewall
```

Verify rules are loaded:

```bash
sudo iptables -L OUTPUT -v
sudo ipset list allowed-domains
```

### Domain Blocked Unexpectedly

Enable logging to see what's being blocked:

```bash
export AIDP_FIREWALL_LOG=1
sudo /usr/local/bin/init-firewall.sh

# Monitor logs
sudo dmesg | grep AIDP-FW-BLOCK
```

### YAML Parsing Issues

If `yq` is not available or YAML is malformed:

```bash
# Test YAML syntax
yq eval '.' .aidp/firewall-allowlist.yml

# Fallback mode (uses essential domains only)
# The script automatically falls back if yq is missing
```

### Provider Domain Not Working

1. Verify the provider declares requirements:

```bash
bundle exec ruby -e "require './lib/aidp/providers/anthropic'; p Aidp::Providers::Anthropic.firewall_requirements"
```

2. Check if YAML contains the domain:

```bash
yq eval '.provider_domains.anthropic' .aidp/firewall-allowlist.yml
```

3. Regenerate configuration:

```bash
bundle exec bin/update-firewall-config
```

## Security Considerations

### Why Broad Azure Ranges?

Azure IP ranges use `/16` CIDR blocks because:
- GitHub Copilot and VS Code services use dynamic IP allocation
- IPs change frequently across Azure regions
- Narrow ranges would break service connectivity
- Comments in YAML explain this design decision

### Firewall Bypass

Never bypass the firewall in production. For debugging only:

```bash
# Temporarily disable (container-specific, not persistent)
sudo iptables -P OUTPUT ACCEPT
```

Always re-enable after debugging:

```bash
sudo /usr/local/bin/init-firewall.sh
```

## Best Practices

1. **Provider Requirements**: Always define provider requirements in the provider class, not directly in YAML
2. **Documentation**: Add comments to YAML explaining why broad ranges are needed
3. **Testing**: Verify firewall after adding domains:
   ```bash
   curl -I https://new.domain.com
   ```
4. **Updates**: Regenerate configuration after modifying provider classes
5. **Version Control**: Commit both provider classes and updated YAML together

## Integration with Issue #238

This implementation supports both:
- Devcontainer firewall setup (current)
- Standalone Docker setup firewall (future - issue #238)

The YAML configuration can be reused for both use cases.

## References

- Issue #286: Move devcontainer firewall domain and IP allowlists into separate file
- Issue #238: Standalone Docker setup firewall
- `.devcontainer/README.md`: Devcontainer documentation
- `lib/aidp/providers/base.rb`: Base provider class with `firewall_requirements` method
