# PR Review & CI-Fix Automation

AIDP's watch mode includes automated pull request reviewing and CI failure remediation through GitHub labels.

## Quick Start

### 1. Start Watch Mode

```bash
aidp watch owner/repo
```

Watch mode monitors for two PR automation labels:

- `aidp-review` - Multi-persona code review (read-only)
- `aidp-fix-ci` - Automatic CI failure fixes (commits and pushes)

### 2. Trigger a Code Review

On any open pull request:

1. Add the `aidp-review` label
2. Wait ~1-2 minutes
3. AIDP posts a multi-persona review comment with categorized findings

### 3. Auto-Fix CI Failures

On a PR with failing CI:

1. Add the `aidp-fix-ci` label
2. Wait ~2-3 minutes
3. AIDP analyzes, fixes, commits, and pushes changes

## Multi-Persona Review Pipeline

When you add the `aidp-review` label to a PR, AIDP evaluates the code from three expert perspectives:

### 1. Senior Developer

**Focus Areas:**

- Code correctness and logic errors
- Architecture and design patterns
- API design and consistency
- Error handling and edge cases
- Code maintainability and readability
- Testing coverage and quality
- Documentation completeness

### 2. Security Specialist

**Focus Areas:**

- Injection vulnerabilities (SQL, command, XSS, etc.)
- Authentication and authorization flaws
- Sensitive data exposure
- Insecure deserialization
- Security misconfiguration
- Insufficient logging and monitoring
- Insecure dependencies
- Secrets and credentials in code
- Input validation and sanitization
- OWASP Top 10 vulnerabilities

### 3. Performance Analyst

**Focus Areas:**

- Algorithm complexity (O(n) vs O(n²), etc.)
- Database query optimization (N+1 queries, missing indexes)
- Memory allocation and garbage collection pressure
- Blocking I/O operations
- Inefficient data structures
- Unnecessary computations or redundant work
- Caching opportunities
- Resource leaks (connections, file handles, etc.)
- Concurrent access patterns
- Network round-trips and latency

## Review Output Format

Reviews are posted as PR comments with severity-categorized findings:

### Example Review

```markdown
## 🤖 AIDP Code Review

### Summary

| Severity | Count |
| ---------- | ------- |
| 🔴 High Priority | 1 |
| 🟠 Major | 2 |
| 🟡 Minor | 3 |
| ⚪ Nit | 5 |

### 🔴 High Priority Issues

**SQL Injection Risk** (Security Specialist)
`lib/api/users.rb:42`
User input directly interpolated into SQL query without sanitization.

<details>
<summary>💡 Suggested fix</summary>

```suggestion
Use parameterized queries instead:
User.where("name = ?", params[:name])
```

</details>

### 🟠 Major Issues

**N+1 Query Detected** (Performance Analyst)
`app/controllers/posts_controller.rb:15`
Loading comments in loop causes N+1 queries.

💡 Use eager loading: `Post.includes(:comments).all`

### 🟡 Minor Issues

**Missing Error Handling** (Senior Developer)
`lib/client.rb:28`
Network call has no timeout or error handling.

💡 Add timeout and rescue NetworkError

### ⚪ Nits

<!-- markdownlint-disable MD033 -->
<details>
<summary>5 stylistic suggestions (click to expand)</summary>
<!-- markdownlint-enable MD033 -->

- Inconsistent naming in method `processData` (use snake_case)
- Missing RDoc comment for public method
- ...

<!-- markdownlint-disable MD033 -->
</details>
<!-- markdownlint-enable MD033 -->
```

### Severity Levels

- **🔴 High Priority**: Critical issues that must be fixed (security vulnerabilities, data loss, crashes)
- **🟠 Major**: Significant problems that should be addressed (incorrect logic, performance issues)
- **🟡 Minor**: Improvements that would be good to have (code quality, maintainability)
- **⚪ Nit**: Stylistic or trivial suggestions (formatting, naming) - collapsed by default

## CI Failure Analysis & Auto-Fix

When you add the `aidp-fix-ci` label to a PR with failing CI checks, AIDP:

1. **Analyzes** the CI failure logs and identifies root causes
2. **Proposes** fixes if it can confidently resolve the issues
3. **Applies** the fixes to the PR branch
4. **Commits** and **pushes** the changes
5. **Posts** a summary explaining what was fixed

### What AIDP Can Fix

**Common fixable CI failures:**

- ✅ Linting errors - Formatting, style violations
- ✅ Simple test failures - Typos, missing imports, incorrect assertions
- ✅ Dependency issues - Missing packages in manifest
- ✅ Configuration errors - Incorrect paths, missing environment variables

### What AIDP Won't Fix

**Complex issues requiring domain knowledge:**

- ❌ Complex logic errors requiring business context
- ❌ Failing integration tests that may indicate real bugs
- ❌ Security scan failures
- ❌ Performance regression issues

### CI Fix Output Example

```markdown
## 🤖 AIDP CI Fix

✅ Successfully analyzed and fixed CI failures!

**Root Causes:**

- Missing import statement in test file
- Incorrect module path in spec/support/helpers.rb

**Applied Fixes:**

- spec/models/user_spec.rb: Added missing require statement
- spec/support/helpers.rb: Fixed module namespace

The fixes have been committed and pushed to this PR. CI should re-run automatically.
```

## Workflow Example

1. **Developer creates PR** with new feature
2. **Add `aidp-review` label** to trigger code review
3. **AIDP posts review** with categorized findings from all three personas
4. **Developer addresses** high priority and major issues
5. **CI fails** due to linting errors
6. **Add `aidp-fix-ci` label** to auto-fix
7. **AIDP fixes and pushes** the corrections
8. **CI passes**, PR is ready for merge

## Configuration

### Custom Label Names

Configure custom labels in `.aidp/aidp.yml`:

```yaml
watch:
  labels:
    review_trigger: "custom-review"
    ci_fix_trigger: "custom-ci-fix"
```

### Provider Selection

Specify which AI provider to use for reviews and fixes:

```yaml
harness:
  default_provider: anthropic  # or openai, google, etc.
```

## Review Logging

All review activities are logged to `.aidp/logs/pr_reviews/`:

```text
.aidp/logs/pr_reviews/
├── pr_123_20250112_143022.json  # Review results
└── ci_fix_123_20250112_150311.json  # CI fix attempts
```

### Log Format

**Review Log:**

```json
{
  "pr_number": 123,
  "timestamp": "2025-01-12T14:30:22Z",
  "reviews": [
    {
      "persona": "Senior Developer",
      "findings_count": 5,
      "findings": [...]
    },
    {
      "persona": "Security Specialist",
      "findings_count": 2,
      "findings": [...]
    },
    {
      "persona": "Performance Analyst",
      "findings_count": 3,
      "findings": [...]
    }
  ]
}
```

**CI Fix Log:**

```json
{
  "pr_number": 123,
  "timestamp": "2025-01-12T15:03:11Z",
  "success": true,
  "analysis": {
    "can_fix": true,
    "root_causes": ["Missing import", "Incorrect path"],
    "fixes": [
      {
        "file": "spec/models/user_spec.rb",
        "action": "edit",
        "description": "Added missing require statement"
      }
    ]
  }
}
```

## Safety & Best Practices

### Avoiding Infinite Loops

AIDP includes safeguards to prevent infinite feedback loops:

1. **One-time processing** - Each PR is processed once per label application
2. **Label removal** - Labels are automatically removed after processing
3. **State tracking** - StateStore prevents re-processing completed reviews
4. **Max attempts** - CI fix attempts are limited (default: 3)

### Security Considerations

**Rule-of-Two Policy** - Watch mode respects repository safety checks:

- Only processes PRs from authorized authors
- Validates repository ownership before running
- Supports `--force` flag for testing (use with caution)

**Review-Only vs Fix Mode:**

- **`aidp-review`** - Read-only analysis, no commits
- **`aidp-fix-ci`** - Commits and pushes fixes to PR branch

### Manual Re-triggering

To re-run a review or fix after making changes:

1. Remove the label from the PR
2. Re-add the label to trigger a fresh analysis

AIDP will process the PR again with the latest changes.

## Limitations

### Current Constraints

1. **No inline comments** - Reviews are posted as general PR comments, not inline code comments (coming in future release)
2. **Single commit** - CI fixes create one commit per fix attempt
3. **No rebase handling** - If PR is rebased during processing, may need manual re-trigger
4. **Rate limiting** - Subject to GitHub API rate limits (watch mode respects intervals)

### Future Enhancements

- Support for custom reviewer personas via skills system
- Inline review comments with line-specific suggestions
- Interactive review mode with approve/request changes
- Configurable severity thresholds
- Review aggregation across multiple PRs
- Support for GitLab and Bitbucket

## Troubleshooting

### Review Not Triggering

**Check:**

1. Is watch mode running? (`aidp watch owner/repo`)
2. Does the PR have the correct label? (default: `aidp-review`)
3. Is the PR author authorized? (see safety checker logs)
4. Has the PR already been reviewed? (check state store in `.aidp/watch/`)

**Solutions:**

```bash
# Verify watch mode is running
$ ps aux | grep "aidp watch"

# Check state store
$ cat .aidp/watch/<repo-name>.yml

# Clear state store entry to re-run
$ rm .aidp/watch/<repo-name>.yml
```

### CI Fix Not Working

**Check:**

1. Are CI checks actually failing? (not just pending)
2. Is the failure type auto-fixable? (see "What AIDP Can Fix" above)
3. Check CI fix logs in `.aidp/logs/pr_reviews/ci_fix_*.json`
4. Review error messages in watch mode output

**Solutions:**

```bash
# Review CI fix logs
$ cat .aidp/logs/pr_reviews/ci_fix_*.json

# Check watch mode output
$ tail -f watch.log
```

### Re-running Failed Reviews

```bash
# Clear state store entry
rm .aidp/watch/<repo-name>.yml

# Or manually edit to remove PR entry
vim .aidp/watch/<repo-name>.yml

# Re-add label to PR
```

## CI Fix Scenarios

### Scenario 1: Linting Errors

```text
CI Error: RuboCop found 5 style violations
AIDP Fix: Auto-corrected formatting and style issues
Result: CI passes ✅
```

### Scenario 2: Missing Test Fixtures

```text
CI Error: Fixture file not found: spec/fixtures/users.yml
AIDP Fix: Cannot auto-fix (requires domain knowledge)
Result: Posted explanation, manual fix needed ⚠️
```

### Scenario 3: Dependency Conflict

```text
CI Error: Gem version conflict between foo (>= 2.0) and bar (< 1.5)
AIDP Fix: Updated Gemfile to compatible versions
Result: CI passes ✅
```

## Related Documentation

- [Watch Mode Guide](FULLY_AUTOMATIC_MODE.md) - Complete guide to watch mode
- [PR Change Requests](PR_CHANGE_REQUESTS.md) - Automated PR modifications
- [Watch Mode Safety](WATCH_MODE_SAFETY.md) - Security features and best practices
- [Configuration Reference](../README.md#watch-mode-automated-github-integration) - Watch mode setup
