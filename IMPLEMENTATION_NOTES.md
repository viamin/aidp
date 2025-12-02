# Enhanced Worktree Handling for Change Request Processing

## Worktree Strategy Configuration

The change request processor now supports advanced worktree management strategies to handle pull request changes more robustly.

### Configuration Options

```ruby
{
  # Worktree strategy for handling git worktrees during PR change processing
  worktree_strategy: "auto", # Options:
  # - "auto": Default behavior, find or create worktree as needed
  # - "always_create": Force new worktree creation for each PR
  # - "reuse_only": Only use existing worktrees, error if not found

  # Maximum age for a worktree before cleanup (in seconds)
  worktree_max_age: 7 * 24 * 60 * 60, # 7 days

  # Automatic cleanup strategies
  worktree_cleanup_on_success: true,   # Remove worktree after successful processing
  worktree_cleanup_on_failure: false   # Keep worktree for debugging after failures
}
```

## Worktree Lookup Strategy

1. Check for existing worktree by PR number
2. Apply strategy-based decision:
   - "auto": Use existing or create new
   - "always_create": Force new worktree
   - "reuse_only": Must use existing worktree

## Error Handling

- Comprehensive logging for worktree preparation
- Detailed error tracking and recovery
- Flexible configuration for different PR processing scenarios

## Best Practices

- Use "auto" strategy for most workflows
- Configure max age and cleanup settings based on project needs
- Monitor logs for worktree management details
