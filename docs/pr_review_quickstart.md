# PR Review & CI-Fix Quick Start

Get started with automated PR reviews and CI fixes in 5 minutes.

## Quick Setup

### 1. Start Watch Mode

```bash
aidp watch viamin/aidp
```

Watch mode now monitors for two new labels:

- `aidp-review` - Code review
- `aidp-fix-ci` - CI auto-fix

### 2. Trigger a Code Review

On any open pull request:

1. Add the `aidp-review` label
2. Wait ~1-2 minutes
3. Aidp posts a multi-persona review comment

### 3. Auto-Fix CI Failures

On a PR with failing CI:

1. Add the `aidp-fix-ci` label
2. Wait ~2-3 minutes
3. Aidp analyzes, fixes, commits, and pushes

## Review Example

```markdown
## 🤖 AIDP Code Review

### Summary

| Severity | Count |
|----------|-------|
| 🔴 High Priority | 1 |
| 🟠 Major | 2 |
| 🟡 Minor | 3 |
| ⚪ Nit | 5 |

### 🔴 High Priority Issues

**SQL Injection Risk** (Security Specialist)
`lib/api/users.rb:42`
User input directly interpolated into SQL query.

💡 Use parameterized queries: `User.where("name = ?", params[:name])`
```

## CI Fix Example

```markdown
## 🤖 AIDP CI Fix

✅ Successfully fixed CI failures!

**Root Causes:**
- Missing import in test file
- Linting errors (formatting)

**Applied Fixes:**
- Added require statement
- Auto-corrected style violations

Changes committed and pushed. CI will re-run.
```

## What Gets Reviewed?

**Three Expert Perspectives:**

1. **Senior Developer** - Logic, architecture, best practices
2. **Security Specialist** - Vulnerabilities, OWASP Top 10
3. **Performance Analyst** - N+1 queries, algorithm complexity

## What Gets Auto-Fixed?

**Can Fix:**

- ✅ Linting errors (formatting, style)
- ✅ Simple test failures (typos, imports)
- ✅ Missing dependencies
- ✅ Config errors (paths, env vars)

**Cannot Fix:**

- ❌ Complex logic errors
- ❌ Security vulnerabilities
- ❌ Performance regressions

## Configuration

**Custom Labels** (`.aidp/aidp.yml`):

```yaml
watch:
  labels:
    review_trigger: "please-review"
    ci_fix_trigger: "fix-ci"
```

**Provider** (`.aidp/aidp.yml`):

```yaml
harness:
  default_provider: anthropic
```

## Logs

Reviews and fixes are logged to:

```text
.aidp/logs/pr_reviews/
├── pr_123_20250112_143022.json
└── ci_fix_123_20250112_150311.json
```

## Re-triggering

To run a review again:

1. Remove the label
2. Re-add the label

Aidp processes it with fresh changes.

## Next Steps

- Read full docs: [pr_review_automation.md](pr_review_automation.md)
- Configure safety: [safety_policies.md](safety_policies.md)
- Customize labels: [configuration.md](configuration.md)

## Need Help?

- **Review not triggering?** Check watch mode is running
- **CI fix failed?** Check `.aidp/logs/pr_reviews/ci_fix_*.json`
- **Want inline comments?** Coming in future release

Happy reviewing! 🎉
