# AIDP Enhanced TUI User Guide

This guide covers the new Terminal User Interface (TUI) features in AIDP, providing a rich, interactive terminal experience for managing AI development workflows.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [TUI Components](#tui-components)
- [Navigation](#navigation)
- [Workflow Control](#workflow-control)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)

## Overview

The Enhanced TUI transforms AIDP from a simple command-line tool into a rich, interactive terminal application. It provides:

- **Beautiful Visual Components**: Progress bars, spinners, frames, and status indicators
- **Interactive Navigation**: Hierarchical menus with breadcrumb navigation
- **Real-time Monitoring**: Live progress tracking and system health
- **Workflow Control**: Pause, resume, cancel, and stop operations with visual feedback
- **Smart Question Collection**: Interactive prompts with validation and error handling

## Getting Started

### Basic TUI Usage

```bash
# Start the interactive TUI (default)
aidp

# Show version information
aidp --version

# Show help information
aidp --help
```

## TUI Components

### Progress Display

The TUI shows real-time progress with beautiful progress bars:

```text
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

```text
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

```text
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

```text
🏠 Main Menu
├── 🚀 Execute Workflow
│   ├── 📋 Simple Mode
│   └── ⚙️ Advanced Mode
└── 🔍 Analyze Workflow
    ├── 📊 Repository Analysis
    ├── 🏗️ Architecture Analysis
    └── 🧪 Test Analysis
```

### Breadcrumb Navigation

Always know where you are in the navigation:

```text
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

```text
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

```text
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

```text
🔄 Current Workflow: Execute Mode
├── 📊 Progress: 3/7 steps completed (43%)
├── ⏱️ Duration: 2m 15s
├── 🎯 Current Step: Implementation
├── 🤖 Provider: Claude (Primary)
└── 📈 Success Rate: 100%
```

## Keyboard Shortcuts

### Global Shortcuts

- **Ctrl+C**: Stop current operation
- **Ctrl+P**: Pause workflow
- **Ctrl+R**: Resume workflow
- **Ctrl+S**: Stop workflow
- **Ctrl+Q**: Quit application
- **F1**: Show help

### Navigation Shortcuts

- **↑/↓**: Navigate menu options
- **←/→**: Navigate between sections
- **Enter**: Select/confirm
- **Escape**: Back/cancel
- **Tab**: Next field/section
- **Shift+Tab**: Previous field/section

## Troubleshooting

### Common Problems

#### TUI Not Displaying Correctly

```bash
# Check terminal compatibility
aidp --help

# If issues persist, try resizing your terminal window
```

#### Navigation Not Working

- Ensure your terminal supports ANSI escape codes
- Try resizing your terminal window
- Check your terminal's color and Unicode support

#### Performance Issues

```bash
# Enable debug output
AIDP_DEBUG=1 aidp

# Log to a file
AIDP_LOG_FILE=aidp.log aidp
```

### Error Messages

#### "TUI Component Failed to Load"

This usually indicates a terminal compatibility issue:

1. Try using a different terminal emulator
2. Check your terminal's color and Unicode support
3. Ensure your terminal window is large enough

#### "Navigation State Corrupted"

If navigation becomes unresponsive:

1. Press **Escape** multiple times to reset
2. Use **Ctrl+C** to exit and restart
3. Start a new session

### Getting Help

```bash
# Show help information
aidp --help

# Show version information
aidp --version
```

### Configuration

Customize TUI behavior in your `aidp.yml`:

```yaml
tui:
  enabled: true
  display:
    show_progress: true
    show_animations: true
    color_scheme: "default"
```

## Best Practices

### Workflow Management

1. **Use keyboard shortcuts** for faster navigation
2. **Check status regularly** to stay informed
3. **Save progress** before exiting
4. **Keep terminal window large enough** for proper display

### Performance

1. **Use debug mode** for troubleshooting
2. **Monitor system resources** if performance degrades
3. **Keep terminal output clean** for better visibility

### Troubleshooting Tips

1. **Check terminal compatibility** before starting
2. **Use the help system** for guidance
3. **Report issues** with terminal and system information
4. **Keep logs** for debugging

---

For more information, see the [main README](../README.md) or run `aidp --help` for command reference.
