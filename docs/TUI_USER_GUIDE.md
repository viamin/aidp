# AIDP Enhanced TUI User Guide

This guide covers the new Terminal User Interface (TUI) features in AIDP, providing a rich, interactive terminal experience for managing AI development workflows.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [TUI Components](#tui-components)
- [Navigation](#navigation)
- [Workflow Control](#workflow-control)
- [Dashboard Features](#dashboard-features)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)

## Overview

The Enhanced TUI transforms AIDP from a simple command-line tool into a rich, interactive terminal application. It provides:

- **Beautiful Visual Components**: Progress bars, spinners, frames, and status indicators
- **Interactive Navigation**: Hierarchical menus with breadcrumb navigation
- **Real-time Monitoring**: Live dashboards for job status and system health
- **Workflow Control**: Pause, resume, cancel, and stop operations with visual feedback
- **Smart Question Collection**: Interactive prompts with validation and error handling

## Getting Started

### Basic TUI Usage

```bash
# Run with enhanced TUI (default)
aidp execute
aidp analyze

# Access the main dashboard
aidp dashboard

# Show enhanced status
aidp status
```

### Traditional Mode

If you prefer the original step-by-step interface:

```bash
# Disable TUI and use traditional mode
aidp execute --no-harness
aidp analyze --no-harness
```

## TUI Components

### Progress Display

The TUI shows real-time progress with beautiful progress bars:

```
🔄 Processing Step 2/5: Architecture Analysis
████████████████████████████████████████ 80% (4.2s remaining)
```

### Status Indicators

Different status types with appropriate icons and colors:

- **Loading**: ⏳ Blue spinner with message
- **Success**: ✅ Green checkmark with completion message
- **Error**: ❌ Red X with error details
- **Warning**: ⚠️ Yellow warning with caution message

### Interactive Frames

Organized content in nested frames:

```
📋 Main Workflow
├── 📝 Step 1: PRD Generation
│   ├── 🔧 Question Collection
│   └── ✅ PRD Creation
└── 📝 Step 2: Architecture Design
    ├── 🔧 Analysis
    └── ✅ Architecture Document
```

### Question Collection

Interactive prompts with validation:

```
❓ What is the main goal of this feature?
   ┌─────────────────────────────────────┐
   │ To enhance the user interface with  │
   │ rich terminal components            │
   └─────────────────────────────────────┘
   ✅ Valid input received
```

## Navigation

### Hierarchical Menus

Navigate through nested menus with clear hierarchy:

```
🏠 Main Menu
├── 🚀 Execute Workflow
│   ├── 📋 Simple Mode
│   └── ⚙️ Advanced Mode
├── 🔍 Analyze Workflow
│   ├── 📊 Repository Analysis
│   ├── 🏗️ Architecture Analysis
│   └── 🧪 Test Analysis
└── 📊 Dashboard
    ├── 📈 Overview
    ├── 🔄 Jobs
    └── 📊 Metrics
```

### Breadcrumb Navigation

Always know where you are in the navigation:

```
Home > Execute Workflow > Advanced Mode > Step Selection
```

### Keyboard Navigation

- **Arrow Keys**: Navigate menu options
- **Enter**: Select option
- **Escape**: Go back or cancel
- **Tab**: Move between sections
- **Ctrl+C**: Stop current operation

## Workflow Control

### Pause and Resume

```bash
# During workflow execution, press Ctrl+P to pause
# The TUI will show:
⏸️ Workflow Paused
   Press Ctrl+R to resume
   Press Ctrl+S to stop
   Press Ctrl+C to cancel

# Resume with Ctrl+R
▶️ Workflow Resumed
   Continuing from Step 3: Implementation
```

### Cancel and Stop

```bash
# Cancel workflow (graceful shutdown)
⏹️ Workflow Cancelled
   All resources cleaned up
   Progress saved for resumption

# Stop workflow (immediate termination)
🛑 Workflow Stopped
   Immediate termination requested
   Cleanup in progress...
```

### Real-time Status

Monitor workflow progress in real-time:

```
🔄 Current Workflow: Execute Mode
├── 📊 Progress: 3/7 steps completed (43%)
├── ⏱️ Duration: 2m 15s
├── 🎯 Current Step: Implementation
├── 🤖 Provider: Claude (Primary)
└── 📈 Success Rate: 100%
```

## Dashboard Features

### Main Dashboard

Access the comprehensive dashboard:

```bash
aidp dashboard
```

The dashboard provides:

- **Overview**: System status and recent activity
- **Jobs**: Background job monitoring and management
- **Metrics**: Performance statistics and analytics
- **Errors**: Error tracking and resolution suggestions
- **History**: Workflow execution history
- **Settings**: TUI configuration options

### Job Monitoring

Monitor background jobs in real-time:

```
🔄 Background Jobs
├── ✅ Job 1: PRD Generation (Completed - 45s)
├── 🔄 Job 2: Architecture Analysis (Running - 2m 15s)
│   └── Progress: ████████████████░░░░ 80%
└── ⏳ Job 3: Test Generation (Queued)
```

### Performance Metrics

View system performance:

```
📊 Performance Metrics
├── ⚡ Average Response Time: 2.3s
├── 🎯 Success Rate: 98.5%
├── 🔄 Total Workflows: 47
├── ⏱️ Average Duration: 8m 32s
└── 🤖 Provider Usage:
    ├── Claude: 65%
    ├── Gemini: 25%
    └── Cursor: 10%
```

## Keyboard Shortcuts

### Global Shortcuts

- **Ctrl+C**: Stop current operation
- **Ctrl+P**: Pause workflow
- **Ctrl+R**: Resume workflow
- **Ctrl+S**: Stop workflow
- **Ctrl+Q**: Quit application
- **F1**: Show help
- **F2**: Toggle dashboard
- **F3**: Show status

### Navigation Shortcuts

- **↑/↓**: Navigate menu options
- **←/→**: Navigate between sections
- **Enter**: Select/confirm
- **Escape**: Back/cancel
- **Tab**: Next field/section
- **Shift+Tab**: Previous field/section

### Dashboard Shortcuts

- **1-9**: Switch to dashboard view
- **R**: Refresh data
- **F**: Filter results
- **S**: Sort results
- **H**: Show/hide help

## Troubleshooting

### Common Issues

#### TUI Not Displaying Correctly

```bash
# Check terminal compatibility
aidp status

# If issues persist, use traditional mode
aidp execute --no-harness
```

#### Navigation Not Working

- Ensure your terminal supports ANSI escape codes
- Try resizing your terminal window
- Use traditional mode if keyboard navigation fails

#### Performance Issues

```bash
# Check system resources
aidp dashboard --view metrics

# Reduce TUI complexity
aidp execute --no-dashboard
```

### Error Messages

#### "TUI Component Failed to Load"

This usually indicates a terminal compatibility issue:

1. Try using a different terminal emulator
2. Use traditional mode: `aidp execute --no-harness`
3. Check your terminal's color and Unicode support

#### "Navigation State Corrupted"

If navigation becomes unresponsive:

1. Press **Escape** multiple times to reset
2. Use **Ctrl+C** to exit and restart
3. Clear navigation history: `aidp harness reset --mode execute`

#### "Dashboard Not Responding"

If the dashboard becomes unresponsive:

1. Press **R** to refresh
2. Press **F2** to toggle dashboard
3. Restart the application

### Getting Help

```bash
# Show TUI help
aidp dashboard --help

# Show all available commands
aidp --help

# Show specific command help
aidp execute --help
aidp analyze --help
aidp dashboard --help
```

### Configuration

Customize TUI behavior in your `aidp.yml`:

```yaml
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

## Best Practices

### Workflow Management

1. **Use the dashboard** to monitor long-running workflows
2. **Pause workflows** when you need to step away
3. **Check status regularly** to stay informed
4. **Use keyboard shortcuts** for faster navigation

### Performance

1. **Close unused dashboard views** to reduce resource usage
2. **Use traditional mode** for simple, quick operations
3. **Monitor system resources** through the metrics view
4. **Clear history periodically** to maintain performance

### Troubleshooting

1. **Start with traditional mode** if TUI has issues
2. **Check terminal compatibility** before using advanced features
3. **Use the help system** for guidance
4. **Report issues** with terminal and system information

---

For more information, see the [main README](../README.md) or run `aidp --help` for command reference.
