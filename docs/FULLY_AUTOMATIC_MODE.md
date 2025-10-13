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
|  aidp-plan label added        |        |  aidp-build label added     |
|                               |        |                             |
| 1. Fetch issue + comments     |        | 1. Verify plan exists       |
| 2. Generate Implementation    |        | 2. Create aidp/issue-*      |
|    Contract proposal          |        |    branch                   |
| 3. Post plan + questions      | -----> | 3. Run fix-forward loop     |
| 4. Await answers              |        | 4. Commit + create PR       |
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
4. Plan metadata is cached locally to avoid duplicate comments.

### Build Trigger (`aidp-build`)

1. Aidp verifies that a cached plan exists; if not it logs a warning and skips.
2. The watch workflow creates or resets an implementation branch named
   `aidp/issue-<number>-<slug>`.
3. `PROMPT.md` is seeded with the approved implementation contract and
   clarifications gathered from the issue thread.
4. The autonomous work loop executes step `16_IMPLEMENTATION`, applying patches,
   running tests/linters, and iterating until completion.
5. When successful, Aidp stages changes, commits with a descriptive message, and
   creates a pull request via `gh pr create` linking back to the issue.
6. On failures (test/lint issues, timeouts, or provider errors) Aidp posts a
   summary comment and leaves the branch intact for manual follow-up.

## Safety Considerations

- Always verify provider authentication before enabling watch mode; the agent
  must operate unattended.
- Use protected branches or required reviews to gate automatic PR merges.
- Keep `aidp-plan` and `aidp-build` labels restricted to trusted maintainers.
- Monitor the `.aidp/watch/*.yml` cache for status history and investigate
  repeated failures.
- Consider running `aidp watch --once` in CI to provide additional safeguards
  before promoting automatic PRs.

## Running in Background

Watch mode can run as a persistent background daemon for unattended operation. See [NON_INTERACTIVE_MODE.md](NON_INTERACTIVE_MODE.md) for complete details on:

- Starting watch mode in background (`aidp listen --background`)
- Detaching/attaching to running daemon
- Monitoring via structured logs
- Safe shutdown and recovery

**Quick Example:**

```bash
# Start watch mode as background daemon
$ aidp listen --background
Daemon started in watch mode (PID: 12345)

# Daemon runs 24/7, processing GitHub triggers
# Monitor via logs:
$ tail -f .aidp/logs/current.log
```

## Related Documentation

- [NON_INTERACTIVE_MODE.md](NON_INTERACTIVE_MODE.md) - Background daemon mode for unattended operation
- [Work Loops Guide](WORK_LOOPS_GUIDE.md) – foundational mechanics of the
  fix-forward execution engine used during the build trigger.
- [CLI Reference](../README.md) – general Aidp CLI capabilities including other
  automation modes.
