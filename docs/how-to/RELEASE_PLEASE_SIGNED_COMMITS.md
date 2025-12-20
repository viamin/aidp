# Release Please & Signed Commits

## Problem

Release-please PRs (like #168) cannot be merged because branch protections require signed commits, but GitHub Actions commits are not GPG-signed by default.

## Important: GitHub Actions Bot Cannot Bypass Protection

**You cannot exempt `github-actions[bot]` from the "Require signed commits" rule.** This is by design for security - it prevents workflows from bypassing all protections, which would allow anyone with write access to create workflows that push to protected branches.

## Solution Options

### Option 1: Use GitHub's REST API for Signed Commits (RECOMMENDED FOR SIMPLE CASES)

GitHub automatically signs commits created via the REST API using bot tokens. This works for **single-file commits**.

**How it works:**

- Commits made via GitHub's REST API with `GITHUB_TOKEN` are automatically signed by GitHub
- Shows as "Verified" in GitHub UI
- No GPG key management needed

**Implementation:**

```yaml
- name: Update coverage badge via API
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    # Encode file content
    CONTENT=$(base64 -w 0 badges/coverage.svg)

    # Get current file SHA
    CURRENT_SHA=$(gh api /repos/${{ github.repository }}/contents/badges/coverage.svg \
      --jq '.sha' || echo "")

    # Update file via API (automatically signed)
    gh api --method PUT /repos/${{ github.repository }}/contents/badges/coverage.svg \
      --field message="chore: update coverage badge" \
      --field content="$CONTENT" \
      --field encoding="base64" \
      --field branch="${{ github.ref_name }}" \
      --field sha="$CURRENT_SHA"
```

**Pros:**

- Simple, no secrets needed
- Commits automatically signed by GitHub
- No GPG key management

**Cons:**

- **Only works for single-file commits**
- Cannot commit multiple files in one commit
- More complex for multi-file updates

**Good for:** Single file updates like badges

### Option 2: Set Up GPG Signing with GitHub App (RECOMMENDED FOR MULTI-FILE)

Create a GitHub App with GPG signing for automated commits. This is the proper solution for workflows like release-please that need to commit multiple files.

**Steps:**

1. **Create a GitHub App:**
   - Go to Settings → Developer settings → GitHub Apps → New GitHub App
   - Grant permissions: Contents (Read & Write), Metadata (Read)
   - Generate a private key, download it
   - Install the app to your repository

2. **Generate GPG Key for the Bot:**

   ```bash
   # Generate GPG key (use bot email)
   gpg --full-generate-key

   # Export private key (base64 encoded)
   gpg --export-secret-keys --armor YOUR_KEY_ID | base64 -w 0

   # Get key ID
   gpg --list-secret-keys --keyid-format=long
   ```

3. **Add Secrets to GitHub:**
   - `APP_ID`: Your GitHub App ID
   - `APP_PRIVATE_KEY`: App's private key (from step 1)
   - `GPG_PRIVATE_KEY`: Base64-encoded GPG private key
   - `GPG_KEY_ID`: GPG key ID
   - `GPG_PASSPHRASE`: GPG key passphrase (if set)

4. **Update Workflow:**

```yaml
- name: Generate GitHub App token
  id: generate-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ vars.APP_ID }}
    private-key: ${{ secrets.APP_PRIVATE_KEY }}

- name: Checkout with App token
  uses: actions/checkout@v4
  with:
    ref: ${{ needs.release-please.outputs.pr-head-branch }}
    token: ${{ steps.generate-token.outputs.token }}

- name: Import GPG key
  run: |
    echo "${{ secrets.GPG_PRIVATE_KEY }}" | base64 --decode | gpg --batch --import

- name: Configure Git with GPG signing
  run: |
    git config user.name "your-bot-name[bot]"
    git config user.email "bot@users.noreply.github.com"
    git config commit.gpgsign true
    git config user.signingkey ${{ secrets.GPG_KEY_ID }}

    # If passphrase protected
    echo "allow-preset-passphrase" >> ~/.gnupg/gpg-agent.conf
    gpg-connect-agent reloadagent /bye
    echo "${{ secrets.GPG_PASSPHRASE }}" | \
      /usr/lib/gnupg/gpg-preset-passphrase --preset ${{ secrets.GPG_KEY_ID }}

- name: Commit changes (will be signed)
  run: |
    git add .
    git commit -m "chore: automated update"
    git push
```

**Pros:**

- Can commit multiple files
- Full GPG signatures
- Works with all git operations
- Bot can bypass branch protection (if configured)

**Cons:**

- Complex setup
- Must manage GPG keys and secrets
- Requires GitHub App creation

**Good for:** Complex workflows like release-please

### Option 3: Disable "Require Signed Commits" (SIMPLEST)

Turn off the signed commits requirement for the `main` branch.

**Steps:**

1. Go to Settings → Branches → Edit `main` protection rule
2. Uncheck "Require signed commits"
3. Save changes

**Pros:**

- Immediate, no code changes
- Works with existing workflows
- Simple maintenance

**Cons:**

- Removes protection against unsigned commits
- May not meet security policies
- Anyone can push unsigned commits

**Good for:** Projects where signed commits aren't a security requirement

## Current Status: publish.yml Workflow ✅ FIXED

The workflow now uses **GitHub's GraphQL API** to create signed commits. Commits are automatically signed by GitHub and show as "Verified".

```yaml
# Current approach - SIGNED ✅
- name: Commit updated coverage badge and baseline to release PR (signed)
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    # Create signed commit via GraphQL API
    gh api graphql -f query='...' -f input="{...}"
```

See [GITHUB_API_SIGNED_COMMITS.md](GITHUB_API_SIGNED_COMMITS.md) for implementation details.

## ✅ Fixed for AIDP

The workflow now uses **GitHub's GraphQL API** (Option 1 approach, extended for multi-file commits). This provides:

- ✅ Automatic signing by GitHub
- ✅ Multi-file commits (badge + baseline)
- ✅ No secrets or GPG keys needed
- ✅ Passes branch protection

**No additional configuration needed** - commits will now be verified automatically.

### Alternative: Disable Signed Commits Requirement

If you prefer to disable the requirement instead:

1. Settings → Branches → Edit `main` rule
2. Uncheck "Require signed commits"
3. Save

## Why This is Complicated

GitHub's security model prevents `github-actions[bot]` from bypassing protections because:

1. Anyone with write access can create workflows
2. Allowing workflows to bypass protections would be a security hole
3. Signed commits verify the author's identity, which workflows don't have

The proper solution requires creating a separate identity (GitHub App) with its own GPG key.

## References

- [Automatically sign commits from GitHub Actions](https://gist.github.com/swinton/03e84635b45c78353b1f71e41007fc7c)
- [Semantic Release with Signed Commits](https://gist.github.com/0xernesto/fda89508b5f73463787d102e1739dc0b)
- [GitHub Docs: Protected Branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub Docs: Commit Signature Verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [Actions Runner Issue #667](https://github.com/actions/runner/issues/667) - Request for built-in signing support
