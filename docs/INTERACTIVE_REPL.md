# Interactive REPL During Work Loops

## Overview

AIDP's Interactive REPL provides **asynchronous live control** during work loop execution. The main REPL remains active while the agent runs in a separate background thread, allowing you to manage, guide, and adjust the active work loop in real time without halting execution.

This feature implements [GitHub Issue #103](https://github.com/viamin/aidp/issues/103).

## Architecture

### Asynchronous Execution Model

```text
┌──────────────────────────────────────────────────────────────┐
│                     Main Thread (REPL)                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Interactive REPL Loop                                 │  │
│  │  - Accept commands (/pause, /inject, etc.)            │  │
│  │  - Display streaming output                           │  │
│  │  - Queue modifications                                │  │
│  │  - Control work loop lifecycle                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                           ↕                                   │
│                  Thread-Safe Queue                            │
│                           ↕                                   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Output Display Thread                                 │  │
│  │  - Poll for work loop output                          │  │
│  │  - Display progress updates                           │  │
│  │  - Stream logs and status                             │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                           ↕
┌──────────────────────────────────────────────────────────────┐
│                   Background Thread (Work Loop)               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Async Work Loop Runner                                │  │
│  │  - Execute work loop iterations                        │  │
│  │  - Check for pause/cancel signals                      │  │
│  │  - Merge queued instructions                           │  │
│  │  - Apply configuration updates                         │  │
│  │  - Send output to main thread                          │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Responsibility |
|-----------|---------------|
| **InteractiveRepl** | Main REPL interface, command handling, user interaction |
| **AsyncWorkLoopRunner** | Thread management, async execution wrapper |
| **WorkLoopState** | Thread-safe state container (running/paused/cancelled) |
| **InstructionQueue** | Queues mid-loop modifications for merging |
| **ReplMacros** | Command parsing and validation |
| **WorkLoopRunner** | Synchronous work loop execution (runs in thread) |

## Live REPL Commands

### Execution Control

#### `/pause`

Pause the work loop at the next safe stopping point.

**Usage:**

```text
/pause
```

**Behavior:**

- Work loop completes current iteration
- State changes to PAUSED
- REPL remains active for inspection and commands
- No checkpoints are lost

**Example:**

```text
aidp[5]> /pause
Pause signal sent to work loop
Work loop paused at iteration 5
aidp[5|PAUSED]>
```

---

#### `/resume`

Resume a paused work loop.

**Usage:**

```text
/resume
```

**Behavior:**

- Work loop continues from where it paused
- State changes to RUNNING
- Queued instructions are merged into next iteration

**Example:**

```text
aidp[5|PAUSED]> /resume
Resume signal sent to work loop
Work loop resumed at iteration 5
aidp[6]>
```

---

#### `/cancel [--no-checkpoint]`

Cancel the work loop gracefully and return to stable state.

**Usage:**

```text
/cancel                # Cancel with checkpoint save
/cancel --no-checkpoint # Cancel without saving
```

**Behavior:**

- Work loop completes current iteration safely
- By default, saves checkpoint with cancellation reason
- Queued instructions are preserved in state
- Returns to IDLE state

**Example:**

```text
aidp[10]> /cancel
Cancelling with checkpoint save...
Work loop cancelled at iteration 10
Saving checkpoint before exit...
✅ Checkpoint saved: .aidp/checkpoints/cancellation_iter_10

⚠️  Work loop cancelled by user
Iterations: 10
```

---

### Instruction Injection

#### `/inject <instruction>`

Add new instructions to be merged into the next iteration.

**Usage:**

```text
/inject <instruction> [--priority high|normal|low]
```

**Behavior:**

- Instruction is queued immediately
- Merged into PROMPT.md at next iteration boundary
- Agent sees instruction along with current work
- Multiple instructions can be queued

**Priority Levels:**

- `critical` - Addressed immediately (if possible)
- `high` - Prioritized in next iteration
- `normal` - Standard priority (default)
- `low` - Addressed when convenient

**Examples:**

```text
# Standard instruction
aidp[3]> /inject Add error handling for network timeouts
Instruction queued for next iteration (priority: normal)

# High priority instruction
aidp[4]> /inject Fix security vulnerability in auth --priority high
Instruction queued for next iteration (priority: high)

# View queued instructions
aidp[4] (2 queued)>
```

---

#### `/merge <plan_update>`

Update the implementation plan or contract for next iteration.

**Usage:**

```text
/merge <plan_update>
```

**Behavior:**

- Plan updates are queued with HIGH priority
- Merged into PROMPT.md under "Plan Updates" section
- Agent reconciles old plan with new changes
- Does not restart work loop - merges incrementally

**Examples:**

```text
# Add new acceptance criteria
aidp[5]> /merge Add acceptance criteria: API handles 429 rate limits

# Clarify requirements
aidp[6]> /merge Clarification: use bcrypt for password hashing, not SHA256

# Add constraint
aidp[7]> /merge New constraint: Must maintain backwards compatibility with v1 API
```

---

### Configuration Updates

#### `/update guard <key>=<value>`

Update guard rail configuration during execution.

**Usage:**

```text
/update guard <key>=<value>
```

**Supported Keys:**

- `max_lines` - Maximum lines per commit
- `include_patterns` - Files to include (glob)
- `exclude_patterns` - Files to exclude (glob)
- `confirm_patterns` - Files requiring confirmation (glob)

**Behavior:**

- Update is queued for next iteration
- Applied at safe boundary (between iterations)
- Does not affect in-progress work
- Changes persist for remainder of work loop

**Examples:**

```text
# Increase max lines per commit
aidp[3]> /update guard max_lines=500
Guard update queued: max_lines = 500
Guard update will apply at next iteration

# Add exclude pattern
aidp[4]> /update guard exclude_patterns=tmp/**
Guard update queued: exclude_patterns = tmp/**

# Require confirmation for critical files
aidp[5]> /update guard confirm_patterns=config/production.yml
Guard update queued: confirm_patterns = config/production.yml
```

---

#### `/reload config`

Reload configuration from `.aidp.yml` file.

**Usage:**

```text
/reload config
```

**Behavior:**

- Reads configuration from disk
- Applies changes at next iteration boundary
- Useful after editing config file during execution
- Invalid config causes error (work loop continues with old config)

**Example:**

```text
# Edit .aidp.yml in another terminal
aidp[8]> /reload config
Configuration reload requested for next iteration
Config reload will apply at next iteration

# Next iteration will use new config
```

---

### Rollback Operations

#### `/rollback <n>`

Rollback last n commits on current branch.

**Usage:**

```text
/rollback <n>
```

**Safety:**

- Only works on feature branches (not main/master)
- Pauses work loop before rollback
- Asks for confirmation to resume after rollback
- Uses `git reset --hard HEAD~n`

**Example:**

```text
aidp[12]> /rollback 2
Work loop paused for rollback
Rolling back 2 commit(s)...
✅ Rollback complete: Reset 2 commit(s)
Resume work loop? (Y/n) y
Work loop resumed at iteration 12
```

---

#### `/undo last`

Undo the last commit (shorthand for `/rollback 1`).

**Usage:**

```text
/undo last
```

**Example:**

```text
aidp[7]> /undo last
Work loop paused for rollback
Rolling back 1 commit(s)...
✅ Rollback complete: Reset 1 commit(s)
Resume work loop? (Y/n) y
```

---

### Information & Status

#### `/status`

Show current state of work loop and queued modifications.

**Usage:**

```text
/status
```

**Output Includes:**

- Work loop state (RUNNING, PAUSED, etc.)
- Current iteration number
- Queued instructions (count and summary)
- REPL macro state (pins, focus, halts)
- Thread status

**Example:**

```text
aidp[15]> /status
Work Loop Status:
  State: RUNNING
  Iteration: 15
  Thread: alive

Queued Instructions: 3
  By Type:
    - USER_INPUT: 2
    - PLAN_UPDATE: 1
  By Priority:
    - HIGH: 1
    - NORMAL: 2

REPL Macro Status:
  Pinned Files: 0
  Focus: All files in scope
  Halt Patterns: 0
  Split Mode: disabled
```

---

### Standard REPL Macros

All standard REPL macros from [REPL_REFERENCE.md](REPL_REFERENCE.md) are also available:

- `/pin <file>` - Mark files read-only
- `/focus <pattern>` - Restrict scope
- `/halt-on <pattern>` - Pause on test failures
- `/help` - Show all commands
- `/reset` - Clear all macros

See [REPL_REFERENCE.md](REPL_REFERENCE.md) for complete documentation.

---

## Workflow Examples

### Example 1: Add Requirement Mid-Execution

Agent is implementing a feature, and you realize a requirement was missed:

```text
aidp[8]> /inject Add validation for email format in User model
Instruction queued for next iteration (priority: normal)

aidp[9]> # Work continues, instruction merged automatically
```

At iteration 9, the agent sees:

```markdown
## 🔄 Queued Instructions from REPL

The following instructions were added during execution and should be
incorporated into your next iteration:

### USER_INPUT
1. Add validation for email format in User model

**Note**: Address these instructions while continuing your current work.
Do not restart from scratch - build on what exists.
```

---

### Example 2: Adjust Configuration During Long Run

Work loop is running, tests are slow, and you want to run only unit tests:

```text
# Edit .aidp.yml to change test commands
$ vim .aidp.yml  # (in another terminal)

# Reload in REPL
aidp[23]> /reload config
Configuration reload requested for next iteration
Config reload will apply at next iteration

# Next iteration will use faster test subset
aidp[24]> # Tests now run faster
```

---

### Example 3: Pause to Inspect State

Work loop is making unexpected changes:

```text
aidp[12]> /pause
Pause signal sent to work loop
Work loop paused at iteration 12

aidp[12|PAUSED]> # Inspect files, run manual tests

$ git diff  # (in another terminal)
$ cat PROMPT.md

aidp[12|PAUSED]> /inject Be more conservative - only modify auth files
Instruction queued for next iteration (priority: high)

aidp[12|PAUSED]> /focus lib/auth/**/*
Focus set to: lib/auth/**/*

aidp[12|PAUSED]> /resume
Resume signal sent to work loop
Work loop resumed at iteration 12
```

---

### Example 4: Rollback Bad Changes

Agent made a commit that breaks tests unexpectedly:

```text
aidp[18]> /pause
Work loop paused at iteration 18

aidp[18|PAUSED]> /undo last
Work loop paused for rollback
Rolling back 1 commit(s)...
✅ Rollback complete: Reset 1 commit(s)
Resume work loop? (Y/n) n

aidp[18|PAUSED]> /inject Previous approach broke tests, try using dependency injection instead
Instruction queued for next iteration (priority: high)

aidp[18|PAUSED]> /resume
Work loop resumed at iteration 18
```

---

### Example 5: Cancel with Checkpoint

Something urgent comes up, need to stop work loop cleanly:

```text
aidp[25]> /cancel
Cancelling with checkpoint save...
Cancellation requested, waiting for safe stopping point...
Saving checkpoint before exit...
Work loop cancelled at iteration 25

⚠️  Work loop cancelled by user
Iterations: 25

# Later, resume from checkpoint
$ aidp execute --resume-from checkpoint_iter_25
```

---

## Interrupt Handling

Press **Ctrl-C** during execution to access the interrupt menu:

```text
aidp[10]> ^C
Interrupt received

What would you like to do?
  1) Cancel work loop
  2) Pause work loop
  3) Continue REPL

Choice: 2
Pause signal sent to work loop
Work loop paused
```

**Double Ctrl-C** forces immediate exit without checkpoint.

---

## Queued Instruction Merging

### How Instructions Are Merged

At each iteration boundary, queued instructions are:

1. **Sorted** by priority, then timestamp
2. **Formatted** into PROMPT.md section
3. **Appended** to current PROMPT.md
4. **Cleared** from queue (to avoid duplication)

### PROMPT.md Format

```markdown
# Work Loop: Feature Implementation

[... existing prompt content ...]

---

## 🔄 Queued Instructions from REPL

The following instructions were added during execution and should be
incorporated into your next iteration:

### USER_INPUT
1. Add error handling for network timeouts
2. Improve logging for debugging

### PLAN_UPDATE
1. Add acceptance criteria: API handles 429 rate limits 🔴 CRITICAL

**Note**: Address these instructions while continuing your current work.
Do not restart from scratch - build on what exists.
```

### Instruction Types

| Type | Description | Priority |
|------|-------------|----------|
| `USER_INPUT` | Direct user instructions | Normal |
| `PLAN_UPDATE` | Plan/contract changes | High |
| `CONSTRAINT` | New constraints | High |
| `CLARIFICATION` | Clarifications on work | Normal |
| `ACCEPTANCE_CRITERIA` | New acceptance criteria | High |

---

## Configuration

### Enable Interactive REPL

In `.aidp.yml`:

```yaml
harness:
  work_loop:
    enabled: true
    interactive_repl: true  # Enable async interactive REPL
    max_iterations: 50
    test_commands:
      - "bundle exec rspec"
    lint_commands:
      - "bundle exec standardrb"
```

### Start Interactive Work Loop

```bash
# Start with interactive REPL
aidp execute --interactive

# Or use standard execute (REPL starts automatically if enabled)
aidp execute
```

---

## State Management

### Work Loop States

```text
IDLE → RUNNING ⇄ PAUSED → CANCELLED
         ↓                    ↓
      COMPLETED            ERROR
```

| State | Description | Can Transition To |
|-------|-------------|-------------------|
| `IDLE` | Not started | RUNNING |
| `RUNNING` | Actively executing | PAUSED, CANCELLED, COMPLETED, ERROR |
| `PAUSED` | Temporarily stopped | RUNNING, CANCELLED |
| `CANCELLED` | User cancelled | _(terminal)_ |
| `COMPLETED` | Successfully finished | _(terminal)_ |
| `ERROR` | Encountered error | _(terminal)_ |

### Thread Safety

All state transitions use Ruby's `MonitorMixin` for thread safety:

- State changes are atomic
- Queues are synchronized
- Output buffering is thread-safe
- No race conditions between REPL and work loop

---

## Output Streaming

### Real-Time Display

The Interactive REPL displays streaming output from the work loop:

```text
aidp[5]>
🔄 Starting iteration 5
📝 Reading PROMPT.md
🤖 Sending to agent...
✅ Agent completed changes
🧪 Running tests...
✅ Tests passed (42 tests)
🔍 Running linters...
✅ Linters passed
📊 Checkpoint recorded

aidp[6]>
```

### Output Types

- `INFO` - Standard progress messages
- `SUCCESS` - Successful operations (✅)
- `WARNING` - Warnings or issues (⚠️)
- `ERROR` - Errors or failures (❌)

---

## Safety & Best Practices

### Safety Features

1. **Graceful Cancellation**: Always saves checkpoint before exit
2. **Rollback Safety**: Only on feature branches, requires confirmation
3. **Iteration Boundaries**: Changes applied at safe points
4. **State Validation**: Prevents invalid state transitions
5. **Error Handling**: Work loop errors don't crash REPL

### Best Practices

#### 1. Use Priorities Wisely

```bash
# Critical issues
/inject Fix security vulnerability --priority high

# Nice-to-haves
/inject Improve error messages --priority low
```

#### 2. Pause Before Major Changes

```bash
# Pause, inspect, then inject changes
/pause
# ... inspect state ...
/inject [changes]
/resume
```

#### 3. Checkpoint Frequently

Let work loop create automatic checkpoints, but use `/cancel` for manual checkpoints before risky operations.

#### 4. Use Rollback Conservatively

Rollback should be last resort. Prefer using `/inject` to guide agent toward better solution.

#### 5. Monitor Queue Size

Too many queued instructions can overwhelm the agent:

```bash
aidp[10] (8 queued)> /status  # Check what's queued
```

---

## Integration with Safety Guards

Interactive REPL works seamlessly with [SAFETY_GUARDS.md](SAFETY_GUARDS.md):

- Guard rails enforced even during async execution
- `/update guard` allows live adjustment
- Pinned files respected across REPL commands
- Focus patterns combine with guard policies

Example:

```yaml
# .aidp.yml
guards:
  include:
    - "lib/**/*.rb"
  exclude:
    - "config/**/*"
  max_lines_per_commit: 300
```

```bash
# In REPL, temporarily increase limit
aidp[5]> /update guard max_lines=500

# Or add new exclude pattern
aidp[6]> /update guard exclude_patterns=tmp/**
```

---

## Checkpoints & Recovery

### Automatic Checkpoints

Checkpoints are created:

- Every N iterations (configured)
- When work loop completes
- When user cancels (via `/cancel`)
- Before rollback operations

### Checkpoint Contents

```text
.aidp/checkpoints/iter_25_cancelled/
├── PROMPT.md              # State at checkpoint
├── work_loop_state.json   # Full state snapshot
├── queued_instructions.json  # Pending instructions
├── git_state.txt          # Git status/diff
└── metadata.json          # Timestamp, reason, etc.
```

### Resume from Checkpoint

```bash
# List checkpoints
aidp checkpoint list

# Resume from specific checkpoint
aidp execute --resume-from checkpoint_iter_25

# Queued instructions are automatically restored
```

---

## Troubleshooting

### Work Loop Doesn't Pause

**Symptoms**: `/pause` command accepted but work loop continues

**Causes**:

- Currently in middle of agent execution
- Waiting for iteration boundary

**Solution**: Wait for current iteration to complete (agent returns control)

---

### Commands Don't Take Effect

**Symptoms**: Commands execute but nothing changes

**Causes**:

- Commands queued for next iteration
- Work loop paused and needs `/resume`

**Solution**: Check status with `/status`, ensure work loop is running

---

### REPL Becomes Unresponsive

**Symptoms**: Can't enter commands

**Causes**:

- Main thread blocked
- Output display thread consuming resources

**Solution**: Press Ctrl-C for interrupt menu, then cancel or pause

---

### Rollback Fails

**Symptoms**: `/rollback` returns error

**Causes**:

- On main/master branch
- Detached HEAD state
- Not enough commits to rollback

**Solution**:

- Check current branch: `git branch --show-current`
- Create feature branch if needed
- Verify commit history: `git log --oneline`

---

### Queued Instructions Not Merged

**Symptoms**: Instructions queued but not appearing in PROMPT.md

**Causes**:

- Work loop cancelled before merge
- Error during merge process

**Solution**:

- Check checkpoint - queued instructions saved
- Resume from checkpoint to continue
- Manually add to PROMPT.md if needed

---

## Performance Considerations

### Thread Overhead

The async model adds minimal overhead:

- Main thread: ~1-2% CPU (polling, display)
- Work loop thread: Normal work loop CPU usage
- Output thread: ~0.5% CPU (500ms poll interval)

### Memory Usage

- State container: <1MB
- Instruction queue: ~100 bytes per instruction
- Output buffer: Auto-drains every 500ms

### Scalability

The interactive REPL scales well:

- ✅ 100+ iterations without degradation
- ✅ 50+ queued instructions handled efficiently
- ✅ Long-running sessions (hours) supported

---

## API Reference

### InteractiveRepl

```ruby
repl = Aidp::Execute::InteractiveRepl.new(
  project_dir,
  provider_manager,
  config,
  options
)

# Start work loop with REPL
result = repl.start_work_loop(step_name, step_spec, context)
```

### AsyncWorkLoopRunner

```ruby
runner = Aidp::Execute::AsyncWorkLoopRunner.new(
  project_dir,
  provider_manager,
  config,
  options
)

# Start async execution
runner.execute_step_async(step_name, step_spec, context)

# Control execution
runner.pause
runner.resume
runner.cancel(save_checkpoint: true)

# Queue instructions
runner.enqueue_instruction(
  "Add error handling",
  type: :user_input,
  priority: :normal
)

# Check status
status = runner.status

# Wait for completion
result = runner.wait
```

### WorkLoopState

```ruby
state = Aidp::Execute::WorkLoopState.new

# State transitions
state.start!
state.pause!
state.resume!
state.cancel!
state.complete!

# Check state
state.running?
state.paused?

# Queue management
state.enqueue_instruction("instruction")
instructions = state.dequeue_instructions

# Output
state.append_output("message", type: :info)
output = state.drain_output
```

### InstructionQueue

```ruby
queue = Aidp::Execute::InstructionQueue.new

# Add instructions
queue.enqueue("Add feature X", type: :user_input, priority: :high)

# Retrieve instructions
instructions = queue.dequeue_all
formatted = queue.format_for_prompt

# Query
count = queue.count
summary = queue.summary
```

---

## Related Documentation

- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Work loop fundamentals
- [REPL Reference](REPL_REFERENCE.md) - Standard REPL commands
- [Safety Guards](SAFETY_GUARDS.md) - Configuration-based constraints
- [Checkpoints](harness-configuration.md#checkpoints) - Checkpoint system

---

## Future Enhancements

Planned improvements for Interactive REPL:

- [ ] Multi-work-loop management (run multiple work loops concurrently)
- [ ] Visual TUI with split panes (output + REPL)
- [ ] Command history and autocomplete
- [ ] Saved command macros
- [ ] Conditional halt patterns with expressions
- [ ] Integration with external tools (webhooks, notifications)
- [ ] Replay capability from saved sessions

---

## Summary

The Interactive REPL transforms AIDP's work loops from batch operations into live, controllable processes. Key benefits:

- **No Interruption**: Work loop runs continuously, REPL always responsive
- **Live Adjustment**: Inject instructions, update config, modify plan mid-execution
- **Safe Control**: Pause, resume, cancel gracefully with checkpoints
- **Real-Time Feedback**: Stream output as work progresses
- **Flexible Rollback**: Undo commits when needed
- **Queue Management**: Multiple modifications merged intelligently

The async architecture ensures smooth operation while maintaining full control over the autonomous agent.
