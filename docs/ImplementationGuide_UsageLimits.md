# Implementation Guide: Usage Limits for Usage-Based Providers (Issue #296)

## Executive Summary

This guide provides comprehensive implementation guidance for adding configurable usage limits to AIDP's usage-based providers. The feature prevents runaway costs by tracking and enforcing token and cost limits per time period, with tier-based limits for mini vs advanced models.

**Architecture Pattern**: Hexagonal Architecture + DDD + SOLID Principles  
**Key Patterns**: Repository Pattern, Strategy Pattern, Service Objects, Dependency Injection

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Implementation Tasks](#implementation-tasks)
4. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
5. [Design Contracts](#design-contracts)
6. [Integration Points](#integration-points)
7. [Testing Strategy](#testing-strategy)
8. [Migration Strategy](#migration-strategy)

---

## Architecture Overview

### Hexagonal Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Wizard (Interactive TUI Configuration)                │ │
│  │  - Usage limit configuration prompts                   │ │
│  │  - Tier-based limit selection                          │ │
│  │  - Period selection (daily/weekly/monthly)             │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                       │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  UsageLimitEnforcer (Service)                          │ │
│  │  - Check limits before API calls                       │ │
│  │  - Raise UsageLimitExceeded when over limit            │ │
│  │  - Coordinate with tracker and provider config         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                       DOMAIN LAYER                          │
│  ┌─────────────────────┐  ┌──────────────────────────────┐ │
│  │ UsagePeriod         │  │ UsageLimitTracker            │ │
│  │ (Value Object)      │  │ (Domain Service)             │ │
│  │ - period_type       │  │ - Track token usage          │ │
│  │ - start_time        │  │ - Track cost                 │ │
│  │ - end_time          │  │ - Reset on period boundary   │ │
│  │ - reset_time        │  │ - Query current usage        │ │
│  └─────────────────────┘  └──────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  UsageLimit (Entity/Value Object)                    │  │
│  │  - max_tokens                                        │  │
│  │  - max_cost                                          │  │
│  │  - period (daily/weekly/monthly)                     │  │
│  │  - tier_limits { mini: {...}, advanced: {...} }     │  │
│  │  - enabled                                           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   INFRASTRUCTURE LAYER                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  ProviderMetrics (Repository)                          │ │
│  │  - Persist usage data to YAML                          │ │
│  │  - Load usage history                                  │ │
│  │  - Atomic writes with file locking                     │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  ConfigSchema (Configuration Schema)                   │ │
│  │  - Define usage_limits schema                          │ │
│  │  - Validate limit configuration                        │ │
│  │  - Apply defaults                                      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  ProviderConfig (Configuration Access)                 │ │
│  │  - usage_limits accessor methods                       │ │
│  │  - Tier-based limit retrieval                          │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities (Single Responsibility Principle)

| Component | Single Responsibility |
|-----------|----------------------|
| **UsageLimitEnforcer** | Enforce usage limits by checking before API calls |
| **UsageLimitTracker** | Track and aggregate usage metrics per period |
| **UsagePeriod** | Represent time periods and handle reset logic |
| **UsageLimit** | Encapsulate limit configuration and validation |
| **ProviderMetrics** | Persist and retrieve usage data |
| **ConfigSchema** | Define and validate configuration schema |
| **ProviderConfig** | Provide typed access to provider configuration |

---

## Domain Model

See full domain model with code examples in the appendix of this guide.

**Key Domain Objects:**
- **UsageLimit** (Value Object): Immutable configuration of limits
- **UsagePeriod** (Value Object): Time period calculations and boundaries
- **UsageLimitTracker** (Domain Service): Track and query usage metrics
- **UsageLimitEnforcer** (Application Service): Orchestrate enforcement

---

## Implementation Tasks

### Research Provider Billing APIs

**Conclusion**: Most providers (Anthropic, Gemini, GitHub Copilot, Cursor) don't expose billing APIs. AIDP must track usage client-side by:
1. Parsing response metadata (tokens used per request)
2. Calculating costs using published pricing tables
3. Persisting usage data locally

| Provider | Billing API | Available Metrics | Client-Side Tracking |
|----------|-------------|-------------------|----------------------|
| Anthropic | No | None | Parse response headers |
| OpenAI | Yes (`/v1/usage`) | Tokens, cost | Can verify against API |
| Gemini | Cloud Console | Tokens, requests | Parse response metadata |
| Cursor | No | None | Count tokens client-side |
| GitHub Copilot | No | None | Count tokens client-side |

---

## Pattern-to-Use-Case Matrix

| Pattern | Use Case | Implementation | Benefit |
|---------|----------|----------------|---------|
| **Value Object** | UsageLimit, UsagePeriod | Immutable objects with equality based on values | Prevents accidental mutation |
| **Repository** | ProviderMetrics persistence | Abstract data access layer | Decouple domain from storage |
| **Service Object** | UsageLimitTracker, UsageLimitEnforcer | Single-purpose services with clear interfaces | Maintain SRP |
| **Strategy** | Period calculation (daily/weekly/monthly) | UsagePeriod encapsulates period logic | Easy to add period types |
| **Dependency Injection** | Enforcer receives tracker and config | Constructor injection with defaults | Testable without external dependencies |
| **Template Method** | Provider hooks (before/after request) | Base class defines hooks | Consistent enforcement |
| **Factory** | UsageLimit.from_config | Create domain objects from configuration | Centralize object creation |
| **Domain Event** | Usage limit exceeded | Raise UsageLimitExceededError | Clear separation of concerns |

---

## Design Contracts

### UsageLimitEnforcer.check_before_request

**Preconditions**:
- Provider must be configured
- Tracker must be initialized  
- Usage limit configuration must be valid

**Postconditions**:
- If limit not exceeded: No exception raised
- If limit exceeded: UsageLimitExceededError raised with usage summary
- Logs debug message regardless of outcome

**Invariants**:
- Usage data is never corrupted
- Period resets are idempotent
- Cost/token tracking is monotonically increasing within a period

### UsageLimitTracker.record_usage

**Preconditions**:
- tokens > 0
- cost >= 0
- tier in [:mini, :advanced]

**Postconditions**:
- Total tokens increased by tokens
- Total cost increased by cost
- Tier-specific usage increased
- Usage persisted to disk
- last_updated timestamp updated

**Invariants**:
- Total tokens >= sum of tier tokens
- Total cost >= sum of tier costs
- Period boundaries are consistent

---

## Integration Points

### 1. Configuration Loading (ConfigManager)

```
ConfigManager.load
  ↓
ConfigSchema.validate (includes usage_limits validation)
  ↓
ConfigSchema.apply_defaults (applies usage_limits defaults)
  ↓
ProviderConfig.new(provider_name)
  ↓
ProviderConfig.usage_limits_config
```

### 2. Provider Execution (Provider Base)

```
Provider.send_message(prompt, tier)
  ↓
Provider.before_api_request(tier)
  ↓
UsageLimitEnforcer.check_before_request(tier)
  ↓ (UsageLimitExceededError if over limit)
Provider.make_api_call(prompt)
  ↓
Provider.after_api_request(tokens, cost, tier)
  ↓
UsageLimitTracker.record_usage(tokens, cost, tier)
  ↓
ProviderMetrics.save_metrics
```

### 3. Interactive Configuration (Wizard)

```
Wizard.run
  ↓
Wizard.configure_providers
  ↓
Wizard.configure_usage_limits(provider_name) (only for usage_based providers)
  ↓
Wizard.save_config
  ↓
ConfigSchema.validate
```

---

## Testing Strategy

### Unit Tests

**Coverage Target**: 95%+ for domain and service classes

**Key Test Files**:
- `spec/aidp/harness/usage_limit_spec.rb` - Value object validation
- `spec/aidp/harness/usage_period_spec.rb` - Period calculations and boundaries
- `spec/aidp/harness/usage_limit_tracker_spec.rb` - Usage tracking and persistence
- `spec/aidp/harness/usage_limit_enforcer_spec.rb` - Enforcement logic
- `spec/aidp/harness/provider_config_spec.rb` - Configuration accessors

**Test Categories**:
1. **Value Object Tests**: Immutability, validation, equality
2. **Period Calculation Tests**: Daily/weekly/monthly boundaries, timezone handling
3. **Usage Tracking Tests**: Increment counters, persist data, period reset
4. **Enforcement Tests**: Check limits, raise errors, tier-specific limits
5. **Configuration Tests**: Schema validation, defaults, accessor methods

**Edge Cases to Test**:
- Period boundaries (month end, year end, DST transitions)
- Concurrent access to usage data
- Corrupted usage data recovery
- Tier limits vs global limits
- Disabled limits (should not enforce)

### Integration Tests

**Full Workflow Tests**:
1. Config → Enforcement → Tracking workflow
2. Provider execution with limits
3. Period reset across time boundaries
4. Multiple providers with different limits

### Test Doubles

**Use Dependency Injection**:
```ruby
let(:metrics_repo) { instance_double(Aidp::Harness::ProviderMetrics) }
let(:tracker) { described_class.new(metrics_repo: metrics_repo) }
```

**Avoid Mocking Time**:
```ruby
# Stub Time.now for deterministic tests
allow(Time).to receive(:now).and_return(fixed_time)
```

---

## Migration Strategy

### Phase 1: Non-Breaking Addition

**Goal**: Add usage tracking without affecting existing functionality

**Steps**:
1. Implement domain classes (UsageLimit, UsagePeriod, UsageLimitTracker)
2. Extend ConfigSchema with usage_limits (default: disabled)
3. Add ProviderConfig accessor methods
4. Add ProviderMetrics persistence support
5. **No enforcement yet** - just tracking

**Validation**: Existing tests pass, new tests added, no behavior changes

### Phase 2: Opt-In Enforcement

**Goal**: Enable enforcement for users who configure it

**Steps**:
1. Implement UsageLimitEnforcer
2. Add provider hooks (before/after request) - check if enabled
3. Update Wizard to prompt for usage limits (usage-based providers only)
4. Documentation and examples

**Validation**: Default behavior unchanged (limits disabled), opt-in users get enforcement

### Phase 3: Default Limits for New Installations

**Goal**: Provide sensible defaults for new users

**Steps**:
1. Update Wizard defaults to suggest limits based on tier
2. Update documentation with recommended limits
3. Add usage monitoring CLI commands

**Validation**: New installations get limits by default, existing configs unchanged

---

## Security and Safety

### Concerns
1. **Cost Overruns**: Primary concern - prevent unexpected bills
2. **Data Integrity**: Usage data must be accurate and not corrupted
3. **Concurrent Access**: Multiple processes may access same usage data

### Mitigations
1. **File Locking**: Use file locking when persisting usage data
2. **Atomic Writes**: Write to temporary file, then rename
3. **Validation**: Validate configuration at load time
4. **Defensive Checks**: Handle missing/corrupted data gracefully

---

## Appendix: Configuration Example

```yaml
harness:
  default_provider: anthropic
  fallback_providers: [gemini, openai]

providers:
  anthropic:
    type: usage_based
    priority: 1
    models:
      - claude-3-5-sonnet-20241022
      - claude-3-5-haiku-20241022
    auth:
      api_key_env: ANTHROPIC_API_KEY
    usage_limits:
      enabled: true
      period: monthly
      tier_limits:
        mini:
          max_tokens: 1_000_000
          max_cost: 10.0
        advanced:
          max_tokens: 5_000_000
          max_cost: 50.0

  gemini:
    type: usage_based
    priority: 2
    usage_limits:
      enabled: true
      max_cost: 30.0
      period: monthly

  cursor:
    type: subscription
    priority: 4
    # Subscription providers don't have usage limits
```

---

## Summary

This implementation guide provides a complete blueprint for adding usage limits to AIDP's usage-based providers. The architecture follows hexagonal/DDD patterns with clear separation of concerns across presentation, application, domain, and infrastructure layers.

**Key Design Decisions**:
1. **Client-side tracking**: Most providers don't expose billing APIs
2. **Tier-based limits**: Different limits for mini vs advanced models
3. **Flexible periods**: Daily, weekly, monthly tracking
4. **Opt-in by default**: Non-breaking migration path
5. **SOLID principles**: Small, focused classes with clear responsibilities
6. **Testability**: Dependency injection enables comprehensive testing

The implementation maintains AIDP's architectural consistency while adding robust cost protection for usage-based providers.
