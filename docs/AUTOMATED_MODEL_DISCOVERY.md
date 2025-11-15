# Automated Model Discovery - Implementation Plan

## Problem Statement

Currently, users must manually configure thinking depth tiers and map models to tiers in `aidp.yml`. This is problematic because:

1. **Poor User Experience**: Error messages tell users to run `aidp config --interactive`, but the wizard doesn't configure tiers
2. **Complex Configuration**: Users need to know which models support which tiers (mini, standard, advanced)
3. **Maintenance Burden**: New models are released frequently, requiring manual config updates
4. **Error-Prone**: Users must look up exact model names and capabilities
5. **Barriers to Entry**: New users struggle to get started with correct tier configuration

## Proposed Solution: Hybrid Model Discovery

Combine static model registry with dynamic discovery for the best of both worlds:

1. **Static Registry**: Ship with built-in model-to-tier mappings for common models
2. **Dynamic Discovery**: Query provider APIs/CLIs to discover available models
3. **Automatic Mapping**: Intelligently map discovered models to appropriate tiers
4. **User Override**: Allow users to customize/override automatic mappings
5. **Caching**: Cache discovered models with TTL to minimize API calls

## Architecture

```text
┌─────────────────────────────────────────────────┐
│           Model Discovery Service               │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐      ┌──────────────────┐   │
│  │   Static     │      │    Dynamic       │   │
│  │   Registry   │◄────►│    Discovery     │   │
│  │  (Bundled)   │      │  (Provider API)  │   │
│  └──────────────┘      └──────────────────┘   │
│         │                       │               │
│         └───────┬───────────────┘               │
│                 ▼                               │
│         ┌──────────────┐                        │
│         │   Merger     │                        │
│         │  (Priority)  │                        │
│         └──────────────┘                        │
│                 │                               │
│                 ▼                               │
│         ┌──────────────┐                        │
│         │    Cache     │                        │
│         │  (24h TTL)   │                        │
│         └──────────────┘                        │
└─────────────────────────────────────────────────┘
```

## Registry Schema Design

### Provider-Agnostic Model Registry

The registry uses **model families** (not specific versions) as the primary key for tier classification. Date-versioned models (e.g., `claude-3-5-sonnet-20241022` vs `claude-3-5-sonnet-20251111`) belong to the same family and tier.

**Example: `lib/aidp/data/model_registry.yml`**

```yaml
# Model Registry - Model family tier classifications
# Uses model families (without version dates) for tier mapping
# Providers handle version-specific naming

model_families:
  # Anthropic Claude Models
  claude-3-5-sonnet:
    name: "Claude 3.5 Sonnet"
    tier: standard
    capabilities: [chat, code, vision]
    context_window: 200000
    max_output: 8192
    speed: fast
    # Typical pricing (may vary by version/provider)
    cost_per_1m_input: 3.00
    cost_per_1m_output: 15.00
    version_pattern: 'claude-3-5-sonnet-\d{8}'  # Matches date-versioned variants

  claude-3-5-haiku:
    name: "Claude 3.5 Haiku"
    tier: mini
    capabilities: [chat, code]
    context_window: 200000
    max_output: 8192
    speed: very_fast
    cost_per_1m_input: 1.00
    cost_per_1m_output: 5.00
    version_pattern: 'claude-3-5-haiku-\d{8}'

  claude-3-opus:
    name: "Claude 3 Opus"
    tier: advanced
    capabilities: [chat, code, vision]
    context_window: 200000
    max_output: 4096
    speed: medium
    cost_per_1m_input: 15.00
    cost_per_1m_output: 75.00
    version_pattern: 'claude-3-opus-\d{8}'

  # OpenAI Models
  gpt-4-turbo:
    name: "GPT-4 Turbo"
    tier: advanced
    capabilities: [chat, code, vision]
    context_window: 128000
    max_output: 4096
    speed: fast
    cost_per_1m_input: 10.00
    cost_per_1m_output: 30.00
    version_pattern: 'gpt-4-turbo(-\d{4}-\d{2}-\d{2})?'

  gpt-4o:
    name: "GPT-4o"
    tier: advanced
    capabilities: [chat, code, vision]
    context_window: 128000
    max_output: 4096
    speed: very_fast

  gpt-4o-mini:
    name: "GPT-4o Mini"
    tier: mini
    capabilities: [chat, code]
    context_window: 128000
    max_output: 16384
    speed: very_fast

  gpt-3.5-turbo:
    name: "GPT-3.5 Turbo"
    tier: mini
    capabilities: [chat]
    context_window: 16385
    max_output: 4096
    speed: very_fast
    cost_per_1m_input: 0.50
    cost_per_1m_output: 1.50

  # Provider-specific models
  cursor-fast:
    name: "Cursor Fast"
    tier: mini
    capabilities: [chat, code]
    context_window: 32000
    speed: very_fast
```

### Provider Adapters Declare Model Support

Each provider adapter declares which models it supports and how to map names:

**Example: `lib/aidp/providers/cursor.rb`**

```ruby
module Aidp
  module Providers
    class Cursor < Adapter
      # Map provider-specific names to model families
      # Provider handles version-specific names (e.g., dates)
      SUPPORTED_MODELS = {
        # Anthropic models (Cursor uses simplified names)
        "claude-3.5-sonnet" => "claude-3-5-sonnet",
        "claude-3.5-haiku" => "claude-3-5-haiku",
        "claude-3-opus" => "claude-3-opus",

        # OpenAI models
        "gpt-4-turbo" => "gpt-4-turbo",
        "gpt-4o" => "gpt-4o",
        "gpt-4o-mini" => "gpt-4o-mini",
        "gpt-3.5-turbo" => "gpt-3.5-turbo",

        # Cursor-specific
        "cursor-fast" => "cursor-fast"
      }.freeze

      def self.model_family(provider_model_name)
        # Map provider's model name to family name
        SUPPORTED_MODELS[provider_model_name]
      end

      def self.provider_model_name(family_name)
        # Map family name back to provider's naming
        SUPPORTED_MODELS.key(family_name) || family_name
      end

      def self.supports_model_family?(family_name)
        SUPPORTED_MODELS.value?(family_name)
      end
    end
  end
end
```

**Example: `lib/aidp/providers/anthropic.rb`**

```ruby
module Aidp
  module Providers
    class Anthropic < Adapter
      # Anthropic uses dated versions, but we normalize to families
      def self.model_family(provider_model_name)
        # Strip date suffix: "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
        provider_model_name.sub(/-\d{8}$/, '')
      end

      def self.provider_model_name(family_name)
        # For Anthropic, we'd use latest version or let API handle it
        # Could maintain a mapping of family → latest version
        LATEST_VERSIONS[family_name] || family_name
      end

      def self.supports_model_family?(family_name)
        SUPPORTED_FAMILIES.include?(family_name)
      end

      SUPPORTED_FAMILIES = [
        "claude-3-5-sonnet",
        "claude-3-5-haiku",
        "claude-3-opus"
      ].freeze

      # Optional: track latest version per family
      LATEST_VERSIONS = {
        "claude-3-5-sonnet" => "claude-3-5-sonnet-20241022",
        "claude-3-5-haiku" => "claude-3-5-haiku-20241022",
        "claude-3-opus" => "claude-3-opus-20240229"
      }.freeze
    end
  end
end
```

### Benefits of This Design

1. **No Version Tracking Burden**: Registry tracks families, not every dated version
2. **Provider Autonomy**: Each provider handles version-specific naming
3. **Future-Proof**: New model versions automatically inherit family tier
4. **Simple Registry**: ~10 model families vs hundreds of versioned models
5. **Flexible Mapping**: Providers can use any naming convention
6. **Dynamic Discovery Works**: Discovered models normalize to families

### Usage Examples

```ruby
# Get model info by family
registry.get_model_info("claude-3-5-sonnet")
# => { name: "Claude 3.5 Sonnet", tier: :standard, ... }

# Get models for a tier (returns families)
registry.models_for_tier(:standard)
# => ["claude-3-5-sonnet", "gpt-4-turbo", "gpt-4o"]

# Provider normalizes versioned name to family
Providers::Anthropic.model_family("claude-3-5-sonnet-20241022")
# => "claude-3-5-sonnet"

# Provider converts family to its preferred name
Providers::Cursor.provider_model_name("claude-3-5-sonnet")
# => "claude-3.5-sonnet"  (Cursor uses dots, not hyphens)

Providers::Anthropic.provider_model_name("claude-3-5-sonnet")
# => "claude-3-5-sonnet-20241022"  (Anthropic uses latest version)

# Check if provider supports a family
Providers::Cursor.supports_model_family?("claude-3-5-sonnet")
# => true

# Pattern matching for version normalization
registry.match_to_family("claude-3-5-sonnet-20251111")  # Future version
# => "claude-3-5-sonnet"

# Find all providers supporting a model family (runtime query)
ModelDiscoveryService.providers_supporting("claude-3-5-sonnet")
# => ["anthropic", "cursor", "kilocode", "opencode", "claude-code"]
```

### How Version Normalization Works

```ruby
# When user configures with specific version:
thinking_depth:
  tiers:
    standard:
      models:
        - provider: anthropic
          model: claude-3-5-sonnet-20241022

# System resolves:
# 1. Anthropic adapter: "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet" (family)
# 2. Registry: "claude-3-5-sonnet" → { tier: :standard, ... }
# 3. Anthropic adapter: Use "claude-3-5-sonnet-20241022" for API call

# When Anthropic releases new version:
# User updates config to: claude-3-5-sonnet-20251111
# ✅ Still maps to same "claude-3-5-sonnet" family → same tier
# ✅ No registry update needed!
```

## Implementation Task List

### Phase 1: Static Model Registry

- [ ] **Create model registry data structure**
  - [ ] Create `lib/aidp/data/model_registry.yml`
  - [ ] Define schema for model metadata (tier, capabilities, context_window, cost, etc.)
  - [ ] **Use model families** (not versioned model IDs) as keys (e.g., `claude-3-5-sonnet`, not `claude-3-5-sonnet-20241022`)
  - [ ] Add version_pattern regex for each family to match versioned variants
  - [ ] Add Anthropic model families (Claude 3.5 Sonnet, Haiku, Opus)
  - [ ] Add OpenAI model families (GPT-4 Turbo, GPT-4o, GPT-4o Mini, GPT-3.5 Turbo)
  - [ ] Add Google/Gemini model families
  - [ ] Add known provider-specific models (e.g., cursor-fast)
  - [ ] Document registry format in comments

- [ ] **Create ModelRegistry class**
  - [ ] Create `lib/aidp/harness/model_registry.rb`
  - [ ] Implement `load_static_registry` to read YAML file
  - [ ] Implement `get_model_info(family_name)` method (returns tier + metadata)
  - [ ] Implement `models_for_tier(tier)` method (returns all families for tier)
  - [ ] Implement `classify_model_tier(family_name)` method (lookup tier by family)
  - [ ] Implement `match_to_family(versioned_name)` using version_pattern regex
  - [ ] Add validation for registry schema
  - [ ] Write unit tests for ModelRegistry

- [ ] **Add provider model family mapping**
  - [ ] Add `model_family(provider_model_name)` class method to Adapter base class
  - [ ] Add `provider_model_name(family_name)` class method for reverse mapping
  - [ ] Add `supports_model_family?(family_name)` class method
  - [ ] Update Anthropic provider:
    - [ ] Implement version stripping logic (remove `-\d{8}` suffix)
    - [ ] Maintain `LATEST_VERSIONS` mapping (optional)
    - [ ] Add `SUPPORTED_FAMILIES` list
  - [ ] Update Cursor provider:
    - [ ] Create `SUPPORTED_MODELS` mapping (provider name → family)
    - [ ] Implement name mapping methods
  - [ ] Update other providers (OpenAI, Gemini, etc.)
  - [ ] Write unit tests for provider model family mapping

- [ ] **Integrate static registry with ThinkingDepthManager**
  - [ ] Update ThinkingDepthManager to use ModelRegistry as fallback
  - [ ] Add fallback logic when model not in user config
  - [ ] Log when using registry defaults vs user config
  - [ ] Write integration tests

### Phase 2: Dynamic Model Discovery

- [ ] **Create provider-specific model discoverers**
  - [ ] Create `lib/aidp/harness/model_discoverers/` directory
  - [ ] Create base `ModelDiscoverer` class with common interface
  - [ ] Implement `AnthropicDiscoverer` (uses `claude models list`)
  - [ ] Implement `OpenAIDiscoverer` (uses `openai api models.list`)
  - [ ] Implement `GeminiDiscoverer` (uses `gcloud ai models list`)
  - [ ] Implement `CursorDiscoverer` (check if Cursor has model listing API)
  - [ ] Handle authentication errors gracefully (don't crash discovery)
  - [ ] Add timeout protection for slow API responses
  - [ ] Write unit tests for each discoverer

- [ ] **Create ModelDiscoveryService**
  - [ ] Create `lib/aidp/harness/model_discovery_service.rb`
  - [ ] Implement `discover_models(provider)` method
  - [ ] Implement intelligent tier classification based on:
    - [ ] Model name patterns (opus → advanced, haiku → mini, etc.)
    - [ ] Context window size (larger → higher tier)
    - [ ] Known capabilities (vision, code, etc.)
  - [ ] Handle discovery failures gracefully (return empty, log warning)
  - [ ] Implement concurrent discovery for multiple providers
  - [ ] Write unit tests with mocked CLI calls

- [ ] **Create discovery cache**
  - [ ] Create `lib/aidp/harness/model_cache.rb`
  - [ ] Implement cache storage (JSON file in `~/.aidp/cache/models.json`)
  - [ ] Add TTL support (default 24 hours)
  - [ ] Implement `get_cached_models(provider)` method
  - [ ] Implement `cache_models(provider, models, ttl)` method
  - [ ] Implement `invalidate_cache(provider)` method
  - [ ] Handle cache file corruption gracefully
  - [ ] Write unit tests for cache operations

### Phase 3: CLI Commands

- [ ] **Implement `aidp models` command group**
  - [ ] Create `lib/aidp/commands/models.rb`
  - [ ] Add command group to CLI router
  - [ ] Write help text and usage examples

- [ ] **Implement `aidp models list` command**
  - [ ] Show all available models for configured providers
  - [ ] Display: provider | model name | tier | capabilities
  - [ ] Color-code by tier (mini=green, standard=yellow, advanced=red)
  - [ ] Show source: [cache], [registry], or [config]
  - [ ] Add `--provider=<name>` filter option
  - [ ] Add `--tier=<tier>` filter option
  - [ ] Add `--refresh` flag to bypass cache
  - [ ] Write integration tests

- [ ] **Implement `aidp models discover` command**
  - [ ] Discover models from all configured providers
  - [ ] Show progress spinner during discovery
  - [ ] Display discovered models in table format
  - [ ] Prompt user: "Add these to aidp.yml? [Y/n]"
  - [ ] Generate YAML snippet for user to review
  - [ ] Add `--auto-add` flag to skip confirmation
  - [ ] Add `--provider=<name>` to discover specific provider
  - [ ] Write integration tests

- [ ] **Implement `aidp models refresh` command**
  - [ ] Clear cache for all providers
  - [ ] Re-discover models
  - [ ] Update cache
  - [ ] Show diff of what changed
  - [ ] Write integration tests

- [ ] **Implement `aidp models validate` command**
  - [ ] Check that all tiers have at least one model
  - [ ] Verify model names are valid for their providers
  - [ ] Check for tier coverage gaps
  - [ ] Suggest fixes for common issues
  - [ ] Write integration tests

### Phase 4: Integration with Config Wizard

- [ ] **Update `aidp config --interactive`**
  - [ ] After configuring provider credentials, auto-run model discovery
  - [ ] Show discovered models: "Found X models for {provider}"
  - [ ] Prompt: "Auto-configure thinking tiers? [Y/n]"
  - [ ] Generate tier configuration automatically
  - [ ] Show preview of generated config
  - [ ] Allow user to customize before saving
  - [ ] Write integration tests

- [ ] **Update setup wizard**
  - [ ] Add model discovery to initial setup flow
  - [ ] Make it part of the "quick start" path
  - [ ] Update wizard progress indicators
  - [ ] Write integration tests

### Phase 5: Auto-Discovery on Provider Configuration

- [ ] **Add discovery hooks to provider configuration**
  - [ ] After provider credentials validated, trigger discovery
  - [ ] Run discovery in background (non-blocking)
  - [ ] Cache results immediately
  - [ ] Show notification: "Discovered X models for {provider}"
  - [ ] Write integration tests

- [ ] **Implement lazy discovery**
  - [ ] On first use of unconfigured tier, check if models available
  - [ ] If discovery cache exists, use it to suggest models
  - [ ] Update error message to include discovered models
  - [ ] Write integration tests

### Phase 6: Enhanced Error Messages

- [ ] **Update "No model available for tier" error**
  - [x] Show current provider and tier
  - [x] Show YAML snippet for manual config
  - [ ] Show discovered models if available in cache
  - [ ] Suggest: "Run `aidp models discover` to find available models"
  - [ ] Write integration tests

- [ ] **Update authentication error messages**
  - [ ] When auth fails, mention that model discovery requires valid credentials
  - [ ] Suggest fixing auth before running model discovery
  - [ ] Write integration tests

### Phase 7: Documentation

- [ ] **User documentation**
  - [ ] Create user guide for model discovery
  - [ ] Add examples to CLI_USER_GUIDE.md
  - [ ] Document all `aidp models` commands
  - [ ] Add troubleshooting section for discovery failures
  - [ ] Create video/GIF walkthrough of auto-discovery

- [ ] **Developer documentation**
  - [ ] Document ModelRegistry API
  - [ ] Document how to add new provider discoverers
  - [ ] Document model classification heuristics
  - [ ] Add architecture diagrams
  - [ ] Document cache format and storage

- [ ] **Configuration examples**
  - [ ] Update aidp.yml.example with thinking_depth section
  - [ ] Add examples for all supported providers
  - [ ] Document tier selection strategy
  - [ ] Add comments explaining auto-discovery

### Phase 8: Testing & Quality

- [ ] **Unit tests**
  - [ ] ModelRegistry (100% coverage)
  - [ ] ModelDiscoveryService (100% coverage)
  - [ ] Each provider discoverer (100% coverage)
  - [ ] ModelCache (100% coverage)
  - [ ] Tier classification logic (100% coverage)

- [ ] **Integration tests**
  - [ ] End-to-end discovery flow
  - [ ] Config wizard with discovery
  - [ ] CLI commands
  - [ ] Cache invalidation scenarios
  - [ ] Multi-provider scenarios

- [ ] **Error handling tests**
  - [ ] Provider CLI not installed
  - [ ] Provider authentication failure
  - [ ] Network timeout during discovery
  - [ ] Malformed API responses
  - [ ] Cache file corruption
  - [ ] Registry file missing/corrupted

- [ ] **Performance tests**
  - [ ] Discovery time for multiple providers
  - [ ] Cache hit/miss performance
  - [ ] Concurrent discovery overhead
  - [ ] Large model list handling

### Phase 9: Optional Enhancements

- [ ] **Model comparison features**
  - [ ] `aidp models compare <model1> <model2>` command
  - [ ] Show differences in capabilities, pricing, speed
  - [ ] Recommend best model for specific use cases

- [ ] **Cost estimation**
  - [ ] Add pricing data to model registry
  - [ ] Show estimated costs per tier
  - [ ] `aidp models cost-estimate` command

- [ ] **Model benchmarking**
  - [ ] Track actual performance by tier
  - [ ] Recommend tier adjustments based on usage
  - [ ] Show which models work best for user's codebase

- [ ] **Provider health dashboard**
  - [ ] `aidp models health` command
  - [ ] Show authentication status per provider
  - [ ] Show last successful discovery time
  - [ ] Show model availability status

## Implementation Priority

### Must Have (MVP)

1. Phase 1: Static Model Registry ⭐
2. Phase 3: `aidp models list` command ⭐
3. Phase 6: Enhanced error messages ⭐

### Should Have

1. Phase 2: Dynamic Discovery
2. Phase 3: `aidp models discover` command
3. Phase 4: Config wizard integration
4. Phase 7: Documentation

### Nice to Have

1. Phase 5: Auto-discovery hooks
2. Phase 3: `aidp models refresh` and `validate` commands
3. Phase 9: Optional enhancements

## Success Metrics

- **User Experience**:
  - ✅ New users can configure tiers in < 2 minutes
  - ✅ Zero-config works for 80% of users (using static registry)
  - ✅ Error messages lead to successful resolution 90% of time

- **Technical**:
  - ✅ Model discovery completes in < 5 seconds per provider
  - ✅ Cache hit rate > 90% after initial discovery
  - ✅ Zero crashes during discovery failures
  - ✅ 100% test coverage for core components

- **Maintenance**:
  - ✅ New model support added in < 1 hour
  - ✅ Registry updates shipped weekly
  - ✅ Discovery works without code changes when providers add models

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Provider CLI not installed | High | Graceful fallback to static registry |
| API changes break discovery | Medium | Version detection + fallback to last known working |
| Slow API responses | Medium | Timeout protection + background discovery |
| Cache corruption | Low | Validation on load + automatic rebuild |
| Incorrect tier classification | Medium | User override capability + feedback mechanism |

## Timeline Estimate

- **Phase 1 (Static Registry)**: 2-3 days
- **Phase 2 (Discovery)**: 3-4 days
- **Phase 3 (CLI Commands)**: 2-3 days
- **Phase 4 (Config Wizard)**: 1-2 days
- **Phase 5 (Auto-discovery)**: 1-2 days
- **Phase 6 (Error Messages)**: 1 day
- **Phase 7 (Documentation)**: 2 days
- **Phase 8 (Testing)**: 2-3 days

**Total**: 14-20 days (2-3 weeks)

## Example Usage

### Scenario 1: New User Setup

```bash
# User runs setup wizard
$ aidp config --interactive

✓ Configured Anthropic provider (valid credentials)
🔍 Discovering available models...
✓ Found 3 models: claude-3-5-sonnet, claude-3-5-haiku, claude-3-opus

Auto-configure thinking tiers? [Y/n]: y

Preview of tier configuration:
  mini:
    - anthropic/claude-3-5-haiku-20241022
  standard:
    - anthropic/claude-3-5-sonnet-20241022
  advanced:
    - anthropic/claude-3-opus-20240229

Add to aidp.yml? [Y/n]: y
✓ Configuration saved!
```

### Scenario 2: Existing User Adds Provider

```bash
# User adds new provider
$ aidp config --interactive

Which provider would you like to configure?
> OpenAI

✓ OpenAI configured successfully
🔍 Discovering models...
✓ Found 5 models

Run 'aidp models list' to see all available models
Run 'aidp models discover' to add them to your config
```

### Scenario 3: Troubleshooting Tier Error

```bash
# User gets tier error
$ aidp execute

❌ ConfigurationError: No model configured for thinking tier 'mini'.

Current provider: anthropic
Required tier: mini

To fix this, add a model to your aidp.yml:

thinking_depth:
  tiers:
    mini:
      models:
        - provider: anthropic
          model: <model-name>

💡 Discovered models available for tier 'mini':
  - claude-3-5-haiku-20241022 (fast, cost-effective)

Run: aidp models discover --tier=mini
to see all options and auto-configure.
```

### Scenario 4: Manual Discovery

```bash
# User wants to see all available models
$ aidp models list

Provider  Model                          Tier      Capabilities       Source
────────────────────────────────────────────────────────────────────────────
anthropic claude-3-5-sonnet-20241022    standard  chat,code,vision   [cache]
anthropic claude-3-5-haiku-20241022     mini      chat,code          [cache]
anthropic claude-3-opus-20240229        advanced  chat,code,vision   [cache]
openai    gpt-4-turbo                   advanced  chat,code,vision   [registry]
openai    gpt-3.5-turbo                 mini      chat               [registry]

💡 Run 'aidp models discover' to refresh this list
💡 Run 'aidp models validate' to check your configuration

# User discovers and adds models
$ aidp models discover

🔍 Discovering models from configured providers...

Found 3 models for anthropic:
  ✓ claude-3-5-sonnet-20241022 → standard
  ✓ claude-3-5-haiku-20241022  → mini
  ✓ claude-3-opus-20240229     → advanced

Add these to aidp.yml? [Y/n]: y

Generated configuration:

thinking_depth:
  tiers:
    mini:
      models:
        - provider: anthropic
          model: claude-3-5-haiku-20241022
    standard:
      models:
        - provider: anthropic
          model: claude-3-5-sonnet-20241022
    advanced:
      models:
        - provider: anthropic
          model: claude-3-opus-20240229

✓ Configuration updated successfully!
```

## Related Issues

- Fixes the error message problem mentioned in crash-early implementation
- Addresses user onboarding difficulties
- Reduces support burden for tier configuration questions
- Enables automatic adaptation to new model releases

## Follow-up Work

After this feature is stable:

- Consider adding model performance analytics
- Track which models work best for different project types
- Implement automatic tier optimization based on usage patterns
- Add cost tracking and budgeting features
