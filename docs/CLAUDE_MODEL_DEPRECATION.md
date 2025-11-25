# Claude Model Deprecation and Registry Integration

## Issue Summary

AIDP users were experiencing 404 errors when using `claude-3-5-sonnet` models in their configurations. Investigation revealed that:

1. **Anthropic deprecated Claude 3.5 models** - The current API only supports Claude 4 series models (4.0, 4.1, 4.5, 3.7)
2. **RubyLLM registry correctly reflects this** - No `claude-3-5-sonnet-*` models exist for the `anthropic` provider
3. **Default configs referenced deprecated models** - AIDP templates used `claude-3-5-sonnet-20241022`

## Current Valid Models (as of Nov 2025)

From RubyLLM registry for Anthropic provider:

### Mini Tier (Fast, Cost-Effective)

- `claude-haiku-4-5-20251001` (latest)
- `claude-3-5-haiku-20241022` (still supported)
- `claude-3-haiku-20240307`

### Standard Tier (Balanced)

- `claude-sonnet-4-5-20250929` (latest)
- `claude-3-7-sonnet-20250219`
- `claude-sonnet-4-0`

### Advanced Tier (High-Capability)

- `claude-opus-4-5-20251101` (latest)
- `claude-opus-4-1-20250805`
- `claude-3-opus-20240229` (still supported)

## Solution Implemented

### 1. Removed ModelDiscoveryService

The CLI-based `ModelDiscoveryService` class has been **completely removed** from the codebase:

- **Production code**: Deleted `lib/aidp/harness/model_discovery_service.rb` (260 lines)
- **Test code**: Deleted `spec/aidp/harness/model_discovery_service_spec.rb`
- **Background discovery**: Removed ~100 lines of background discovery infrastructure from wizard
- **Models CLI command**: Migrated to use `RubyLLMRegistry` directly

The service was replaced because:

- **Slower**: Required spawning CLI processes vs. in-memory registry lookups
- **Stale data**: Could return cached information that didn't reflect API reality
- **Complex**: Background threads, caching layer, CLI dependency management
- **Redundant**: RubyLLM gem already maintains an authoritative, validated registry

### 2. Wizard Now Uses RubyLLM Registry

The setup wizard (`lib/aidp/setup/wizard.rb`) now pulls model information directly from the RubyLLM registry instead of relying on CLI-based discovery:

```ruby
def discover_models_from_registry(provider, registry)
  model_ids = registry.models_for_provider(provider)
  
  model_ids.map do |model_id|
    info = registry.get_model_info(model_id)
    {
      name: model_id,
      tier: info[:tier],
      context_window: info[:context_window],
      capabilities: info[:capabilities]
    }
  end
end
```

**Benefits:**

- Only valid, currently-supported models appear in generated configs
- Automatic tier classification based on model characteristics
- No dependency on provider CLI availability
- Always up-to-date with ruby_llm gem updates

### 2. Tier Classification

Models are automatically classified into tiers based on:

| Tier | Criteria | Examples |
| ---- | -------- | -------- |
| mini | Name contains: haiku, mini, flash, small OR pricing < $1/million tokens | claude-haiku-4-5 |
| standard | Default (neither mini nor advanced) | claude-sonnet-4-5 |
| pro/advanced | Name contains: opus, turbo, pro, preview, o1 OR pricing > $10/million tokens | claude-opus-4-5 |

**Note:** The registry uses "advanced" internally, but CLI displays "pro" for consistency with AIDP configuration.

### 3. Models CLI Command Updated

The `aidp models` command now uses RubyLLM registry instead of CLI-based discovery:

**Commands available:**

```bash
aidp models list [--provider=<name>] [--tier=<tier>]  # List models from registry
aidp models discover --provider=<name>                 # Show models for a provider
aidp models validate                                    # Validate configuration
```

**Removed:**

- `aidp models refresh` - No longer needed (registry is always current)

## Migration Guide

### For Users with Existing Configs

If your `aidp.yml` contains deprecated model names like `claude-3-5-sonnet-20241022`:

1. **Run the setup wizard** to regenerate thinking tiers:

   ```bash
   aidp config --interactive
   ```

2. **Or manually update** your `aidp.yml`:

   ```yaml
   providers:
     anthropic:
       thinking_tiers:
         mini:
           models:
             - claude-haiku-4-5-20251001
         standard:
           models:
             - claude-sonnet-4-5-20250929
         pro:
           models:
             - claude-opus-4-5-20251101
   ```

### For New Projects

The wizard will automatically generate configurations with valid models when you run:

```bash
aidp init
# or
aidp config --interactive
```

## Technical Details

### RubyLLM Registry vs CLI Discovery

**Previous Approach (CLI Discovery):**

- Called `claude list-models` or similar CLI commands
- Required provider CLI installation
- Could return outdated or unavailable models
- Slow (network calls)

**New Approach (RubyLLM Registry):**

- Uses ruby_llm gem's curated model database (651+ models)
- No external dependencies
- Fast (in-memory lookup)
- Guaranteed valid models
- Regular updates via gem updates

### Why Claude 3.5 Sonnet is Missing

Anthropic deprecated the entire Claude 3.5 Sonnet family when they released Claude 4 series. The RubyLLM registry correctly reflects this:

- `claude-3-5-haiku-20241022` ✅ Still available (mini tier)
- `claude-3-5-sonnet-20241022` ❌ Deprecated (no replacement in 3.x)
- `claude-sonnet-4-5-20250929` ✅ Current standard tier model

The model naming changed from `claude-3-5-sonnet` to `claude-sonnet-4-5` format.

## Related Files

- `lib/aidp/setup/wizard.rb` - Updated discovery methods
- `lib/aidp/harness/ruby_llm_registry.rb` - Registry wrapper with tier classification
- `lib/aidp/harness/thinking_depth_manager.rb` - Tier selection logic
- `spec/aidp/harness/ruby_llm_registry_spec.rb` - Registry tests

## See Also

- [Anthropic Models Documentation](https://docs.claude.com/en/docs/about-claude/models)
- [RubyLLM Gem](https://github.com/patterns-ai-core/ruby-llm)
- [Thinking Depth Tiers](./THINKING_DEPTH.md)
