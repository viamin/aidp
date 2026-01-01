---
name: MCP Tool Risk Classification via AGD
about: Implement AGD-based automatic risk profiling for MCP tools
title: 'Implement MCP Tool Risk Classification via AI-Generated Determinism (AGD)'
labels: enhancement, security
assignees: ''
---

## Summary

Implement AI-Generated Determinism (AGD) for automatic risk classification of MCP tools. During configuration (post-config callback), AI analyzes available MCP tools and generates a deterministic risk profile that is stored and used at runtime without further AI calls.

## Background

This issue is part of the Rule of Two security framework (Issue #225). The current implementation tracks three flags:
- `untrusted_input`: Processing untrusted content
- `private_data`: Access to secrets/credentials
- `egress`: External communication capability

MCP tools can enable one or more of these flags depending on their capabilities (e.g., filesystem access, network requests, git operations). Currently, this classification would need to be done manually. AGD allows the AI to generate these classifications once during configuration.

## Requirements

### 1. AGD Risk Profile Generation

During `aidp init` or when MCP configuration changes, invoke AI to analyze each MCP tool and generate a risk profile:

```yaml
# .aidp/security/mcp_risk_profile.yml (auto-generated)
generated_at: "2024-01-15T10:30:00Z"
generator_model: "claude-3-5-sonnet"
version: 1

tools:
  filesystem:
    flags: ["private_data"]
    risk_level: medium
    rationale: "Can read/write files which may contain secrets"

  bash:
    flags: ["private_data", "egress"]
    risk_level: high
    rationale: "Shell access enables credential access and network operations"

  git:
    flags: ["egress"]
    risk_level: medium
    rationale: "Can push to remote repositories"

  gh:
    flags: ["private_data", "egress"]
    risk_level: high
    rationale: "GitHub CLI uses tokens and communicates externally"

  web:
    flags: ["egress"]
    risk_level: medium
    rationale: "HTTP requests to external services"
```

### 2. Post-Configuration Callback

Add a callback in the provider configuration flow:

```ruby
class McpRiskProfileGenerator
  def self.generate_after_config(project_dir:, provider_name:)
    mcp_servers = fetch_mcp_servers(provider_name)
    return if mcp_servers.empty?

    profile = analyze_tools_with_ai(mcp_servers)
    save_profile(project_dir, profile)
  end
end
```

### 3. Runtime Integration

Modify `WorkLoopSecurityAdapter` to read the risk profile and automatically enable trifecta flags when MCP tools are invoked:

```ruby
def check_mcp_tool_call!(tool_name:)
  profile = load_mcp_risk_profile
  tool_config = profile.dig(:tools, tool_name.to_sym)

  return unless tool_config

  tool_config[:flags].each do |flag|
    @current_state.enable(flag.to_sym, source: "mcp_tool:#{tool_name}")
  end
end
```

### 4. CLI Commands

```bash
# Regenerate risk profile
aidp security mcp-profile regenerate

# Show current risk profile
aidp security mcp-profile show

# Manually override a tool's classification
aidp security mcp-profile set <tool> --flags egress,private_data
```

### 5. Profile Validation

On startup, validate the profile is compatible with current MCP configuration:
- Warn if new tools are present that aren't profiled
- Warn if profiled tools are no longer available
- Offer to regenerate profile

## Implementation Notes

### AGD Pattern

Follow the AGD pattern documented in `docs/AI_GENERATED_DETERMINISM.md`:

1. **Generation Phase**: AI runs once during configuration
2. **Storage Phase**: Results stored in YAML config
3. **Runtime Phase**: Deterministic execution using stored config

### ZFC Integration

The AI analysis should use ZFC principles:
- AI determines semantic meaning (what the tool does)
- Code handles mechanical aspects (loading, caching, validation)

### Security Considerations

- The risk profile should be git-ignored (contains analysis of available tools)
- Profile regeneration should require explicit user action
- Override mechanism for users who disagree with AI classification
- Audit logging when profile is regenerated

## Acceptance Criteria

- [ ] `aidp init` generates MCP risk profile if MCP tools detected
- [ ] Risk profile is used during work loop execution
- [ ] TrifectaState automatically updated based on MCP tool usage
- [ ] CLI commands for viewing and managing risk profile
- [ ] RSpec tests for profile generation and runtime integration
- [ ] Documentation in `docs/SECURITY_FRAMEWORK.md`

## Related

- Issue #225: Rule of Two Security Framework (parent issue)
- `docs/AI_GENERATED_DETERMINISM.md`: AGD pattern documentation
- `lib/aidp/security/work_loop_adapter.rb`: Integration point
