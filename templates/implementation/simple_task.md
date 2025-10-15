# Simple Task Execution

You are executing a simple, focused task within the AIDP work loop.

## Your Task

{{task_description}}

## Important Instructions

1. **Read the task above carefully**
2. **Execute the task exactly as described**
3. **Verify your work** by running any validation commands specified
4. **Edit this PROMPT.md** to track progress and mark complete when done
5. **Request follow-up units** by adding `NEXT_UNIT: <unit_name>` to your
   response when deterministic work (tests, linting, wait states) should run
   next

## Completion Criteria

When the task is 100% complete:

1. The task description requirements are fully met
2. Any specified validation commands pass
3. You've added this line to PROMPT.md:

```text
STATUS: COMPLETE
```

## Context

{{additional_context}}

## Notes

- Keep your changes minimal and focused on the task
- If the task involves running commands, show the command output
- If the task involves fixing issues, list what was fixed
- When you need automation to continue after this task, emit `NEXT_UNIT: agentic`
  or a deterministic unit such as `run_full_tests` or `wait_for_github`
