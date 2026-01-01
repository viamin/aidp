# AIDP Security Framework

## Overview

AIDP implements a "Rule of Two" security framework based on Meta's agentic security principles to prevent prompt injection attacks. The core concept is simple: **never enable more than two of three dangerous conditions simultaneously**.

## The Lethal Trifecta

The three dangerous conditions are:

1. **Untrusted Input** (`untrusted_input`) - Processing content from untrusted sources like GitHub issues, pull requests, external URLs, or webhook payloads
2. **Private Data Access** (`private_data`) - Access to secrets, credentials, API keys, or other sensitive data
3. **Egress Capability** (`egress`) - Ability to communicate externally via git push, API calls, HTTP requests, or other network operations

When all three conditions are active simultaneously (the "lethal trifecta"), an attacker could potentially:

- Inject malicious instructions via untrusted input
- Access sensitive credentials
- Exfiltrate those credentials to an external server

By limiting operations to a maximum of two conditions, we break the attack chain.

## Architecture

### Core Components

```text
lib/aidp/security/
├── trifecta_state.rb       # State machine for tracking the three flags
├── rule_of_two_enforcer.rb # Main enforcement engine
├── policy_violation.rb     # Exception types
├── secrets_registry.rb     # User-declared secrets storage
├── secrets_proxy.rb        # Short-lived token broker
├── work_loop_adapter.rb    # WorkLoopRunner integration
└── watch_mode_handler.rb   # Watch mode fail-forward logic
```

### TrifectaState

Tracks the three security flags per work unit:

```ruby
state = Aidp::Security::TrifectaState.new(work_unit_id: "unit_123")

# Enable flags with source tracking
state.enable(:untrusted_input, source: "github_issue")
state.enable(:egress, source: "git_push")

# This would raise PolicyViolation - can't have all three
state.enable(:private_data, source: "api_key_access")
```

### RuleOfTwoEnforcer

The main enforcement engine that manages work unit lifecycle:

```ruby
enforcer = Aidp::Security.enforcer

enforcer.with_work_unit(work_unit_id: "task_1") do |state|
  state.enable(:untrusted_input, source: "issue_body")
  # ... perform work ...
end
```

### SecretsProxy

Agents never receive raw credentials. Instead, the SecretsProxy:

1. Stores registered secrets in a secure registry
2. Issues short-lived, capability-scoped tokens
3. Exchanges tokens for actual credentials at execution time
4. Strips secrets from agent environment

```ruby
# Register a secret
registry = Aidp::Security.secrets_registry
registry.register(name: "github_token", env_var: "GITHUB_TOKEN")

# Request a token (never exposes actual secret)
proxy = Aidp::Security.secrets_proxy
token = proxy.request_token(secret_name: "github_token", scope: "git_push")

# Exchange token for actual value (in isolated execution context)
value = proxy.exchange_token(token[:token])
```

## Configuration

Add to your `.aidp/aidp.yml`:

```yaml
security:
  rule_of_two:
    enabled: true
    policy: strict  # or 'relaxed'

  secrets_proxy:
    enabled: true
    token_ttl: 300  # seconds

  watch_mode:
    max_retry_attempts: 3
    fail_forward_enabled: true
    needs_input_label: aidp-needs-input
```

## CLI Commands

### Show Security Status

```bash
aidp security status
```

Shows current security posture, active work units, and proxy status.

### Register Secrets

```bash
# Register a secret (env var name matches secret name)
aidp security register GITHUB_TOKEN

# Register with custom env var
aidp security register github_token --env-var GITHUB_TOKEN
```

### List Registered Secrets

```bash
aidp security list
```

Shows all registered secrets (names only, never values).

### Proxy Status

```bash
aidp security proxy-status
```

Shows active tokens and recent usage.

### Run Security Audit

```bash
aidp security audit
```

Runs RSpec security tests including prompt injection scenarios.

## Work Loop Integration

The security framework automatically integrates with AIDP's work loops:

1. **Work Unit Tracking**: Each agentic work unit gets a unique trifecta state
2. **Input Detection**: Untrusted sources (issues, PRs) automatically enable `untrusted_input`
3. **Egress Checking**: Agent calls check if `egress` can be enabled before executing
4. **Environment Sanitization**: Registered secrets are stripped from agent process environment

### Example Flow

```text
Issue from GitHub (untrusted_input=true)
         ↓
    Work Loop starts
         ↓
    Agent needs to push (egress requested)
         ↓
    Check: would this create trifecta?
         ↓
    If not → enable egress, continue
    If yes → PolicyViolation raised
```

## Watch Mode Fail-Forward

When a security violation occurs in watch mode:

1. **Retry with alternatives** (up to `max_retry_attempts`)
   - Try using secrets proxy instead of direct credential access
   - Try sanitizing untrusted input
   - Try deferring egress operations

2. **If all retries fail**:
   - Add explanatory comment to PR/issue
   - Add `aidp-needs-input` label
   - Stop processing

## Security Patterns

### Safe: Two of Three

```ruby
# Processing untrusted input with egress (but no credentials)
state.enable(:untrusted_input, source: "github_issue")
state.enable(:egress, source: "git_push")
# ✓ Safe - no credential access

# Using credentials with egress (but trusted input)
state.enable(:private_data, source: "api_key")
state.enable(:egress, source: "api_call")
# ✓ Safe - input is trusted
```

### Blocked: All Three

```ruby
state.enable(:untrusted_input, source: "pr_body")
state.enable(:private_data, source: "github_token")
state.enable(:egress, source: "comment_post")
# ✗ PolicyViolation - lethal trifecta
```

### Resolution Strategies

When a violation is detected, consider:

1. **Use Secrets Proxy**: Route credentials through the proxy with scoped tokens
2. **Trust Validation**: Add the author to `watch.safety.author_allowlist`
3. **Deterministic Unit**: Use a non-agent operation that doesn't need all capabilities
4. **Manual Execution**: Queue the operation for human execution

## Testing Security

Run the security test suite:

```bash
bundle exec rspec spec/aidp/security/
```

### Prompt Injection Scenarios

The audit command runs scenarios that test resistance to:

- Direct prompt injection in issue bodies
- Indirect injection via referenced content
- Credential extraction attempts
- Exfiltration through comments/commits

## Environment Variables

The security framework respects these environment variables:

| Variable                 | Description                                                    |
|--------------------------|----------------------------------------------------------------|
| `AIDP_SECURITY_DISABLED` | Set to `1` to disable all security enforcement (testing only)  |
| `AIDP_PROXY_TOKEN_TTL`   | Override default token TTL in seconds                          |

## Future Work

See [Issue #XXX: MCP Tool Risk Classification via AGD](link) for planned improvements:

- Automatic risk profiling of MCP tools
- AI-generated deterministic rules for tool classification
- Integration with devcontainer security policies

## References

- [Meta's Agentic Security Principles](https://about.fb.com/news/...)
- [AIDP LLM Style Guide](./LLM_STYLE_GUIDE.md)
- [AIDP Safety Guards](./SAFETY_GUARDS.md)
