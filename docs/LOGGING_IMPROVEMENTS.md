# Logging Improvements (Issue #129)

## Overview

Comprehensive logging system overhaul introducing unified `Aidp::Logger`, adding configuration support, and improving log visibility.

## Changes Implemented

### 1. Logger Configuration

- **Config File Support**: Logger now reads settings from `.aidp/aidp.yml`
- **Environment Variable**: `AIDP_LOG_LEVEL` overrides config file settings
- **CLI Integration**: Logger initialized at startup via `setup_logging` method
- **Log Levels**: Supports `debug`, `info`, `warn`, `error`

### 2. Log File Organization

- **Main Log**: `.aidp/logs/aidp.log` - All log levels with proper level marking
- **Level Marking**: All entries clearly marked (DEBUG, INFO, WARN, ERROR)

### 3. Logger Introduction (Breaking Cleanup)

- **Unified Class**: Primary class is `Aidp::Logger` (file: `lib/aidp/logger.rb`)
- **Removed Legacy**: `Aidp::DebugLogger` and alias `Aidp::AidpLogger` removed (no backward compatibility needed pre-release)
- **DebugMixin Refactor**: All debug methods now use `Aidp.logger`
- **Component Tagging**: Automatic component tags derived from class names
- **Metadata Support**: Rich context via `**metadata` parameter

### 4. Comprehensive Logging Points

Added logging to key components:

- **ProviderManager**: Provider switches, fallback decisions, health checks
- **WorkLoopRunner**: Step execution, iterations, state transitions
- **EnhancedRunner**: Harness execution start with mode/workflow details
- **GuidedAgent**: Planning iterations and errors

### 5. Log Output Behavior

- **Unified Visibility**: Debug logs appear in main log file (not just debug file)
- **Level Filtering**: Config/ENV controls what gets logged
- **Dual Output**: All levels written to both main and debug files for flexibility
- **Structured Format**: Timestamp, level, component, message, optional metadata

## Configuration Example

```yaml
# .aidp/aidp.yml
logging:
  level: debug  # or: info, warn, error
```

## Usage Examples

### Environment Variable Override

```bash
# Override config file setting
export AIDP_LOG_LEVEL=debug
aidp harness run

# Or set for single command
AIDP_LOG_LEVEL=error aidp execute
```

### Programmatic Usage

```ruby
# DebugMixin provides logging methods
class MyClass
  include Aidp::DebugMixin

  def process
    debug_log("Processing started", step: 1, status: "active")
    # ... work ...
    debug_log("Processing complete", duration: elapsed_time)
  end
end

# Direct logger access
Aidp.logger.info("workflow", "Starting execution", workflow_id: "abc123")
Aidp.logger.debug("provider", "Switching provider", from: "claude", to: "copilot")
Aidp.logger.error("harness", "Execution failed", error: e.message)
```

### Log Output Format

```text
# Main log (.aidp/logs/aidp.log)
2025-10-14T19:57:08.100Z DEBUG provider Switching to fallback provider from=claude-sonnet to=github-copilot
2025-10-14T19:57:08.150Z INFO workflow Starting guided workflow goal="Fix authentication"
2025-10-14T19:57:08.200Z ERROR harness Execution failed error="Provider unavailable"

# (Removed) Separate debug log section – all details now appear in the single `aidp.log` when level permits
2025-10-14T19:57:08.100Z DEBUG provider Switching to fallback provider from=claude-sonnet to=github-copilot
2025-10-14T19:57:08.150Z INFO workflow Starting guided workflow goal="Fix authentication"
2025-10-14T19:57:08.200Z ERROR harness Execution failed error="Provider unavailable"
```

## Testing

- All 21 logger specs pass
- Manual verification confirms:
  - Config file settings respected
  - ENV variable override works
  - Debug logs appear in main log with DEBUG marking
  - (Legacy auto-migration removed; not applicable)

## Files Modified

- `lib/aidp/cli.rb` - Added logger initialization
- `lib/aidp/logger.rb` - Class consolidated as `Aidp::Logger`; all levels written to both files
- `lib/aidp/debug_mixin.rb` - Refactored to use unified logger terminology
- `spec/aidp/logger_spec.rb` - Updated to describe `Aidp::Logger`
- `lib/aidp/harness/provider_manager.rb` - Added comprehensive logging
- `lib/aidp/execute/work_loop_runner.rb` - Added execution flow logging
- `lib/aidp/harness/enhanced_runner.rb` - Added initialization logging
- `spec/aidp/logger_spec.rb` - Updated to reflect new behavior

## Migration Notes

Legacy migration logic has been removed (pre-release). If upgrading from an earlier experimental snapshot with `.aidp/debug_logs/`, manually move or discard old files.
