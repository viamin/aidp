# Watch Mode Safety Features

## Overview

Watch mode allows AIDP to automatically process GitHub issues with specific labels (`aidp:plan` or `aidp:build`). While this is powerful for automation, it poses security risks when running on public repositories where untrusted users can create issues.

This document describes the safety features implemented to protect against malicious or unintended code execution.

## Security Risks

Running automated code execution based on public GitHub issues exposes several risks:

1. **Arbitrary Code Execution**: Malicious users could submit issues that trigger harmful code to be generated and executed
2. **Resource Abuse**: Bad actors could create many issues to consume system resources
3. **Data Exfiltration**: Generated code could attempt to steal secrets or sensitive data
4. **Supply Chain Attacks**: Automated commits could introduce vulnerable or malicious dependencies

## Safety Features

### 1. Public Repository Protection

**Default Behavior**: Watch mode is **DISABLED** for public repositories by default.

When you attempt to run watch mode on a public repository without explicit configuration, AIDP will:

- Check if the repository is public
- Raise an error preventing watch mode from starting
- Display a helpful message explaining how to enable it safely

**Enabling for Public Repositories**:

```yaml
# aidp.yml
watch:
  safety:
    allow_public_repos: true  # Explicitly opt-in to public repo automation
```

### 2. Author Allowlist

Restrict which GitHub users can trigger automated work through issues.

**Configuration**:

```yaml
# aidp.yml
watch:
  safety:
    author_allowlist:
      - trusted_maintainer
      - another_collaborator
      - verified_contributor
```

**Behavior**:

- Issues from users **not** in the allowlist are skipped
- If no allowlist is configured, all authors are allowed (backward compatible)
- Applies to both issue creators and assignees

**Benefits**:

- Only trusted users can trigger automation
- Prevents random contributors from running arbitrary code
- Can be combined with GitHub's protected branches and CODEOWNERS

### 3. Container Requirement

Optionally require watch mode to run in a containerized environment for additional isolation.

**Configuration**:

```yaml
# aidp.yml
watch:
  safety:
    require_container: true  # Only run in Docker/Podman/devcontainer
```

**Detection**:
AIDP detects containers by checking for:

- `/.dockerenv` (Docker)
- `/run/.containerenv` (Podman)
- `AIDP_ENV=development` (devcontainer)

**Benefits**:

- Limits blast radius if malicious code is executed
- Prevents access to host filesystem and credentials
- Can be combined with read-only volumes and network restrictions

### 4. Force Flag

For development or testing, you can bypass all safety checks:

```bash
aidp watch https://github.com/owner/repo --force
```

⚠️ **WARNING**: This is **DANGEROUS** and should only be used in controlled environments where you trust all potential issue authors.

## Recommended Configuration

### For Private Repositories

Private repos are safer by default since only collaborators can create issues:

```yaml
# aidp.yml (minimal configuration)
watch:
  safety:
    # No additional config needed - private repos are allowed by default
```

### For Public Repositories

Public repos require explicit safety measures:

```yaml
# aidp.yml (recommended for public repos)
watch:
  safety:
    allow_public_repos: true
    author_allowlist:
      - owner-username
      - trusted-maintainer-1
      - trusted-maintainer-2
    require_container: true
```

### High Security Setup

For maximum protection on public repositories:

```yaml
# aidp.yml (high security)
watch:
  safety:
    allow_public_repos: true
    author_allowlist:
      - single-admin-user  # Minimal list
    require_container: true

# Additional measures:
# 1. Run in isolated Docker container with:
#    - Read-only volumes for source code
#    - No network access to internal services
#    - Limited CPU/memory resources
# 2. Use GitHub's protected branches
# 3. Require manual PR review before merge
# 4. Monitor logs for suspicious activity
# 5. Set up alerts for unexpected automation triggers
```

## Error Messages

### Unsafe Repository Error

```text
🛑 Watch mode is DISABLED for public repositories by default.

Running automated code execution on untrusted public input is dangerous!

To enable watch mode for this public repository, add to your aidp.yml:

  watch:
    safety:
      allow_public_repos: true
      author_allowlist:  # Only these users can trigger automation
        - trusted_maintainer
        - another_admin
      require_container: true  # Require sandboxed environment

Alternatively, use --force to bypass this check (NOT RECOMMENDED).
```

### Unauthorized Author

```text
⏭️  Skipping issue #123 - author 'untrusted-user' not authorized
```

Or if enforcing strictly:

```text
Issue #123 author 'untrusted-user' not in allowlist.
Add to watch.safety.author_allowlist in aidp.yml to allow.
```

## Migration Guide

If you're already using watch mode without these safety features:

### Existing Private Repository Setup

No action required - private repos continue to work as before.

### Existing Public Repository Setup

**Step 1:** Add explicit configuration to `aidp.yml`:

```yaml
watch:
  safety:
    allow_public_repos: true
    # Optional: add author allowlist for extra security
    author_allowlist:
      - your-github-username
      - co-maintainer
```

**Step 2:** Consider adding container requirement:

```yaml
watch:
  safety:
    allow_public_repos: true
    require_container: true
```

**Step 3:** Review and update your deployment to use containers if needed

## Implementation Details

### Repository Visibility Detection

AIDP checks repository visibility via:

1. **GitHub CLI** (if available): `gh repo view owner/repo --json visibility`
2. **GitHub API** (fallback): `GET /repos/owner/repo` → check `private` field
3. **Error Handling**: If unable to determine, assumes public (safer default)
4. **Caching**: Visibility is cached per runner instance to avoid repeated API calls

### Author Extraction

Authors are extracted from issues in this priority order:

1. `issue[:author]` or `issue["author"]` (from issue creator)
2. `issue[:assignees][0]` or `issue["assignees"][0]` (first assignee)
3. Returns `nil` if neither is available

### Processing Flow

```text
1. Start watch mode
2. Check repository visibility
3. If public && !allow_public_repos → STOP (raise error)
4. Begin polling for issues
5. For each issue with aidp:plan or aidp:build label:
   a. Fetch issue details (including author)
   b. Check author authorization
   c. If unauthorized && allowlist exists → Skip issue
   d. If authorized → Process issue normally
```

## Testing Safety Features

### Test Author Authorization

1. Configure an allowlist with only your username
2. Create a test issue from an alternate account
3. Verify it's skipped in watch mode logs

### Test Repository Visibility

1. Try running watch mode on a public repo without config
2. Verify it fails with helpful error message
3. Add `allow_public_repos: true` and retry

### Test Container Requirement

1. Set `require_container: true`
2. Run watch mode outside a container
3. Verify warning is displayed

## Best Practices

1. **Start Restrictive**: Begin with a small author allowlist and expand as needed
2. **Monitor Logs**: Watch for unauthorized access attempts
3. **Use Containers**: Always run in isolated environments for public repos
4. **Protected Branches**: Combine with GitHub branch protection rules
5. **Manual Review**: Consider requiring manual PR approval even with automation
6. **Regular Audits**: Periodically review the author allowlist
7. **Principle of Least Privilege**: Only grant automation access to truly trusted users

## Future Enhancements

Potential additions for even stronger security:

- Rate limiting per author
- IP allowlisting
- Webhook signature verification
- Integration with GitHub Apps for fine-grained permissions
- Audit logging of all automated actions
- Dry-run mode to preview changes before execution
- Time-based restrictions (only run during business hours)
- Content filtering (reject issues with suspicious patterns)

## Related Documentation

- [Watch Mode Guide](FULLY_AUTOMATIC_MODE.md)
- [Configuration Reference](CONFIGURATION.md)
- [Container Setup](../.devcontainer/README.md)
