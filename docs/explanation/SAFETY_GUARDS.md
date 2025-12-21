# Safety Guards

## Overview

Safety Guards provide constraints to limit what AIDP can change during work loops. This feature helps you maintain control over critical files, limit the scope of changes, and ensure that modifications stay within defined boundaries.

## Configuration

Add the `guards` section to your `aidp.yml` under `harness.work_loop`:

```yaml
harness:
  work_loop:
    enabled: true
    max_iterations: 50

    # Safety guards configuration
    guards:
      enabled: true  # Enable/disable guards

      # Include patterns: only allow changes to these files
      include_files:
        - "lib/**/*.rb"
        - "app/models/**/*.rb"

      # Exclude patterns: prevent changes to these files
      exclude_files:
        - "config/database.yml"
        - "config/secrets.yml"
        - ".env*"
        - "db/schema.rb"

      # Files requiring one-time confirmation before modification
      confirm_files:
        - "Gemfile"
        - "package.json"
        - "config/routes.rb"

      # Maximum lines changed per commit
      max_lines_per_commit: 500

      # Bypass guards (for testing)
      bypass: false
```

## Guard Types

### 1. Include Patterns

Whitelist files that AIDP is allowed to modify. If specified, only files matching at least one include pattern can be changed.

**Example:**

```yaml
guards:
  enabled: true
  include_files:
    - "lib/**/*.rb"        # Only Ruby files in lib/
    - "spec/**/*_spec.rb"  # Only spec files
```

**Behavior:**

- Empty `include_files` = allow all files (unless excluded)
- Non-empty `include_files` = only allow matching files

### 2. Exclude Patterns

Blacklist files that AIDP is not allowed to modify. These patterns override include patterns.

**Example:**

```yaml
guards:
  enabled: true
  exclude_files:
    - "config/database.yml"     # Protect database config
    - "config/secrets.yml"      # Protect secrets
    - ".env*"                   # Protect environment files
    - "db/schema.rb"            # Protect schema
    - "vendor/**/*"             # Protect vendored code
```

**Behavior:**

- Excluded files cannot be modified even if they match include patterns
- Useful for protecting critical configuration files

### 3. Confirmation Required Files

Files that require one-time confirmation before modification. AIDP will prompt for confirmation the first time it attempts to modify these files.

**Example:**

```yaml
guards:
  enabled: true
  confirm_files:
    - "Gemfile"                 # Confirm before changing dependencies
    - "package.json"            # Confirm before changing npm deps
    - "config/routes.rb"        # Confirm before changing routes
    - "*.lock"                  # Confirm before changing lock files
```

**Behavior:**

- First modification requires confirmation
- Subsequent modifications in same session don't require re-confirmation
- Useful for files that have broad impact

### 4. Max Lines Per Commit

Limit the total number of lines that can be changed in a single commit.

**Example:**

```yaml
guards:
  enabled: true
  max_lines_per_commit: 500  # Limit to 500 lines total
```

**Behavior:**

- Counts additions + deletions across all files
- Prevents overly large commits
- Encourages incremental changes

## Pattern Syntax

Guards support glob patterns for file matching:

| Pattern | Description | Example |
| --------- | ------------- | --------- |
| `*` | Match any characters except `/` | `*.rb` matches `file.rb` |
| `**` | Match any characters including `/` | `lib/**/*.rb` matches `lib/foo/bar.rb` |
| `?` | Match single character | `file?.rb` matches `file1.rb` |
| `[abc]` | Match character class | `file[123].rb` matches `file1.rb` |
| `{a,b}` | Match alternatives | `*.{rb,js}` matches `file.rb` or `file.js` |

### Pattern Examples

```yaml
# Match all Ruby files
- "**/*.rb"

# Match specific directory
- "app/models/**/*"

# Match multiple extensions
- "**/*.{rb,js,py}"

# Match environment files
- ".env*"

# Match test files
- "spec/**/*_spec.rb"
- "test/**/*_test.rb"

# Match configuration
- "config/**/*.{yml,yaml}"
```

## Guard Policy Enforcement

### During Work Loops

Guards are enforced at key points during work loop execution:

1. **Before Apply Patch**: Check if files can be modified
2. **After Changes**: Validate total lines changed
3. **Before Commit**: Final validation check

### Validation Process

```text
┌─────────────────────────────────────────────┐
│         Guard Policy Validation              │
└─────────────────────────────────────────────┘

1. Check if guards enabled
   ├─ No  → Allow all changes
   └─ Yes → Continue validation

2. For each changed file:
   ├─ Check exclude patterns
   │  └─ Match? → REJECT
   ├─ Check include patterns (if any)
   │  └─ No match? → REJECT
   └─ Check confirmation required
      └─ Not confirmed? → REQUEST CONFIRMATION

3. Check max lines per commit
   └─ Exceeded? → REJECT

4. All checks passed → ALLOW
```

### Error Handling

When a guard policy violation occurs:

1. **Display Error**: Show which constraint was violated
2. **Stop Execution**: Prevent changes from being applied
3. **Log Violation**: Record in work loop history
4. **Agent Feedback**: Add violation to PROMPT.md for agent to see

## Use Cases

### 1. Protect Critical Files

Prevent AIDP from modifying sensitive configuration:

```yaml
guards:
  enabled: true
  exclude_files:
    - "config/database.yml"
    - "config/secrets.yml"
    - ".env*"
```

### 2. Limit Scope to Feature

Restrict changes to a specific feature area:

```yaml
guards:
  enabled: true
  include_files:
    - "lib/features/authentication/**/*"
    - "spec/features/authentication/**/*"
```

### 3. Gradual Rollout

Allow changes to tests first, then implementation:

**Phase 1 - Tests only:**

```yaml
guards:
  enabled: true
  include_files:
    - "spec/**/*_spec.rb"
```

**Phase 2 - Implementation:**

```yaml
guards:
  enabled: true
  include_files:
    - "lib/**/*.rb"
    - "spec/**/*_spec.rb"
```

### 4. Safe Refactoring

Limit change size during risky refactoring:

```yaml
guards:
  enabled: true
  max_lines_per_commit: 200
  confirm_files:
    - "**/*.rb"  # Confirm each file
```

### 5. Dependency Management

Require approval for dependency changes:

```yaml
guards:
  enabled: true
  confirm_files:
    - "Gemfile"
    - "Gemfile.lock"
    - "package.json"
    - "package-lock.json"
    - "requirements.txt"
```

## Bypassing Guards

### Temporary Bypass

Set environment variable to bypass guards for a single run:

```bash
AIDP_BYPASS_GUARDS=1 aidp execute
```

### Configuration Bypass

Disable guards in configuration:

```yaml
guards:
  enabled: false
  # or
  bypass: true
```

### When to Bypass

- Testing guard configuration
- Emergency fixes
- Automated CI/CD workflows
- Trusted agent operations

**⚠️ Warning**: Bypassing guards removes safety constraints. Use with caution.

## Guard Policy Summary

At the start of each work loop, AIDP displays the active guard policy:

```text
🔄 Starting fix-forward work loop for step: implementation

🛡️  Safety Guards Enabled:
  ✓ Include patterns: lib/**/*.rb, spec/**/*_spec.rb
  ✗ Exclude patterns: config/database.yml, .env*
  ⚠️  Require confirmation: Gemfile, package.json
  📏 Max lines per commit: 500
```

## Best Practices

### 1. Start Restrictive

Begin with tight constraints and loosen as needed:

```yaml
guards:
  enabled: true
  include_files:
    - "lib/features/new_feature/**/*"  # Very specific
  max_lines_per_commit: 200            # Small changes
```

### 2. Layer Protections

Combine multiple guard types:

```yaml
guards:
  enabled: true
  include_files:
    - "lib/**/*.rb"              # Allow lib changes
  exclude_files:
    - "lib/legacy/**/*"          # Except legacy code
  confirm_files:
    - "lib/core/**/*"            # Confirm core changes
  max_lines_per_commit: 500      # Limit size
```

### 3. Match Your Risk Tolerance

Adjust guards based on:

- **High Risk**: Tight guards, many exclusions, low line limits
- **Medium Risk**: Moderate guards, key exclusions, reasonable limits
- **Low Risk**: Loose guards, few exclusions, high limits

### 4. Document Your Guards

Add comments explaining your guard choices:

```yaml
guards:
  enabled: true

  # Only allow changes to authentication feature during development
  include_files:
    - "lib/authentication/**/*"
    - "spec/authentication/**/*"

  # Protect production configuration
  exclude_files:
    - "config/database.yml"    # Contains production credentials
    - "config/secrets.yml"     # Contains API keys
```

### 5. Review Guard Violations

When guards block changes:

1. Review the violation reason
2. Decide if guard is too restrictive
3. Adjust configuration if appropriate
4. Document why you changed it

## Integration with Work Loops

Guards integrate seamlessly with the work loop fix-forward pattern:

### Normal Flow (No Guards)

```text
READY → APPLY_PATCH → TEST → PASS/FAIL
```

### Flow with Guards

```text
READY → [GUARD CHECK] → APPLY_PATCH → TEST → PASS/FAIL
          ↓
       VIOLATION?
          ↓
     REJECT + FEEDBACK TO AGENT
```

### Guard Violations in PROMPT.md

When a guard blocks changes, the violation is added to PROMPT.md:

```markdown
## Fix-Forward Iteration 5

### Guard Policy Violations
- lib/legacy/old_code.rb: File matches exclude pattern in guards configuration
- Total lines changed (650) exceeds limit (500)

**Fix-forward instructions**: Adjust your changes to comply with the guard
policy. Either reduce the scope of changes or modify different files that
are allowed by the policy.
```

## Examples

### Example 1: Feature Development

Restrict changes to a specific feature:

```yaml
guards:
  enabled: true
  include_files:
    - "lib/features/user_auth/**/*.rb"
    - "app/controllers/auth/**/*.rb"
    - "spec/**/*_spec.rb"
  exclude_files:
    - "db/schema.rb"
  max_lines_per_commit: 500
```

### Example 2: Legacy Code Protection

Protect legacy code from modification:

```yaml
guards:
  enabled: true
  exclude_files:
    - "lib/legacy/**/*"
    - "app/legacy/**/*"
    - "vendor/**/*"
  confirm_files:
    - "lib/core/**/*.rb"
```

### Example 3: Configuration Safety

Ensure configuration files require approval:

```yaml
guards:
  enabled: true
  confirm_files:
    - "config/**/*.yml"
    - "config/**/*.yaml"
    - ".env*"
    - "Gemfile"
    - "package.json"
```

### Example 4: Incremental Refactoring

Limit change size during large refactoring:

```yaml
guards:
  enabled: true
  max_lines_per_commit: 200
  include_files:
    - "lib/refactoring_target/**/*"
  exclude_files:
    - "lib/refactoring_target/legacy/**/*"
```

## Troubleshooting

### Guards Not Enforcing

**Check:**

1. Is `enabled: true` in your configuration?
2. Is `AIDP_BYPASS_GUARDS` environment variable set?
3. Is `bypass: true` in your configuration?

### Too Many Violations

**Solutions:**

1. Loosen include patterns
2. Reduce exclude patterns
3. Increase `max_lines_per_commit`
4. Break work into smaller steps

### Confirmation Not Working

**Notes:**

- Confirmation is auto-approved in automated mode
- Interactive confirmation requires REPL support (coming soon)
- Check if file is already confirmed in current session

## Roadmap

Future enhancements planned for safety guards:

- [ ] Interactive confirmation via REPL
- [ ] Per-file line change limits
- [ ] Custom validation scripts
- [ ] Guard violation analytics
- [ ] Temporary guard suspension with timeout
- [ ] Guard presets for common scenarios
- [ ] Integration with git hooks

## References

- [GitHub Issue #97](https://github.com/viamin/aidp/issues/97) - Original safety rails feature request
- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Work loop documentation
- [Configuration Guide](harness-configuration.md) - Full configuration options

## Summary

Safety Guards provide essential controls for managing what AIDP can change during work loops:

- **Include/Exclude Patterns**: Control which files can be modified
- **Confirmation Required**: Get approval for critical file changes
- **Line Limits**: Prevent overly large commits
- **Flexible Configuration**: Adjust guards to match your risk tolerance
- **Work Loop Integration**: Seamless enforcement during execution

Use guards to maintain control while leveraging AIDP's autonomous capabilities.
