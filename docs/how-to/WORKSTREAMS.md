# Parallel Workstreams Guide

## Overview

AIDP supports **parallel workstreams** using git worktrees, allowing you to work on multiple tasks simultaneously in isolated environments. Each workstream has its own git branch and working directory, preventing conflicts between concurrent work.

## Quick Start

```bash
# Create a new workstream
aidp ws new issue-123

# List all workstreams
aidp ws list

# Check workstream status
aidp ws status issue-123

# Remove a workstream
aidp ws rm issue-123
```

## What is a Workstream?

A workstream is an isolated development environment that includes:

- **Git worktree**: Separate working directory with full repository files
- **Git branch**: Dedicated branch (default: `aidp/{slug}`)
- **Isolated state**: Each workstream has its own `.aidp/` directory
- **Registry tracking**: Centralized tracking in `.aidp/worktrees.json`

### Directory Structure

```text
your-project/
├── .aidp/
│   └── worktrees.json          # Registry of all workstreams
└── .worktrees/
    └── issue-123-fix-auth/     # Workstream directory
        ├── .aidp/              # Isolated AIDP state
        ├── lib/                # Full repository contents
        ├── spec/
        └── ...
```

## CLI Commands

### Create a Workstream

```bash
# Basic creation
aidp ws new my-feature

# Create from a specific branch
aidp ws new my-feature --base-branch develop

# The slug must be lowercase with hyphens
aidp ws new issue-123-fix-auth
```

**Slug Requirements:**

- Lowercase letters and numbers only
- Use hyphens (not underscores or spaces)
- Examples: `issue-123`, `feature-x`, `fix-auth-bug`

### List Workstreams

```bash
aidp ws list
```

**Output Example:**

```text
Workstreams
================================================================================
  | Slug              | Branch                  | Created          | Status
--+-------------------+-------------------------+------------------+----------
✓ | issue-123         | aidp/issue-123          | 2025-10-17 10:30 | active
✓ | feature-dashboard | aidp/feature-dashboard  | 2025-10-17 11:15 | active
```

### Check Status

```bash
# Check specific workstream
aidp ws status issue-123

# Output shows:
# - Path to workstream directory
# - Git branch name
# - Creation timestamp
# - Active/inactive status
# - Git status (modified files, etc.)
```

### Remove a Workstream

```bash
# Remove workstream (keeps git branch)
aidp ws rm issue-123

# Remove workstream and delete git branch
aidp ws rm issue-123 --delete-branch

# Skip confirmation prompt
aidp ws rm issue-123 --force
```

**Warning:** You cannot remove a workstream that's currently active in the REPL. Switch to another workstream first.

## REPL Integration

When using the AIDP REPL, you can manage workstreams with `/ws` macros:

### REPL Commands

```ruby
# List workstreams
/ws list

# Create workstream
/ws new issue-456

# Create from specific branch
/ws new feature-x --base-branch develop

# Switch to a workstream
/ws switch issue-456

# Check status (uses current if no slug given)
/ws status
/ws status issue-456

# Remove workstream
/ws rm issue-456
/ws rm issue-456 --delete-branch
```

### Context Awareness

The REPL tracks your current workstream:

```ruby
# Check REPL status (includes current workstream)
/status

# Output includes:
# Current Workstream: issue-456
#   Path: /path/to/project/.worktrees/issue-456
#   Branch: aidp/issue-456
```

**Workstream Operations:**

- All operations are scoped to the current workstream when one is active
- The REPL prevents you from removing the current workstream
- Switch to a different workstream before removing

## Use Cases

### Working on Multiple Features

```bash
# Start feature A
aidp ws new feature-a

# Switch to main directory to start feature B
cd ~/projects/my-app
aidp ws new feature-b

# Work on both in parallel
cd .worktrees/feature-a    # Work on feature A
cd ../feature-b            # Work on feature B
```

### Testing Different Approaches

```bash
# Create workstreams for different approaches
aidp ws new approach-1
aidp ws new approach-2 --base-branch approach-1

# Compare implementations side by side
diff -r .worktrees/approach-1/lib .worktrees/approach-2/lib
```

### Isolating Experimental Changes

```bash
# Create experimental workstream
aidp ws new experiment-new-arch

# Work in isolation
cd .worktrees/experiment-new-arch
# Make experimental changes...

# If experiment fails, just remove it
aidp ws rm experiment-new-arch --delete-branch --force
```

## Best Practices

### Naming Workstreams

- **Use descriptive slugs**: `fix-login-bug` not `temp1`
- **Include issue numbers**: `issue-123-auth-fix`
- **Keep it short**: Shorter slugs are easier to work with

### Managing Workstreams

- **Clean up regularly**: Remove completed workstreams to avoid clutter
- **One task per workstream**: Keep workstreams focused on single tasks
- **Merge frequently**: Don't let workstreams diverge too far from main

### Git Workflow

Each workstream creates a git branch:

```bash
# Workstream branch naming
Workstream slug: issue-123
Git branch: aidp/issue-123

# You can work with these branches normally
git checkout aidp/issue-123
git merge main
git push origin aidp/issue-123
```

## Troubleshooting

### Orphaned Workstreams

If a workstream directory is deleted manually, the registry may be out of sync:

```bash
# List shows inactive workstreams
aidp ws list

# Remove orphaned entries
aidp ws rm orphaned-slug --force
```

### Branch Conflicts

If a branch already exists when creating a workstream:

```bash
# Error: branch 'aidp/my-feature' already exists

# Options:
1. Use a different slug: aidp ws new my-feature-v2
2. Delete the old branch: git branch -d aidp/my-feature
3. Create from existing branch: git worktree add .worktrees/my-feature aidp/my-feature
```

### Git Worktree Errors

If you encounter git worktree errors:

```bash
# Check git worktree list
git worktree list

# Prune stale worktrees
git worktree prune

# Manually remove worktree
git worktree remove .worktrees/slug
```

### Cannot Remove Current Workstream

If trying to remove the active workstream in REPL:

```ruby
# Error: Cannot remove current workstream. Switch to another first.

# Solution: Switch away first
/ws switch other-workstream
# Or exit REPL and use CLI
```

## Advanced Usage

### Custom Branch Names

While the default branch pattern is `aidp/{slug}`, you can create workstreams with custom branches:

```bash
# Create workstream from existing branch
git worktree add .worktrees/custom-slug existing-branch

# Then manually register (if needed)
# Edit .aidp/worktrees.json
```

### Workstream State

Each workstream maintains isolated state in its own `.aidp/` directory:

- `.aidp/harness/` - Harness state
- `.aidp/logs/` - Log files
- `.aidp/kb/` - Knowledge base cache

This ensures complete isolation between workstreams.

### Multiple Worktrees

You can have many active workstreams:

```bash
# Create multiple workstreams
aidp ws new feature-1
aidp ws new feature-2
aidp ws new feature-3

# Each has its own directory
.worktrees/
├── feature-1/
├── feature-2/
└── feature-3/
```

## Technical Details

### Git Worktree Support

- Requires Git 2.5 or later
- Uses `git worktree add` and `git worktree remove`
- Each worktree shares the same `.git` repository
- Branches are tracked in the main repository

### Registry Format

The workstream registry (`.aidp/worktrees.json`) stores:

```json
{
  "issue-123": {
    "path": "/full/path/to/project/.worktrees/issue-123",
    "branch": "aidp/issue-123",
    "created_at": "2025-10-17T10:30:00Z"
  }
}
```

### Performance

- Worktree creation: ~100ms
- No impact on main working directory
- Supports 10+ concurrent workstreams
- State files: ~1KB per workstream

## FAQ

**Q: What's the difference between a worktree and a git branch?**

A: A git branch is just a pointer to commits. A worktree is a physical working directory with its own branch checked out. This lets you work on multiple branches simultaneously without switching.

**Q: Will workstreams affect my main working directory?**

A: No. Workstreams are completely isolated in `.worktrees/`. Your main directory is unaffected.

**Q: Can I use workstreams with my existing git workflow?**

A: Yes. Workstreams create regular git branches that you can push, merge, and manage normally.

**Q: What happens if I delete a workstream directory manually?**

A: The registry will show it as inactive. Use `aidp ws rm <slug> --force` to clean up the registry entry.

**Q: Can workstreams be nested?**

A: No. Each workstream is a direct subdirectory of `.worktrees/`.

**Q: How do I move work from a workstream to my main directory?**

A: Use git to merge the workstream's branch:

```bash
git checkout main
git merge aidp/issue-123
aidp ws rm issue-123 --delete-branch
```

## See Also

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [AIDP README](../README.md)
- [Issue #119](https://github.com/viamin/aidp/issues/119)
