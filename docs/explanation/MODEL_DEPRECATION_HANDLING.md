# Model Deprecation Detection and Auto-Upgrade

## Overview

This document describes the dynamic model deprecation detection and automatic upgrade system. When the system encounters a deprecation error from a provider API, it **automatically records the deprecated model** in a local cache (`.aidp/deprecated_models.json`) and uses that information for future runs.

## Problem Statement

Users were seeing deprecation errors like:

```text
The model 'claude-3-7-sonnet-20250219' is deprecated and will reach end-of-life on February 19th, 2026
```

The issues were:

1. Config files contained deprecated model IDs
2. No automatic detection or upgrade mechanism
3. Registry didn't filter out deprecated models
4. Hardcoded lists required code changes and gem releases

## Solution: Dynamic Deprecation Cache

### Key Innovation: Learn from API Errors

Instead of hardcoding deprecated models, the system **dynamically learns** from provider API responses:

1. **Runtime Detection**: When an API returns a deprecation error, the system detects it
2. **Automatic Recording**: The deprecated model is saved to `.aidp/deprecated_models.json` with metadata
3. **Future Prevention**: Subsequent model selection automatically skips cached deprecated models
4. **No Code Changes**: New deprecations don't require gem updates or code changes

### Zero Framework Cognition (ZFC) Exception

**Why Pattern Matching Is Used Here**: Provider error classification is a **legitimate exception to ZFC principles**:

**The Circular Dependency Problem**:

1. When a provider (e.g., Anthropic) fails with an error, we need to classify that error
2. ZFC normally delegates semantic analysis to AI via `AIDecisionEngine`
3. `AIDecisionEngine` uses the **same provider** that's currently failing
4. **Circular dependency**: Can't use a failing provider to diagnose itself

**Why This Exception Is Justified** (per `STYLE_GUIDE.md`):

- ZFC allows "structural safety checks" when AI cannot be used
- Provider errors must be classified even when AI is unavailable
- Error messages from providers follow predictable patterns (rate limit, auth, deprecation)
- Simple string matching is sufficient and has no ReDoS vulnerabilities

**Implementation Strategy**:

```ruby
def self.classify_provider_error(error_message)
  msg_lower = error_message.downcase
  
  # Simple string.include? checks (not regex) - safe and effective
  is_rate_limit = msg_lower.include?("rate limit") || msg_lower.include?("session limit")
  is_deprecation = msg_lower.include?("deprecat") || msg_lower.include?("end-of-life")
  is_auth_error = msg_lower.include?("auth") && (msg_lower.include?("expired") || msg_lower.include?("invalid"))
  
  # Returns classification without needing AI
end
```

**Key Characteristics**:

- Uses simple `string.include?()` checks, not complex regex
- No ReDoS vulnerabilities (polynomial regex patterns)
- Works reliably even when all providers are down
- Good confidence (0.85) due to predictable error message formats
- Logs reasoning: "Pattern-based classification (ZFC exception: circular dependency)"

**When ZFC Would Apply**: If we had a **secondary, independent AI provider** specifically for error classification (e.g., a local model), we could use ZFC. But requiring a second provider just for error classification would add unnecessary complexity.

### Cache Structure

```json
{
  "version": "1.0",
  "updated_at": "2025-11-25T10:30:00Z",
  "providers": {
    "anthropic": {
      "claude-3-7-sonnet-20250219": {
        "deprecated_at": "2025-11-25T10:30:00Z",
        "replacement": "claude-sonnet-4-5-20250929",
        "reason": "The model 'claude-3-7-sonnet-20250219' is deprecated and will reach end-of-life..."
      }
    }
  }
}
```

## Solution Components

### 1. DeprecationCache (`lib/aidp/harness/deprecation_cache.rb`)

**Purpose**: Persistent storage for deprecated models detected at runtime

**Key Features**:

- Lazy-loaded JSON cache at `.aidp/deprecated_models.json`
- Per-provider deprecation tracking
- Metadata: replacement model, deprecation date, reason
- Thread-safe persistence
- Graceful handling of corrupted cache files

**API**:

```ruby
cache = Aidp::Harness::DeprecationCache.new

# Add deprecated model (called automatically when detected)
cache.add_deprecated_model(
  provider: "anthropic",
  model_id: "claude-3-7-sonnet-20250219",
  replacement: "claude-sonnet-4-5-20250929",
  reason: "Model deprecated by Anthropic"
)

# Check if model is deprecated
cache.deprecated?(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")
# => true

# Get replacement
cache.replacement_for(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")
# => "claude-sonnet-4-5-20250929"

# Get all deprecated models for a provider
cache.deprecated_models(provider: "anthropic")
# => ["claude-3-7-sonnet-20250219", "claude-3-opus-20240229", ...]

# Get full metadata
cache.info(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")
# => {"deprecated_at" => "...", "replacement" => "...", "reason" => "..."}

# Cache management
cache.stats          # Statistics
cache.clear!         # Clear all deprecations
cache.remove_deprecated_model(provider: "anthropic", model_id: "model-id")
```

### 2. Anthropic Provider (`lib/aidp/providers/anthropic.rb`)

**Runtime Detection**: Detects deprecation errors in API responses

**Automatic Recording**: When a deprecation error is detected:

1. Extracts the deprecated model ID
2. Finds replacement using registry intelligence
3. **Records to cache** with `deprecation_cache.add_deprecated_model()`
4. Retries request with upgraded model

**Key Methods**:

- `check_model_deprecation(model_name)` - Checks cache for replacement
- `find_replacement_model(deprecated, provider:)` - Intelligent replacement finding
- `send_message` - Detects deprecation errors and auto-upgrades

### 3. RubyLLM Registry (`lib/aidp/harness/ruby_llm_registry.rb`)

**Filtering Layer**: Uses deprecation cache to filter model lists

**Key Features**:

- `model_deprecated?(model_id, provider)` - Queries cache
- `find_replacement_model(deprecated, provider:)` - Finds best replacement
- `resolve_model(..., skip_deprecated: true)` - Filters during resolution
- `models_for_tier(..., skip_deprecated: true)` - Filters tier results

### 4. Thinking Depth Manager (`lib/aidp/harness/thinking_depth_manager.rb`)

**Config-Time Checking**: Validates configured models before use

**Auto-Upgrade Flow**:

1. Check if configured model is in deprecation cache
2. If deprecated, find replacement
3. If found, use replacement
4. If not found, try next configured model or catalog

## Usage

### For Users

**No action required!** The system:

1. Detects deprecation errors automatically
2. Records them to `.aidp/deprecated_models.json`
3. Finds and uses replacements
4. Prevents using deprecated models in future

**Initial Setup** (one-time):

```bash
# Seed cache with known deprecated models
ruby scripts/seed_deprecated_models.rb
```

**To view cached deprecations**:

```bash
cat .aidp/deprecated_models.json | jq
```

### For Developers

**The system is now fully dynamic** - no code changes needed when models deprecate!

**To manually add a deprecated model** (if needed):

```ruby
require "aidp/harness/deprecation_cache"

cache = Aidp::Harness::DeprecationCache.new
cache.add_deprecated_model(
  provider: "anthropic",
  model_id: "old-model-id",
  replacement: "new-model-id",
  reason: "Manual addition"
)
```

**Testing deprecation handling**:

```ruby
# Check if model is deprecated
cache.deprecated?(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")
# => true

# Get replacement
cache.replacement_for(provider: "anthropic", model_id: "claude-3-7-sonnet-20250219")
# => "claude-sonnet-4-5-20250929"

# Check stats
cache.stats
# => {providers: ["anthropic"], total_deprecated: 5, by_provider: {"anthropic" => 5}}
```

## Logging

The system logs deprecation events extensively:

```text
INFO deprecation_cache Added deprecated model (provider=anthropic model=claude-3-7-sonnet-20250219 replacement=claude-sonnet-4-5-20250929)
```

```text
WARN thinking_depth_manager Configured model is deprecated (tier=standard provider=anthropic model=claude-3-7-sonnet-20250219)
INFO thinking_depth_manager Auto-upgrading to non-deprecated model (old_model=claude-3-7-sonnet-20250219 new_model=claude-sonnet-4-5-20250929)
```

```text
ERROR anthropic Model deprecation detected (model=claude-3-7-sonnet-20250219 message=...)
INFO anthropic Auto-upgrading to non-deprecated model (old_model=claude-3-7-sonnet-20250219 new_model=claude-sonnet-4-5-20250929)
```

## Testing

Three comprehensive test suites:

1. **`spec/aidp/harness/deprecation_cache_spec.rb`** (20 tests)
   - Cache persistence and loading
   - Add/remove/query operations
   - Stats and metadata
   - Error handling

2. **`spec/aidp/harness/ruby_llm_registry_deprecation_spec.rb`** (16 tests)
   - Deprecation checking
   - Replacement finding
   - Model resolution with filtering
   - Tier filtering

3. **`spec/aidp/providers/anthropic_deprecation_spec.rb`** (7 tests)
   - Anthropic-specific deprecation logic
   - Cache integration
   - Registry fallback
   - Error pattern matching

**All 43 tests passing** ✅

## Benefits

1. **Zero Maintenance**: Models deprecate themselves automatically
2. **No Gem Updates**: New deprecations don't require code changes
3. **Persistent Learning**: Deprecations persist across runs
4. **Provider Agnostic**: Works for any provider
5. **Intelligent**: Finds best replacements using family matching
6. **Transparent**: Extensive logging shows deprecation events
7. **Safe**: Defaults to filtering deprecated models
8. **Flexible**: Can be manually managed if needed

## Migration from Hardcoded Lists

The system includes a migration script to seed the cache with known deprecated models:

```bash
ruby scripts/seed_deprecated_models.rb
```

This creates `.aidp/deprecated_models.json` with known deprecated models from the previous hardcoded constants.

## Configuration Update (Optional)

Users with deprecated models in their config can optionally update manually:

```bash
aidp config --interactive
```

Or edit `.aidp/aidp.yml`:

```yaml
providers:
  anthropic:
    thinking_tiers:
      standard:
        models:
        # OLD: - claude-3-7-sonnet-20250219
        - claude-sonnet-4-5-20250929  # NEW
        - claude-sonnet-4-5
```

The system auto-upgrades at runtime, so this is optional but recommended for clarity.

## Related Documentation

- `docs/CLAUDE_MODEL_DEPRECATION.md` - Claude-specific deprecation details
- `docs/AUTOMATED_MODEL_DISCOVERY.md` - Model discovery system
- `docs/LLM_STYLE_GUIDE.md` - Coding standards followed
