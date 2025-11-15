# AIDP CLI User Guide

Complete guide to using the AI Dev Pipeline command-line interface.

## Table of Contents

- [Quick Start](#quick-start)
- [Copilot Mode](#copilot-mode)
- [Harness Mode](#harness-mode)
- [Background Jobs](#background-jobs)
- [Progress Checkpoints](#progress-checkpoints)
- [System Management](#system-management)
- [Model Management](#model-management)
- [Workflow Examples](#workflow-examples)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
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

# Start Copilot interactive mode (default)
aidp

# High-level project analysis
aidp init

# Check system status
aidp status
```

### First Time Setup

When you run AIDP for the first time in a project, it launches a setup wizard:

```bash
$ cd /your/project
$ aidp

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

## Copilot Mode

Copilot is the unified interactive mode that can perform both analysis and development tasks.

### Starting Copilot

```bash
# Start Copilot (default)
aidp

# Copilot will guide you through:
# - Understanding your project goals
# - Selecting the right workflow
# - Performing analysis or development
```

**What Copilot Can Do:**

- Analyze your codebase (architecture, dependencies, quality)
- Build new features from PRD to implementation
- Perform security audits
- Review test coverage
- Generate documentation
- And more - just ask!

### High-Level Project Analysis

For initial project setup and documentation:

```bash
# Run comprehensive project analysis
aidp init

# Creates:
# - LLM_STYLE_GUIDE.md
# - PROJECT_ANALYSIS.md
# - CODE_QUALITY_PLAN.md
```

**Note**: To run full analysis or development workflows, use Copilot mode (`aidp`) and select your desired workflow. The harness will automatically execute all steps and handle error recovery.

### Interactive Workflow Selection

When you run `aidp` (Copilot mode), you get an interactive workflow selector:

```bash
$ aidp

Welcome to AI Dev Pipeline! Choose your mode

Available workflows:
> Full PRD to Implementation - Complete feature development lifecycle
  PRD Only - Generate Product Requirements Document
  Architecture Only - Design system architecture
  Implementation Only - Code the feature
  Full Analysis - Complete codebase analysis
  Custom - Select specific steps

# Answer any workflow-specific questions
# Harness runs workflow automatically with progress tracking
```

## Harness Mode

The AIDP Harness is the autonomous execution engine that runs complete workflows from start to finish. When you use Copilot mode or background jobs, the harness handles provider switching, rate limits, error recovery, and user interaction automatically.

### Overview

The harness transforms AIDP from a step-by-step tool into an intelligent development assistant by:

- **Automatic Step Execution**: Runs all workflow steps sequentially without manual intervention
- **Intelligent Error Recovery**: Retries failed operations with exponential backoff
- **Provider Management**: Switches between configured providers when needed
- **Rate Limit Handling**: Automatically waits and switches providers when rate limited
- **Progress Persistence**: Saves state so you can resume after interruptions

### Harness States

The harness progresses through several states during execution:

| State | Description | What You Can Do |
|-------|-------------|-----------------|
| 🚀 **Running** | Actively executing steps | Monitor progress, pause, or stop |
| ⏸️ **Paused for Input** | Waiting for your response to questions | Answer questions to continue |
| ⏳ **Rate Limited** | Waiting for provider cooldown | Wait for automatic resume or switch providers |
| ❌ **Error - Retrying** | Encountered error, attempting recovery | Monitor recovery or cancel if stuck |
| ✅ **Completed** | All steps finished successfully | Review results |

### User Interaction

#### Answering Agent Questions

When the agent needs information, you'll see numbered questions:

```text
🤖 Agent Questions:
1. What is the primary purpose of this application?
2. What are the main user personas?
3. What are the key features to implement?

Please answer each question (press Enter after each):
```

Simply type your answers and press Enter after each one.

#### File Selection with @ Symbol

To provide files to the agent, type `@` to open the file selector:

```text
📁 Select files to include:
1. lib/models/user.rb
2. spec/models/user_spec.rb
3. README.md

Enter numbers (comma-separated) or type 'all': 1,2
```

#### Control Commands During Execution

While the harness is running:

- **`p` + Enter**: Pause execution
- **`r` + Enter**: Resume execution
- **`s` + Enter**: Stop execution
- **`Ctrl+C`**: Emergency stop

### Provider Management

#### Automatic Provider Switching

The harness automatically switches providers when:

- **Rate Limits**: Provider hits API rate limits - immediate switch
- **Failures**: Provider fails after retry attempts - switch after 2-3 failures
- **Timeouts**: Provider doesn't respond in time - switch after timeout
- **Configuration**: Based on your fallback provider chain

#### Provider Status Display

```text
🔄 Current Provider: Claude (claude-3-5-sonnet)
📊 Token Usage: 1,250 / 10,000 (12.5%)
⏱️  Response Time: 2.3s
🔄 Fallback Chain: Claude → Gemini → Cursor
```

#### Configuring Providers

Control provider behavior through your `aidp.yml`:

```yaml
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
  max_retries: 3

providers:
  claude:
    type: "usage_based"
    max_tokens: 100000
  gemini:
    type: "usage_based"
    max_tokens: 50000
  cursor:
    type: "subscription"
```

### Error Handling & Recovery

#### Automatic Retry Strategies

The harness implements different retry strategies based on error type:

| Error Type | Strategy | Retries | Behavior |
|------------|----------|---------|----------|
| **Rate Limit** | Immediate switch | 0 | Switch to fallback provider immediately |
| **Network Error** | Linear backoff | 3 | Retry with 1s, 2s, 3s delays |
| **Server Error** | Exponential backoff | 5 | Retry with 2s, 4s, 8s, 16s, 32s delays |
| **Timeout** | Fixed delay | 2 | Retry after 5s delay |
| **Auth Error** | Immediate fail | 0 | No retry, report authentication failure |

#### Error Recovery Display

```text
❌ Error: Rate limit exceeded
🔄 Switching to Gemini (gemini-pro)
⏳ Retrying in 1.2s...
✅ Recovery successful
```

#### Manual Error Handling

If automatic recovery fails:

```bash
# 1. Check overall status
aidp status

# 2. Check harness state
aidp harness status

# 3. Review error logs
tail -f .aidp/logs/errors.log

# 4. Reset harness if stuck
aidp harness reset --mode=analyze  # or --mode=execute

# 5. Restart workflow
aidp  # Copilot mode
```

### Progress Tracking

The harness provides real-time progress updates through checkpoints (see [Progress Checkpoints](#progress-checkpoints) section).

Example status display:

```text
📊 AIDP Harness Status
═══════════════════════════════════════

🔍 Current Workflow Progress:
  ✅ 01_REPOSITORY_ANALYSIS (2m 15s)
  ✅ 02_ARCHITECTURE_ANALYSIS (1m 45s)
  🔄 03_TEST_ANALYSIS (running...)
  ⏳ 04_FUNCTIONALITY_ANALYSIS (pending)
  ⏳ 05_DOCUMENTATION_ANALYSIS (pending)

🔄 Current Provider: Claude (claude-3-5-sonnet)
📊 Token Usage: 3,250 / 10,000 (32.5%)
⏱️  Total Runtime: 4m 2s
```

Progress is automatically saved and can be resumed after interruptions.

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

#### Lines of Code (LOC)

- Total lines of code in project files
- Excludes `node_modules`, `vendor`, etc.
- Tracks growth over time

#### Test Coverage

- Estimated based on ratio of test files to source files
- Higher is better (aim for 80%+)

#### Code Quality

- Based on linter output (if configured)
- Score from 0-100, higher is better
- Falls back to 100 if no linter configured

#### PRD Task Progress

- Percentage of completed checkboxes in `docs/prd.md`
- Tracks: `- [x]` vs `- [ ]` items
- Shows feature implementation progress

#### Status Indicators

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

**Dashboard Updates:**

The provider health dashboard now reflects real-time state:

- **LastUsed** - Shows when each provider was last called during workflows (updates automatically)
- **Tokens** - Displays cumulative token usage tracked across all provider invocations
- **RateLimited** - Shows time remaining until rate limit resets (e.g., "yes (2m15s)")
- All metrics are persisted to `.aidp/provider_metrics.yml` and `.aidp/provider_rate_limits.yml`

**Status Values:**

- `healthy` - Provider is working correctly
- `unhealthy` - Provider has issues (check Reason column)
- `unhealthy_auth` - Authentication failed
- `circuit_open` - Circuit breaker triggered (too many errors)

### Detailed Provider Information

Get detailed information about a specific provider's capabilities:

```bash
$ aidp providers info claude

Provider Information: claude
============================================================
Last Checked: 2025-10-08T20:08:06-07:00
CLI Available: Yes

Authentication Method: subscription

MCP Support: Yes

Permission Modes:
  - acceptEdits
  - bypassPermissions
  - default
  - plan

Capabilities:
  ✓ Bypass Permissions
  ✓ Model Selection
  ✓ Mcp Config
  ✓ Tool Restrictions
  ✓ Session Management
  ✓ Output Formats

Notable Flags: (25 total)
  --permission-mode <mode>
    Permission mode to use for the session...
  --model <model>
    Model for the current session...

  ... and 23 more flags
  Run 'claude --help' for full details
============================================================
```

This command introspects each provider's CLI to gather:

- Available permission modes and security flags
- MCP (Model Context Protocol) server support
- **Configured MCP servers** - Lists all MCP servers that have been added to the provider (e.g., filesystem, brave-search, database)
- Authentication method (API key vs subscription)
- Tool restriction capabilities
- Session management features
- Output format options
- All available command-line flags

**MCP Server Information:**

For providers that support MCP (like Claude), AIDP will detect and list configured MCP servers:

```bash
MCP Servers: (3 configured)
  ✓ filesystem (enabled)
    File system access and operations
  ✓ brave-search (enabled)
    Web search via Brave Search API
  ○ database (disabled)
    Database query execution
```

This helps you understand what additional tools and capabilities each provider has access to through MCP servers.

**Refresh Provider Information:**

```bash
# Refresh info for a specific provider
$ aidp providers refresh claude

# Refresh info for all configured providers
$ aidp providers refresh
```

Provider information is automatically cached in `.aidp/providers/` and refreshed when stale (older than 24 hours) or when explicitly requested with `--refresh`.

### MCP Server Dashboard

View all MCP servers configured across all providers in a unified dashboard:

```bash
$ aidp mcp

MCP Server Dashboard
================================================================================
MCP Server      claude  cursor  gemini
dash-api        ✓       -       -
chrome-devtools ✓       -       -
filesystem      -       ✓       -
brave-search    ✓       -       ✓

Legend: ✓ = Enabled  ✗ = Error/Disabled  - = Not configured
================================================================================
```

This table shows:

- All MCP servers configured across any provider
- Which providers have each server enabled (✓), disabled (✗), or not configured (-)
- At-a-glance view of provider capabilities for task requirements

**Check Provider Eligibility:**

Check which providers have specific MCP servers required for a task:

```bash
$ aidp mcp check dash-api filesystem

Task Eligibility Check
Required MCP Servers: dash-api, filesystem
✓ Eligible Providers (2/8):
  • claude
  • cursor
```

This helps you understand:

- Which providers can handle tasks requiring specific MCP tools
- Which providers would be ineligible as fallback options
- Whether you need to configure additional MCP servers

**Use Cases:**

1. **Task Planning** - Before starting a task, check if any provider has the required MCP servers
2. **Fallback Strategy** - Identify which providers can serve as fallbacks for specific tasks
3. **Configuration Gaps** - Discover MCP servers that should be added to more providers
4. **Capability Overview** - See all available MCP tools at a glance

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

## Model Management

AIDP provides powerful model discovery and validation tools to help you manage AI models across different providers.

### Listing Available Models

View all available models from the static registry:

```bash
# List all available models
aidp models list

# Filter by tier (mini, standard, advanced)
aidp models list --tier=mini
aidp models list --tier=standard
aidp models list --tier=advanced

# Filter by provider
aidp models list --provider=anthropic
aidp models list --provider=cursor
```

**Example output:**

```
Available Models

Provider    Model Family           Tier      Capabilities       Context  Speed
anthropic   claude-3-5-sonnet     standard  vision,thinking    200K     fast
anthropic   claude-3-haiku        mini      vision             200K     fast
anthropic   claude-3-opus         advanced  vision,thinking    200K     medium
cursor      gpt-4o                standard  vision             128K     fast
cursor      gpt-4o-mini           mini      vision             128K     fast

💡 Showing 5 models from the static registry
💡 Model families are provider-agnostic (e.g., 'claude-3-5-sonnet' works across providers)
```

### Discovering Models from Providers

Automatically discover models available from configured providers:

```bash
# Discover models from all configured providers
aidp models discover

# Discover models from a specific provider
aidp models discover --provider=anthropic
```

**What happens during discovery:**

1. AIDP queries each provider's CLI tool
2. Models are classified into tiers (mini/standard/advanced)
3. Results are cached for 24 hours
4. Provider-specific versions are mapped to model families

**Example output:**

```
🔍 Discovering models from configured providers...
[✓] Querying provider APIs...

✓ Found 12 models for anthropic:
  Mini tier:
    - claude-3-haiku-20240307
  Standard tier:
    - claude-3-5-sonnet-20241022
    - claude-3-5-sonnet-20240620
  Advanced tier:
    - claude-3-opus-20240229

✅ Discovered 12 total models
💾 Models cached for 24 hours
```

**Auto-Discovery during setup:**

When you configure a provider through the setup wizard, AIDP automatically discovers available models in the background. You'll see a notification when discovery completes:

```bash
$ aidp --setup-config

# After configuring anthropic provider...
💾 Discovered 12 models for anthropic
```

### Refreshing Model Cache

Clear cached model data and re-discover:

```bash
# Refresh cache for all providers
aidp models refresh

# Refresh cache for specific provider
aidp models refresh --provider=anthropic
```

Use this when:
- New models have been released
- Provider CLI was recently updated
- Cache appears stale or incorrect

### Validating Model Configuration

Validate your `aidp.yml` configuration to ensure all tiers have models and all configured models are valid:

```bash
aidp models validate
```

**What gets validated:**

1. **Tier coverage** - Every tier (mini/standard/advanced) has at least one model configured
2. **Provider compatibility** - All configured models are supported by their providers
3. **Registry presence** - Models exist in the model registry

**Example output (valid configuration):**

```
🔍 Validating model configuration...

✅ Configuration is valid!
All tiers have models configured
All configured models are valid for their providers
```

**Example output (issues found):**

```
🔍 Validating model configuration...

❌ Found 2 configuration errors:

1. No model configured for 'advanced' tier
   Tier: advanced

   💡 Suggested fix:
   Add to aidp.yml under providers.anthropic.thinking.tiers.advanced.models:
     - model: claude-3-opus

2. Model 'invalid-model' not supported by provider 'cursor'
   Provider: cursor
   Tier: mini
   Model: invalid-model

   💡 Suggested fix:
   Try using: gpt-4o-mini, claude-3-haiku

💡 Run 'aidp models discover' to see available models
💡 Run 'aidp models list --tier=<tier>' to see models for a specific tier
```

### Enhanced Error Messages

When a tier configuration is missing, AIDP provides smart error messages that:

1. **Check the cache** for discovered models
2. **Show suggestions** from available models
3. **Generate YAML snippets** for easy copy-paste

**Example error with suggestions:**

```
❌ No model configured for 'standard' tier
   Provider: anthropic

💡 Discovered models for this tier:
   - claude-3-5-sonnet-20241022
   - claude-3-5-sonnet-20240620

   Add to aidp.yml:
   providers:
     anthropic:
       thinking:
         tiers:
           standard:
             models:
               - model: claude-3-5-sonnet-20241022
```

### Model Configuration in aidp.yml

Configure models for each thinking tier in your `aidp.yml`:

```yaml
providers:
  anthropic:
    type: usage_based
    api_key: ${ANTHROPIC_API_KEY}
    thinking:
      tiers:
        mini:
          models:
            - model: claude-3-haiku
        standard:
          models:
            - model: claude-3-5-sonnet
        advanced:
          models:
            - model: claude-3-opus
```

**Tips:**

- Use model families (e.g., `claude-3-5-sonnet`) rather than specific versions
- Providers automatically select the latest version of each family
- Configure at least one model per tier for complete coverage
- Multiple models per tier enable fallback strategies

### Understanding Model Tiers

AIDP organizes models into three tiers:

- **Mini tier**: Fast, cost-effective models for simple tasks
  - Examples: `claude-3-haiku`, `gpt-4o-mini`
  - Use for: Code formatting, simple edits, basic queries

- **Standard tier**: Balanced models for most development work
  - Examples: `claude-3-5-sonnet`, `gpt-4o`
  - Use for: Feature development, refactoring, code review

- **Advanced tier**: Most capable models for complex tasks
  - Examples: `claude-3-opus`, `o1-preview`
  - Use for: Architecture design, complex algorithms, deep reasoning

AIDP automatically selects the appropriate tier based on task complexity and can escalate between tiers as needed.

### Troubleshooting Model Discovery

#### Discovery returns no models

**Possible causes:**
1. Provider CLI not installed
2. Provider not authenticated
3. Provider CLI not in PATH

**Solutions:**

```bash
# Check if provider CLI is installed
which claude  # For Anthropic
which cursor  # For Cursor

# Authenticate with provider
claude /login     # For Anthropic
cursor --auth     # For Cursor (check provider docs)

# Verify provider is configured in aidp.yml
cat .aidp/aidp.yml | grep -A 5 "providers:"
```

#### Models discovered but not showing in validation

**Possible causes:**
1. Cache is stale
2. Model not in static registry

**Solutions:**

```bash
# Refresh the cache
aidp models refresh

# Check if models are in cache
ls -lh ~/.aidp/cache/models.json

# Validate configuration
aidp models validate
```

#### "Model not supported by provider" error

**Possible causes:**
1. Model family not available for this provider
2. Typo in model name

**Solutions:**

```bash
# List models available for this provider
aidp models list --provider=anthropic

# Discover latest models from provider
aidp models discover --provider=anthropic

# Check model name spelling in aidp.yml
cat .aidp/aidp.yml | grep -A 10 "tiers:"
```

#### Provider CLI authentication errors

**Possible causes:**
1. Auth token expired
2. Invalid credentials
3. Network issues

**Solutions:**

```bash
# Re-authenticate with provider
claude /login     # Anthropic
# Follow provider-specific auth instructions

# Verify auth works
claude models     # Should list models if authenticated

# Check network connectivity
ping api.anthropic.com
```

#### Auto-discovery not running during setup

**Possible causes:**
1. Provider CLI not installed when wizard ran
2. Provider authentication failed
3. Background discovery timeout

**Solutions:**

```bash
# Manually discover after setup
aidp models discover

# Check provider installation
which claude  # Should return path if installed

# Check logs for errors
cat ~/.aidp/logs/aidp.log | grep discovery
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
aidp                                   # Start Copilot mode (interactive)
aidp init                              # High-level project analysis
aidp --background                      # Start workflow in background
aidp --background --follow             # Background + follow logs

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

## Configuration

### Harness Configuration

Configure harness behavior through your `aidp.yml` file:

```yaml
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

  # Rate limit handling
  rate_limit_strategy: "provider_first"  # or "model_first", "cost_optimized"
  rate_limit_cooldown: 60  # seconds

  # Circuit breaker
  circuit_breaker:
    enabled: true
    failure_threshold: 5
    timeout: 60
    success_threshold: 3
```

### Provider Configuration

Configure each provider's behavior:

```yaml
providers:
  claude:
    type: "usage_based"  # API-based provider
    max_tokens: 100000
    retry_count: 3
    timeout: 30

  gemini:
    type: "usage_based"
    max_tokens: 50000
    retry_count: 2
    timeout: 45

  cursor:
    type: "subscription"  # No API key needed
    retry_count: 1
    timeout: 60
```

### Error Recovery Configuration

Customize retry strategies:

```yaml
harness:
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 3
      base_delay: 1.0
    server_error:
      strategy: "exponential_backoff"
      max_retries: 5
      base_delay: 2.0
    timeout:
      strategy: "fixed_delay"
      max_retries: 2
      delay: 5.0
```

### Configuration File Locations

AIDP looks for configuration in this order:

1. `./aidp.yml` (project root)
2. `./.aidp.yml` (project root, hidden)
3. `~/.aidp.yml` (user home directory)
4. Default values (built-in)

### Validation

Check your configuration:

```bash
# Validate configuration file
aidp config validate

# Show current configuration
aidp config show

# Show specific section
aidp config show harness
aidp config show providers
```

## Troubleshooting

### Common Issues

#### Harness Won't Start

**Symptoms**: Workflow fails to start, no progress display

**Solutions**:

```bash
# Check configuration
aidp config validate

# Reset to defaults
aidp config reset

# Check file permissions
ls -la aidp.yml
chmod 644 aidp.yml
```

#### Provider Authentication Errors

**Symptoms**: "Authentication failed", "Invalid API key"

**Solutions**:

```bash
# Set API keys
export AIDP_CLAUDE_API_KEY="your-claude-api-key"
export AIDP_GEMINI_API_KEY="your-gemini-api-key"

# Add to shell profile for persistence
echo 'export AIDP_CLAUDE_API_KEY="your-key"' >> ~/.bashrc

# Verify configuration
aidp config show providers
aidp providers  # Check provider health
```

#### Rate Limit Issues

**Symptoms**: Frequent pauses, "Rate limit exceeded" errors

**Solutions**:

```bash
# Configure fallback providers
# Add to aidp.yml:
harness:
  fallback_providers: ["gemini", "cursor"]
  rate_limit_strategy: "provider_first"

# Check current status
aidp harness status
aidp providers
```

#### Harness Stuck in Loop

**Symptoms**: Keeps retrying same step, no progress

**Solutions**:

```bash
# Stop and reset
aidp harness stop
aidp harness reset --mode=analyze  # or --mode=execute

# Check for stuck jobs
aidp jobs

# Review error logs
tail -f .aidp/logs/errors.log
```

#### State Corruption

**Symptoms**: "State file corrupted", can't resume

**Solutions**:

```bash
# Reset harness state
aidp harness reset --mode=analyze --clear-all

# Remove corrupted state files
rm -f .aidp/harness/analyze_state.json
rm -f .aidp/harness/execute_state.json

# Restart workflow
aidp
```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Run with debug logging
AIDP_DEBUG=1 aidp

# Run with verbose output
AIDP_VERBOSE=1 aidp

# Set debug log level
AIDP_LOG_LEVEL=debug aidp
```

### Getting Help

```bash
# Show help
aidp help

# Show harness help
aidp harness help

# Show configuration help
aidp config help
```

## Next Steps

- Read the [Work Loops Guide](WORK_LOOPS_GUIDE.md) to understand iterative execution
- Check [Interactive REPL Guide](INTERACTIVE_REPL.md) for REPL commands
- See [Skills User Guide](SKILLS_USER_GUIDE.md) for skill management
- Review [README](../README.md) for installation and setup
