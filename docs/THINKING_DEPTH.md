# Thinking Depth Configuration

Thinking Depth is a feature that allows AIDP to dynamically select AI models based on task complexity. By configuring thinking depth tiers, you can optimize for cost, speed, and quality by using simpler models for straightforward tasks and more powerful "thinking" models for complex challenges.

## Overview

AIDP supports five thinking depth tiers, each corresponding to different model capabilities:

| Tier | Description | Use Cases | Example Models |
| ------ | ------------- | ----------- | ---------------- |
| **mini** | Fastest, most cost-effective | Simple edits, formatting, documentation | claude-3-haiku, gpt-4o-mini |
| **standard** | Balanced performance | General development tasks, refactoring | claude-3-5-sonnet, gpt-4o |
| **thinking** | Advanced reasoning | Complex algorithms, architecture decisions | o1-preview, o1-mini, o3-mini |
| **pro** | Maximum capability | Critical bugs, large-scale refactoring | claude-3-opus, gemini-1.5-pro |
| **max** | Reserved for future models | N/A | Future flagship models |

## Configuration

### Basic Configuration

Add a `thinking:` section to your `.aidp/aidp.yml`:

```yaml
thinking:
  # Default tier for new work loops
  default_tier: standard

  # Maximum tier allowed (controls escalation ceiling)
  max_tier: pro

  # Allow switching providers if current provider lacks the tier
  allow_provider_switch: true

  # Escalation settings
  escalation:
    # Escalate after N consecutive failures
    on_fail_attempts: 2

    # Escalate based on complexity thresholds
    on_complexity_threshold:
      files_changed: 10
      modules_touched: 5

  # Per-tier permission modes (optional)
  permissions_by_tier:
    mini: safe
    standard: tools
    thinking: tools
    pro: dangerous

  # Override tiers for specific skills or templates (optional)
  overrides:
    skill.security_audit: pro
    template.critical_bugfix: thinking
```

### Configuration Options

#### `default_tier`

The starting tier for new work loops. Defaults to `standard`.

**Valid values**: `mini`, `standard`, `thinking`, `pro`, `max`

```yaml
thinking:
  default_tier: standard  # Start with balanced performance
```

#### `max_tier`

The maximum tier that can be used, even when escalating. Defaults to `standard`.

**Valid values**: `mini`, `standard`, `thinking`, `pro`, `max`

```yaml
thinking:
  max_tier: pro  # Allow escalation up to pro tier
```

**Note**: Setting `max_tier` below `default_tier` will cap the default tier.

#### `allow_provider_switch`

Whether to try alternate providers when the current provider doesn't support the requested tier. Defaults to `true`.

```yaml
thinking:
  allow_provider_switch: true  # Try other providers if needed
```

#### `escalation.on_fail_attempts`

Number of consecutive failures before automatically escalating to the next tier. Defaults to `2`.

```yaml
thinking:
  escalation:
    on_fail_attempts: 3  # Escalate after 3 failures
```

#### `escalation.on_complexity_threshold`

Thresholds that trigger automatic escalation based on task complexity.

```yaml
thinking:
  escalation:
    on_complexity_threshold:
      files_changed: 15      # Escalate if modifying 15+ files
      modules_touched: 8     # Escalate if touching 8+ modules
```

#### `permissions_by_tier`

Map tiers to permission modes. This allows you to restrict dangerous operations to higher tiers.

**Valid values**: `safe`, `tools`, `dangerous`

```yaml
thinking:
  permissions_by_tier:
    mini: safe         # Mini tier: read-only operations
    standard: tools    # Standard tier: can use tools
    pro: dangerous     # Pro tier: can perform destructive operations
```

#### `overrides`

Override the tier for specific skills or templates.

```yaml
thinking:
  overrides:
    skill.security_audit: pro       # Always use pro for security audits
    skill.quick_fix: mini          # Use mini for quick fixes
    template.critical_bugfix: thinking  # Use thinking tier for critical bugs
```

## REPL Commands

During interactive work loops, you can control thinking depth using `/thinking` commands:

### `/thinking show`

Display current thinking depth configuration and status.

```text
/thinking show
```

**Output**:

```text
Thinking Depth Configuration:

Current Tier: standard
Default Tier: standard
Max Tier: pro

Available Tiers:
  → standard
  ↑ pro
    mini
    thinking
    max

Legend: → current, ↑ max allowed

Current Model: anthropic/claude-3-5-sonnet-20241022
  Tier: standard
  Context Window: 200000

Provider Switching: enabled

Escalation Settings:
  Fail Attempts Threshold: 2
```

### `/thinking set <tier>`

Change the current tier for the session.

```text
/thinking set thinking
```

**Note**: The tier will be capped at your configured `max_tier`.

### `/thinking max <tier>`

Change the maximum allowed tier for the session.

```text
/thinking max pro
```

**Note**: This is a session-scoped override and doesn't persist to config.

### `/thinking reset`

Reset to the default tier and clear escalation count.

```text
/thinking reset
```

## CLI Commands

### `aidp providers info`

View the models catalog with thinking depth tiers.

```bash
aidp providers info
```

**Output**:

```text
Models Catalog - Thinking Depth Tiers
================================================================================
Provider       Model                      Tier     Context Tools Cost
anthropic      claude-3-5-sonnet-20241022 standard 200k    yes   $3.0/MTok
anthropic      claude-3-opus-20240229     pro      200k    yes   $15.0/MTok
openai         gpt-4o-mini                mini     128k    yes   $0.15/MTok
openai         o1-preview                 thinking 128k    no    $15.0/MTok
================================================================================
```

## Models Catalog

The models catalog (`.aidp/models_catalog.yml`) defines which models belong to which tiers. You can customize this to add new models or change tier assignments.

**Example catalog structure**:

```yaml
schema_version: "1.0"
providers:
  anthropic:
    display_name: "Anthropic"
    models:
      claude-3-5-sonnet-20241022:
        tier: standard
        context_window: 200000
        max_output: 8192
        supports_tools: true
        cost_per_mtok_input: 3.0
        cost_per_mtok_output: 15.0

      claude-3-opus-20240229:
        tier: pro
        context_window: 200000
        max_output: 4096
        supports_tools: true
        cost_per_mtok_input: 15.0
        cost_per_mtok_output: 75.0
```

## How Thinking Depth Works

### Automatic Escalation

AIDP can automatically escalate to higher tiers when:

1. **Consecutive Failures**: After N failures (configured via `escalation.on_fail_attempts`)
2. **Complexity Thresholds**: When task complexity exceeds thresholds (configured via `escalation.on_complexity_threshold`)

### Manual Control

You can manually control the tier at any time using `/thinking set <tier>` in the REPL.

### Provider Switching

If `allow_provider_switch: true`, AIDP will try alternate providers when the current provider doesn't have a model at the requested tier.

**Example**: If you're using `cursor` (which only has `standard` tier models) and escalate to `thinking`, AIDP will automatically switch to `openai` to use `o1-preview`.

### Model Selection

For each tier, AIDP selects the "best" model by:

1. Looking for models at the exact tier
2. Preferring the current provider
3. Switching providers if allowed and necessary
4. Selecting based on context window and features

## Use Cases

### Cost Optimization

Start with `mini` tier for routine tasks and only escalate when needed:

```yaml
thinking:
  default_tier: mini
  max_tier: standard
```

### Quality-First

Use high-quality models by default:

```yaml
thinking:
  default_tier: standard
  max_tier: pro
```

### Safety-Conscious

Restrict dangerous operations to higher tiers:

```yaml
thinking:
  permissions_by_tier:
    mini: safe
    standard: safe
    thinking: tools
    pro: dangerous
```

### Task-Specific Overrides

Ensure critical tasks always use appropriate tiers:

```yaml
thinking:
  overrides:
    skill.security_audit: pro
    skill.refactoring: thinking
    skill.documentation: mini
```

## Best Practices

1. **Start Conservative**: Begin with `default_tier: standard` and `max_tier: standard` until you understand your workload.

2. **Monitor Costs**: Higher tiers cost more. Use `/thinking show` to see current tier and model costs.

3. **Test Escalation**: Verify escalation works by triggering failures or complexity thresholds in a test environment.

4. **Provider Diversity**: Enable `allow_provider_switch: true` to ensure all tiers are available even if your primary provider doesn't support them.

5. **Document Overrides**: When adding overrides, document why specific skills need specific tiers.

6. **Session Overrides**: Use `/thinking max <tier>` for temporary overrides during a work session rather than editing config.

## Troubleshooting

### "No model found for tier"

**Cause**: No provider has a model at the requested tier.

**Solution**:

- Check `.aidp/models_catalog.yml` has models for the tier
- Enable `allow_provider_switch: true`
- Lower `max_tier` to a tier you have models for

### Escalation not working

**Cause**: Current tier is already at `max_tier`.

**Solution**:

- Increase `max_tier` in config or via `/thinking max <tier>`
- Check escalation settings are configured

### Wrong model being selected

**Cause**: Model selection logic prefers current provider.

**Solution**:

- Use `/thinking show` to see which model is selected
- Check models catalog to see available models per tier
- Switch providers manually or enable `allow_provider_switch`

## Related Documentation

- [Configuration Guide](CONFIGURATION.md) - Full configuration reference
- [Interactive REPL](INTERACTIVE_REPL.md) - REPL commands and features
- [Issue #157](https://github.com/viamin/aidp/issues/157) - Original feature proposal

## Future Enhancements

The following enhancements are planned but not yet implemented:

- **Automatic Complexity Estimation**: Analyze task context to recommend optimal tier
- **Cost Tracking**: Track spending per tier to inform budget decisions
- **Tier History**: View tier changes over time for a work loop
- **Tier Analytics**: Statistics on which tiers are most effective
