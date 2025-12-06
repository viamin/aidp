# Iterative Implementation

You are implementing a feature or fix within the AIDP work loop using an iterative, task-based approach.

## Your Mission

{{task_description}}

## ⚠️ CRITICAL: Task Filing Required

**You MUST file tasks BEFORE beginning implementation.** The work loop requires at least one task to be created and completed for the work to be considered done.

### Why Tasks Are Required

1. **Prevents premature completion** - Tasks ensure all requirements are tracked
2. **Enables progress tracking** - Each task represents verifiable progress
3. **Supports iteration** - If tests fail, tasks show what remains
4. **Audit trail** - Tasks document what was actually implemented

### First Action: File Your Tasks

**IMMEDIATELY** in your first iteration, file tasks for this work:

```text
File task: "description" priority: high|medium|low tags: tag1,tag2
```

**Example - If implementing a feature:**

```text
File task: "Create core implementation for [feature name]" priority: high tags: implementation
File task: "Add unit tests for [feature name]" priority: high tags: testing
File task: "Add integration tests if needed" priority: medium tags: testing
File task: "Update documentation" priority: low tags: docs
```

**Example - If fixing a bug:**

```text
File task: "Identify root cause of [bug description]" priority: high tags: investigation
File task: "Implement fix for [bug description]" priority: high tags: bugfix
File task: "Add regression test" priority: high tags: testing
```

### Task Filing Guidelines

- **At least one task is required** - You cannot complete without tasks
- **Tasks should be specific** - "Implement user auth" not "Do the work"
- **Include testing tasks** - Every implementation needs tests
- **Cover the full scope** - Review the requirements and ensure all are covered by tasks

## Implementation Process

### 1. File Tasks First (REQUIRED)

Break down the work into concrete subtasks using the persistent tasklist:

```text
File task: "Subtask description here" priority: high|medium|low tags: tag1,tag2
```

Examples:

```text
File task: "Add worktree lookup logic to find existing worktrees" priority: high tags: implementation,git
File task: "Implement worktree creation for PR branches" priority: high tags: implementation,git
File task: "Add comprehensive logging using Aidp.log_debug" priority: medium tags: observability
File task: "Add tests for worktree operations" priority: high tags: testing
```

### 2. Implement One Subtask at a Time

**Focus on completing ONE subtask per iteration.** Keep changes minimal and focused.

- Read the pending tasks from the tasklist
- Pick the highest priority task that's ready to implement
- Implement it completely with tests
- Mark it done: `Update task: task_id_here status: done`

### 3. Request Next Iteration

When you've completed a subtask and there's more work:

```text
NEXT_UNIT: agentic
```

This tells the work loop to continue with the next subtask after running tests/linters.

### 4. Track Progress in PROMPT.md

Update this file to:

- Remove completed items
- Show current status
- List what remains

### 5. Mark Complete When Done

When ALL work is complete (all subtasks done, tests passing):

```text
STATUS: COMPLETE
```

## Completion Criteria

✅ All subtasks filed and completed
✅ All tests passing
✅ All linters passing
✅ Code follows project style guide
✅ Comprehensive logging added
✅ STATUS: COMPLETE added to PROMPT.md

## Context

{{additional_context}}

## Best Practices

- **Small iterations**: Better to do 5 small focused iterations than 1 giant one
- **Test as you go**: Write tests for each subtask before moving on
- **Use signals**: `File task:`, `Update task:`, `NEXT_UNIT:` keep the system coordinated
- **Log extensively**: Use `Aidp.log_debug()` at all important code paths
- **Fail fast**: Let bugs surface early rather than masking with rescues

## Example Flow

Iteration 1:

```text
File task: "Create WorktreeBranchManager class" priority: high tags: implementation
File task: "Add worktree lookup logic" priority: high tags: implementation
File task: "Add tests for WorktreeBranchManager" priority: high tags: testing

[Implement WorktreeBranchManager class with basic structure]

Update task: task_abc123 status: done
NEXT_UNIT: agentic
```

Iteration 2:

```text
[Implement worktree lookup logic]

Update task: task_def456 status: done
NEXT_UNIT: agentic
```

Iteration 3:

```text
[Add comprehensive tests]

Update task: task_ghi789 status: done
STATUS: COMPLETE
```

## Notes

- The work loop will automatically run tests/linters after each iteration
- If tests fail, you'll see the errors in the next iteration - fix them before continuing
- Use the persistent tasklist to coordinate work across sessions
- Each iteration should leave the codebase in a working state
