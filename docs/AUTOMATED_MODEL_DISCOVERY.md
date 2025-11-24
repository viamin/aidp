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
┌─────────────────────────────────────────────────────────┐
│           Model Discovery Service                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐                                      │
│  │   Static     │                                      │
│  │   Registry   │──────┐                               │
│  │  (Bundled)   │      │                               │
│  └──────────────┘      │                               │
│                        ▼                                │
│           ┌─────────────────────────┐                  │
│           │   Provider Classes      │                  │
│           │  (lib/aidp/providers/)  │                  │
│           ├─────────────────────────┤                  │
│           │ • discover_models()     │◄── CLI/API       │
│           │ • model_family()        │    Queries       │
│           │ • supports_model_*?()   │                  │
│           │ • MODEL_PATTERN regex   │                  │
│           └─────────────────────────┘                  │
│                        │                                │
│                        ▼                                │
│                ┌──────────────┐                         │
│                │    Cache     │                         │
│                │  (24h TTL)   │                         │
│                └──────────────┘                         │
└─────────────────────────────────────────────────────────┘
```

**Key Architectural Principles:**

1. **Provider-Centric**: All provider-specific code lives in `lib/aidp/providers/`
2. **Pattern-Based**: Models are matched using regex patterns, not hardcoded lists
3. **Dynamic Support**: New models automatically supported if they match patterns
4. **No PR Required**: Adding a new model version requires zero code changes

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
      # Normalize a provider-specific model name to its model family
      # Cursor uses dots instead of hyphens for version numbers
      def self.model_family(provider_model_name)
        # Convert dots to hyphens: "claude-3.5-sonnet" → "claude-3-5-sonnet"
        provider_model_name.gsub(/(\d)\.(\d)/, '\1-\2')
      end

      # Convert a model family name to the provider's preferred model name
      # Returns family name as-is (Cursor accepts standard names)
      def self.provider_model_name(family_name)
        family_name
      end

      # Check if this provider supports a given model family
      # Pattern-based matching for claude, gpt, and cursor models
      def self.supports_model_family?(family_name)
        family_name.match?(/^(claude|gpt|cursor)-/)
      end

      # Discover available models from the model registry
      # Cursor doesn't have a dedicated model listing API,
      # so we rely on the static registry
      def self.discover_models
        registry = Aidp::Harness::ModelRegistry.new
        all_models = registry.all_models

        # Filter to models this provider supports
        all_models.select { |model| supports_model_family?(model[:family]) }
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
      # Model name pattern for Anthropic Claude models
      # Matches both versioned and unversioned Claude models
      MODEL_PATTERN = /^claude-[\d\.-]+-(?:opus|sonnet|haiku)(?:-\d{8})?$/i

      # Normalize a provider-specific model name to its model family
      # Anthropic uses date-versioned models
      def self.model_family(provider_model_name)
        # Strip date suffix: "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
        provider_model_name.sub(/-\d{8}$/, '')
      end

      # Convert a model family name to the provider's preferred model name
      # Returns family name as-is for configuration flexibility
      # Users can specify exact versions in their aidp.yml if needed
      def self.provider_model_name(family_name)
        family_name
      end

      # Check if this provider supports a given model family
      # Pattern-based matching automatically supports new Claude models
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from Claude CLI
      # Queries 'claude models list' and parses the output
      def self.discover_models
        return [] unless available?

        output = `claude models list 2>&1`
        return [] unless $?.success?

        # Parse CLI output and extract model names
        models = parse_models_output(output)

        # Map to model family structure
        models.map do |model_name|
          {
            provider: "anthropic",
            model: model_name,
            family: model_family(model_name)
          }
        end
      rescue => e
        Aidp.log_error("anthropic_discovery", "Failed to discover models", error: e.message)
        []
      end
    end
  end
end
```

### Benefits of This Design

1. **No Version Tracking Burden**: Registry tracks families, not every dated version
2. **Provider Autonomy**: Each provider handles version-specific naming via class methods
3. **Future-Proof**: New model versions automatically inherit family tier
4. **Simple Registry**: ~10 model families vs hundreds of versioned models
5. **Flexible Mapping**: Providers can use any naming convention
6. **Dynamic Discovery Works**: Discovered models normalize to families
7. **Pattern-Based Support**: Regex patterns automatically support new models without code changes
8. **No Hardcoded Lists**: MODEL_PATTERN replaces SUPPORTED_FAMILIES/SUPPORTED_MODELS/LATEST_VERSIONS
9. **Provider-Centric**: All provider-specific code lives in lib/aidp/providers/, not scattered
10. **Zero PRs for New Models**: New Claude/GPT versions work immediately if they match the pattern

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
providers:
  anthropic:
    thinking_tiers:
      standard:
        models:
          - claude-3-5-sonnet-20241022

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

> **⚡ ARCHITECTURAL REFACTORING COMPLETED (2025-11-15)**
>
> After initial implementation, a major architectural refactoring was completed to address key design principles:
>
> - **Provider-Centric Design**: Moved all discovery logic from `lib/aidp/harness/model_discoverers/` into `lib/aidp/providers/`
> - **Pattern-Based Support**: Replaced hardcoded `SUPPORTED_FAMILIES`, `SUPPORTED_MODELS`, and `LATEST_VERSIONS` with regex `MODEL_PATTERN` matching
> - **Zero-PR Model Support**: New model versions automatically work if they match the pattern
> - **Simplified Architecture**: Providers implement `discover_models()` directly; ModelDiscoveryService calls them via constantize
>
> See commit `b175db0` for full implementation details.

### Phase 1: Static Model Registry ✅ COMPLETED

- [x] **Create model registry data structure**
  - [x] Create `lib/aidp/data/model_registry.yml`
  - [x] Define schema for model metadata (tier, capabilities, context_window, cost, etc.)
  - [x] **Use model families** (not versioned model IDs) as keys (e.g., `claude-3-5-sonnet`, not `claude-3-5-sonnet-20241022`)
  - [x] Add version_pattern regex for each family to match versioned variants
  - [x] Add Anthropic model families (Claude 3.5 Sonnet, Haiku, Opus)
  - [x] Add OpenAI model families (GPT-4 Turbo, GPT-4o, GPT-4o Mini, GPT-3.5 Turbo)
  - [x] Add Google/Gemini model families
  - [x] Add known provider-specific models (e.g., cursor-fast)
  - [x] Document registry format in comments

- [x] **Create ModelRegistry class**
  - [x] Create `lib/aidp/harness/model_registry.rb`
  - [x] Implement `load_static_registry` to read YAML file
  - [x] Implement `get_model_info(family_name)` method (returns tier + metadata)
  - [x] Implement `models_for_tier(tier)` method (returns all families for tier)
  - [x] Implement `classify_model_tier(family_name)` method (lookup tier by family)
  - [x] Implement `match_to_family(versioned_name)` using version_pattern regex
  - [x] Add validation for registry schema
  - [x] Write unit tests for ModelRegistry

- [x] **Add provider model family mapping** ⚡ REFACTORED (Pattern-Based)
  - [x] Add `model_family(provider_model_name)` class method to providers
  - [x] Add `provider_model_name(family_name)` class method for reverse mapping
  - [x] Add `supports_model_family?(family_name)` class method
  - [x] Update Anthropic provider:
    - [x] Implement version stripping logic (remove `-\d{8}` suffix)
    - [x] ~~Maintain `LATEST_VERSIONS` mapping~~ **REMOVED** (returns family as-is)
    - [x] ~~Add `SUPPORTED_FAMILIES` list~~ **REPLACED** with MODEL_PATTERN regex
  - [x] Update Cursor provider:
    - [x] ~~Create `SUPPORTED_MODELS` mapping~~ **REPLACED** with pattern-based matching
    - [x] Implement name mapping methods using regex patterns
  - [x] Update Gemini provider with MODEL_PATTERN regex
  - [x] Write unit tests for provider model family mapping

- [x] **Integrate static registry with CLI**
  - [x] Create `aidp models list` command using ModelRegistry
  - [x] Display models with tier classifications
  - [x] Add filtering by provider and tier

### Phase 2: Dynamic Model Discovery ✅ COMPLETED

- [x] **Create provider-specific model discoverers** ⚡ REFACTORED (Provider-Centric)
  - [x] ~~Create `lib/aidp/harness/model_discoverers/` directory~~ **REMOVED** (provider-centric design)
  - [x] ~~Create base `ModelDiscoverer` class~~ **NOT NEEDED** (providers implement directly)
  - [x] Implement `AnthropicDiscoverer` **→ Anthropic.discover_models()** (uses `claude models list`)
  - [x] Implement `CursorDiscoverer` **→ Cursor.discover_models()** (uses registry)
  - [x] Implement `GeminiDiscoverer` **→ Gemini.discover_models()** (uses registry)
  - [x] Handle authentication errors gracefully (don't crash discovery)
  - [x] Add timeout protection for slow API responses
  - [x] Write unit tests for each discoverer

- [x] **Create ModelDiscoveryService**
  - [x] Create `lib/aidp/harness/model_discovery_service.rb`
  - [x] Implement `discover_models(provider)` method
  - [x] Calls provider class methods directly via constantize
  - [x] Implement intelligent tier classification using ModelRegistry
  - [x] Handle discovery failures gracefully (return empty, log warning)
  - [x] Implement discovery for multiple providers
  - [x] Write unit tests with mocked provider calls

- [x] **Create discovery cache**
  - [x] Create `lib/aidp/harness/model_cache.rb`
  - [x] Implement cache storage (JSON file in `~/.aidp/cache/models.json`)
  - [x] Add TTL support (default 24 hours)
  - [x] Implement `get_cached_models(provider)` method
  - [x] Implement `cache_models(provider, models, ttl)` method
  - [x] Implement `invalidate_cache(provider)` method
  - [x] Handle cache file corruption gracefully
  - [x] Write unit tests for cache operations

### Phase 3: CLI Commands ✅ COMPLETED

- [x] **Implement `aidp models` command group**
  - [x] Create `lib/aidp/cli/models_command.rb`
  - [x] Add command group to CLI router
  - [x] Write help text and usage examples

- [x] **Implement `aidp models list` command**
  - [x] Show all available models for configured providers
  - [x] Display: provider | model name | tier | capabilities
  - [x] Color-code by tier (mini=green, standard=yellow, advanced=red)
  - [x] Show source: [cache], [registry], or [config]
  - [x] Add `--provider=<name>` filter option
  - [x] Add `--tier=<tier>` filter option
  - [x] Add `--refresh` flag to bypass cache
  - [x] Write integration tests

- [x] **Implement `aidp models discover` command**
  - [x] Discover models from all configured providers
  - [x] Show progress spinner during discovery
  - [x] Display discovered models in table format
  - [x] Prompt user: "Add these to aidp.yml? [Y/n]"
  - [x] Generate YAML snippet for user to review
  - [x] Add `--auto-add` flag to skip confirmation
  - [x] Add `--provider=<name>` to discover specific provider
  - [x] Write integration tests

- [x] **Implement `aidp models refresh` command**
  - [x] Clear cache for all providers
  - [x] Re-discover models
  - [x] Update cache
  - [x] Show diff of what changed
  - [x] Write integration tests

- [x] **Implement `aidp models validate` command** ✅ COMPLETED
  - [x] Check that all tiers have at least one model
  - [x] Verify model names are valid for their providers
  - [x] Check for tier coverage gaps
  - [x] Suggest fixes for common issues
  - [x] Smart validation uses provider pattern matching (not hardcoded lists)
  - [x] Helpful error messages with YAML snippets
  - [ ] Write integration tests (deferred)

### Phase 4: Integration with Config Wizard ✅ COMPLETED

- [x] **Update `aidp config --interactive`**
  - [x] After configuring provider credentials, auto-run model discovery
  - [x] Show discovered models: "Found X models for {provider}"
  - [x] Prompt: "Auto-configure thinking tiers? [Y/n]"
  - [x] Generate tier configuration automatically
  - [x] Show preview of generated config
  - [x] Allow user to customize before saving
  - [x] Write integration tests

- [x] **Update setup wizard**
  - [x] Add model discovery to initial setup flow (`configure_thinking_tiers` method)
  - [x] Make it part of the "quick start" path
  - [x] Update wizard progress indicators
  - [x] Write integration tests

### Phase 5: Auto-Discovery on Provider Configuration ✅ COMPLETED

- [x] **Add discovery hooks to provider configuration**
  - [x] After provider credentials validated, trigger discovery
  - [x] Run discovery in background (non-blocking)
  - [x] Cache results immediately
  - [x] Show notification: "Discovered X models for {provider}"
  - [x] Implemented in setup wizard's `ensure_provider_billing_config` method
  - [x] Background threads created for each provider configuration
  - [x] Notifications displayed via `finalize_background_discovery`
  - [x] Graceful handling of provider CLI unavailability
  - [ ] Write integration tests (deferred)

- [ ] **Implement lazy discovery**
  - [ ] On first use of unconfigured tier, check if models available
  - [ ] If discovery cache exists, use it to suggest models
  - [ ] Update error message to include discovered models
  - [ ] Write integration tests

### Phase 6: Enhanced Error Messages ✅ COMPLETED

- [x] **Update "No model available for tier" error**
  - [x] Show current provider and tier
  - [x] Show YAML snippet for manual config with ready-to-paste example
  - [x] Show discovered models if available in cache
  - [x] Suggest: "Run `aidp models discover` to find available models"
  - [x] Implemented in ThinkingDepthManager with display_enhanced_tier_error method
  - [x] Checks ModelCache for discovered models automatically
  - [x] Displays up to 3 discovered models for the missing tier
  - [x] Provides 3 actionable steps if no cached models found
  - [ ] Write integration tests (deferred)

- [x] **Update authentication error messages**
  - [x] When auth fails, mention that model discovery requires valid credentials
  - [x] Enhanced Anthropic provider auth error with discovery note
  - [x] Added: "Note: Model discovery requires valid authentication."
  - [ ] Write integration tests (deferred)

### Phase 7: Documentation ✅ COMPLETED (User Docs)

- [x] **User documentation**
  - [x] Create user guide for model discovery
  - [x] Add examples to CLI_USER_GUIDE.md
  - [x] Document all `aidp models` commands (list, discover, refresh, validate)
  - [x] Add troubleshooting section for discovery failures
  - [x] Comprehensive coverage of:
    - Listing available models with filtering
    - Discovering models from providers
    - Refreshing model cache
    - Validating model configuration
    - Enhanced error messages with smart suggestions
    - Model tiers explanation (mini/standard/advanced)
    - Troubleshooting common issues (5 scenarios)
  - [ ] Create video/GIF walkthrough of auto-discovery (deferred)

- [ ] **Developer documentation** (deferred)
  - [ ] Document ModelRegistry API
  - [ ] Document how to add new provider discoverers
  - [ ] Document model classification heuristics
  - [ ] Add architecture diagrams
  - [ ] Document cache format and storage

- [ ] **Configuration examples** (deferred)
  - [ ] Update aidp.yml.example with thinking_depth section
  - [ ] Add examples for all supported providers
  - [ ] Document tier selection strategy
  - [ ] Add comments explaining auto-discovery

### Phase 8: Testing & Quality ⚡ IN PROGRESS

- [x] **Unit tests** ✅ ADDED (Coverage improvements)
  - [x] ModelsCommand comprehensive test coverage (all subcommands)
  - [x] ThinkingDepthManager enhanced error message tests
  - [x] Wizard background discovery tests
  - [x] ModelCache (38 tests, 100% coverage including permission handling)
  - [ ] ModelRegistry (100% coverage)
  - [ ] ModelDiscoveryService (100% coverage)
  - [ ] Each provider discoverer (100% coverage)
  - [ ] Tier classification logic (100% coverage)

- [ ] **Integration tests**
  - [ ] End-to-end discovery flow
  - [ ] Config wizard with discovery
  - [ ] CLI commands
  - [ ] Cache invalidation scenarios
  - [ ] Multi-provider scenarios

- [x] **Error handling tests** ✅ ADDED
  - [x] Provider CLI not installed (models_command_spec)
  - [x] Discovery failure graceful handling (wizard_spec)
  - [x] Cache corruption handling (thinking_depth_manager_spec)
  - [x] Network timeout during discovery
  - [ ] Malformed API responses
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
| ------ | -------- | ------------ |
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

providers:
  anthropic:
    thinking_tiers:
      mini:
        models:
          - <model-name>

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

providers:
  anthropic:
    thinking_tiers:
      mini:
        models:
          - claude-3-5-haiku-20241022
      standard:
        models:
          - claude-3-5-sonnet-20241022
      advanced:
        models:
          - claude-3-opus-20240229

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
