# GitHub API Signed Commits Implementation

## Overview

The `publish.yml` workflow now creates **verified commits** using GitHub's GraphQL API instead of git commands. This ensures commits are automatically signed by GitHub and will pass branch protection rules requiring signed commits.

## How It Works

### The Problem

- `git commit` commands (including via `git-auto-commit-action`) create **unsigned commits**
- Branch protection with "Require signed commits" blocks unsigned commits
- `github-actions[bot]` cannot bypass this requirement

### The Solution

- **GitHub's GraphQL API automatically signs commits** created by bot tokens
- The `createCommitOnBranch` mutation creates commits that show as "Verified" in GitHub
- No GPG key management required
- Works for multi-file commits

## Implementation in publish.yml

The workflow now uses this approach in the `update-coverage-badge` job:

```yaml
- name: Commit updated coverage badge to release PR (verified)
  uses: actions/github-script@ed597411d8f924073f98dfc5c65a23a2325f34cd
  env:
    PR_BRANCH: ${{ needs.release-please.outputs.pr-head-branch }}
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    script: |
      const fs = require('fs');

      const branch = process.env.PR_BRANCH;
      if (!branch) {
        core.setFailed('Release PR branch was not detected.');
        return;
      }

      const owner = context.repo.owner;
      const repo = context.repo.repo;

      let expectedHeadOid;
      try {
        const { data: ref } = await github.rest.git.getRef({
          owner,
          repo,
          ref: `heads/${branch}`
        });
        expectedHeadOid = ref.object.sha;
      } catch (error) {
        core.setFailed(`Unable to resolve head ref for ${branch}: ${error.message}`);
        return;
      }

      core.info(`Preparing verified commit on ${branch} at ${expectedHeadOid}`);

      const badge = fs.readFileSync('badges/coverage.svg');

      const mutation = `
        mutation($input: CreateCommitOnBranchInput!) {
          createCommitOnBranch(input: $input) {
            commit {
              oid
              url
            }
          }
        }
      `;

      const input = {
        branch: {
          repositoryNameWithOwner: `${owner}/${repo}`,
          branchName: branch
        },
        message: {
          headline: 'chore: update coverage badge'
        },
        fileChanges: {
          additions: [
            {
              path: 'badges/coverage.svg',
              contents: badge.toString('base64')
            }
          ]
        },
        expectedHeadOid
      };

      const result = await github.graphql(mutation, { input });
      const commit = result.createCommitOnBranch.commit;
      core.notice(`Created verified commit ${commit.oid} updating coverage badge (${commit.url})`);
```

## Key Features

### ✅ Automatically Signed

- Commits created via GitHub API are automatically signed by GitHub
- Shows "Verified" badge in GitHub UI
- Passes "Require signed commits" branch protection

### ✅ Multi-File Commits

- Can commit multiple files in a single commit
- Our use case: badge + baseline in one commit
- No limit on number of files (within reason)

### ✅ No Secrets Required

- Uses standard `GITHUB_TOKEN` (available in all workflows)
- No GPG keys to generate or manage
- No GitHub App setup needed

### ✅ Atomic Operations

- `expectedHeadOid` ensures commit is based on expected state
- Prevents race conditions if multiple workflows run
- Fails safely if branch has moved

## GraphQL Mutation Breakdown

### Input Structure

```graphql
mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) {
    commit {
      oid          # SHA of created commit
      committedDate
    }
  }
}
```

### Input Parameters

| Field | Type | Description |
| ------- | ------ | ------------- |
| `branch.repositoryNameWithOwner` | String | Full repo name (owner/repo) |
| `branch.branchName` | String | Branch to commit to |
| `message.headline` | String | Commit message (first line) |
| `message.body` | String | Commit message body (optional) |
| `fileChanges.additions` | Array | Files to add/update |
| `fileChanges.deletions` | Array | Files to delete (optional) |
| `expectedHeadOid` | String | Current HEAD SHA (for safety) |

### File Addition Format

```json
{
  "path": "path/to/file.txt",
  "contents": "base64-encoded-content"
}
```

**Important:** Content must be base64-encoded!

## Verification

After the workflow runs, check the commit in GitHub:

1. Go to the release PR
2. Click on the coverage update commit
3. Look for the "Verified" badge next to the commit message
4. Badge should say "Verified" with GitHub's signature

## Troubleshooting

### Error: "Resource not accessible by integration"

**Cause:** Missing `contents: write` permission

**Fix:** Ensure workflow has proper permissions:

```yaml
permissions:
  contents: write
  pull-requests: write
```

### Error: "expectedHeadOid is not the current HEAD"

**Cause:** Branch has moved since workflow started (race condition)

**Fix:** This is expected behavior - the commit will be skipped safely. The next workflow run will succeed.

### Error: "GraphQL: Invalid input"

**Cause:** Malformed GraphQL input (usually JSON escaping issue)

**Fix:** Check that all JSON strings are properly escaped in the input object.

### Commit not showing as verified

**Cause:** Using git commands instead of API, or wrong token

**Fix:**

- Ensure using `gh api graphql` (not `git commit`)
- Verify using `GITHUB_TOKEN` (not a PAT)
- Check the commit author is `github-actions[bot]`

## Comparison: git vs GitHub API

| Feature | `git commit` | GitHub GraphQL API |
| --------- | -------------- | ------------------- |
| **Signature** | ❌ Unsigned | ✅ Auto-signed by GitHub |
| **Multi-file** | ✅ Yes | ✅ Yes |
| **Setup** | Simple | Slightly more complex |
| **GPG Keys** | ❌ Required for signing | ✅ Not needed |
| **Branch Protection** | ❌ Blocked if unsigned | ✅ Passes |
| **Verified Badge** | ❌ No | ✅ Yes |

## Alternative: REST API (Single File Only)

For single-file commits, you can use the simpler REST API:

```bash
gh api --method PUT /repos/${{ github.repository }}/contents/path/to/file \
  --field message="commit message" \
  --field content="$(base64 -w 0 file)" \
  --field branch="branch-name" \
  --field sha="current-file-sha"
```

**Limitation:** Only works for one file at a time.

## When to Use This Approach

**Use GitHub API for commits when:**

- ✅ Repository requires signed commits
- ✅ Committing from GitHub Actions workflows
- ✅ No GPG key management desired
- ✅ Multiple files need to be committed together

**Use git commands when:**

- ❌ No signed commit requirement
- ❌ Very complex commit operations (merges, rebases)
- ❌ Committing many files (100+) at once

## Security Considerations

### Why This is Secure

1. **Bot Token Authentication**: `GITHUB_TOKEN` is scoped to the repository
2. **Automatic Signing**: GitHub signs commits, proving they came from GitHub Actions
3. **Audit Trail**: Commits clearly show `github-actions[bot]` as author
4. **Expected Head Check**: Prevents accidental overwrites

### What This Prevents

- ❌ Unsigned commits bypassing protection
- ❌ Commits from unauthorized actors
- ❌ Tampering with commit history
- ❌ Race conditions causing data loss

## References

- [GitHub GraphQL API: createCommitOnBranch](https://docs.github.com/en/graphql/reference/mutations#createcommitonbranch)
- [GitHub Docs: Commit Signature Verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [Automatically sign commits from GitHub Actions (Gist)](https://gist.github.com/swinton/03e84635b45c78353b1f71e41007fc7c)
- [GitHub GraphQL Explorer](https://docs.github.com/en/graphql/overview/explorer)

## Related Documentation

- [RELEASE_PLEASE_SIGNED_COMMITS.md](RELEASE_PLEASE_SIGNED_COMMITS.md) - Overview of all signing options
- [COVERAGE_BASELINE_IN_RELEASES.md](COVERAGE_BASELINE_IN_RELEASES.md) - Why coverage updates are in release PRs
