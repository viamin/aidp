# AIDP Label Reference

This document describes all labels used by AIDP's Watch Mode for triggering automated workflows.

## Overview

AIDP uses GitHub labels to trigger different automated workflows. When a label is added to an issue or PR, Watch Mode detects it and executes the corresponding processor.

## Issue Labels

### aidp-plan

**Purpose:** Generate an implementation plan for an issue.

**Behavior:**

1. Analyzes the issue description
2. Generates a structured plan with:
   - Summary of proposed changes
   - List of implementation tasks
   - Clarifying questions (if any)
3. Posts the plan as a comment
4. If questions exist, adds `aidp-needs-input` label
5. If no questions, adds `aidp-build` label (if configured)

**Default Label:** `aidp-plan`

**Configuration:**

```yaml
watch:
  labels:
    plan_trigger: "aidp-plan"
```

---

### aidp-build

**Purpose:** Execute autonomous implementation of a planned issue.

**Prerequisites:**

- Issue should have an AIDP plan comment (from `aidp-plan`)

**Behavior:**

1. Extracts plan data from issue comments
2. Creates a workstream (git worktree)
3. Runs the AI work loop for implementation
4. Commits and pushes changes
5. Creates a draft PR (if configured)
6. Posts completion comment
7. Removes `aidp-build` label

**Default Label:** `aidp-build`

**Configuration:**

```yaml
watch:
  labels:
    build_trigger: "aidp-build"
```

---

### aidp-auto

**Purpose:** End-to-end automation from issue to PR ready for review.

**On Issues:**

1. Runs the planning phase
2. Runs the build phase
3. Creates a draft PR
4. Transfers `aidp-auto` label to the PR

**On PRs:**

1. Runs automated code review
2. Fixes CI failures
3. Iterates until:
   - Review complete AND CI passing
   - OR iteration cap (20) reached
4. When complete:
   - Converts draft to ready for review
   - Requests label-adder as reviewer
   - Posts completion comment
   - Removes `aidp-auto` label

**Default Label:** `aidp-auto`

**Configuration:**

```yaml
watch:
  labels:
    auto_trigger: "aidp-auto"
```

---

### aidp-needs-input

**Purpose:** Indicates the issue is waiting for human input.

**When Added:**

- Planning phase has clarifying questions
- Build phase needs clarification
- Implementation is incomplete with questions

**When Removed:**

- Manually by user after providing answers
- Replaced with `aidp-build` to resume

**Default Label:** `aidp-needs-input`

**Configuration:**

```yaml
watch:
  labels:
    needs_input: "aidp-needs-input"
```

---

## PR Labels

### aidp-review

**Purpose:** Perform automated code review on a PR.

**Behavior:**

1. Fetches PR diff and changed files
2. Runs multi-persona review (senior dev, security, performance)
3. Posts review findings as a comment
4. Records review completion in state

**Reviewers:**

- Senior Developer: Architecture, patterns, maintainability
- Security: Vulnerabilities, input validation, secrets
- Performance: Efficiency, resource usage

**Default Label:** `aidp-review`

**Configuration:**

```yaml
watch:
  labels:
    review_trigger: "aidp-review"
```

---

### aidp-fix-ci

**Purpose:** Automatically fix CI failures on a PR.

**Behavior:**

1. Fetches CI logs and failure details
2. Analyzes root causes
3. Applies fixes
4. Commits and pushes
5. Removes label when CI passes

**Default Label:** `aidp-fix-ci`

**Configuration:**

```yaml
watch:
  labels:
    ci_fix_trigger: "aidp-fix-ci"
```

---

### aidp-request-changes

**Purpose:** Implement change requests from PR reviews.

**Behavior:**

1. Extracts requested changes from review comments
2. Applies changes to the codebase
3. Commits and pushes
4. Posts completion comment
5. Removes label

**Default Label:** `aidp-request-changes`

**Configuration:**

```yaml
watch:
  labels:
    change_request_trigger: "aidp-request-changes"
```

---

## Configuration Example

Full label configuration in `.aidp/aidp.yml`:

```yaml
watch:
  labels:
    # Issue triggers
    plan_trigger: "aidp-plan"
    build_trigger: "aidp-build"
    auto_trigger: "aidp-auto"
    needs_input: "aidp-needs-input"

    # PR triggers
    review_trigger: "aidp-review"
    ci_fix_trigger: "aidp-fix-ci"
    change_request_trigger: "aidp-request-changes"
```

## Label Lifecycle

### Issue Flow

```text
aidp-plan → aidp-needs-input (if questions)
          → aidp-build (if no questions)

aidp-build → (removed on completion)
           → aidp-needs-input (if clarification needed)

aidp-auto → aidp-auto (transferred to created PR)
```

### PR Flow

```text
aidp-review → (removed on completion)

aidp-fix-ci → (removed when CI passes)

aidp-auto → aidp-auto (loops until ready)
          → (removed when complete)

aidp-request-changes → (removed on completion)
```

## Best Practices

1. **Start with Planning**: Use `aidp-plan` first to get a structured implementation plan
2. **Review Plans**: Check the generated plan before adding `aidp-build`
3. **Answer Questions**: Respond to clarifying questions and remove `aidp-needs-input`
4. **Use Auto for End-to-End**: Use `aidp-auto` for complete automation
5. **Monitor Progress**: Check state files and logs for processing status
6. **Manual Override**: Remove labels to stop processing if needed

## Troubleshooting

### Label not triggering processing

1. Verify exact label name matches configuration
2. Check if author is in allowlist (if configured)
3. Check Watch Mode logs for errors

### Duplicate processing

1. Ensure only one Watch Mode instance per repository
2. Check state files for stale entries
3. Review detection comments on issues/PRs

## Related Documentation

- [WATCH_MODE.md](WATCH_MODE.md) - Complete Watch Mode guide
- [WATCH_MODE_SAFETY.md](WATCH_MODE_SAFETY.md) - Safety configuration
- [CONFIGURATION.md](CONFIGURATION.md) - Full configuration reference
