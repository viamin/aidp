# REPL Reference

## Overview

AIDP's REPL (Read-Eval-Print-Loop) provides interactive macros for fine-grained human control during work loop execution. These commands allow you to:

- Pin files to prevent modifications
- Focus work on specific directories or patterns
- Split complex work into smaller contracts
- Halt on specific test failure patterns

## Available Commands

### `/pin <file|glob>`

Mark one or more files as read-only to prevent AIDP from modifying them.

**Usage:**
```
/pin <file|glob>
```

**Examples:**
```bash
/pin config/database.yml
/pin config/*.yml
/pin .env*
/pin Gemfile
```

**Behavior:**
- Files matching the pattern become read-only for the current work loop
- Supports glob patterns (`*`, `**`, `?`)
- Multiple files can be pinned
- Pinned files persist until unpinned or REPL session ends

**Use Cases:**
- Protect critical configuration files
- Prevent accidental changes to production settings
- Lock down dependency files during refactoring

---

### `/unpin <file|glob>`

Remove read-only protection from previously pinned files.

**Usage:**
```
/unpin <file|glob>
```

**Examples:**
```bash
/unpin config/database.yml
/unpin config/*.yml
/unpin Gemfile
```

**Behavior:**
- Removes pin protection from matching files
- Returns error if no matching pinned files found
- Supports same glob patterns as `/pin`

---

### `/focus <dir|glob>`

Restrict AIDP's work scope to specific files or directories.

**Usage:**
```
/focus <dir|glob>
```

**Examples:**
```bash
/focus lib/features/auth/**/*
/focus lib/**/*.rb
/focus spec/**/*_spec.rb
/focus app/models/**/*
```

**Behavior:**
- Only files matching focus patterns can be modified
- Multiple focus patterns can be active simultaneously
- Files outside focus scope are treated as read-only
- Focus is additive - each `/focus` adds to the allowed set

**Use Cases:**
- Limit changes to a specific feature directory
- Focus on implementation files while developing
- Restrict to test files during TDD sessions

---

### `/unfocus`

Remove all focus restrictions, allowing work on any files again.

**Usage:**
```
/unfocus
```

**Examples:**
```bash
/unfocus
```

**Behavior:**
- Clears all active focus patterns
- All files become eligible for modification (except pinned files)
- Cannot unfocus individual patterns (use `/reset` for selective clearing)

---

### `/split`

Enable split mode to divide the current work plan into smaller, more manageable contracts.

**Usage:**
```
/split
```

**Examples:**
```bash
/split
```

**Behavior:**
- Signals AIDP to break down the current work into smaller steps
- Each sub-contract completes independently
- Useful for complex features that benefit from incremental implementation
- Split mode persists for the current work loop

**Use Cases:**
- Break down large features into smaller chunks
- Create more granular checkpoints
- Enable more frequent testing and validation

---

### `/halt-on <pattern>`

Pause the work loop when test failures match a specific pattern.

**Usage:**
```
/halt-on <pattern>
```

**Examples:**
```bash
/halt-on authentication.*failed
/halt-on 'database.*connection.*error'
/halt-on "UserModel.*validation"
/halt-on NoMethodError
```

**Behavior:**
- Pattern is treated as a case-insensitive regular expression
- Work loop pauses when any test failure message matches the pattern
- Multiple halt patterns can be active
- Patterns remain active until removed with `/unhalt`

**Use Cases:**
- Stop immediately when a critical test fails
- Inspect state when specific errors occur
- Debug intermittent failures
- Prevent cascading failures in specific areas

---

### `/unhalt [pattern]`

Remove halt-on pattern(s).

**Usage:**
```
/unhalt [pattern]
```

**Examples:**
```bash
# Remove specific pattern
/unhalt authentication.*failed

# Remove all halt patterns
/unhalt
```

**Behavior:**
- With pattern: removes only that specific pattern
- Without pattern: removes all halt patterns
- Returns error if specified pattern wasn't set

---

### `/status`

Display current state of all REPL macros.

**Usage:**
```
/status
```

**Example Output:**
```
REPL Macro Status:

Pinned Files (2):
  - config/database.yml
  - .env

Focus Patterns (1):
  - lib/features/auth/**/*

Halt Patterns (1):
  - authentication.*failed

Split Mode: enabled
```

**Behavior:**
- Shows all active constraints
- Lists pinned files
- Displays focus patterns
- Shows halt patterns
- Indicates split mode status

---

### `/reset`

Clear all REPL macros and return to default state.

**Usage:**
```
/reset
```

**Examples:**
```bash
/reset
```

**Behavior:**
- Unpins all files
- Removes all focus restrictions
- Clears all halt patterns
- Disables split mode
- Essentially starts fresh

**Use Cases:**
- Clear all constraints at once
- Reset after completing a focused task
- Start a new work phase with clean slate

---

### `/help [command]`

Display help information for REPL commands.

**Usage:**
```
/help [command]
```

**Examples:**
```bash
# List all commands
/help

# Get help for specific command
/help /pin
/help /focus
/help /halt-on
```

**Behavior:**
- Without argument: lists all available commands
- With command name: shows detailed help for that command
- Returns error for unknown commands

---

## Pattern Syntax

REPL commands support glob patterns for file matching:

| Pattern | Description | Example |
|---------|-------------|---------|
| `*` | Match any characters except `/` | `*.rb` matches `file.rb` |
| `**` | Match zero or more directories | `lib/**/*.rb` matches `lib/foo/bar.rb` |
| `?` | Match single character | `file?.rb` matches `file1.rb` |
| `[abc]` | Match character class | `file[123].rb` matches `file1.rb` |
| `{a,b}` | Match alternatives | `*.{rb,js}` matches `file.rb` or `file.js` |

### Pattern Examples

```bash
# All Ruby files
/pin **/*.rb

# Specific directory
/focus lib/features/auth/**/*

# Multiple extensions
/pin *.{yml,yaml,env}

# Test files
/focus spec/**/*_spec.rb

# Configuration files
/pin config/**/*.{yml,yaml}
```

## Workflow Examples

### Example 1: Protected Configuration

Protect critical files while working on a feature:

```bash
# Pin configuration files
/pin config/database.yml
/pin .env*
/pin config/secrets.yml

# Focus on feature directory
/focus lib/features/user_auth/**/*

# Check status
/status
```

### Example 2: TDD Workflow

Focus on tests first, then implementation:

```bash
# Start with test focus
/focus spec/models/user_spec.rb

# ... write tests ...

# Expand focus to implementation
/focus lib/models/user.rb

# ... implement feature ...
```

### Example 3: Debugging Specific Failures

Halt on specific errors for investigation:

```bash
# Halt on authentication errors
/halt-on authentication.*failed

# Halt on database errors
/halt-on database.*error

# Run work loop - will pause when patterns match
```

### Example 4: Incremental Feature Development

Break down large features with split mode:

```bash
# Enable split mode
/split

# Focus on one aspect at a time
/focus lib/features/checkout/cart.rb
/focus spec/features/checkout/cart_spec.rb

# ... complete cart functionality ...

/unfocus
/focus lib/features/checkout/payment.rb
/focus spec/features/checkout/payment_spec.rb

# ... complete payment functionality ...
```

### Example 5: Safe Refactoring

Protect files while refactoring others:

```bash
# Pin files you don't want to touch
/pin lib/legacy/**/*
/pin app/controllers/**/*

# Focus on refactoring target
/focus lib/services/user_service.rb

# Halt on any failures
/halt-on error
/halt-on failed
```

## Integration with Work Loops

REPL macros integrate seamlessly with AIDP's work loop system:

### Pinned Files

- Treated as read-only by the work loop
- Agent will skip modifying pinned files
- Violations logged in work loop output

### Focus Patterns

- Restrict agent's modification scope
- Files outside focus are treated as pinned
- Empty focus list = all files in scope

### Halt Patterns

- Work loop pauses when pattern matches test failure
- Agent can inspect PROMPT.md and state
- Resume with `/unhalt` or continue work loop

### Split Mode

- Work plan divided into smaller contracts
- Each contract has its own success criteria
- More frequent checkpoints and validation

## REPL Session Management

### Starting a REPL Session

```bash
# Start work loop with REPL support
aidp execute --repl

# Or enable in configuration
# .aidp.yml:
harness:
  work_loop:
    repl_enabled: true
```

### During a Session

- Commands can be issued at any iteration
- State persists throughout the work loop
- Use `/status` to check current constraints

### Ending a Session

- Macros cleared when work loop completes
- Can use `/reset` to clear during session
- State doesn't persist across work loop runs

## Best Practices

### 1. Start Restrictive, Then Loosen

```bash
# Begin with tight constraints
/pin config/**/*
/focus lib/specific_feature/**/*

# Gradually expand as needed
/unfocus
/focus lib/**/*.rb
```

### 2. Use Status Frequently

```bash
# Check what's active
/status

# Verify constraints before proceeding
```

### 3. Combine Constraints

```bash
# Pin + Focus for maximum control
/pin Gemfile
/pin package.json
/focus lib/services/**/*
```

### 4. Clear When Changing Context

```bash
# Moving to different feature
/reset
/focus lib/other_feature/**/*
```

### 5. Use Halt for Critical Paths

```bash
# Stop on important failures
/halt-on security.*violation
/halt-on authentication.*bypass
```

## Troubleshooting

### "No matching pinned files found"

- File wasn't pinned or pattern doesn't match
- Check `/status` to see pinned files
- Verify glob pattern syntax

### "File outside focus scope"

- File doesn't match any active focus patterns
- Use `/status` to check focus patterns
- Use `/unfocus` to remove restrictions

### "Halt pattern never triggers"

- Pattern doesn't match test failure messages
- Patterns are case-insensitive regex
- Check actual failure message format
- Use `/unhalt` to remove incorrect pattern

### Work loop seems frozen

- May have hit a halt pattern
- Check console for halt notification
- Use `/unhalt` to resume
- Use `/status` to check active halts

## Command Reference Summary

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/pin` | `<file\|glob>` | Mark files as read-only |
| `/unpin` | `<file\|glob>` | Remove read-only protection |
| `/focus` | `<dir\|glob>` | Restrict scope to pattern |
| `/unfocus` | _(none)_ | Remove all focus restrictions |
| `/split` | _(none)_ | Enable split mode |
| `/halt-on` | `<pattern>` | Pause on matching failures |
| `/unhalt` | `[pattern]` | Remove halt pattern(s) |
| `/status` | _(none)_ | Show current macro state |
| `/reset` | _(none)_ | Clear all macros |
| `/help` | `[command]` | Show help information |

## Related Documentation

- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Work loop fundamentals
- [Safety Guards](SAFETY_GUARDS.md) - Configuration-based constraints
- [Harness Configuration](harness-configuration.md) - AIDP configuration

## Implementation Notes

- REPL macros are implemented in `lib/aidp/execute/repl_macros.rb`
- Fully tested with 61 test cases
- Pattern matching uses `File.fnmatch` for safety (no ReDoS risk)
- All commands return structured results for integration

## Future Enhancements

Planned features for REPL macros:

- [ ] Interactive confirmation prompts
- [ ] Macro presets and saved configurations
- [ ] Conditional halt patterns (halt-if conditions)
- [ ] Time-based constraints (work window limits)
- [ ] Resource usage limits (max files changed, max lines)
- [ ] Integration with version control (halt on merge conflicts)
- [ ] Macro scripting (chain multiple commands)

---

**Note**: This REPL system provides fine-grained control while preserving AIDP's autonomous capabilities. Use constraints judiciously to guide work without over-constraining the agent.
