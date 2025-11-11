# Aidp Self-Update Guide

This guide explains how to configure and use Aidp's self-updating functionality in devcontainer environments.

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Supervisor Setup](#supervisor-setup)
- [CLI Commands](#cli-commands)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Overview

Aidp can automatically update itself when running in watch mode inside devcontainers. This ensures you're always running the latest version without manual intervention.

**Key Features:**

- Semver-based update policies (exact, patch, minor, major)
- Checkpoint system preserves watch mode state across updates
- Restart loop protection prevents infinite failures
- Comprehensive audit logging
- Supervisor integration for seamless restarts

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Aidp Watch Mode                          │
│                                                             │
│  1. Poll GitHub issues                                      │
│  2. Process plan/build triggers                             │
│  3. Check for updates (every check_interval_seconds)        │
│                                                             │
│  IF update available AND allowed by policy:                 │
│    a. Capture current state (paths, triggers, context)      │
│    b. Write checkpoint to .aidp/checkpoints/                │
│    c. Exit with code 75                                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Supervisor (supervisord/s6/runit)              │
│                                                             │
│  Detects exit code 75:                                      │
│    1. Run `bundle update aidp`                              │
│    2. Restart aidp watch                                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Aidp Watch Mode (Restarted)                │
│                                                             │
│  On boot:                                                   │
│    1. Check for checkpoint in .aidp/checkpoints/            │
│    2. Restore watch mode state (repository, interval, etc.) │
│    3. Resume monitoring from where it left off              │
│    4. Delete checkpoint after successful restore            │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

Add auto-update configuration to `.aidp/aidp.yml`:

```yaml
auto_update:
  enabled: true                     # Master switch
  policy: minor                     # Update policy (off, exact, patch, minor, major)
  allow_prerelease: false           # Allow X.Y.Z-alpha/beta/rc versions
  check_interval_seconds: 3600      # Check every hour (min: 300, max: 86400)
  supervisor: supervisord           # Supervisor type (supervisord, s6, runit, none)
  max_consecutive_failures: 3       # Restart loop protection
```

### Update Policies

| Policy | Allows | Example |
|--------|--------|---------|
| `off` | No updates | Always stay on current version |
| `exact` | Exact version only | 1.2.3 → 1.2.3 (no updates) |
| `patch` | Patch updates | 1.2.3 → 1.2.4 ✓, 1.2.3 → 1.3.0 ✗ |
| `minor` | Minor + patch updates | 1.2.3 → 1.3.0 ✓, 1.2.3 → 2.0.0 ✗ |
| `major` | All updates | 1.2.3 → 2.0.0 ✓ |

**Recommendation**: Use `minor` for automatic updates or `patch` for conservative environments.

## Supervisor Setup

Choose one of the supported supervisors based on your devcontainer setup.

### supervisord (Recommended)

**1. Install supervisord:**

```dockerfile
# In your .devcontainer/Dockerfile
RUN apt-get update && apt-get install -y supervisor
```

**2. Copy supervisor configuration:**

```bash
# In your devcontainer postCreateCommand
cp /workspaces/your-project/support/supervisord/aidp-watch.conf /etc/supervisor/conf.d/
cp /workspaces/your-project/support/supervisord/aidp-watch-wrapper.sh /usr/local/bin/
chmod +x /usr/local/bin/aidp-watch-wrapper.sh
```

**3. Set environment variables:**

```json
// In .devcontainer/devcontainer.json
{
  "containerEnv": {
    "PROJECT_DIR": "/workspaces/your-project"
  }
}
```

**4. Start supervisor:**

```bash
supervisorctl reread
supervisorctl update
supervisorctl start aidp-watch
```

**Monitoring:**

```bash
supervisorctl status aidp-watch
supervisorctl tail -f aidp-watch
```

### s6

**1. Install s6:**

```dockerfile
RUN apt-get update && apt-get install -y s6
```

**2. Copy s6 service:**

```bash
cp -r support/s6/aidp-watch /etc/s6/aidp-watch
chmod +x /etc/s6/aidp-watch/run
chmod +x /etc/s6/aidp-watch/finish
```

**3. Start service:**

```bash
s6-svc -u /etc/s6/aidp-watch
```

### runit

**1. Install runit:**

```dockerfile
RUN apt-get update && apt-get install -y runit
```

**2. Copy runit service:**

```bash
cp -r support/runit/aidp-watch /etc/sv/aidp-watch
chmod +x /etc/sv/aidp-watch/run
chmod +x /etc/sv/aidp-watch/finish
```

**3. Enable service:**

```bash
ln -s /etc/sv/aidp-watch /etc/service/
```

## CLI Commands

Manage auto-update settings via the CLI:

### Check Status

```bash
aidp settings auto-update status
```

**Output:**

```
Auto-Update Configuration
============================================================
Enabled: Yes
Policy: minor
Supervisor: supervisord
Allow Prerelease: No
Check Interval: 3600s
Max Consecutive Failures: 3

Current Version: 0.24.0
Latest Available: 0.25.0
Update Available: Yes (allowed by policy)

Failure Tracker:
Consecutive Failures: 0/3
Last Success: 2025-01-15T10:30:00Z
```

### Enable/Disable Auto-Update

```bash
# Enable
aidp settings auto-update on

# Disable
aidp settings auto-update off
```

### Change Update Policy

```bash
aidp settings auto-update policy minor
```

### Toggle Prerelease Updates

```bash
aidp settings auto-update prerelease
```

## Logs

Auto-update maintains comprehensive logs:

### Update Audit Log

Location: `.aidp/logs/updates.log`

Format: JSON Lines

```json
{"timestamp":"2025-01-15T10:30:00Z","event":"check","current_version":"0.24.0","available_version":"0.25.0","update_available":true,"update_allowed":true}
{"timestamp":"2025-01-15T10:30:05Z","event":"update_initiated","checkpoint_id":"uuid-v4","from_version":"0.24.0","to_version":"0.25.0"}
{"timestamp":"2025-01-15T10:30:15Z","event":"restore","checkpoint_id":"uuid-v4","restored_version":"0.25.0"}
{"timestamp":"2025-01-15T10:30:15Z","event":"success","from_version":"0.24.0","to_version":"0.25.0"}
```

### Wrapper Logs

- Supervisord: `.aidp/logs/wrapper.log`
- s6: `.aidp/logs/s6-finish.log`
- runit: `.aidp/logs/runit-finish.log`

### View Recent Updates

```bash
cat .aidp/logs/updates.log | jq 'select(.event=="success")'
```

## Checkpoints

Checkpoints preserve watch mode state across updates.

**Location:** `.aidp/checkpoints/`

**Contents:**

```json
{
  "checkpoint_id": "uuid-v4",
  "created_at": "2025-01-15T10:30:00Z",
  "aidp_version": "0.24.0",
  "mode": "watch",
  "watch_state": {
    "repository": "viamin/aidp",
    "interval": 30,
    "provider_name": "anthropic",
    "persona": null,
    "safety_config": {...},
    "worktree_context": {
      "branch": "main",
      "commit_sha": "abc123",
      "remote_url": "git@github.com:viamin/aidp.git"
    },
    "state_store_snapshot": {
      "plans": {...},
      "builds": {...}
    }
  },
  "metadata": {
    "hostname": "codespace-abc",
    "project_dir": "/workspaces/aidp",
    "ruby_version": "3.3.0"
  },
  "checksum": "sha256-hash"
}
```

**Lifecycle:**

1. Created before update (exit code 75)
2. Validated on next boot (checksum, version compatibility)
3. Restored to resume watch mode
4. Deleted after successful restoration

## Troubleshooting

### Updates Not Triggering

**Check auto-update is enabled:**

```bash
aidp settings auto-update status
```

**Verify supervisor configuration:**

```bash
# supervisord
supervisorctl status aidp-watch

# s6
s6-svstat /etc/s6/aidp-watch

# runit
sv status aidp-watch
```

**Check logs:**

```bash
cat .aidp/logs/updates.log | jq
tail -f .aidp/logs/wrapper.log
```

### Bundle Update Fails

**Gemfile version constraint:**

```ruby
# Gemfile - ensure it allows updates
gem "aidp" # Good - no constraint
gem "aidp", "~> 0.24" # OK - allows minor updates
gem "aidp", "= 0.24.0" # Bad - locked to exact version
```

**Network connectivity:**

```bash
# Test RubyGems connectivity
gem list --remote aidp
```

**File permissions:**

```bash
# Ensure project directory is writable
ls -la /workspaces/your-project
```

### Restart Loop Detected

If you see "Too many consecutive update failures", check:

**1. View failure log:**

```bash
cat .aidp/auto_update_failures.json
```

**2. Check recent update attempts:**

```bash
cat .aidp/logs/updates.log | jq 'select(.event=="failure")'
```

**3. Reset failure tracker (emergency):**

```bash
rm .aidp/auto_update_failures.json
aidp settings auto-update off
aidp settings auto-update on
```

**4. Manual update:**

```bash
bundle update aidp
```

### Checkpoint Restore Fails

**Invalid checkpoint (checksum mismatch):**

Checkpoints are validated via SHA256 checksum. If corrupted:

```bash
# Remove invalid checkpoint
rm .aidp/checkpoints/*.json

# Restart watch mode (fresh start)
aidp watch https://github.com/org/repo/issues
```

**Incompatible version:**

Checkpoints from major version N may not be compatible with N+1.

**Recovery:**

```bash
# Clear checkpoints and restart fresh
rm -rf .aidp/checkpoints/
aidp watch https://github.com/org/repo/issues
```

## Security Considerations

### Safe Update Mechanism

1. **Bundler Respects Gemfile.lock**: Updates use `bundle update aidp`, which:
   - Respects version constraints in Gemfile
   - Only updates the aidp gem, not dependencies (unless necessary)
   - Uses verified gem signatures from RubyGems.org

2. **Opt-In By Default**: Auto-update is disabled by default (`enabled: false`)

3. **Audit Trail**: All update attempts logged to `.aidp/logs/updates.log`

4. **Checksum Validation**: Checkpoints verified via SHA256 before restoration

5. **Restart Loop Protection**: Max 3 consecutive failures before disabling auto-update

### Best Practices

**1. Use conservative update policies in production-like environments:**

```yaml
auto_update:
  enabled: true
  policy: patch # Only patch updates
  allow_prerelease: false
  max_consecutive_failures: 2
```

**2. Review update logs regularly:**

```bash
# View last 10 updates
cat .aidp/logs/updates.log | tail -n 10 | jq
```

**3. Test major updates manually first:**

```yaml
auto_update:
  policy: minor # Block major updates
```

**4. Monitor supervisor logs:**

```bash
tail -f .aidp/logs/wrapper.log
```

**5. Use file permissions:**

```bash
# Restrict checkpoint directory
chmod 700 .aidp/checkpoints/
```

## Integration with Watch Mode

Auto-update is designed specifically for watch mode (`aidp watch`). It does NOT affect:

- Interactive mode (`aidp`)
- Init mode (`aidp init`)
- One-off commands (`aidp settings`, `aidp jobs`, etc.)

**Workflow:**

```bash
# 1. Configure auto-update
aidp settings auto-update on
aidp settings auto-update policy minor

# 2. Start watch mode (supervisor manages restarts)
supervisorctl start aidp-watch

# 3. Monitor
supervisorctl status aidp-watch
tail -f .aidp/logs/updates.log
```

## Example Devcontainer Setup

```json
// .devcontainer/devcontainer.json
{
  "name": "Aidp Development",
  "dockerFile": "Dockerfile",
  "containerEnv": {
    "PROJECT_DIR": "/workspaces/my-project"
  },
  "postCreateCommand": "bash .devcontainer/setup-supervisor.sh",
  "forwardPorts": []
}
```

```bash
#!/bin/bash
# .devcontainer/setup-supervisor.sh

set -euo pipefail

# Install supervisor
sudo apt-get update
sudo apt-get install -y supervisor

# Copy supervisor config
sudo cp support/supervisord/aidp-watch.conf /etc/supervisor/conf.d/
sudo cp support/supervisord/aidp-watch-wrapper.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/aidp-watch-wrapper.sh

# Set up aidp auto-update
mise exec -- bundle exec aidp settings auto-update on
mise exec -- bundle exec aidp settings auto-update policy minor

# Start supervisor
sudo supervisord -c /etc/supervisor/supervisord.conf
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start aidp-watch

echo "Aidp watch mode started with auto-update enabled"
echo "Monitor with: supervisorctl status aidp-watch"
```

## Frequently Asked Questions

### Can I use auto-update outside of devcontainers?

Yes, but it's designed for ephemeral environments. In persistent environments (e.g., production servers), manual updates are recommended for better control.

### What happens if the update breaks something?

The restart loop protection prevents infinite failures. After 3 consecutive failures, auto-update is disabled automatically. Manual intervention required.

### Can I rollback to a previous version?

Bundler maintains Gemfile.lock. To rollback:

```bash
# Revert Gemfile.lock
git checkout HEAD^ -- Gemfile.lock
bundle install

# Or specify version explicitly
bundle update aidp --conservative --patch
```

### Does auto-update work with custom gem sources?

Yes, as long as the source is configured in your Gemfile:

```ruby
source "https://rubygems.pkg.github.com/your-org"
gem "aidp"
```

### How do I test auto-update locally?

See `support/README.md` for supervisor setup instructions. Test with:

```bash
# Simulate exit code 75
exit 75

# Or test wrapper script directly
bash support/supervisord/aidp-watch-wrapper.sh
```

---

For more information:

- [Configuration Reference](CONFIGURATION.md)
- [Development Containers](DEVELOPMENT_CONTAINER.md)
- [Watch Mode Safety](WATCH_MODE_SAFETY.md)
