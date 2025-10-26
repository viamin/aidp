# Coverage Baseline Updates in Release PRs

## Overview

Coverage baseline updates are now included in release-please PRs instead of creating separate PRs. This provides a cleaner, more atomic release process.

## How It Works

### On Release-Please PR Creation

When release-please creates a PR (triggered by pushes to `main`):

1. **Run tests with coverage** - The `update-coverage-badge` job runs full test suite
2. **Generate coverage badge** - Creates/updates `badges/coverage.svg`
3. **Update baseline if improved** - Runs `rake coverage:update_baseline_if_improved`
4. **Commit both files** - Single commit adds badge and baseline to the release PR

### Workflow Location

[.github/workflows/publish.yml](.github/workflows/publish.yml) - Job: `update-coverage-badge`

```yaml
- name: Generate coverage summary & badge
  run: bundle exec rake coverage:summary

- name: Update coverage baseline if improved
  run: bundle exec rake coverage:update_baseline_if_improved

- name: Commit updated coverage badge and baseline to release PR
  uses: stefanzweifel/git-auto-commit-action@v5
  with:
    commit_message: 'chore: update coverage badge and baseline'
    file_pattern: 'badges/coverage.svg coverage_baseline.json'
```

## Benefits

### ✅ Fewer PRs

- One release PR instead of two (release + coverage)
- Reduces notification noise
- Simpler to review

### ✅ Atomic Releases

- Coverage baseline updates with the version that improved it
- Clear relationship between code changes and coverage
- Easier to track coverage history

### ✅ Better Changelog

- Coverage improvements documented with the release
- Shows in release notes when merged
- Historical record of coverage progression

### ✅ Simpler Workflow

- No separate coverage PR automation needed
- One workflow to maintain instead of two
- Fewer potential points of failure

### ✅ Clearer History

- `git log` shows coverage improvements with releases
- Each release has its associated coverage metrics
- Easy to see which release improved coverage

## What Changed

### Before

1. Push to `main` → Tests run
2. If coverage improved → Create separate PR for baseline update
3. Review and merge coverage PR
4. Later, release-please creates release PR
5. Review and merge release PR

**Result**: 2 PRs per release if coverage improved

### After

1. Push to `main` → Tests run
2. Release-please creates release PR
3. Release PR automatically updated with coverage badge + baseline
4. Review and merge single release PR

**Result**: 1 PR per release

## Testing

### Regular Test Workflow

The standard test workflow ([.github/workflows/test.yml](.github/workflows/test.yml)) still:

- Runs on all PRs
- Generates coverage reports
- Checks coverage ratchet (prevents decreases)
- Updates badge and summary

It **does NOT**:

- Create PRs (removed)
- Update baseline on main (moved to release flow)
- Commit or push (removed)

**Security**: The test workflow now runs with minimal permissions (`contents: read` only), following the principle of least privilege.

### Coverage Ratchet

The coverage ratchet still prevents coverage from decreasing:

- Fails CI if coverage drops below baseline
- Forces maintainers to improve or justify coverage decreases
- Baseline only increases automatically (via release PR)

## Manual Baseline Updates

If you need to manually update the baseline (e.g., after justified decrease):

```bash
# Run tests with coverage
COVERAGE=1 bundle exec rspec

# Update baseline to current coverage
bundle exec rake coverage:update_baseline

# Commit the change
git add coverage_baseline.json
git commit -m "chore: update coverage baseline to X.XX%"
```

## Troubleshooting

### Coverage badge not updating

- Check that tests ran successfully in the release PR
- Verify `update-coverage-badge` job completed
- Check for errors in the workflow logs

### Baseline not improving

- Coverage may not have actually improved
- Check `coverage/coverage.json` for current coverage
- Verify baseline file is being committed

### Auto-commit not working

- Requires `pull-requests: write` permission (already configured)
- Check that `git-auto-commit-action` has correct permissions
- Verify branch protection allows commits from github-actions[bot]

## Related Files

- [.github/workflows/publish.yml](.github/workflows/publish.yml) - Release workflow
- [.github/workflows/test.yml](.github/workflows/test.yml) - Test workflow
- [lib/tasks/coverage.rake](lib/tasks/coverage.rake) - Coverage rake tasks
- [coverage_baseline.json](coverage_baseline.json) - Current baseline
- [badges/coverage.svg](badges/coverage.svg) - Coverage badge

## See Also

- [RELEASE_PLEASE_SIGNED_COMMITS.md](RELEASE_PLEASE_SIGNED_COMMITS.md) - Handling signed commits in release PRs
- [SimpleCov Configuration](spec/spec_helper.rb) - Coverage configuration
