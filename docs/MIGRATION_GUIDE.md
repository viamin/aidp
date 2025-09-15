# Migration Guide: From Legacy Interface to Enhanced TUI

This guide helps you migrate from the legacy AIDP interface to the new Enhanced TUI system.

## Overview

The Enhanced TUI is a complete overhaul of the AIDP interface that provides:
- Rich terminal components with progress bars, spinners, and status indicators
- Interactive navigation with hierarchical menus
- Real-time dashboards and monitoring
- Workflow control with pause, resume, cancel, and stop operations
- Background job management

## What's New

### New Commands

| Legacy Command | New TUI Command | Description |
|----------------|-----------------|-------------|
| `aidp execute` | `aidp execute` (enhanced) | Now with rich TUI by default |
| `aidp analyze` | `aidp analyze` (enhanced) | Now with rich TUI by default |
| `aidp status` | `aidp status` (enhanced) | Enhanced with TUI formatting |
| N/A | `aidp dashboard` | New TUI dashboard |
| N/A | `aidp jobs` | Background job management |
| N/A | `aidp harness status` | Detailed harness status |

### New Options

| Option | Description |
|--------|-------------|
| `--no-harness` | Use traditional mode (legacy behavior) |
| `--dashboard` | Show TUI dashboard during execution |
| `--view <view>` | Specify dashboard view (jobs, metrics, errors) |

## Migration Steps

### 1. Update Your Workflow

#### Before (Legacy)
```bash
# Simple step-by-step execution
aidp execute next
aidp analyze 01_REPOSITORY_ANALYSIS
aidp status
```

#### After (Enhanced TUI)
```bash
# Rich TUI experience (default)
aidp execute                    # Full TUI workflow
aidp analyze                    # Full TUI workflow
aidp status                     # Enhanced status display

# Access dashboard
aidp dashboard

# Traditional mode (if needed)
aidp execute --no-harness      # Legacy behavior
```

### 2. Update Your Scripts

#### Before
```bash
#!/bin/bash
# Legacy script
aidp execute next
if [ $? -eq 0 ]; then
    echo "Step completed"
    aidp execute next
fi
```

#### After
```bash
#!/bin/bash
# Enhanced TUI script
aidp execute                    # Full TUI workflow
if [ $? -eq 0 ]; then
    echo "Workflow completed successfully"
    aidp dashboard --view metrics  # Check performance
fi
```

### 3. Update Your CI/CD

#### Before
```yaml
# Legacy CI configuration
- name: Run AIDP Analysis
  run: |
    aidp analyze --background
    aidp status
```

#### After
```yaml
# Enhanced TUI CI configuration
- name: Run AIDP Analysis
  run: |
    aidp analyze --no-harness  # Use traditional mode in CI
    aidp status
```

### 4. Update Your Configuration

#### Before
```yaml
# aidp.yml (legacy)
providers:
  default: claude
  fallback: gemini
```

#### After
```yaml
# aidp.yml (enhanced)
providers:
  default: claude
  fallback: gemini

# New TUI configuration
tui:
  enabled: true
  dashboard:
    auto_refresh: true
    refresh_interval: 2
  navigation:
    show_breadcrumbs: true
    keyboard_shortcuts: true
  display:
    show_progress: true
    show_animations: true
    color_scheme: "default"
```

## Backward Compatibility

### What Still Works

✅ **All existing commands** continue to work exactly as before
✅ **All existing options** are preserved
✅ **All existing configuration** is still valid
✅ **File-based agent interaction** is still supported
✅ **Existing templates** remain compatible

### What's Different

🔄 **Default behavior**: Commands now use TUI by default
🔄 **Visual experience**: Rich terminal components instead of plain text
🔄 **Navigation**: Interactive menus instead of command-line options
🔄 **Status display**: Enhanced formatting with progress indicators

### Opting Out

If you prefer the legacy interface:

```bash
# Use traditional mode for all commands
aidp execute --no-harness
aidp analyze --no-harness

# Or set environment variable
export AIDP_NO_TUI=true
aidp execute
aidp analyze
```

## New Features You Can Use

### 1. Interactive Dashboard

```bash
# Access the main dashboard
aidp dashboard

# Specific views
aidp dashboard --view jobs      # Job monitoring
aidp dashboard --view metrics   # Performance metrics
aidp dashboard --view errors    # Error tracking
```

### 2. Workflow Control

```bash
# During execution, use keyboard shortcuts:
# Ctrl+P - Pause workflow
# Ctrl+R - Resume workflow
# Ctrl+S - Stop workflow
# Ctrl+C - Cancel workflow
```

### 3. Background Job Management

```bash
# Monitor background jobs
aidp jobs

# Filter jobs by status
aidp jobs --status running
aidp jobs --status completed
aidp jobs --status failed
```

### 4. Enhanced Status

```bash
# Rich status display
aidp status

# Detailed harness status
aidp harness status --mode analyze
aidp harness status --mode execute
```

## Troubleshooting Migration

### Issue: TUI Not Working

**Symptoms**: Commands show plain text instead of rich TUI
**Solution**:
```bash
# Check terminal compatibility
aidp status

# Use traditional mode
aidp execute --no-harness
```

### Issue: Navigation Not Responding

**Symptoms**: Keyboard navigation doesn't work
**Solution**:
```bash
# Use traditional mode
aidp execute --no-harness

# Or try different terminal
```

### Issue: Performance Issues

**Symptoms**: TUI is slow or unresponsive
**Solution**:
```bash
# Disable animations
aidp execute --no-dashboard

# Use traditional mode
aidp execute --no-harness
```

### Issue: Scripts Breaking

**Symptoms**: Existing scripts fail with TUI
**Solution**:
```bash
# Add --no-harness to scripts
aidp execute --no-harness
aidp analyze --no-harness
```

## Best Practices

### For Interactive Use

1. **Use TUI by default** for the best experience
2. **Use the dashboard** to monitor long-running workflows
3. **Learn keyboard shortcuts** for faster navigation
4. **Use traditional mode** only when necessary

### For Scripts and CI

1. **Use `--no-harness`** in scripts and CI environments
2. **Set environment variables** for consistent behavior
3. **Test both modes** to ensure compatibility
4. **Use status commands** to check results

### For Configuration

1. **Start with defaults** and customize as needed
2. **Use TUI configuration** to optimize your experience
3. **Keep legacy configuration** for backward compatibility
4. **Test configuration changes** before deploying

## Getting Help

### Documentation

- [TUI User Guide](TUI_USER_GUIDE.md) - Comprehensive TUI documentation
- [Style Guide](STYLE_GUIDE.md) - Coding standards and patterns
- [Main README](../README.md) - General AIDP documentation

### Commands

```bash
# Get help for any command
aidp --help
aidp execute --help
aidp analyze --help
aidp dashboard --help

# Show TUI help
aidp dashboard --help
```

### Support

If you encounter issues during migration:

1. **Check the troubleshooting section** above
2. **Use traditional mode** as a fallback
3. **Report issues** with terminal and system information
4. **Check the documentation** for detailed guidance

## Summary

The Enhanced TUI provides a significantly improved user experience while maintaining full backward compatibility. You can:

- **Migrate gradually** - use TUI for interactive work, traditional mode for scripts
- **Opt out completely** - use `--no-harness` for legacy behavior
- **Customize your experience** - configure TUI settings to your preferences
- **Get help when needed** - comprehensive documentation and help system

The migration is designed to be smooth and non-disruptive, allowing you to adopt new features at your own pace.
