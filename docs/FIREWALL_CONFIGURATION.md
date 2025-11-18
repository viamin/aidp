# Firewall Configuration Guide

This document explains how the AIDP devcontainer firewall configuration works and how to manage firewall allowlists.

## Overview

The AIDP devcontainer implements strict network access control using an **auto-generated YAML configuration file** that is built from provider requirements. This approach:

- **Provider classes declare their firewall requirements** via `firewall_requirements` class method
- **Core infrastructure** is defined as constants in `ProviderRequirementsCollector`
- **YAML is auto-generated** during container setup, not manually maintained
- **Single source of truth**: Provider classes and collector constants, not the YAML file
- Supports automatic collection and deduplication of requirements

## Architecture

### Components

1. **Provider Requirements** (`lib/aidp/providers/*.rb`)
   - **Source of truth** for provider-specific firewall requirements
   - Each provider class defines its requirements via `firewall_requirements` class method
   - Returns hash with `:domains` and `:ip_ranges` keys

2. **Requirements Collector** (`lib/aidp/firewall/provider_requirements_collector.rb`)
   - **Source of truth** for core infrastructure requirements (constants)
   - Defines `CORE_DOMAINS`, `STATIC_IP_RANGES`, `AZURE_IP_RANGES`
   - Collects requirements from all provider classes
   - Deduplicates and merges all requirements
   - **Generates** the YAML configuration file

3. **YAML Configuration** (`.aidp/firewall-allowlist.yml`)
   - **Auto-generated build artifact**, not source code
   - Generated during `postCreateCommand` or on-demand via `bin/update-firewall-config`
   - Used by `init-firewall.sh` at container startup
   - **Not committed to git** (in `.aidp/` which is gitignored)

4. **Firewall Script** (`.devcontainer/init-firewall.sh`)
   - Reads YAML configuration using `yq`
   - Auto-generates YAML if missing (failsafe)
   - Resolves domains to IPs at runtime
   - Configures iptables and ipset

## Configuration File Structure

The YAML file is **auto-generated** from:

**Source (Provider Classes + Collector Constants):**
```ruby
# In lib/aidp/providers/anthropic.rb
def self.firewall_requirements
  {
    domains: ["api.anthropic.com", "claude.ai"],
    ip_ranges: []
  }
end

# In lib/aidp/firewall/provider_requirements_collector.rb
CORE_DOMAINS = {
  ruby: ["rubygems.org", "api.rubygems.org"],
  github: ["github.com", "api.github.com"]
}.freeze

STATIC_IP_RANGES = [
  {cidr: "140.82.112.0/20", comment: "GitHub infrastructure"},
  {cidr: "127.0.0.0/8", comment: "Localhost"}
].freeze
```

**Generated YAML (`.aidp/firewall-allowlist.yml`):**
```yaml
version: 1
static_ip_ranges:
  - cidr: "140.82.112.0/20"
    comment: "GitHub main infrastructure"
  - cidr: "127.0.0.0/8"
    comment: "Localhost"
azure_ip_ranges:
  - cidr: "20.189.0.0/16"
    comment: "Azure WestUS2 (broad range due to dynamic IP allocation)"
core_domains:
  ruby:
    - "rubygems.org"
    - "api.rubygems.org"
  github:
    - "github.com"
    - "api.github.com"
provider_domains:
  anthropic:
    - "api.anthropic.com"
    - "claude.ai"
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

1. Edit `lib/aidp/firewall/provider_requirements_collector.rb`
2. Add domains to the `CORE_DOMAINS` constant:

```ruby
CORE_DOMAINS = {
  ruby: [
    "rubygems.org",
    "api.rubygems.org",
    "new.ruby-domain.com"  # Add here
  ],
  # ... other categories
}.freeze
```

3. Regenerate the YAML:

```bash
bundle exec ruby bin/update-firewall-config
```

### Option 3: Static IP Ranges

For IP ranges that should always be allowed:

1. Edit `lib/aidp/firewall/provider_requirements_collector.rb`
2. Add to `STATIC_IP_RANGES` or `AZURE_IP_RANGES`:

```ruby
STATIC_IP_RANGES = [
  {cidr: "140.82.112.0/20", comment: "GitHub infrastructure"},
  {cidr: "10.0.0.0/8", comment: "Private network range"}  # Add here
].freeze
```

3. Regenerate the YAML:

```bash
bundle exec ruby bin/update-firewall-config
```

## Managing Provider Requirements

### Viewing Current Requirements

Generate a report of all provider firewall requirements:

```bash
bundle exec ruby bin/update-firewall-config --report
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

### Regenerating Configuration

After modifying provider requirements or collector constants, regenerate the YAML:

```bash
# Dry run (show what would be generated)
bundle exec ruby bin/update-firewall-config --dry-run

# Actually generate the file
bundle exec ruby bin/update-firewall-config
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
