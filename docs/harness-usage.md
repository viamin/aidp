# AIDP Harness Usage Guide

## Overview

The AIDP Harness is a powerful autonomous execution system that transforms AIDP from a step-by-step tool into a fully automated development assistant. The harness runs complete workflows from start to finish, handling rate limits, user feedback, error recovery, and provider switching automatically.

## Quick Start

### Basic Usage

The harness is now the default execution mode for both `analyze` and `execute` commands:

```bash
# Run all analysis steps automatically
aidp analyze

# Run all development steps automatically
aidp execute

# Run specific step (traditional mode still works)
aidp analyze 01_REPOSITORY_ANALYSIS
aidp execute 00_PRD
```

### What Happens When You Run Harness Mode

1. **Automatic Step Execution**: The harness runs all steps in sequence without manual intervention
2. **Intelligent Pausing**: Automatically pauses when user feedback is needed or rate limits are hit
3. **Provider Management**: Switches providers automatically when needed
4. **Error Recovery**: Retries failed operations and recovers from errors
5. **Real-time Monitoring**: Shows live status updates and progress

## Harness States

### Running State

- **Status**: `🚀 Running`
- **Description**: Actively executing steps
- **User Action**: Can pause, stop, or wait for completion

### Paused for User Input

- **Status**: `⏸️ Waiting for user input`
- **Description**: Agent has asked questions and is waiting for your response
- **User Action**: Answer questions or provide feedback

### Paused for Rate Limit

- **Status**: `⏳ Rate limited - waiting 2m 30s`
- **Description**: Provider hit rate limit, waiting for cooldown
- **User Action**: Wait for automatic resume or cancel

### Error State

- **Status**: `❌ Error - retrying`
- **Description**: Encountered error, attempting recovery
- **User Action**: Monitor recovery or cancel if needed

### Completed State

- **Status**: `✅ Completed`
- **Description**: All steps finished successfully
- **User Action**: Review results or start new workflow

## User Interaction

### Answering Agent Questions

When the agent asks questions, you'll see a numbered list:

```
🤖 Agent Questions:
1. What is the primary purpose of this application?
2. What are the main user personas?
3. What are the key features to implement?

Please answer each question (press Enter after each):
```

Simply type your answers and press Enter after each one.

### File Selection with @ Symbol

When you need to provide files, type `@` to open the file selector:

```
📁 Select files to include:
1. lib/models/user.rb
2. spec/models/user_spec.rb
3. README.md

Enter numbers (comma-separated) or type 'all': 1,2
```

### Control Commands

During execution, you can use these commands:

- **`p` + Enter**: Pause execution
- **`r` + Enter**: Resume execution
- **`s` + Enter**: Stop execution
- **`Ctrl+C`**: Emergency stop

## Provider Management

### Automatic Provider Switching

The harness automatically switches providers when:

- **Rate Limits**: Provider hits API rate limits
- **Failures**: Provider fails after retry attempts
- **Timeouts**: Provider doesn't respond in time
- **Configuration**: Based on your provider preferences

### Provider Status Display

```
🔄 Current Provider: Claude (claude-3-5-sonnet)
📊 Token Usage: 1,250 / 10,000 (12.5%)
⏱️  Response Time: 2.3s
🔄 Fallback Chain: Claude → Gemini → Cursor
```

### Manual Provider Control

You can influence provider selection through configuration:

```yaml
# aidp.yml
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
  max_retries: 3
```

## Error Handling & Recovery

### Automatic Retry Logic

The harness implements intelligent retry strategies:

- **Rate Limits**: Immediate provider switch (no retry)
- **Network Errors**: Linear backoff retry
- **Server Errors**: Exponential backoff retry
- **Timeouts**: Fixed delay retry
- **Auth Errors**: Immediate fail (no retry)

### Error Recovery Display

```
❌ Error: Rate limit exceeded
🔄 Switching to Gemini (gemini-pro)
⏳ Retrying in 1.2s...
✅ Recovery successful
```

### Manual Error Handling

If automatic recovery fails:

1. **Check Status**: Use `aidp status` to see current state
2. **Review Logs**: Check error logs for details
3. **Reset State**: Use `aidp harness reset --mode=analyze` if needed
4. **Manual Retry**: Restart with `aidp analyze` or `aidp execute`

## Progress Tracking

### Real-time Status

The harness provides continuous status updates:

```
📊 AIDP Harness Status
═══════════════════════════════════════

🔍 Analyze Mode Progress:
  ✅ 01_REPOSITORY_ANALYSIS (2m 15s)
  ✅ 02_ARCHITECTURE_ANALYSIS (1m 45s)
  🔄 03_TEST_ANALYSIS (running...)
  ⏳ 04_FUNCTIONALITY_ANALYSIS (pending)
  ⏳ 05_DOCUMENTATION_ANALYSIS (pending)

🔄 Current Provider: Claude (claude-3-5-sonnet)
📊 Token Usage: 3,250 / 10,000 (32.5%)
⏱️  Total Runtime: 4m 2s
```

### Progress Persistence

Your progress is automatically saved and can be resumed:

```bash
# Check current progress
aidp status

# Resume from where you left off
aidp analyze  # Continues from last incomplete step
```

## Configuration

### Basic Configuration

Create an `aidp.yml` file in your project root:

```yaml
# aidp.yml
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
  gemini:
    type: "api"
    max_tokens: 50000
    cursor:
      type: "subscription"
```

### Advanced Configuration

```yaml
# aidp.yml
harness:
  enabled: true
  max_retries: 3
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
  no_api_keys_required: false

  # Rate limit handling
  rate_limit_strategy: "provider_first"
  rate_limit_cooldown: 60

  # Error handling
  retry_strategies:
    network_error: "linear_backoff"
    server_error: "exponential_backoff"
    timeout: "fixed_delay"
    authentication: "immediate_fail"

providers:
  claude:
    type: "api"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 3
    timeout: 30

  gemini:
    type: "api"
    max_tokens: 50000
    default_flags: []
    retry_count: 2
    timeout: 45

    cursor:
      type: "subscription"
    default_flags: []
    retry_count: 1
    timeout: 60
```

## Monitoring & Debugging

### Status Commands

```bash
# Show current harness status
aidp harness status

# Show detailed progress
aidp status

# Show background jobs
aidp jobs

# Show configuration
aidp config show
```

### Logging

The harness provides detailed logging:

```bash
# View harness logs
tail -f .aidp/logs/harness.log

# View error logs
tail -f .aidp/logs/errors.log

# View provider logs
tail -f .aidp/logs/providers.log
```

### Debug Mode

Enable debug mode for detailed output:

```bash
# Run with debug logging
AIDP_DEBUG=1 aidp analyze

# Run with verbose output
AIDP_VERBOSE=1 aidp execute
```

## Best Practices

### 1. Start Simple

Begin with default configuration and adjust as needed:

```bash
# Start with defaults
aidp analyze

# Add configuration as you learn
echo "harness:\n  default_provider: claude" > aidp.yml
```

### 2. Monitor Progress

Keep an eye on the status display to understand what's happening:

```bash
# In another terminal
watch -n 5 "aidp status"
```

### 3. Use Appropriate Providers

Configure providers based on your needs:

- **Claude**: Best for complex analysis and code generation
- **Gemini**: Good for general tasks and cost-effective
- **Cursor**: Best for code-specific tasks and IDE integration

### 4. Handle Rate Limits Gracefully

Don't worry about rate limits - the harness handles them automatically:

```yaml
# Configure fallback providers
harness:
  fallback_providers: ["claude", "gemini", "cursor"]
```

### 5. Save Your Work

The harness automatically saves progress, but you can also:

```bash
# Manual state save
aidp harness save

# Reset if needed
aidp harness reset --mode=analyze
```

## Troubleshooting

### Common Issues

#### Harness Won't Start

```bash
# Check configuration
aidp config validate

# Reset to defaults
aidp harness reset --mode=analyze
```

#### Provider Errors

```bash
# Check provider status
aidp harness status

# Test provider manually
aidp analyze 01_REPOSITORY_ANALYSIS
```

#### Stuck in Loop

```bash
# Stop harness
aidp harness stop

# Check for stuck jobs
aidp jobs

# Reset state
aidp harness reset --mode=analyze
```

#### Rate Limit Issues

```bash
# Check rate limit status
aidp harness status

# Wait for cooldown or switch providers
aidp config set harness.default_provider gemini
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

## Examples

### Complete Analysis Workflow

```bash
# Start complete analysis
aidp analyze

# Harness will:
# 1. Run 01_REPOSITORY_ANALYSIS
# 2. Pause for user questions if needed
# 3. Continue to 02_ARCHITECTURE_ANALYSIS
# 4. Handle any rate limits automatically
# 5. Complete all 7 analysis steps
# 6. Show final results
```

### Complete Development Workflow

```bash
# Start complete development
aidp execute

# Harness will:
# 1. Create PRD (00_PRD)
# 2. Create NFRS (01_NFRS)
# 3. Design architecture (02_ARCHITECTURE)
# 4. Continue through all 16 steps
# 5. Handle user feedback automatically
# 6. Complete full development cycle
```

### Custom Provider Configuration

```yaml
# aidp.yml
harness:
  default_provider: "claude"
  fallback_providers: ["gemini"]

providers:
  claude:
    type: "api"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
  gemini:
    type: "api"
    max_tokens: 50000
```

## Migration from Step-by-Step

If you're used to running individual steps:

### Before (Step-by-Step)

```bash
aidp analyze 01_REPOSITORY_ANALYSIS
aidp analyze 02_ARCHITECTURE_ANALYSIS
aidp analyze 03_TEST_ANALYSIS
# ... continue manually
```

### After (Harness Mode)

```bash
aidp analyze  # Runs all steps automatically
```

### Traditional Mode Still Available

You can still run individual steps:

```bash
# Traditional mode (bypasses harness)
aidp analyze 01_REPOSITORY_ANALYSIS --no-harness

# Or use step-specific commands
aidp analyze 01_REPOSITORY_ANALYSIS
```

## Advanced Features

### Custom Step Sequences

Configure custom step execution:

```yaml
# aidp.yml
harness:
  custom_sequences:
    quick_analysis:
      - "01_REPOSITORY_ANALYSIS"
      - "02_ARCHITECTURE_ANALYSIS"
    full_analysis:
      - "01_REPOSITORY_ANALYSIS"
      - "02_ARCHITECTURE_ANALYSIS"
      - "03_TEST_ANALYSIS"
      - "04_FUNCTIONALITY_ANALYSIS"
      - "05_DOCUMENTATION_ANALYSIS"
      - "06_STATIC_ANALYSIS"
      - "07_REFACTORING_RECOMMENDATIONS"
```

### Provider-Specific Configuration

```yaml
# aidp.yml
providers:
  claude:
    type: "api"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 3
    timeout: 30
    rate_limit_strategy: "provider_first"

  gemini:
    type: "api"
    max_tokens: 50000
    default_flags: []
    retry_count: 2
    timeout: 45
    rate_limit_strategy: "model_first"
```

### Error Recovery Strategies

```yaml
# aidp.yml
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
    authentication:
      strategy: "immediate_fail"
      max_retries: 0
```

## Conclusion

The AIDP Harness transforms your development workflow from manual step-by-step execution to fully automated, intelligent assistance. With automatic provider management, error recovery, and user interaction handling, you can focus on the high-level decisions while the harness handles the execution details.

Start with the basic usage and gradually explore the advanced features as you become more comfortable with the system. The harness is designed to be powerful yet simple, providing automation without sacrificing control.
