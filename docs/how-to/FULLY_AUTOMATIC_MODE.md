# Fully Automatic Watch Mode

Aidp can now operate in a fully automatic "watch" mode that monitors a GitHub
repository, drafts plans, and executes approved work loops end-to-end. This
mode sits on top of the standard work loop engine and orchestrates planning,
implementation, and pull request creation without human supervision.

## Prerequisites

- Git repository checked out locally with write access.
- GitHub issue labels `aidp-plan` and `aidp-build` defined in the repository.
- GitHub CLI (`gh`) authenticated for the repository (required for private
  projects, commenting, and PR creation).
- Recommended: existing Aidp configuration (`aidp.yml`) with providers that can
  run unattended (e.g., Cursor CLI, Claude CLI).
- Use the [Setup Wizard](SETUP_WIZARD.md) (`aidp config --interactive`) to
  define provider choices, work loop commands, and guard rails before enabling
  watch mode.

## Deterministic Backbone

Watch mode now leans on deterministic units to keep the loop alive between
agent invocations. The default `wait_for_github` unit polls for new issues,
labels, or comments and re-enqueues itself until an event is detected. When
activity arrives it emits `NEXT_UNIT: agentic`, handing control back to the
fix-forward agent. This allows Aidp to remain token-efficient while still
reacting instantly to repository changes.

Tune the behaviour via `harness.work_loop.units` in `aidp.yml`. You can supply
additional deterministic units (e.g., nightly test suites or long-running CI
builds) and adjust cooldowns/backoff without modifying the agent workflow.

## Starting Watch Mode

```bash
aidp watch https://github.com/<owner>/<repo>/issues

# Optional flags
aidp watch owner/repo --interval 120 --provider claude
aidp watch owner/repo --once   # Run a single polling cycle (useful for CI)
```

When running, Aidp observes the repository for label changes and reacts as
follows:

```text
+-------------------------------+        +-----------------------------+
| aidp-plan label added | aidp-build label added |
|  |
| 1. Fetch issue + comments | 1. Verify plan exists |
| 2. Generate Implementation | 2. Create aidp/issue-* |
| Contract proposal | branch |
| 3. Post plan + questions | -----> | 3. Run fix-forward loop |
| 4. Await answers | 4. Commit + create PR |
+-------------------------------+        | 5. Comment success/failure  |
                                         +-----------------------------+
```

### Plan Trigger (`aidp-plan`)

1. Aidp reads the issue and existing comments.
2. A plan generator (provider-backed when possible) produces an implementation
   contract containing:
   - Summary of the proposed solution.
   - Structured task list.
   - Clarifying questions for the requester.
3. The plan is posted as a comment instructing collaborators to reply inline.
4. Plan metadata is cached locally with iteration tracking.

#### Iterative Planning

Watch mode supports multiple planning cycles for issues that need refinement:

1. **Initial Plan**: When `aidp-plan` is first added to an issue, Aidp generates and
   posts a plan comment with structured sections (summary, tasks, questions).

2. **Re-planning**: If the `aidp-plan` label is re-applied to an issue that already
   has a plan, Aidp detects this and performs an iterative update:
   - Archives the previous plan content in a collapsible `<details>` section with HTML comments
   - Generates a fresh plan based on current issue state and comments
   - Updates the same comment (preserving comment thread context)
   - Increments the iteration counter in state tracking

3. **Archived Plans**: Previous iterations are preserved in the comment using HTML
   comment markers (`<!-- ARCHIVED_PLAN_START -->` ... `<!-- ARCHIVED_PLAN_END -->`),
   allowing users to review the planning evolution while keeping the current plan
   visible.

4. **Clean Build Prompts**: When the `aidp-build` trigger runs, archived plan sections
   are automatically stripped from the implementation prompt, ensuring the AI agent
   only sees the current, active plan.

**Example workflow:**

```text
1. Add aidp-plan → Initial plan posted (Iteration 1)
2. Team discusses, identifies issues in comments
3. Re-add aidp-plan → Plan updated, old plan archived (Iteration 2)
4. Repeat as needed for complex issues
5. Add aidp-build → Implementation uses only latest plan
```

This iterative approach allows for collaborative refinement of implementation plans
without losing historical context or confusing the build agent with outdated information.

### Build Trigger (`aidp-build`)

1. Aidp verifies that a cached plan exists; if not it logs a warning and skips.
2. The watch workflow creates or resets an implementation branch named
   `aidp/issue-<number>-<slug>`.
3. `PROMPT.md` is seeded with the approved implementation contract and
   clarifications gathered from the issue thread.
4. The autonomous work loop executes step `16_IMPLEMENTATION`, applying patches,
   running tests/linters, and iterating until completion.
5. **Implementation verification** checks completeness before creating PR:
   - Extracts requirements from the linked issue
   - Compares implementation against acceptance criteria
   - If incomplete: creates follow-up tasks and continues work loop
   - If complete: proceeds to PR creation
6. When successful, Aidp stages changes, commits with a descriptive message, and
   creates a pull request via `gh pr create` linking back to the issue.
7. On failures (test/lint issues, timeouts, or provider errors) Aidp posts a
   summary comment and leaves the branch intact for manual follow-up.

#### Incomplete Implementation Handling

If verification determines the implementation is incomplete:

- Changes are committed locally (preserving work done)
- Follow-up tasks are created for missing requirements
- Work loop continues automatically (no PR created yet)
- State is recorded in `.aidp/watch/*.yml`
- Next iteration addresses remaining requirements

This ensures that PRs are only created when implementations fully address all issue requirements.

## Safety Considerations

- Always verify provider authentication before enabling watch mode; the agent
  must operate unattended.
- Use protected branches or required reviews to gate automatic PR merges.
- Keep `aidp-plan` and `aidp-build` labels restricted to trusted maintainers.
- Monitor the `.aidp/watch/*.yml` cache for status history and investigate
  repeated failures.
- Consider running `aidp watch --once` in CI to provide additional safeguards
  before promoting automatic PRs.

## State Management

Aidp uses **GitHub as the single source of truth** for watch mode state, enabling:

- Manual intervention by adding/removing labels
- Human-visible state in the GitHub UI
- State that survives workspace deletion or branch switches

### State Detection from Comments

AIDP determines completion status by analyzing GitHub comments:

- **Build completed**: Looks for "✅ Implementation complete for #N" comments
- **Review completed**: Looks for "🔍 Review complete" comments  
- **CI fix completed**: Looks for "✅ CI fixes applied" comments
- **Plan exists**: Parses plan proposal comments with HTML markers

This means:

- If you re-add a trigger label (e.g., `aidp-build`), work will restart
- Completion is visible directly in the GitHub UI
- State is shared across all AIDP instances watching the repository

## Running in Background

Watch mode runs continuously in the foreground by default. For unattended operation, you can run it in the background using standard shell job control:

```bash
# Run watch mode in background using shell job control
nohup aidp watch owner/repo > watch.log 2>&1 &

# Or using screen/tmux for persistent sessions
screen -dmS aidp-watch aidp watch owner/repo

# Monitor via logs
tail -f watch.log

# Or check the process
ps aux | grep "aidp watch"
```

**Note:** Background daemon mode with `--background` flag is planned for future releases. For now, use shell job control or process managers like systemd, supervisor, or Docker for production deployments.

## Related Documentation

- [Watch Mode Safety](WATCH_MODE_SAFETY.md) - Security features and best practices for watch mode
- [Non-Interactive Mode](NON_INTERACTIVE_MODE.md) - Background daemon mode details (implementation in progress)
- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Foundational mechanics of the fix-forward execution engine used during the build trigger
- [CLI Reference](../README.md) - General AIDP CLI capabilities including other automation modes
- [Workstreams Guide](WORKSTREAMS.md) - Using git worktrees for parallel development
