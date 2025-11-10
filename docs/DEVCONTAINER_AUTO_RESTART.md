# Devcontainer Auto-Restart with Rerun

This guide explains how to use [rerun](https://github.com/alexch/rerun) to automatically restart AIDP when files change during development in a devcontainer.

## Overview

Rerun is a lightweight command-line tool that monitors filesystem changes and automatically restarts your application. It's ideal for development workflows where you want immediate feedback after code changes.

## Installation

### In Devcontainer

Add rerun to your Gemfile:

```ruby
# Gemfile
group :development do
  gem "rerun", "~> 0.14.0"
end
```

Then run:

```bash
bundle install
```

### Manual Installation

```bash
gem install rerun
```

### System Requirements

- **Ubuntu/Linux**: Works out of the box (uses inotify)
- **macOS**: Requires `gem install rb-fsevent`
- **Windows**: Requires `gem install wdm`

## Basic Usage

### Auto-restart AIDP on File Changes

```bash
# Watch Ruby files and restart AIDP
rerun --pattern "**/*.rb" -- bin/aidp

# Watch specific directories
rerun --dir lib --dir spec -- bin/aidp

# Custom pattern for Ruby and YAML files
rerun --pattern "**/*.{rb,yml}" -- bin/aidp
```

### Watch Tests

```bash
# Auto-run tests when files change
rerun --pattern "**/*.rb" -- bundle exec rspec

# Run specific test file
rerun --pattern "lib/**/*.rb,spec/**/*_spec.rb" -- bundle exec rspec spec/aidp/providers/
```

### Watch Harness Configuration

```bash
# Restart when .aidp/ config changes
rerun --dir .aidp --pattern "**/*.{yml,yaml,json}" -- bin/aidp
```

## Advanced Configuration

### Configuration File

Create `.rerun` in your project root:

```ruby
# .rerun
--pattern **/*.{rb,yml,yaml}
--dir lib
--dir .aidp
--signal TERM
--no-notify
```

Then simply run:

```bash
rerun -- bin/aidp
```

### Common Options

```bash
# Ignore specific directories
rerun --ignore "tmp/**,log/**" -- bin/aidp

# Add delay before restart (seconds)
rerun --wait 2 -- bin/aidp

# Clear screen before each restart
rerun --clear -- bin/aidp

# Background mode (less intrusive)
rerun --background -- bin/aidp

# Custom restart signal
rerun --signal INT -- bin/aidp
```

### Interactive Commands

While rerun is running, you can use keyboard commands:

- `r` - Force restart now
- `f` - Force restart (even if nothing changed)
- `p` - Pause/unpause file watching
- `x` - Exit rerun

## Devcontainer Integration

### Option 1: VSCode Task

Add to `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "AIDP Auto-Restart",
      "type": "shell",
      "command": "rerun",
      "args": [
        "--pattern", "**/*.{rb,yml}",
        "--dir", "lib",
        "--dir", ".aidp",
        "--clear",
        "--",
        "bin/aidp"
      ],
      "isBackground": true,
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    },
    {
      "label": "Tests Auto-Run",
      "type": "shell",
      "command": "rerun",
      "args": [
        "--pattern", "**/*.rb",
        "--dir", "lib",
        "--dir", "spec",
        "--clear",
        "--",
        "bundle", "exec", "rspec"
      ],
      "isBackground": true,
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    }
  ]
}
```

Run with: `Tasks: Run Task` → `AIDP Auto-Restart`

### Option 2: Devcontainer Post-Start Command

Add to `.devcontainer/devcontainer.json`:

```json
{
  "postStartCommand": "rerun --background --pattern '**/*.rb' -- bin/aidp",
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  }
}
```

### Option 3: Docker Compose Service

Add to `docker-compose.yml`:

```yaml
services:
  aidp-dev:
    build: .
    volumes:
      - .:/workspace
    command: rerun --pattern "**/*.rb" -- bin/aidp
    environment:
      - AIDP_ENV=development
```

## Use Cases

### 1. Provider Development

Monitor provider changes and auto-restart:

```bash
rerun \
  --pattern "lib/aidp/providers/**/*.rb" \
  --pattern "lib/aidp/harness/**/*.rb" \
  --clear \
  -- bin/aidp providers
```

### 2. Configuration Iteration

Watch config files and show provider status:

```bash
rerun \
  --dir .aidp \
  --pattern "**/*.{yml,yaml}" \
  --clear \
  -- bin/aidp providers info
```

### 3. Test-Driven Development

Auto-run tests on save:

```bash
rerun \
  --pattern "{lib,spec}/**/*.rb" \
  --clear \
  -- bundle exec rspec --format documentation
```

### 4. Harness Development

Watch harness components and restart:

```bash
rerun \
  --pattern "lib/aidp/harness/**/*.rb" \
  --pattern "lib/aidp/providers/**/*.rb" \
  --clear \
  -- bin/aidp harness status
```

## Performance Considerations

### CPU Usage

Rerun uses OS-native file watching, which is very efficient:

- **Linux (inotify)**: Negligible CPU usage
- **macOS (FSEvents)**: Minimal CPU usage
- **Windows (WDM)**: Low CPU usage

### Large Codebases

For large projects, limit watched directories:

```bash
# Good: Watch specific directories
rerun --dir lib/aidp/providers -- bin/aidp

# Avoid: Watching entire node_modules or vendor
rerun --ignore "node_modules/**,vendor/**" -- bin/aidp
```

## Troubleshooting

### Rerun Not Detecting Changes

1. Check file patterns:
   ```bash
   # Debug mode shows what files are being watched
   rerun --verbose --pattern "**/*.rb" -- bin/aidp
   ```

2. Verify inotify limits (Linux):
   ```bash
   # Check current limit
   cat /proc/sys/fs/inotify/max_user_watches

   # Increase limit if needed
   echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

### Restart Loops

If AIDP writes files that trigger restarts:

```bash
# Ignore output directories
rerun \
  --ignore "tmp/**,log/**,.aidp/cache/**" \
  -- bin/aidp
```

### Permission Errors in Devcontainer

Ensure rerun has correct permissions:

```bash
# In devcontainer.json
"remoteUser": "vscode",
"postCreateCommand": "bundle install"
```

## Alternatives

If rerun doesn't fit your needs:

1. **Guard** - More features, Ruby-focused
   ```bash
   gem install guard guard-rspec
   guard init rspec
   guard
   ```

2. **Watchman** - Facebook's file watching service
   ```bash
   apt-get install watchman
   watchman-make -p 'lib/**/*.rb' -t test
   ```

3. **Nodemon** - JavaScript ecosystem (can run any command)
   ```bash
   npm install -g nodemon
   nodemon --exec "bin/aidp" --watch lib --ext rb
   ```

## Best Practices

1. **Use .rerun file** for project-specific defaults
2. **Ignore temporary files** to avoid restart loops
3. **Clear screen** (`--clear`) for clean output
4. **Watch specific directories** for better performance
5. **Use background mode** for less intrusive development

## Example .rerun Configuration

```ruby
# .rerun
# Auto-restart AIDP on file changes

# Watch patterns
--pattern **/*.{rb,yml,yaml}

# Watch directories
--dir lib/aidp/providers
--dir lib/aidp/harness
--dir .aidp

# Ignore directories
--ignore tmp/**
--ignore log/**
--ignore coverage/**
--ignore .git/**

# Options
--clear
--signal TERM
--wait 1

# No desktop notifications in devcontainer
--no-notify
```

## Integration with CI/CD

Rerun is for development only. Don't use in production or CI:

```ruby
# Gemfile
group :development do
  gem "rerun"
end
```

## Summary

Rerun is an excellent choice for devcontainer auto-restart because:

- ✅ Works out-of-the-box on Ubuntu/Linux
- ✅ Lightweight and efficient
- ✅ Simple command-line interface
- ✅ No complex configuration required
- ✅ Interactive controls during development
- ✅ Integrates well with VSCode tasks

For most AIDP development workflows in a devcontainer, start with:

```bash
rerun --pattern "**/*.{rb,yml}" --clear -- bin/aidp
```

Then customize based on your specific needs.
