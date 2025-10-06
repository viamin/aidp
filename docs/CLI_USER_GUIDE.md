# AIDP CLI User Guide

Complete guide to using the AI Dev Pipeline command-line interface.

## Table of Contents

- [Quick Start](#quick-start)
- [Execution Modes](#execution-modes)
- [Background Jobs](#background-jobs)
- [Progress Checkpoints](#progress-checkpoints)
- [System Management](#system-management)
- [Workflow Examples](#workflow-examples)
- [Tips & Best Practices](#tips--best-practices)

## Quick Start

### Basic Commands

```bash
# Show help
aidp --help

# Show version
aidp --version

# Run setup wizard
aidp --setup-config

# Start interactive execute mode
aidp execute

# Start interactive analyze mode
aidp analyze

# Check system status
aidp status
```

### First Time Setup

When you run AIDP for the first time in a project, it launches a setup wizard:

```bash
$ cd /your/project
$ aidp execute

Welcome to AIDP Configuration Setup!

Choose a configuration template:
1. Minimal (single provider: cursor)
2. Development template (multiple providers, safe defaults)
3. Production template (full-feature example)
4. Full example (verbose documented config)
5. Custom (interactive prompts)

Enter your choice (1-5):
```

The wizard creates an `aidp.yml` file with your chosen configuration. You can re-run the wizard anytime with:

```bash
aidp --setup-config
```

## Execution Modes

AIDP has two primary modes: **Execute** (build features) and **Analyze** (analyze code).

### Execute Mode

Execute mode guides you through building new features from PRD to implementation.

```bash
# Interactive mode - select workflow and answer questions
aidp execute

# Background mode - run without blocking terminal
aidp execute --background

# Background with log following
aidp execute --background --follow
```

**Available Execute Workflows:**

- Full PRD to Implementation
- PRD Only
- Architecture Only
- Implementation Only
- Custom Step Selection

### Analyze Mode

Analyze mode examines your codebase and generates insights.

```bash
# Interactive analysis
aidp analyze

# Background analysis
aidp analyze --background

# Background with log following
aidp analyze --background --follow
```

**Available Analyze Workflows:**

- Full Analysis (all steps)
- Code Structure Analysis
- Dependency Analysis
- Quality Metrics Only
- Custom Step Selection

### Interactive Workflow Selection

When you run `aidp execute` or `aidp analyze` without flags, you get an interactive workflow selector:

```bash
$ aidp execute

Welcome to AI Dev Pipeline! Choose your mode
> 🏗️ Execute Mode - Build new features with guided development workflow

Select a workflow:
> Full PRD to Implementation - Complete feature development lifecycle
  PRD Only - Generate Product Requirements Document
  Architecture Only - Design system architecture
  Implementation Only - Code the feature
  Custom - Select specific steps

# Answer any workflow-specific questions
# Workflow runs automatically with progress tracking
```

## Background Jobs

Background execution allows you to run workflows without blocking your terminal.

### Starting Background Jobs

```bash
# Start in background
$ aidp execute --background
✓ Started background job: 20251005_235912_a1b2c3d4

Monitor progress:
  aidp jobs status 20251005_235912_a1b2c3d4
  aidp jobs logs 20251005_235912_a1b2c3d4 --tail
  aidp checkpoint summary

Stop the job:
  aidp jobs stop 20251005_235912_a1b2c3d4

# Start and immediately follow logs
$ aidp execute --background --follow
✓ Started background job: 20251005_235912_a1b2c3d4
Following logs (Ctrl+C to stop following)...
[2025-10-05 23:59:12] Starting execute mode in background
[2025-10-05 23:59:12] Job ID: 20251005_235912_a1b2c3d4
```

### Listing Jobs

```bash
$ aidp jobs list

Background Jobs
================================================================================

Job ID            Mode      Status      Started              Duration
20251005_235...   Execute   ● Running   2025-10-05 23:59:12  15m 23s
20251005_221...   Analyze   ✓ Complete  2025-10-05 22:15:08  45m 12s
20251005_183...   Execute   ⏹ Stopped   2025-10-05 18:30:45  1h 12m

Commands:
  aidp jobs status <job_id>        - Show detailed status
  aidp jobs logs <job_id> --tail   - Show recent logs
  aidp jobs stop <job_id>          - Stop a running job
```

### Job Status

```bash
# One-time status check
$ aidp jobs status 20251005_235912_a1b2c3d4

Job Status: 20251005_235912_a1b2c3d4
================================================================================

Mode:       execute
Status:     ● Running
PID:        12345
Running:    Yes
Started:    2025-10-05 23:59:12

Latest Checkpoint:
  Step:       01_IMPLEMENTATION
  Iteration:  15
  Updated:    23s ago
  Metrics:
    LOC:      2,543
    Coverage: 78.5%
    Quality:  85.2%

Log file: .aidp/jobs/20251005_235912_a1b2c3d4/output.log

# Follow status with auto-refresh (updates every 2s)
$ aidp jobs status 20251005_235912_a1b2c3d4 --follow
# Screen clears and updates automatically
# Press Ctrl+C to stop following
```

### Job Logs

```bash
# Show all logs
$ aidp jobs logs 20251005_235912_a1b2c3d4

# Show last 50 lines
$ aidp jobs logs 20251005_235912_a1b2c3d4 --tail

# Follow logs in real-time (like tail -f)
$ aidp jobs logs 20251005_235912_a1b2c3d4 --follow
[2025-10-05 23:59:12] Starting execute mode in background
[2025-10-05 23:59:13] Iteration 1 started
[2025-10-05 23:59:45] Tests running...
[2025-10-05 23:59:48] ✓ Tests passed
# Press Ctrl+C to stop following
```

### Stopping Jobs

```bash
$ aidp jobs stop 20251005_235912_a1b2c3d4
✓ Job stopped successfully

# Job sends SIGTERM, waits 5 seconds, then SIGKILL if needed
# Job metadata updated to show "stopped" status
```

## Progress Checkpoints

Checkpoints track code quality metrics and task progress throughout execution.

### Checkpoint Summary

```bash
# Show current progress
$ aidp checkpoint summary

📈 Progress Summary
================================================================================
Step: 01_IMPLEMENTATION
Iteration: 15
Status: ✓ Healthy

Current Metrics:
  Lines of Code: 2,543
  Test Coverage: 78.5%
  Code Quality: 85.2%
  PRD Task Progress: 65.0%
  File Count: 42

Trends:
  Lines of Code: ↑ +127 (+5.2%)
  Test Coverage: ↑ +2.3% (+3.0%)
  Code Quality: → +0.1% (+0.1%)
  PRD Task Progress: ↑ +15.0% (+30.0%)

  Quality Score: 76.35%
```

### Watch Mode

Auto-refresh checkpoint summary for real-time monitoring:

```bash
# Auto-refresh every 5 seconds (default)
$ aidp checkpoint summary --watch

# Custom refresh interval (10 seconds)
$ aidp checkpoint summary --watch --interval 10

# Screen clears and updates automatically
# Shows "Last update: 5s ago | Refreshing in 5s..."
# Press Ctrl+C to stop watching
```

### Checkpoint Commands

```bash
# Show latest checkpoint (detailed view)
$ aidp checkpoint show

📊 Checkpoint - Iteration 15
────────────────────────────────────────────────────────
  Lines of Code: 2543
  Test Coverage: 78.5%
  Code Quality: 85.2%
  PRD Task Progress: 65.0%
  File Count: 42
  Overall Status: ✓ Healthy
────────────────────────────────────────────────────────

# View checkpoint history
$ aidp checkpoint history           # Last 10 checkpoints
$ aidp checkpoint history 50        # Last 50 checkpoints

📜 Checkpoint History (Last 10)
================================================================================
Iteration  Time      LOC   Coverage  Quality  PRD Progress  Status
15         23:59:45  2543  78.5%     85.2%    65.0%         ✓ Healthy
14         23:54:30  2416  76.2%     85.1%    50.0%         ✓ Healthy
13         23:49:15  2289  74.0%     84.9%    50.0%         ⚠ Warning
...

# Show detailed metrics
$ aidp checkpoint metrics

📊 Detailed Metrics
============================================================
Lines of Code: 2543
File Count: 42
Test Coverage: 78.5%
Code Quality: 85.2%
PRD Task Progress: 65.0%
Tests: ✓ Passing
Linters: ✓ Passing
============================================================

# Clear checkpoint data
$ aidp checkpoint clear
Are you sure you want to clear all checkpoint data? (y/N): y
✓ Checkpoint data cleared.

# Clear without confirmation
$ aidp checkpoint clear --force
✓ Checkpoint data cleared.
```

### Understanding Metrics

**Lines of Code (LOC)**

- Total lines of code in project files
- Excludes `node_modules`, `vendor`, etc.
- Tracks growth over time

**Test Coverage**

- Estimated based on ratio of test files to source files
- Higher is better (aim for 80%+)

**Code Quality**

- Based on linter output (if configured)
- Score from 0-100, higher is better
- Falls back to 100 if no linter configured

**PRD Task Progress**

- Percentage of completed checkboxes in `docs/prd.md`
- Tracks: `- [x]` vs `- [ ]` items
- Shows feature implementation progress

**Status Indicators**

- `✓ Healthy` - Quality score ≥ 80%
- `⚠ Warning` - Quality score 60-79%
- `✗ Needs Attention` - Quality score < 60%

## System Management

### Provider Health

Check the status of all configured AI providers:

```bash
$ aidp providers

Provider Health Dashboard (0.52s)
Provider   Status     Avail  Circuit  RateLimited  Tokens  LastUsed  Reason
cursor     healthy    yes    closed   no           12,543  23:59:45  -
claude     healthy    yes    closed   no           8,234   23:45:12  -
gemini     unhealthy  no     open     no           0       -         No API key
```

**Status Values:**

- `healthy` - Provider is working correctly
- `unhealthy` - Provider has issues (check Reason column)
- `unhealthy_auth` - Authentication failed
- `circuit_open` - Circuit breaker triggered (too many errors)

### Harness State

Manage harness execution state:

```bash
# Show harness status
$ aidp harness status
Harness Status
Mode: (unknown)
State: idle

# Reset harness state (clears progress)
$ aidp harness reset --mode execute
Harness state reset for mode: execute

$ aidp harness reset --mode analyze
Harness state reset for mode: analyze
```

### System Status

Quick overview of system state:

```bash
$ aidp status

AI Dev Pipeline Status
----------------------
Analyze Mode: available
Execute Mode: available
Use 'aidp analyze' or 'aidp execute' to start a workflow
```

## Workflow Examples

### Example 1: Interactive Feature Development

```bash
# Start execute mode
$ aidp execute

# Select "Full PRD to Implementation"
# Answer questions interactively:
#   - What feature do you want to build?
#   - What are the key requirements?
#   - Any technical constraints?

# Workflow runs automatically:
# 1. Generates PRD in docs/prd.md
# 2. Creates architecture in docs/Architecture.md
# 3. Generates task breakdown
# 4. Implements code with work loops
# 5. Runs tests and linters each iteration
# 6. Completes when all criteria met

# Review results
$ cat docs/prd.md
$ cat docs/Architecture.md
```

### Example 2: Background Development with Monitoring

```bash
# Terminal 1: Start background job
$ aidp execute --background
✓ Started background job: 20251005_235912_a1b2c3d4

# Terminal 2: Watch progress in real-time
$ aidp checkpoint summary --watch
# Auto-refreshes every 5 seconds
# Shows metrics updating as code is written

# Terminal 3: Monitor job details
$ aidp jobs status 20251005_235912_a1b2c3d4 --follow
# Auto-refreshes every 2 seconds
# Shows current step, iteration, checkpoint age

# Terminal 4: Follow logs
$ aidp jobs logs 20251005_235912_a1b2c3d4 --follow
# Streams logs in real-time
# See exactly what the agent is doing

# Later: Check results
$ aidp checkpoint summary
$ aidp jobs logs 20251005_235912_a1b2c3d4 --tail
```

### Example 3: Quick Codebase Analysis

```bash
# Start analysis in background
$ aidp analyze --background
✓ Started background job: 20251005_221508_def456

# Check progress occasionally
$ aidp jobs list
# Shows job running

# View checkpoint to see analysis progress
$ aidp checkpoint summary

# When done, review knowledge base
$ ls .aidp/kb/
symbols.json  imports.json  calls.json  metrics.json
hotspots.json  seams.json  tests.json  cycles.json

# View detailed results
$ cat .aidp/kb/hotspots.json | jq '.'
$ cat .aidp/kb/seams.json | jq '.'
```

### Example 4: Resuming After Interruption

```bash
# Job was interrupted or stopped
$ aidp jobs list
Job ID            Mode      Status      Started
20251005_235...   Execute   ⏹ Stopped   2025-10-05 23:59:12

# Check what was completed
$ aidp checkpoint history
# Shows progress up to interruption

# Resume by starting new job
# AIDP uses .aidp-progress.yml to skip completed steps
$ aidp execute
# Asks if you want to continue from where you left off
# Or start fresh

# Or manually reset if you want fresh start
$ aidp harness reset --mode execute
$ aidp execute
```

### Example 5: Multiple Projects

```bash
# Project 1: Start background job
$ cd ~/projects/app1
$ aidp execute --background
✓ Started background job: 20251005_235912_a1b2c3d4

# Project 2: Start another background job
$ cd ~/projects/app2
$ aidp analyze --background
✓ Started background job: 20251005_235920_xyz789

# Monitor both
$ cd ~/projects/app1
$ aidp jobs list        # Shows app1 jobs
$ aidp checkpoint summary

$ cd ~/projects/app2
$ aidp jobs list        # Shows app2 jobs
$ aidp checkpoint summary

# Jobs are isolated per project directory
```

## Tips & Best Practices

### Background Execution

✅ **Do:**

- Use background mode for long-running tasks (> 10 min)
- Monitor with `--watch` commands for real-time feedback
- Check checkpoint history to see trends
- Use `--follow` when starting to ensure job launches correctly

❌ **Don't:**

- Run multiple background jobs in the same project simultaneously
- Forget to check job status before starting another
- Ignore "stuck" status - investigate if job hasn't updated in 10+ minutes

### Checkpoint Monitoring

✅ **Do:**

- Watch checkpoint summary during background execution
- Review history to identify quality regressions
- Clear old checkpoint data when starting new features
- Pay attention to trend indicators (↑↓→)

❌ **Don't:**

- Ignore "Needs Attention" status - quality may be degrading
- Rely solely on checkpoints - also review actual code
- Compare metrics across different projects

### Job Management

✅ **Do:**

- Use descriptive names in workflow selection (helps identify jobs)
- Stop stuck jobs and investigate logs
- Keep job history for troubleshooting
- Follow logs when debugging issues

❌ **Don't:**

- Let too many completed jobs accumulate (clean up `.aidp/jobs/` periodically)
- Kill jobs forcefully (use `aidp jobs stop`)
- Ignore authentication errors in provider health

### Provider Management

✅ **Do:**

- Check `aidp providers` if workflows fail
- Configure fallback providers in `aidp.yml`
- Set up API keys properly in environment
- Monitor rate limits with provider dashboard

❌ **Don't:**

- Rely on single provider (configure fallbacks)
- Ignore circuit breaker open status
- Commit API keys to version control

### Work Loops

✅ **Do:**

- Configure test and lint commands in `aidp.yml`
- Let work loops run multiple iterations (don't stop early)
- Review PROMPT.md to see what agent is working on
- Trust the agent to self-correct based on test failures

❌ **Don't:**

- Set max_iterations too low (50 is reasonable)
- Interrupt work loops mid-iteration
- Manually edit code while work loop is running
- Disable tests/linters (they ensure quality)

### Debugging

When things go wrong:

1. **Check job logs**

   ```bash
   aidp jobs logs <job_id> --tail
   ```

2. **Review checkpoint data**

   ```bash
   aidp checkpoint summary
   aidp checkpoint history
   ```

3. **Check provider health**

   ```bash
   aidp providers
   ```

4. **Enable debug mode**

   ```bash
   AIDP_DEBUG=1 aidp execute
   ```

5. **Review configuration**

   ```bash
   cat aidp.yml
   ```

6. **Check harness state**

   ```bash
   aidp harness status
   ```

7. **Reset if needed**

   ```bash
   aidp harness reset --mode execute
   aidp checkpoint clear --force
   ```

## Command Quick Reference

```bash
# Execution
aidp execute                           # Interactive execute mode
aidp execute --background              # Background execution
aidp execute --background --follow     # Background + follow logs
aidp analyze                           # Interactive analyze mode
aidp analyze --background              # Background analysis

# Jobs
aidp jobs list                         # List all jobs
aidp jobs status <id>                  # Show job status
aidp jobs status <id> --follow         # Follow job status
aidp jobs logs <id>                    # Show job logs
aidp jobs logs <id> --tail             # Last 50 lines
aidp jobs logs <id> --follow           # Stream logs
aidp jobs stop <id>                    # Stop a job

# Checkpoints
aidp checkpoint show                   # Latest checkpoint (detailed)
aidp checkpoint summary                # Progress summary
aidp checkpoint summary --watch        # Auto-refresh every 5s
aidp checkpoint summary --watch --interval 10  # Custom interval
aidp checkpoint history                # Last 10 checkpoints
aidp checkpoint history 50             # Last 50 checkpoints
aidp checkpoint metrics                # Detailed metrics
aidp checkpoint clear                  # Clear with confirmation
aidp checkpoint clear --force          # Clear without confirmation

# System
aidp status                            # System status
aidp providers                         # Provider health
aidp harness status                    # Harness state
aidp harness reset --mode <mode>       # Reset harness
aidp --setup-config                    # Re-run setup wizard
aidp --help                            # Show help
aidp --version                         # Show version
```

## Environment Variables

```bash
# API Keys
export AIDP_CLAUDE_API_KEY="your-key"
export AIDP_GEMINI_API_KEY="your-key"

# Debug
export AIDP_DEBUG=1                    # Enable debug output
export AIDP_LOG_FILE=aidp.log          # Log to file

# Tree-sitter
export TREE_SITTER_PARSERS="path/to/parsers"
```

## Next Steps

- Read the [Work Loops Guide](WORK_LOOPS_GUIDE.md) to understand iterative execution
- Check [Configuration Guide](harness-configuration.md) for advanced options
- See [Troubleshooting Guide](harness-troubleshooting.md) for common issues
- Review [README](../README.md) for installation and setup
