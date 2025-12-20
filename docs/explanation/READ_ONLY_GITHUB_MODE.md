# Read-Only GitHub Mode

## Overview

AIDP's Read-Only GitHub Mode enables secure analysis and interaction with GitHub repositories without requiring write access or authentication. This mode is designed for situations where you want to analyze external codebases, contribute to open source projects, or work with repositories where you have limited access.

## Access Model

### Read-Only Operations

In Read-Only GitHub Mode, AIDP can:

- **Clone public repositories** using HTTPS (no authentication required)
- **Analyze repository structure** and codebase patterns
- **Run analysis workflows** on the local clone
- **Generate recommendations** and documentation
- **Create local branches** for experimentation
- **Generate patches/diffs** for proposed changes

### What's NOT Allowed

Read-Only GitHub Mode explicitly prevents:

- **Direct pushes** to the original repository
- **Pull request creation** via API (requires authentication)
- **Issue creation** or modification
- **Repository settings** changes
- **Branch protection** modifications
- **GitHub Actions** triggering

## Privacy Rules

### Data Handling

AIDP follows strict privacy principles in Read-Only mode:

1. **Local Processing Only**
   - All analysis happens on your local machine
   - No repository data is sent to external services (except your configured AI provider for analysis)
   - Cloned repositories remain in your local filesystem

2. **Credential Isolation**
   - No GitHub authentication tokens required
   - No access to private repositories
   - No ability to perform authenticated operations

3. **Output Control**
   - Generated artifacts (PRDs, analysis reports) stay local
   - You control what (if anything) gets shared
   - No automatic reporting back to repository owners

4. **Provider Transparency**
   - Your configured AI provider (Claude, GPT, etc.) may receive code snippets for analysis
   - This is the same as using any AI assistant with code
   - No additional privacy exposure beyond your normal AI usage

### Consent Model

When working with external repositories:

- **Public repositories**: Publicly available, analysis is permissible
- **Forked repositories**: Follow the original repository's license terms
- **Licensed code**: Respect license terms (MIT, GPL, etc.)
- **Proprietary code**: Only analyze if you have explicit permission

## GitHub Usage Patterns

### Repository Analysis

```bash
# Clone and analyze a public repository
git clone https://github.com/user/repo.git
cd repo
aidp analyze

# Or use AIDP's built-in cloning
aidp analyze --repo https://github.com/user/repo.git
```

### Contribution Workflow

1. **Fork the repository** on GitHub (manual step)
2. **Clone your fork** locally
3. **Run AIDP analysis** to understand the codebase
4. **Use AIDP execute** to implement features/fixes
5. **Test locally** using AIDP's work loops
6. **Create pull request** manually via GitHub UI

### Research and Learning

```bash
# Analyze architecture patterns
aidp analyze 02_ARCHITECTURE_ANALYSIS

# Study testing approaches  
aidp analyze 03_TEST_ANALYSIS

# Generate documentation
aidp analyze 05_DOCUMENTATION_ANALYSIS
```

## Configuration

### Enabling Read-Only Mode

Add to your `aidp.yml`:

```yaml
github:
  read_only_mode: true
  clone_depth: 1  # Shallow clone for faster analysis
  preserve_history: false  # Skip git history analysis
```

### Repository Settings

```yaml
github:
  read_only_mode: true
  allowed_operations:
    - clone
    - analyze
    - local_branch
    - diff_generation
  blocked_operations:
    - push
    - pull_request_api
    - issue_creation
```

### Privacy Controls

```yaml
privacy:
  external_data_sharing: false  # Never send data outside local analysis
  credential_isolation: true    # Ensure no auth tokens are used
  local_only_artifacts: true    # Keep all outputs local
```

## Use Cases

### Open Source Contribution

**Scenario**: You want to contribute to a popular open source project

1. **Discovery**: Use AIDP to analyze the codebase structure
2. **Understanding**: Generate architecture documentation
3. **Feature Planning**: Create PRDs for your proposed contribution
4. **Implementation**: Use work loops to develop and test locally
5. **Submission**: Create PR manually with AIDP-generated artifacts

### Competitive Analysis

**Scenario**: You want to understand how competitors structure their code

1. **Analysis**: Run AIDP analyze workflows on public repositories
2. **Pattern Recognition**: Identify architectural patterns and best practices
3. **Documentation**: Generate comparison reports
4. **Learning**: Apply insights to your own projects

**Note**: Only analyze public repositories and respect licensing terms.

### Learning and Research

**Scenario**: You're studying how large projects implement specific features

1. **Code Study**: Analyze how authentication, testing, or deployment is handled
2. **Pattern Extraction**: Generate documentation of patterns you find
3. **Best Practices**: Create guides based on real-world implementations
4. **Educational Content**: Generate tutorials or blog posts (respecting licenses)

### Security Auditing

**Scenario**: You want to analyze public repositories for security patterns

1. **Static Analysis**: Run AIDP's security-focused analysis workflows
2. **Pattern Detection**: Identify common security patterns or anti-patterns
3. **Report Generation**: Create security assessment reports
4. **Recommendation**: Generate improvement suggestions

**Note**: Only for educational/research purposes on public code.

## Implementation Details

### Technical Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Read-Only GitHub Mode                     │
└─────────────────────────────────────────────────────────────┘

    GitHub Public Repo
           │
           │ (HTTPS clone - no auth)
           ↓
      Local Clone
           │
           │ (All analysis local)
           ↓
    AIDP Analysis Engine
           │
           │ (Code snippets only)
           ↓
     AI Provider (Claude/GPT/etc.)
           │
           │ (Analysis results)
           ↓
    Local Artifacts
    (PRDs, docs, patches)
```

### Safety Mechanisms

1. **Authentication Check**: Verify no GitHub tokens are present
2. **Operation Filtering**: Block any write operations at the API level
3. **Network Monitoring**: Log all external requests (should only be AI provider)
4. **Artifact Isolation**: Ensure all outputs remain local

### Error Handling

```ruby
# Example error cases
if github_operation_requires_auth?
  raise SecurityError, "Read-only mode cannot perform authenticated operations"
end

if attempting_push?
  raise SecurityError, "Read-only mode cannot push to repositories"
end
```

## Command Reference

### Analysis Commands

```bash
# Analyze repository structure
aidp analyze 01_REPOSITORY_ANALYSIS --read-only

# Generate architecture documentation
aidp analyze 02_ARCHITECTURE_ANALYSIS --read-only

# Security pattern analysis
aidp analyze 06_STATIC_ANALYSIS --read-only --security-focus
```

### Repository Commands

```bash
# Clone and analyze in one step
aidp clone-analyze https://github.com/user/repo.git

# Analyze existing clone
aidp analyze --local-only

# Generate contribution guide
aidp generate-contribution-guide
```

### Safety Commands

```bash
# Verify read-only status
aidp status --security-check

# List allowed operations
aidp capabilities --read-only-mode

# Check for auth leakage
aidp audit --privacy-check
```

## Best Practices

### Repository Selection

✅ **Appropriate for Read-Only Analysis:**

- Open source projects with permissive licenses
- Public repositories you want to contribute to
- Educational repositories and examples
- Your own public repositories

❌ **Avoid Analyzing:**

- Private repositories (you can't access them anyway)
- Proprietary code without permission
- Repositories with restrictive licenses for analysis
- Archived or deprecated projects (limited value)

### Privacy Best Practices

1. **Review AI Provider Terms**: Understand what code snippets your AI provider sees
2. **Minimize Context**: Only send relevant code snippets to AI for analysis
3. **Local Storage**: Keep all analysis artifacts on your machine
4. **License Compliance**: Respect repository licenses in your analysis and outputs

### Effective Contribution Process

1. **Start with Issues**: Look for "good first issue" labels
2. **Understand First**: Run full analysis before implementing
3. **Follow Patterns**: Use AIDP to understand existing code patterns
4. **Test Thoroughly**: Use work loops to ensure quality before PR
5. **Document Changes**: Use AIDP to generate clear PR descriptions

### Security Considerations

1. **No Sensitive Data**: Never analyze repositories with sensitive information
2. **License Compliance**: Respect copyrights and licenses
3. **Attribution**: Give credit when using patterns or inspiration from analyzed code
4. **Responsible Disclosure**: If you find security issues, follow responsible disclosure

## Troubleshooting

### Common Issues

**Problem**: Cannot clone repository

```text
Error: Repository not found or access denied
```

**Solution**: Ensure the repository is public and the URL is correct

**Problem**: Analysis fails with auth errors

```text
Error: GitHub API requires authentication
```

**Solution**: Verify read-only mode is enabled and no auth tokens are configured

**Problem**: AI provider rejects code analysis

```text
Error: Content policy violation
```

**Solution**: Ensure you're only analyzing appropriate, legal code

### Limitations

1. **No Real-Time Data**: Analysis is based on snapshot at clone time
2. **No Private Dependencies**: Can't resolve private package dependencies
3. **Limited Context**: May miss external services or integrations
4. **Static Analysis Only**: Can't run the application or tests that require secrets

## Legal and Ethical Guidelines

### Copyright Respect

- **Attribution**: Always credit original authors and projects
- **License Compliance**: Follow the terms of the repository's license
- **Fair Use**: Analysis for learning/research is generally acceptable
- **Commercial Use**: Be extra careful with commercial applications

### Ethical Analysis

- **Purpose Matters**: Analyze for learning, contribution, or legitimate research
- **No Harm Intent**: Don't analyze to copy, steal, or create competing clones
- **Community Benefit**: Consider how your analysis might benefit the broader community
- **Transparency**: Be open about your analysis if asked by project maintainers

### Responsible Disclosure

If you discover security issues during analysis:

1. **Don't Publish**: Don't make vulnerabilities public immediately
2. **Contact Maintainers**: Reach out privately to repository maintainers
3. **Follow Process**: Respect the project's security reporting process
4. **Give Time**: Allow reasonable time for fixes before any disclosure

## Summary

Read-Only GitHub Mode enables secure, privacy-conscious analysis of public repositories while maintaining strict boundaries around data access and usage. By combining local analysis with AI-powered insights, you can:

- **Learn** from high-quality open source projects
- **Contribute** more effectively to projects you care about
- **Research** architectural patterns and best practices
- **Analyze** code security and quality patterns

All while respecting privacy, licenses, and community norms.

Remember: Read-Only mode is about **analysis and learning**, not about bypassing proper contribution processes. Always follow project guidelines and respect maintainer preferences when contributing to open source projects.
