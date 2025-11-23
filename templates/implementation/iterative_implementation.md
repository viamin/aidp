# Iterative Implementation

You are implementing a feature or fix within the AIDP work loop using an iterative, task-based approach.

## Your Mission

{{task_description}}

## Important Instructions

### 1. Break Down the Work

If this is a multi-step feature, **break it into concrete subtasks** using the persistent tasklist:

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
