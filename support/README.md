# Aidp Supervisor Support Scripts

This directory contains support scripts for running Aidp watch mode under various process supervisors in devcontainer environments.

## Overview

Aidp's auto-update feature uses exit code 75 to signal the supervisor that an update is available and should be installed. The supervisor wrapper scripts detect this exit code, run `bundle update aidp`, and restart the process.

## Supported Supervisors

### supervisord

**Files:**
- `supervisord/aidp-watch.conf` - supervisord program configuration
- `supervisord/aidp-watch-wrapper.sh` - Wrapper script that handles updates

**Setup:**

1. Copy the configuration file:
   ```bash
   cp support/supervisord/aidp-watch.conf /etc/supervisor/conf.d/
   ```

2. Copy the wrapper script:
   ```bash
   cp support/supervisord/aidp-watch-wrapper.sh /usr/local/bin/
   chmod +x /usr/local/bin/aidp-watch-wrapper.sh
   ```

3. Set environment variables in supervisor config or export them:
   ```bash
   export PROJECT_DIR=/workspace/your-project
   export HOME=/home/vscode
   export USER=vscode
   ```

4. Reload supervisord:
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

**Files:**
- `s6/aidp-watch/run` - s6 run script
- `s6/aidp-watch/finish` - s6 finish script (handles exit code 75)

**Setup:**

1. Copy the service directory:
   ```bash
   cp -r support/s6/aidp-watch /etc/s6/aidp-watch
   chmod +x /etc/s6/aidp-watch/run
   chmod +x /etc/s6/aidp-watch/finish
   ```

2. Set environment variables:
   ```bash
   export PROJECT_DIR=/workspace/your-project
   ```

3. Enable and start the service:
   ```bash
   s6-svc -u /etc/s6/aidp-watch
   ```

**Monitoring:**
```bash
s6-svstat /etc/s6/aidp-watch
```

### runit

**Files:**
- `runit/aidp-watch/run` - runit run script
- `runit/aidp-watch/finish` - runit finish script (handles exit code 75)

**Setup:**

1. Copy the service directory:
   ```bash
   cp -r support/runit/aidp-watch /etc/sv/aidp-watch
   chmod +x /etc/sv/aidp-watch/run
   chmod +x /etc/sv/aidp-watch/finish
   ```

2. Set environment variables:
   ```bash
   export PROJECT_DIR=/workspace/your-project
   ```

3. Enable and start the service:
   ```bash
   ln -s /etc/sv/aidp-watch /etc/service/
   ```

**Monitoring:**
```bash
sv status aidp-watch
sv log aidp-watch
```

## Environment Variables

All supervisor scripts support the following environment variables:

- `PROJECT_DIR` - Path to your project directory (required)
- `HOME` - User home directory (default: current user's home)
- `USER` - Username (default: current user)

## Logs

The wrapper scripts log to:
- `$PROJECT_DIR/.aidp/logs/wrapper.log` (supervisord)
- `$PROJECT_DIR/.aidp/logs/s6-finish.log` (s6)
- `$PROJECT_DIR/.aidp/logs/runit-finish.log` (runit)

Aidp's own logs are in:
- `$PROJECT_DIR/.aidp/logs/updates.log` - Auto-update audit log
- `$PROJECT_DIR/.aidp/logs/aidp.log` - Main application log

## Auto-Update Configuration

Enable auto-updates in `.aidp/aidp.yml`:

```yaml
auto_update:
  enabled: true
  policy: minor              # off, exact, patch, minor, major
  allow_prerelease: false
  check_interval_seconds: 3600
  supervisor: supervisord    # supervisord, s6, runit
  max_consecutive_failures: 3
```

See `docs/SELF_UPDATE.md` for complete configuration and troubleshooting.

## Troubleshooting

### Wrapper script not found
Ensure the wrapper script is executable and in the correct location:
```bash
which aidp-watch-wrapper.sh
ls -la /usr/local/bin/aidp-watch-wrapper.sh
```

### Updates not triggering
Check that:
1. Auto-update is enabled in `.aidp/aidp.yml`
2. Supervisor is correctly configured
3. Exit code 75 is in the supervisor's restart codes
4. Logs show the update check is running

### Bundle update fails
Check:
1. `Gemfile` allows the newer version of aidp
2. Network connectivity to rubygems.org
3. File permissions on project directory
4. Ruby version compatibility

View update logs:
```bash
cat $PROJECT_DIR/.aidp/logs/updates.log | jq
cat $PROJECT_DIR/.aidp/logs/wrapper.log
```

## Testing

Test the wrapper script manually:
```bash
export PROJECT_DIR=/workspace/your-project
bash support/supervisord/aidp-watch-wrapper.sh
```

Simulate exit code 75:
```bash
# In a test script
exit 75
```

## Security Considerations

- Wrapper scripts use `set -euo pipefail` for safety
- All paths are validated before use
- No shell interpolation of user input
- Logs are append-only
- Bundle respects `Gemfile.lock` to prevent malicious updates

## Further Reading

- [Aidp Self-Update Guide](../docs/SELF_UPDATE.md)
- [Devcontainer Integration](../docs/DEVELOPMENT_CONTAINER.md)
- [Configuration Reference](../docs/CONFIGURATION.md)
