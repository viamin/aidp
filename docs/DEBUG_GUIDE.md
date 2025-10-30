# Debug System Guide

This guide explains how to use the debug system to troubleshoot issues with analyze mode and other aidp operations.

## Overview

The debug system provides comprehensive logging and debugging capabilities to help identify issues with:

- Command execution (provider calls)
- Step execution in analyze mode
- Error handling and recovery
- Provider interactions

## Debug Levels

The debug system supports two levels of verbosity:

- Shows step execution progress
- Shows error information

- Shows backtraces for errors
- Shows timing information

## Usage

### Environment Variable

Set the `DEBUG` environment variable to enable debug mode:

```bash
# Basic debug mode
DEBUG=1 aidp

# Verbose debug mode
DEBUG=2 aidp

# Debug a specific step
DEBUG=1 aidp analyze 01_REPOSITORY_ANALYSIS
```

## Test Coverage

You can generate code coverage reports using SimpleCov (issue #127). Configuration now lives in the project root `.simplecov` file for centralized management.

Enable coverage when running the test suite:

```bash
COVERAGE=1 bundle exec rspec
```

Reports are written to `coverage/index.html`. Open that file in a browser to inspect line and branch coverage.

Configuration highlights (see `.simplecov`):

- Branch coverage enabled
- Minimum overall coverage: 85%
- Minimum per-file coverage: 50%
- Spec, pkg, tmp directories filtered out

To debug which files are being tracked, run with `DEBUG=1 COVERAGE=1`.

### Debug Output

Debug information is displayed in two places:

1. **Console Output**: Colored, formatted output to the terminal
2. **Log Files**: Structured logs saved to `.aidp/debug_logs/`

### Log Files

Debug output is written to `.aidp/logs/aidp.log` (single consolidated log file). Set `AIDP_LOG_LEVEL=debug` or configure `logging.level: debug` in `aidp.yml` to include debug entries.

- Working directory
- Debug level

- All debug history in one place
- No log file cleanup needed

Each log file contains:

- Run banners separating different sessions
- Timestamped messages
- Structured data in JSON format
- Both human-readable and machine-parseable formats

## Debug Information

### Run Banners

Each debug session starts with a banner that makes it easy to identify when a run started:

```text
================================================================================
AIDP DEBUG SESSION STARTED
================================================================================
Timestamp: 2025-09-18 11:41:17.335
Command: aidp analyze 01_REPOSITORY_ANALYSIS (DEBUG=1)
Working Directory: /Users/bart.agapinan/workspace/aidp
Debug Level: 1
================================================================================
```

**Using run banners for debugging**:

- Search for "AIDP DEBUG SESSION STARTED" to find all runs
- Use timestamps to find specific runs
- Check command line to see exactly how aidp was invoked
- Verify debug level and working directory

### Command Execution

When providers execute commands, debug mode shows:

```text
🔧 Executing command: cursor-agent -p
📝 Input: [prompt content or file path]
❌ Error output: [stderr output]
📤 Output: [stdout output - verbose mode only]
🏁 Exit code: 0
```

### Step Execution

For analyze mode steps:

```text
🔄 Starting execution: 01_REPOSITORY_ANALYSIS (harness_mode=true, options=[:user_input])
📝 Composed prompt for 01_REPOSITORY_ANALYSIS (prompt_length=1234, provider=cursor)
🔄 Harness execution completed: 01_REPOSITORY_ANALYSIS (status=completed, provider=cursor)
```

### Error Handling

When errors occur:

```text
💥 Error: StandardError: cursor-agent failed with exit code 1
📍 Backtrace: [backtrace - verbose mode only]
🔧 ErrorHandler: Processing error (error_type=command_failed, provider=cursor, model=default)
🔄 ErrorHandler: Attempting retry (strategy=default, max_retries=2)
```

### Provider Interactions

For provider calls:

```text
🤖 cursor: Starting execution (timeout=300)
📝 Sending prompt to cursor-agent
🔧 Executing command: cursor-agent -p
```

## Troubleshooting Common Issues

### Step Fails with "Unknown Error"

1. Enable debug mode: `DEBUG=1 aidp analyze`
2. Look for the command being executed
3. Check the stderr output for the actual error
4. Verify the provider is available and working

### Provider Timeout Issues

1. Use verbose debug: `DEBUG=2 aidp analyze`
2. Check the timeout settings in the debug output
3. Look for stuck detection messages
4. Verify the provider is responding

### Template or Prompt Issues

1. Enable verbose debug to see the full prompt
2. Check if template files exist
3. Verify template variable substitution

### Network or API Issues

1. Look for network error messages in stderr
2. Check provider availability
3. Verify API keys or authentication

## Integration

The debug system is integrated throughout aidp:

- **Providers**: All providers (Cursor, Anthropic, Gemini) include debug logging
- **Analyze Runner**: Step execution is logged with context
- **Error Handler**: Error recovery and retry logic is logged
- **Harness System**: Provider switching and execution is logged

## Adding Debug to Custom Code

To add debug support to any class:

```ruby
require_relative "debug_mixin"

class MyClass
  include Aidp::DebugMixin

  def my_method
    debug_log("Starting my method", level: :info)
    debug_step("MY_STEP", "Processing", { data: "value" })
    debug_provider("my-provider", "Calling", { param: "value" })

    begin
      # Your code here
    rescue => e
      debug_error(e, { context: "my_method" })
      raise
    end
  end
end
```

## Debug Methods

### Basic Logging

```ruby
debug_log("Message", level: :info, data: { key: "value" })
```

### Logging Step Execution

```ruby
debug_step("STEP_NAME", "action", { details: "value" })
```

### Logging Provider Interaction

```ruby
debug_provider("provider-name", "action", { param: "value" })
```

### Logging Error

```ruby
debug_error(exception, { context: "additional_info" })
```

### Logging Command Execution

```ruby
result = debug_execute_command("command", args: ["arg1"], input: "data")
```

### Logging Timing Information

```ruby
debug_timing("operation", duration, { details: "value" })
```

## Log File Analysis

Debug log files contain structured data that can be analyzed:

```bash
# View recent debug logs
ls -la .aidp/debug_logs/

# Search for specific errors
grep "ERROR" .aidp/debug_logs/*.log

# Extract structured data
grep "DATA:" .aidp/debug_logs/*.log | jq .
```

## Best Practices

1. **Start with DEBUG=1** for basic troubleshooting
2. **Use DEBUG=2** for detailed analysis
3. **Check log files** for persistent debugging information
4. **Look for patterns** in error messages and retry attempts
5. **Verify provider availability** before running analyze mode
6. **Check timeout settings** if steps are timing out

## Examples

### Debugging a Failing Step

```bash
# Run with basic debug
DEBUG=1 aidp analyze 01_REPOSITORY_ANALYSIS

# Look for:
# - Command being executed
# - Stderr output showing the actual error
# - Provider availability
```

### Debugging Provider Issues

```bash
# Run with verbose debug
DEBUG=2 aidp analyze

# Look for:
# - Provider initialization
# - Command execution details
# - Network or authentication errors
# - Timeout issues
```

### Analyzing Log Files

```bash
# Check the most recent log file
tail -f .aidp/debug_logs/aidp_debug_*.log

# Search for specific errors
grep -i "error\|failed" .aidp/debug_logs/*.log
```

This debug system should help you identify and resolve issues with analyze mode execution, provider interactions, and error handling.

## Guided Workflow Verbose Mode (`--verbose`)

The guided workflow now supports a dedicated verbosity channel separate from `DEBUG`.

Usage options:

```bash
aidp --verbose            # Print planning prompts + raw provider responses live
DEBUG=1 aidp              # Log (not print) planning prompts/responses at debug level
DEBUG=1 aidp --verbose    # Print to console AND log (dual path)
AIDP_VERBOSE=1 aidp       # Env-based equivalent of --verbose (helpful in scripts)
```

Behavior matrix:

| Flag combination | Console output (planning) | Logged (debug) | Notes |
|------------------|---------------------------|----------------|-------|
| (none)           | No                        | No             | Minimal, user sees only synthesized questions |
| `--verbose` or `AIDP_VERBOSE=1` | Yes | No (unless DEBUG=1) | High transparency for interactive sessions |
| `DEBUG=1`        | No                        | Yes            | Keeps terminal clean but preserves artifacts |
| `--verbose` + `DEBUG=1` | Yes | Yes | Full traceability |

What is surfaced:

1. Full planning prompt sent to provider each iteration
2. Raw provider response text (before parsing)
3. Fallback reasoning when structured parsing fails
4. Manual recovery sentinel question when activated

Manual Recovery Flow:

If the provider emits invalid planning JSON repeatedly, the system cycles through three structured fallback questions. On continued failure it enters a manual recovery mode, prompting you to supply a single aggregated line:

```text
Auth feature; Developers; Login requirement; No external DB
```

This maps to:

- Scope (included features)
- User personas
- Functional requirements
- Technical constraints

Skip manual entry with `skip`.

Implementation notes:

- Manual recovery parsing now runs before generic keyword heuristics to avoid misclassification (the sentinel contains the word `users`).
- Fallback attempts are counted (`invalid_planning_responses`) to prevent infinite repetition.
- All emissions use helper methods to centralize formatting (`emit_verbose_raw_prompt`, `emit_verbose_iteration`).

Troubleshooting tips:

- Not seeing prompts? Ensure neither `--verbose` nor `AIDP_VERBOSE=1` is set and only `DEBUG=1` is active (they'll be in logs instead).
- Seeing repeated fallback prompts? Inspect logs for provider raw output to diagnose malformed JSON sources.
- Want to diff plan evolution? Enable `DEBUG=1` and review successive plan summaries in the log.
