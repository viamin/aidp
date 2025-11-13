# PR Change Requests

## Overview

The PR Change Requests feature allows AIDP to automatically implement changes on existing pull requests based on review comments. This is particularly useful when you want to request changes on your own PR (which GitHub doesn't allow through the native "Request Changes" review feature).

## How It Works

### Workflow

1. **User posts a comment** describing the desired changes on a PR
2. **User applies the `aidp-request-changes` label** (or your configured label)
3. **AIDP reads the comment** and analyzes what changes are being requested
4. **AIDP implements the changes** on the PR branch
5. **AIDP runs tests/linters** (if configured)
6. **AIDP commits and pushes** the changes
7. **AIDP posts a summary comment** and removes the label

### Clarification Flow

If AIDP cannot confidently implement the requested changes:

1. AIDP posts clarifying questions
2. AIDP replaces `aidp-request-changes` with `aidp-needs-input` label
3. User responds to the questions in a new comment
4. User re-applies the `aidp-request-changes` label
5. AIDP re-analyzes with the new context

Maximum 3 clarification rounds are allowed per change request.

## Configuration

### Basic Setup

Add to your `.aidp/aidp.yml`:

```yaml
watch:
  labels:
    change_request_trigger: "aidp-request-changes"  # Label to trigger
    needs_input: "aidp-needs-input"                 # Clarification label

  safety:
    # For public repos, specify allowed users
    author_allowlist:
      - "your-github-username"
      - "trusted-collaborator"

  pr_change_requests:
    enabled: true
    allow_multi_file_edits: true
    run_tests_before_push: true
    commit_message_prefix: "aidp: pr-change"
    require_comment_reference: true
    max_diff_size: 2000
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable the feature |
| `allow_multi_file_edits` | boolean | `true` | Allow changes across multiple files |
| `run_tests_before_push` | boolean | `true` | Run tests/linters before pushing |
| `commit_message_prefix` | string | `"aidp: pr-change"` | Prefix for commit messages |
| `require_comment_reference` | boolean | `true` | Require at least one comment |
| `max_diff_size` | integer | `2000` | Maximum PR diff size (lines) |

### Safety Configuration

#### Private Repositories

For private repositories, an empty `author_allowlist` means all authenticated repository contributors can trigger changes.

```yaml
watch:
  safety:
    author_allowlist: []  # Anyone with repo access
```

#### Public Repositories

For public repositories, you **must** specify allowed users:

```yaml
watch:
  safety:
    allow_public_repos: true
    author_allowlist:
      - "maintainer1"
      - "maintainer2"
```

## Usage Examples

### Example 1: Simple Code Fix

**Comment:**
```
Please fix the typo in the error message on line 42 of src/validator.rb.
It should say "Invalid input" instead of "Invlaid input".
```

**Action:** Apply `aidp-request-changes` label

**Result:** AIDP fixes the typo, commits, and pushes

### Example 2: Refactoring Request

**Comment:**
```
Can you extract the validation logic in the `process` method into a separate
`validate_input` private method? This would make the code more readable.
```

**Action:** Apply `aidp-request-changes` label

**Result:** AIDP refactors the code, runs tests, commits, and pushes

### Example 3: Multiple File Changes

**Comment:**
```
Please update the following:
1. Add a `timeout` parameter to the HTTP client in lib/client.rb
2. Update the corresponding test in spec/client_spec.rb
3. Document the new parameter in README.md
```

**Action:** Apply `aidp-request-changes` label

**Result:** AIDP makes all three changes across multiple files

### Example 4: Clarification Needed

**Comment:**
```
Please improve the error handling.
```

**Action:** Apply `aidp-request-changes` label

**AIDP Response:**
```
I need clarification to implement the requested changes.

Questions:
1. Which specific error conditions should be handled?
2. How should errors be reported (logged, raised, returned)?
3. Are there specific files or functions you want me to modify?

Please respond to these questions in a comment, then re-apply the label.
```

## Test Failure Handling

AIDP uses a **fix-forward strategy**:

- If tests pass: Changes are committed and pushed
- If tests fail: Changes are committed locally but NOT pushed
- AIDP posts a comment explaining the test failure
- User can fix manually or provide additional context and re-trigger

This prevents breaking the PR while still preserving the work done.

## Limitations

### Maximum Diff Size

Large PRs (> `max_diff_size` lines) are automatically skipped to prevent overwhelming the AI analysis. You can increase this limit in your configuration, but be aware of potential AI model limitations.

### Clarification Rounds

Maximum 3 clarification rounds per change request. After that, manual implementation is required.

### Comment Weighting

When multiple comments exist:
- Newer comments are weighted higher
- All approved commenter input is considered
- The most recent request takes precedence for conflicts

## Label Management

### Automatic Label Removal

AIDP automatically removes the `aidp-request-changes` label after:
- Successfully implementing changes
- Determining changes cannot be implemented
- Test/lint failures (fix-forward)
- Reaching maximum clarification rounds
- PR diff too large

### Label Replacement

When clarification is needed, AIDP:
1. Removes `aidp-request-changes`
2. Adds `aidp-needs-input`

After responding to questions, re-apply `aidp-request-changes` to continue.

## Best Practices

### Writing Effective Change Requests

**Good:**
- "Fix the typo in line 42: 'occured' → 'occurred'"
- "Extract the sorting logic into a `sort_by_priority` method"
- "Add error handling for nil values in the `process_data` method"

**Needs Improvement:**
- "Make it better" (too vague)
- "Fix the bug" (no context)
- "Refactor everything" (too broad)

### Incremental Changes

For large refactorings, break into multiple change requests:

**Instead of:**
```
Completely refactor the authentication system
```

**Do:**
```
Step 1: Extract validation logic to AuthValidator
Step 2: Move password hashing to PasswordHasher
Step 3: Add unit tests for new classes
```

### Combining with Other Labels

You can use multiple AIDP labels together:

```
1. Apply aidp-request-changes for code changes
2. After changes are pushed, apply aidp-review for review
3. Apply aidp-fix-ci if tests fail
```

## Troubleshooting

### Changes Not Applied

**Check:**
1. Is watch mode running? (`aidp watch <repo-url>`)
2. Is the label correctly applied?
3. Are you on the author allowlist (public repos)?
4. Is the PR diff within size limits?
5. Check logs for error messages

### Clarification Loop

If stuck in clarification rounds:
1. Provide very specific instructions in your next comment
2. Include file paths, line numbers, and exact changes
3. Consider implementing manually if too complex

### Test Failures

If tests consistently fail:
1. Review the test output in AIDP's comment
2. Verify your request is technically correct
3. Check if tests need updating separately
4. Consider manual implementation

## Advanced Configuration

### Custom Label Names

```yaml
watch:
  labels:
    change_request_trigger: "custom-change-label"
    needs_input: "custom-input-label"
```

### Disable Testing

```yaml
watch:
  pr_change_requests:
    run_tests_before_push: false
```

**Warning:** Disabling tests may result in broken code being pushed.

### Adjust Diff Size Limit

```yaml
watch:
  pr_change_requests:
    max_diff_size: 5000  # For larger PRs
```

## Integration with CI/CD

PR change requests work seamlessly with CI:

1. AIDP commits changes to PR branch
2. CI automatically runs on new commit
3. If CI fails, use `aidp-fix-ci` to auto-fix
4. If CI passes, PR is ready for merge

## Security Considerations

### Author Allowlist

Always use an allowlist for public repositories to prevent unauthorized users from triggering automated code changes.

### Code Review

AIDP-implemented changes should still be reviewed:
- AIDP posts a summary of all changes
- Review the diff before merging
- Use `aidp-review` label for automated code review

### Sensitive Changes

Avoid using PR change requests for:
- Security-critical code
- Authentication/authorization logic
- Database migrations
- Infrastructure changes

These should always be implemented and reviewed manually.

## FAQ

**Q: Can I use this on my own PRs?**
A: Yes! That's the primary use case. GitHub doesn't allow requesting changes on your own PRs, so this fills that gap.

**Q: What happens if multiple people comment with different requests?**
A: AIDP weighs newer comments higher. The most recent approved commenter's request takes precedence.

**Q: Can AIDP handle complex refactorings?**
A: AIDP works best with specific, focused changes. For large refactorings, break into multiple smaller requests.

**Q: Do I need to have tests?**
A: No, but it's recommended. Set `run_tests_before_push: false` if you don't have tests.

**Q: Can I retry if it fails?**
A: Yes! Just re-apply the `aidp-request-changes` label. Provide more context in a new comment if needed.

**Q: Does this work with draft PRs?**
A: Yes, PR change requests work on both draft and regular PRs.

## Related Features

- **aidp-review**: Automated code review with multiple personas
- **aidp-fix-ci**: Automatically fix CI failures
- **aidp-build**: Implement entire features from issue descriptions

## See Also

- [Watch Mode Safety Guide](WATCH_MODE_SAFETY.md)
- [Configuration Reference](aidp.yml.example)
