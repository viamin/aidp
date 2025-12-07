# AIDP Watch Mode

Watch Mode enables AIDP to autonomously monitor GitHub repositories for issues and pull requests tagged with specific labels, then process them through automated workflows.

## Overview

Watch Mode provides a label-based autonomous workflow system that:

1. Monitors repositories for labeled issues and PRs
2. Executes appropriate processors based on labels
3. Tracks state across processing cycles
4. Provides feedback collection via reactions

## Quick Start

```bash
# Start watch mode for a repository
aidp watch viamin/aidp

# Start with verbose logging
aidp watch viamin/aidp --verbose
```

## Label-Based Workflows

### Issue Labels

| Label | Description | Processor |
|-------|-------------|-----------|
| `aidp-plan` | Generate an implementation plan | PlanProcessor |
| `aidp-build` | Execute autonomous implementation | BuildProcessor |
| `aidp-auto` | Plan + Build combined workflow | AutoProcessor |
| `aidp-needs-input` | Awaiting clarification | (blocks processing) |

### PR Labels

| Label | Description | Processor |
|-------|-------------|-----------|
| `aidp-review` | Perform automated code review | ReviewProcessor |
| `aidp-fix-ci` | Fix CI failures | CiFixProcessor |
| `aidp-auto` | Review + CI Fix loop until ready | AutoPrProcessor |
| `aidp-request-changes` | Implement change requests | ChangeRequestProcessor |

## The aidp-auto Workflow

The `aidp-auto` label provides end-to-end automation from issue to merged PR.

### On Issues (AutoProcessor)

When an issue is labeled with `aidp-auto`:

1. **Planning**: Generates an implementation plan with tasks and questions
2. **Clarification**: Posts questions and waits for answers if needed
3. **Building**: Executes the implementation plan
4. **PR Creation**: Creates a draft PR with the implementation
5. **Label Transfer**: Moves `aidp-auto` label from issue to PR

### On PRs (AutoPrProcessor)

When a PR is labeled with `aidp-auto`:

1. **Review Loop**: Runs automated code review (multi-persona)
2. **CI Fix Loop**: Fixes CI failures if any
3. **Iteration Tracking**: Counts processing iterations (cap: 20)
4. **Completion Detection**: Checks for:
   - Automated review completed
   - CI passing (success or skipped states)
5. **Ready for Review**: When complete:
   - Converts draft PR to ready for review
   - Requests the label-adder as reviewer
   - Posts completion comment
   - Removes `aidp-auto` label

### Completion Criteria

A PR is considered ready for human review when:

- Automated review has been completed
- CI status is passing (accepts `success` or `skipped` states)
- OR iteration cap (20) has been reached

### Iteration Cap

The iteration cap prevents infinite processing loops:

- Default: 20 iterations
- When reached, PR is marked ready regardless of completion state
- Completion comment indicates cap was reached
- Human reviewer notified to continue manually

## State Management

Watch Mode persists state to `.aidp/watch/{repository}.yml`:

```yaml
plans:
  123:
    summary: "Implementation summary"
    tasks: ["Task 1", "Task 2"]
    iteration: 1

builds:
  123:
    status: "completed"
    branch: "aidp/issue-123-feature"
    pr_url: "https://github.com/..."

auto_prs:
  456:
    iteration: 5
    status: "in_progress"
    last_processed_at: "2024-01-15T10:30:00Z"

reviews:
  456:
    timestamp: "2024-01-15T10:30:00Z"
    total_findings: 3
```

## Safety Features

Watch Mode includes several safety guards:

### Author Allowlist

Only process issues/PRs from authorized users:

```yaml
# .aidp/aidp.yml
watch:
  safety:
    author_allowlist:
      - "username1"
      - "username2"
```

### Public Repository Protection

Disabled by default for public repositories:

```yaml
watch:
  safety:
    allow_public_repos: true
```

### In-Progress Label

Prevents concurrent processing of the same item by multiple instances:

- Adds `aidp-in-progress` label during processing
- Removes on completion

### Detection Comments

Posts detection comments to prevent duplicate processing:

```
## 🔍 aidp: Processing Detected

AIDP has detected the `aidp-build` label on this issue...
```

## Configuration

### Label Customization

Override default labels in `.aidp/aidp.yml`:

```yaml
watch:
  labels:
    plan_trigger: "ai-plan"
    build_trigger: "ai-build"
    auto_trigger: "ai-auto"
    review_trigger: "ai-review"
    ci_fix_trigger: "ai-fix-ci"
    change_request_trigger: "ai-changes"
    needs_input: "ai-needs-input"
```

### VCS Preferences

Configure PR creation behavior:

```yaml
work_loop:
  version_control:
    auto_create_pr: true
    pr_strategy: "draft"  # draft or ready
    conventional_commits: true
    co_author_ai: true
```

## Feedback Collection

Watch Mode collects feedback via GitHub reactions:

| Reaction | Meaning |
|----------|---------|
| 👍 | Positive feedback |
| 👎 | Negative feedback |
| 🎉 | Exceptional work |
| 😕 | Confused/unclear |

Reactions are tracked in state and can be used for evaluation.

## Troubleshooting

### Common Issues

**Issue not being processed:**
1. Check if the label exactly matches configuration
2. Verify author is in allowlist (if configured)
3. Check for `aidp-in-progress` label blocking processing
4. Review `.aidp/watch/*.yml` for state conflicts

**CI status not detected:**
- AIDP checks both GitHub Check Runs and Commit Statuses
- Both `success` and `skipped` states count as passing
- Unknown CI state will not trigger completion

**PR stuck in auto loop:**
- Check iteration count in state file
- Review CI logs for persistent failures
- Consider manually removing `aidp-auto` label

### Logs

Enable verbose mode for detailed logging:

```bash
aidp watch owner/repo --verbose
```

Check `.aidp/logs/` for detailed execution logs.

## Related Documentation

- [LABELS.md](LABELS.md) - Complete label reference
- [WATCH_MODE_SAFETY.md](WATCH_MODE_SAFETY.md) - Safety configuration details
- [CLI_USER_GUIDE.md](CLI_USER_GUIDE.md) - Full CLI reference
- [WORK_LOOPS_GUIDE.md](WORK_LOOPS_GUIDE.md) - Work loop details
