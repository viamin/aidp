# Issue #165 Implementation Plan: Zero Framework Cognition (ZFC) Compliance

**Status**: 🚧 IN PROGRESS - Phase 1: Foundation (MVP)
**Issue**: <https://github.com/viamin/aidp/issues/165>
**Created**: 2025-10-26
**Last Updated**: 2025-10-26

---

## Executive Summary

This document outlines the implementation plan for bringing AIDP into compliance with **Zero Framework Cognition (ZFC)** principles. ZFC advocates for delegating all reasoning, decision-making, and semantic analysis to AI models, while keeping orchestration code "dumb" - purely mechanical.

**Current State**: 9 identified ZFC violations where local heuristics replace AI decision-making
**Goal**: Replace brittle pattern matching with AI-powered decision logic
**Cost Control**: Use `mini` tier for all ZFC operations (~$11/month additional)

**Estimated Total Effort**: 4-6 weeks (full compliance)
**Minimum Viable Product (MVP)**: 1-2 weeks (Phase 1)

---

## Table of Contents

1. [ZFC Principles Summary](#zfc-principles-summary)
2. [Current Violations](#current-violations)
3. [Implementation Phases](#implementation-phases)
4. [Technical Design](#technical-design)
5. [Testing Strategy](#testing-strategy)
6. [Cost Management](#cost-management)
7. [Rollout Strategy](#rollout-strategy)
8. [Success Metrics](#success-metrics)

---

## ZFC Principles Summary

### Allowed (ZFC-Compliant)

✅ **Pure orchestration**: I/O, plumbing, file operations
✅ **Structural safety checks**: Schema validation, required fields, timeouts
✅ **Policy enforcement**: Budgets, rate-limits, confidence thresholds
✅ **Mechanical transforms**: Parameter substitution, formatting
✅ **State management**: Lifecycle tracking, progress monitoring
✅ **Typed error handling**: Using SDK error types

### Forbidden (ZFC-Violations)

❌ **Local reasoning/decision logic**: Ranking, scoring, selection in client code
❌ **Semantic analysis**: Heuristic classification, inference about output
❌ **Quality judgments**: Opinions baked into code rather than delegated to model
❌ **Pattern matching for meaning**: Regex/keyword detection for semantic content

### The Golden Rule

> If it requires understanding meaning, ask the AI. If it's purely mechanical, keep it in code.

---

## Current Violations

### Critical (Must Fix)

1. **Provider Selection & Load Balancing** ([lib/aidp/harness/provider_manager.rb:411-425](lib/aidp/harness/provider_manager.rb#L411-L425))
   - Hard-coded scoring formula for provider ranking
   - Impact: HIGH - runs on every request
   - Effort: 3-4 days

2. **Model Tier Escalation** ([lib/aidp/harness/thinking_depth_manager.rb:89-108](lib/aidp/harness/thinking_depth_manager.rb#L89-L108))
   - Heuristic thresholds for when to escalate
   - Impact: HIGH - affects cost and quality
   - Effort: 2-3 days

### Major (High Priority)

1. **Semantic Condition Detection** ([lib/aidp/harness/condition_detector.rb:45-195](lib/aidp/harness/condition_detector.rb#L45-L195))
   - 150+ regex patterns for rate limits, auth errors, etc.
   - Impact: HIGH - extremely brittle
   - Effort: 4-5 days

2. **Completion Detection** ([lib/aidp/harness/completion_checker.rb:67-89](lib/aidp/harness/completion_checker.rb#L67-L89))
   - Keyword matching for "finished", "done", etc.
   - Impact: MEDIUM - language-dependent
   - Effort: 1-2 days

3. **Health Scoring** ([lib/aidp/providers/base.rb:234-256](lib/aidp/providers/base.rb#L234-L256))
   - Weighted formula for provider health
   - Impact: MEDIUM - affects routing
   - Effort: 2-3 days

4. **Project Analysis Confidence** ([lib/aidp/init/project_analyzer.rb:145-167](lib/aidp/init/project_analyzer.rb#L145-L167))
   - Heuristic confidence scoring
   - Impact: LOW - only at init
   - Effort: 2-3 days

5. **Error Classification** (Multiple files)
   - 40+ error patterns for retry logic
   - Impact: MEDIUM - affects resilience
   - Effort: 2-3 days

### Minor (Polish)

1. **Workflow Selection** ([lib/aidp/execute/workflow_selector.rb:78-123](lib/aidp/execute/workflow_selector.rb#L78-L123))
   - Pattern matching for workflow routing
   - Impact: LOW - works reasonably well
   - Effort: 2-3 days

2. **Skill Routing** ([lib/aidp/skills/router.rb:56-89](lib/aidp/skills/router.rb#L56-L89))
   - Hard-coded routing logic
   - Impact: LOW - simple cases
   - Effort: 1-2 days

---

## Implementation Phases

### Phase 1: Foundation (MVP) - 1-2 Weeks

**Goal**: Replace most brittle violations with AI decision-making
**Priority**: HIGH
**Effort**: 7-10 days

#### Tasks

1. ✅ **Create AI Decision Framework** (2 days) - **COMPLETED**
   - ✅ Built `Aidp::Harness::AIDecisionEngine` class (370 lines)
   - ✅ Schema validation for AI responses (type, enum, range validation)
   - ✅ Integration with ThinkingDepthManager for tier selection
   - ✅ Default to `mini` tier for all decisions
   - ✅ Caching layer with TTL support for repeated decisions
   - ✅ JSON extraction from wrapped AI responses
   - ✅ 3 decision templates: condition_detection, error_classification, completion_detection
   - ✅ Configuration support (thinking + zfc sections in aidp.yml.example)
   - ✅ Configuration accessors in Configuration class
   - ✅ Comprehensive test suite (26 tests, 100% passing)

2. ✅ **Replace Condition Detection** (3 days) - **COMPLETED**
   - File: `lib/aidp/harness/condition_detector.rb`
   - ✅ Created `ZfcConditionDetector` wrapper class (298 lines)
   - ✅ Implemented AI classification with schema (condition_detection template)
   - ✅ A/B testing infrastructure built-in
   - ✅ Comprehensive test suite (28 tests, 100% passing)
   - ✅ Statistics tracking (accuracy, cost, fallback rate)
   - ✅ Graceful fallback to legacy on AI failures
   - ✅ **Integrated into EnhancedRunner and Runner**
   - ✅ **Supports both Configuration and ConfigManager**
   - ✅ **All 4066 tests passing**
   - Original code: 1526 lines of regex patterns (preserved as fallback)
   - Ready for production deployment with feature flags

3. ✅ **Replace Completion Detection** (1 day) - **COMPLETED**
   - File: `lib/aidp/harness/completion_checker.rb`
   - ✅ Implemented in `ZfcConditionDetector#is_work_complete?`
   - ✅ Schema: `{ complete: boolean, confidence: float, reasoning: string }`
   - ✅ Uses `mini` tier with confidence threshold
   - ✅ A/B testing support
   - ✅ Test coverage included in ZfcConditionDetector specs

4. ✅ **Replace Error Classification** (2 days) - **COMPLETED**
   - Files: Error handling across multiple modules
   - ✅ Added `classify_error` method to `ZfcConditionDetector`
   - ✅ Schema: `{ error_type: string, retryable: boolean, recommended_action: string, confidence: float }`
   - ✅ Uses `mini` tier with confidence threshold
   - ✅ A/B testing support for error classification
   - ✅ 8 comprehensive tests added (36 total for ZfcConditionDetector)
   - ✅ **All 4074 tests passing**
   - Ready for integration with ErrorHandler
   - Provides better recovery strategy recommendations than pattern matching

5. ✅ **Add Feature Flags** (1 day) - **COMPLETED**
   - ✅ Configuration schema in `templates/aidp.yml.example`
   - ✅ Per-decision type granularity (condition_detection, error_classification, completion_detection)
   - ✅ Tier selection per decision type
   - ✅ Confidence thresholds per decision type
   - ✅ Cache TTL configuration
   - ✅ Cost limits (max_daily_cost, max_cost_per_decision)
   - ✅ A/B testing configuration
   - ✅ Fallback to legacy always available
   - Ready for production deployment

6. **Testing & Validation** (2 days) - **IN PROGRESS**
   - ✅ Unit tests for AIDecisionEngine (26 tests, 100% passing)
   - ✅ Unit tests for ZfcConditionDetector (36 tests, 100% passing)
   - ✅ Integration tests with Runner and EnhancedRunner
   - ✅ **All 4074 tests passing with ZFC integration**
   - ✅ A/B testing infrastructure for ZFC vs legacy comparison
   - ✅ Statistics tracking (accuracy, cost estimates, fallback rate)
   - ⏳ TODO: Performance benchmarks (latency impact measurement)
   - ⏳ TODO: Real-world cost tracking (requires production deployment)

#### Deliverables

- ✅ AIDecisionEngine framework (370 lines, 26 tests)
- ✅ ZfcConditionDetector wrapper (399 lines, 36 tests)
- ✅ 3 major violations fixed (condition detection, completion detection, error classification)
- ✅ Feature flags for safe rollout (configuration schema complete)
- ✅ Comprehensive test coverage (4074 tests, 100% passing)
- ✅ A/B testing infrastructure
- ✅ Statistics tracking and cost estimation
- ✅ **Integrated into Runner and EnhancedRunner**
- ⏳ Performance benchmarks (pending)

#### Success Criteria

- ✅ All tests passing (4074/4074)
- ⏳ <10% latency increase vs pattern matching (needs benchmarking)
- ⏳ >95% accuracy on test cases (needs production A/B testing)
- ✅ <$20/month additional cost (estimated ~$11/month with mini tier at default usage)
- ✅ Zero regressions in existing functionality (all tests pass)

---

### Phase 2: Decision Logic (Core ZFC) - 2-3 Weeks

**Goal**: Replace core decision-making with AI
**Priority**: HIGH
**Effort**: 10-15 days

#### Tasks

1. **AI-Driven Provider Selection** (4 days)
   - File: `lib/aidp/harness/provider_manager.rb`
   - Remove load calculation formula
   - Gather context: provider stats, current load, historical performance
   - Ask AI: "Which provider should handle this request?"
   - Schema: `{ provider_name: string, reasoning: string, confidence: float }`
   - Use `mini` tier with 5-minute cached decisions
   - Performance testing (latency impact)

2. **AI-Driven Tier Escalation** (3 days)
   - File: `lib/aidp/harness/thinking_depth_manager.rb`
   - Remove heuristic thresholds (failure counts, complexity scores)
   - Gather context: task description, previous failures, current tier
   - Ask AI: "Should we escalate to a more capable model?"
   - Schema: `{ should_escalate: boolean, target_tier: string, reasoning: string }`
   - Use `mini` tier (ironic but cost-effective)
   - Track escalation accuracy

3. **AI-Based Workflow Routing** (3 days)
   - Files: `lib/aidp/execute/workflow_selector.rb`, `lib/aidp/skills/router.rb`
   - Remove pattern matching for workflow/skill selection
   - Ask AI: "Which workflow/skill is best for this task?"
   - Schema: `{ workflow_name: string, skill_name: string | null, reasoning: string }`
   - Use `mini` tier
   - Validate against available workflows/skills

4. **Integration Testing** (2 days)
   - End-to-end workflow testing with ZFC enabled
   - Stress testing (high-frequency decisions)
   - Fallback behavior when AI unavailable
   - Cost monitoring

5. **Documentation** (1 day)
   - Update architecture docs
   - Add ZFC decision flow diagrams
   - Document tier selection rationale

#### Deliverables

- ✅ AI-driven provider selection
- ✅ AI-driven tier escalation
- ✅ AI-based routing
- ✅ Comprehensive integration tests
- ✅ Updated architecture docs

#### Success Criteria

- Provider selection improves or matches legacy algorithm
- Tier escalation reduces unnecessary expensive calls
- Routing accuracy >95%
- Total additional cost <$50/month
- Latency increase <20%

---

### Phase 3: Quality Judgments (Polish) - 1 Week

**Goal**: Replace remaining heuristics
**Priority**: MEDIUM
**Effort**: 5-7 days

#### Tasks

1. **AI-Driven Health Assessment** (3 days)
   - File: `lib/aidp/providers/base.rb`
   - Remove scoring formula
   - Ask AI: "How healthy is this provider for the current context?"
   - Schema: `{ health_score: 0.0..1.0, issues: [string], recommendation: string }`
   - Use `mini` tier with 10-minute refresh
   - Compare against formula-based approach

2. **AI-Based Project Analysis** (3 days)
   - File: `lib/aidp/init/project_analyzer.rb`
   - Remove pattern matching and confidence formulas
   - Ask AI: "Analyze this project structure"
   - Schema: `{ project_type: string, confidence: float, frameworks: [string], recommendations: [string] }`
   - Use `mini` tier (one-time cost at init)
   - Validate against known project types

3. **Testing & Refinement** (1 day)
   - Test edge cases
   - Performance validation
   - Cost tracking

#### Deliverables

- ✅ AI-driven health assessment
- ✅ AI-based project analysis
- ✅ Full test coverage
- ✅ Performance benchmarks

#### Success Criteria

- Health assessment more context-aware
- Project analysis handles edge cases better
- No significant cost increase
- Clean, maintainable code

---

### Phase 4: Documentation & Governance - 3-5 Days

**Goal**: Prevent future ZFC violations
**Priority**: MEDIUM
**Effort**: 3-5 days

#### Tasks

1. **Create ZFC Guidelines** (2 days)
   - Document: `docs/ZFC_GUIDELINES.md`
   - Provide examples of compliant vs violated patterns
   - Decision tree: "Should this be AI or code?"
   - Code review checklist
   - Add to onboarding docs

2. **Update Style Guides** (1 day)
   - Add ZFC section to `docs/STYLE_GUIDE.md`
   - Add ZFC section to `docs/LLM_STYLE_GUIDE.md`
   - Include examples and anti-patterns

3. **Add Linting/Checks** (2 days)
   - Create `scripts/check_zfc_compliance.rb`
   - Detect pattern matching in decision code
   - Flag hard-coded weights and scoring formulas
   - Identify semantic regex patterns
   - CI check: "Does this PR introduce ZFC violations?"
   - Optional: Add to pre-commit hooks

#### Deliverables

- ✅ ZFC_GUIDELINES.md
- ✅ Updated style guides
- ✅ ZFC compliance checker script
- ✅ CI integration

#### Success Criteria

- Clear guidelines for all developers
- Automated detection of violations
- CI catches new violations before merge
- Team onboarding includes ZFC principles

---

## Technical Design

### AI Decision Engine Architecture

```ruby
module Aidp
  module Harness
    class AIDecisionEngine
      # Core decision-making interface
      def decide(decision_type, context, schema:, tier: "mini", cache_ttl: nil)
        # 1. Check cache (if cache_ttl specified)
        # 2. Build prompt from decision_type template
        # 3. Call AI with schema validation
        # 4. Validate response structure
        # 5. Cache result (if cache_ttl specified)
        # 6. Return structured decision
      end

      # Decision type templates
      DECISION_TEMPLATES = {
        condition_detection: {
          prompt: "Classify this API response condition",
          schema: ConditionSchema,
          default_tier: "mini"
        },
        provider_selection: {
          prompt: "Select the best provider for this request",
          schema: ProviderSelectionSchema,
          default_tier: "mini",
          cache_ttl: 300  # 5 minutes
        },
        # ... more templates
      }
    end
  end
end
```

### Schema Design Pattern

All AI decisions must return structured data validated against JSON schemas:

```ruby
ConditionSchema = {
  type: "object",
  properties: {
    condition: {
      type: "string",
      enum: ["rate_limit", "auth_error", "timeout", "success", "other"]
    },
    confidence: {
      type: "number",
      minimum: 0.0,
      maximum: 1.0
    },
    reasoning: { type: "string" }
  },
  required: ["condition", "confidence"]
}
```

### Integration with Thinking Depth

```ruby
# AIDecisionEngine uses ThinkingDepthManager for tier selection
def decide(decision_type, context, schema:, tier: nil, cache_ttl: nil)
  # Use explicit tier or fall back to decision type default
  selected_tier = tier || DECISION_TEMPLATES[decision_type][:default_tier]

  # Get provider/model for tier
  thinking_manager = ThinkingDepthManager.new(@config)
  provider, model_name, _model_data = thinking_manager.select_model_for_tier(selected_tier)

  # Make AI call with selected model
  result = @provider_manager.call(
    provider: provider,
    model: model_name,
    prompt: build_prompt(decision_type, context),
    schema: schema
  )

  validate_schema(result, schema)
  result
end
```

### Caching Strategy

Use simple TTL-based caching for repeated decisions:

```ruby
class DecisionCache
  def initialize
    @cache = {}
    @timestamps = {}
  end

  def get(key, ttl)
    return nil unless @cache.key?(key)
    return nil if Time.now - @timestamps[key] > ttl
    @cache[key]
  end

  def set(key, value)
    @cache[key] = value
    @timestamps[key] = Time.now
  end
end
```

### Feature Flag Integration

```yaml
# config/aidp.yml
zfc:
  enabled: true  # Master toggle

  decisions:
    condition_detection:
      enabled: true
      tier: mini
      cache_ttl: 60

    provider_selection:
      enabled: true
      tier: mini
      cache_ttl: 300

    tier_escalation:
      enabled: false  # Not ready yet
      tier: mini

    # ... more decision types

  fallback_to_legacy: true  # If AI fails, use old pattern matching
```

---

## Testing Strategy

### Unit Tests

For each replaced violation:

1. **AIDecisionEngine Core**
   - Schema validation
   - Tier selection
   - Caching behavior
   - Error handling

2. **Decision Type Tests**
   - Condition detection accuracy
   - Provider selection correctness
   - Tier escalation logic
   - Completion detection precision

3. **Edge Cases**
   - Non-English responses
   - Ambiguous inputs
   - Malformed data
   - AI service unavailable

### Integration Tests

1. **End-to-End Workflows**
   - Run complete work loops with ZFC enabled
   - Verify decisions match or exceed legacy behavior
   - Test fallback to legacy when ZFC disabled

2. **Performance Tests**
   - Latency impact measurements
   - Cache hit rate validation
   - Concurrent decision handling

3. **Cost Tracking Tests**
   - Count AI calls per work loop
   - Verify `mini` tier used by default
   - Track total token usage

### A/B Testing

Run both ZFC and legacy logic in parallel for comparison:

```ruby
def detect_condition(response)
  # Run both approaches
  zfc_result = detect_condition_ai(response) if zfc_enabled?(:condition_detection)
  legacy_result = detect_condition_legacy(response)

  # Log comparison for analysis
  log_zfc_comparison(:condition_detection, zfc_result, legacy_result)

  # Return based on feature flag
  zfc_enabled?(:condition_detection) ? zfc_result : legacy_result
end
```

### Success Metrics

Track these in tests and production:

- **Accuracy**: % of correct classifications vs ground truth
- **Latency**: Added time per decision
- **Cost**: $ per decision type
- **Reliability**: % of successful AI calls
- **Cache Hit Rate**: % of decisions served from cache

---

## Cost Management

### Default Tier Strategy

**CRITICAL**: All ZFC operations use `mini` tier unless explicitly justified

```ruby
# GOOD: Explicit mini tier
AIDecisionEngine.decide(:condition_detection, context,
                        schema: ConditionSchema,
                        tier: "mini")

# BAD: Using expensive tier for simple classification
AIDecisionEngine.decide(:condition_detection, context,
                        schema: ConditionSchema,
                        tier: "thinking")  # ❌ Wasteful
```

### Cost Budgets

Set per-decision type cost limits in config:

```yaml
zfc:
  cost_limits:
    max_cost_per_decision: 0.001  # $0.001 per decision
    max_daily_cost: 5.00           # $5/day total
    alert_threshold: 0.8           # Alert at 80% of budget
```

### Cost Monitoring

```ruby
class CostMonitor
  def track_decision(decision_type, tokens_used, tier)
    cost = calculate_cost(tokens_used, tier)

    # Log to metrics
    @metrics.increment("zfc.decisions.#{decision_type}.cost", cost)
    @metrics.increment("zfc.decisions.#{decision_type}.count")

    # Check budget
    daily_cost = @metrics.get("zfc.daily_cost")
    if daily_cost > @config[:max_daily_cost]
      alert("ZFC cost budget exceeded: $#{daily_cost}")
      disable_zfc_temporarily if @config[:auto_disable_on_budget_exceed]
    end
  end
end
```

### Expected Costs (with mini tier)

| Decision Type | Calls/Loop | Cost/Call | Cost/Loop |
|--------------|------------|-----------|-----------|
| Condition detection | 10 | $0.000075 | $0.00075 |
| Error classification | 5 | $0.000075 | $0.000375 |
| Completion check | 3 | $0.000075 | $0.000225 |
| Provider selection | 1 | $0.000075 | $0.000075 |
| Workflow routing | 1 | $0.000075 | $0.000075 |
| **TOTAL** | **20** | - | **$0.0015/loop** |

**Monthly**: 100 loops/day × 30 days × $0.0015 = **$4.50/month**

Even better than original estimate due to aggressive use of `mini` tier!

---

## Rollout Strategy

### Phase 1: Internal Testing (1 week)

1. Enable ZFC in development environment
2. Run against test suite
3. Manually test common workflows
4. Monitor costs and performance
5. Fix any issues found

### Phase 2: Canary Deployment (1 week)

1. Enable for 10% of production traffic
2. Monitor metrics closely:
   - Accuracy vs legacy
   - Latency impact
   - Cost tracking
   - Error rates
3. Compare ZFC vs legacy side-by-side
4. Adjust based on findings

### Phase 3: Gradual Rollout (2 weeks)

1. Week 1: 50% of traffic
2. Week 2: 100% of traffic
3. Keep legacy code as fallback
4. Continue monitoring metrics

### Phase 4: Cleanup (1 week)

1. Remove legacy pattern matching code
2. Remove feature flags (if stable)
3. Final documentation updates
4. Celebrate! 🎉

### Rollback Plan

If issues occur:

1. **Immediate**: Set `zfc.enabled: false` in config
2. **Selective**: Disable specific decision types
3. **Gradual**: Reduce traffic percentage
4. **Full**: Revert to legacy code completely

Feature flags enable instant rollback without code changes.

---

## Success Metrics

### Primary Metrics (Must Achieve)

1. **Resilience**
   - ✅ Panic rate decreases by >20%
   - ✅ Edge case handling improves (qualitative assessment)
   - ✅ False positive/negative rate decreases

2. **Cost**
   - ✅ Total monthly cost <$50 (stretch: <$20)
   - ✅ >90% of decisions use `mini` tier
   - ✅ No cost runaway scenarios

3. **Performance**
   - ✅ Latency increase <30% (stretch: <20%)
   - ✅ Cache hit rate >40%
   - ✅ No timeout increases

4. **Code Quality**
   - ✅ Remove >1000 lines of pattern matching
   - ✅ Reduce cyclomatic complexity
   - ✅ Improve maintainability scores

### Secondary Metrics (Nice to Have)

1. **Developer Experience**
   - Easier to add new conditions/workflows
   - Less regex debugging
   - Clearer code intent

2. **User Experience**
   - Better error messages
   - Smarter routing
   - Fewer failures

3. **Adaptability**
   - Handles non-English responses
   - Adapts to new error types
   - No code changes for new patterns

---

## Risk Mitigation

### Risk: AI Service Outages

**Mitigation**:

- Feature flag: `fallback_to_legacy: true`
- Keep legacy code until proven stable
- Cache aggressively to reduce dependency
- Circuit breaker: disable ZFC after N failures

### Risk: Unexpected Costs

**Mitigation**:

- Hard budget limits with auto-disable
- Daily cost alerts
- Per-decision cost tracking
- Default to `mini` tier always
- Aggressive caching

### Risk: Accuracy Degradation

**Mitigation**:

- A/B testing phase
- Ground truth validation
- Confidence thresholds
- Human review for low-confidence decisions
- Easy rollback via feature flags

### Risk: Latency Impact

**Mitigation**:

- Async decision-making where possible
- Aggressive caching (5-10 minute TTLs)
- Parallel AI calls when independent
- Timeout protection
- Fast `mini` tier models

### Risk: Team Adoption

**Mitigation**:

- Comprehensive documentation
- Training sessions
- Code review checklist
- Linting tools
- Examples and patterns

---

## Open Questions

1. **Cache invalidation**: When should we invalidate cached decisions?
   - Provider health changes?
   - Config updates?
   - Time-based only?

2. **Confidence thresholds**: What confidence level triggers fallback to legacy?
   - 0.8? 0.9?
   - Per-decision type?

3. **Monitoring**: What dashboards/alerts do we need?
   - Grafana? Built-in?
   - PagerDuty integration?

4. **Testing**: Do we need a ZFC test harness?
   - Mock AI responses?
   - Record/replay?

5. **Documentation**: Who's the audience?
   - Developers only?
   - End users?
   - Operations team?

---

## Next Steps

1. **Team Review** (this document)
   - Discuss approach
   - Validate priorities
   - Adjust timeline
   - Assign owners

2. **Spike: AIDecisionEngine** (1-2 days)
   - Prototype core framework
   - Test with one decision type
   - Validate approach

3. **Go/No-Go Decision**
   - Based on spike results
   - Cost projections
   - Team capacity

4. **Begin Phase 1** (if approved)
   - Create feature branch
   - Start implementation
   - Regular status updates

---

## References

- [ZFC Compliance Assessment](ZFC_COMPLIANCE_ASSESSMENT.md)
- [Thinking Depth Implementation](THINKING_DEPTH_IMPLEMENTATION_PLAN.md)
- [Steve Yegge's ZFC Article](https://steve-yegge.medium.com/zero-framework-cognition-a-way-to-build-resilient-ai-applications-56b090ed3e69)
- [Issue #165](https://github.com/viamin/aidp/issues/165)
- [Issue #157 - Thinking Depth](https://github.com/viamin/aidp/issues/157)
