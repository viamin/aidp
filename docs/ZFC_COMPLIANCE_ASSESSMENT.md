# Zero Framework Cognition (ZFC) Compliance Assessment

**Issue**: #165 - Evaluate ZFC integration into AIDP

**Created**: 2025-10-25

**Status**: Analysis Complete - Recommendations Pending

---

## Executive Summary

This document assesses AIDP's current architecture against Zero Framework Cognition (ZFC) principles proposed by Steve Yegge. ZFC advocates for delegating all reasoning, decision-making, and semantic analysis to AI models, while keeping orchestration code "dumb" - purely mechanical.

**Key Finding**: AIDP has **9 significant ZFC violations** where local heuristics, scoring formulas, and semantic pattern matching replace AI decision-making. These violations make the system more brittle and less resilient to edge cases.

**Impact**: Moving toward ZFC compliance would improve resilience but increase model call frequency and costs. The recently implemented **Thinking Depth** feature (#157) provides the foundation for cost-optimized ZFC adoption via model pyramids.

**Critical Implementation Rule**: All ZFC decision operations should use the **`mini` tier** (cheapest, fastest) unless accuracy measurements demonstrate otherwise. Most ZFC decisions are simple classifications that don't require expensive models.

---

## Zero Framework Cognition Principles

### Allowed (ZFC-Compliant)

✅ **Pure orchestration**: I/O, plumbing, file operations
✅ **Structural safety checks**: Schema validation, required fields, timeouts, cancellation
✅ **Policy enforcement**: Budgets, rate-limits, confidence thresholds, approval gates
✅ **Mechanical transforms**: Parameter substitution, formatting, compilation of AI data
✅ **State management**: Lifecycle tracking, progress monitoring, journaling, escalation policies
✅ **Typed error handling**: Using SDK error types rather than message parsing

### Forbidden (ZFC-Violations)

❌ **Local reasoning/decision logic**: Ranking, scoring, selection in client code
❌ **Plan/composition/scheduling**: Order, dependencies, retries decided outside model
❌ **Semantic analysis**: Heuristic classification, inference about output
❌ **Quality judgments**: Opinions baked into code rather than delegated to model

### The Correct ZFC Flow

1. **Gather raw context** (I/O only: user intent, files, mission state)

2. **Call AI model for decisions** (classification, selection, ordering, next steps)

3. **Validate structure** (schema, safety, policy enforcement)

4. **Execute mechanically** (run AI's decisions without modifying them)

### Why ZFC Matters

From Steve Yegge's experience building 4 AI-enabled developer productivity tools:

> "ZFC violations make your program brittle. It will panic for no reason, have more failures, retry more often, have lower throughput, higher downtime, and will feel like it has developed a serious attitude problem. Your program will suck."

**The Core Problem**: Pattern matching and heuristics miss edge cases:

- **Language Independence**: Keyword matching ("finished", "done", "complete") fails on non-English output

- **Synonym Blindness**: Misses "ended", "concluded", "finalized" and countless other variations

- **Context Ignorance**: Can't distinguish between "rate limit" in an error vs. a discussion

**Why AI is Better**:

- Handles "a multitude more edge cases" than any pattern can anticipate

- Understands context and nuance that regex cannot

- Adapts to new phrasings without code changes

**Historical Precedent**:

- **Smart Endpoints, Dumb Pipes** (Martin Fowler, 2014): Microservices architectural principle

- **Mechanism vs. Policy** (Unix philosophy): Separation of "how" from "what"

- **Software 2.0** (Andrej Karpathy): Replacing code with models

ZFC is the "AI world's version of similar-looking ideas from the past 30-40 years."

---

## AIDP ZFC Compliance Analysis

### Critical Violations (2)

#### 1. Provider Selection & Load Balancing

**File**: `lib/aidp/harness/provider_manager.rb` (lines 474-602)

**Violation**: Local ranking/scoring formula decides which provider to use

**Current Implementation**:

```ruby
def calculate_provider_load(provider_name)
  stats = @stats[provider_name]
  success_rate = stats[:successful_requests].to_f / total_requests

  # ZFC VIOLATION: Weighted formula encodes decision logic
  load_score = (1 - success_rate) * 100 +
               stats[:avg_response_time] +
               stats[:current_usage]

  load_score
end

def select_provider
  # ZFC VIOLATION: Ranking via min_by without AI input
  available_providers.min_by { |p| calculate_provider_load(p) }
end

```

**Why This Violates ZFC**:

- Encodes opinion about what makes a "good" provider (success rate = 100 weight, response time = 1 weight)

- Decides ranking order without consulting AI

- Hard-coded weights are brittle - don't adapt to context

**ZFC-Compliant Approach**:

```ruby
def select_provider
  context = gather_provider_context

  # Delegate decision to AI
  decision = ai_model.call(
    prompt: "Select the best provider for this request",
    context: context,
    schema: ProviderSelectionSchema
  )

  # Validate structure only
  validate_provider_selection(decision)

  # Execute mechanically
  decision[:provider_name]
end

```

**Impact**: High - This is invoked on every request, making it a hot path

---

#### 2. Model Tier Escalation (Thinking Depth)

**File**: `lib/aidp/harness/thinking_depth_manager.rb` (lines 215-298)

**Violation**: Heuristic thresholds decide when to escalate to more powerful models

**Current Implementation**:

```ruby
def should_escalate_on_complexity?(context)
  thresholds = @configuration.escalation_complexity_threshold

  # ZFC VIOLATION: Assumes file count = complexity
  files_changed = context[:files_changed] || 0
  if thresholds[:files_changed] && files_changed >= thresholds[:files_changed]
    return true
  end

  # ZFC VIOLATION: Hard-coded module count threshold
  modules_touched = context[:modules_touched] || 0
  if thresholds[:modules_touched] && modules_touched >= thresholds[:modules_touched]
    return true
  end

  false
end

def should_escalate_on_failures?(failure_count)
  # ZFC VIOLATION: Hard-coded "2 failures = escalate"
  failure_count >= @configuration.escalation_fail_attempts
end

```

**Why This Violates ZFC**:

- Assumes file count/module count correlate with complexity (often wrong)

- Hard-codes "2 failures means escalate" without understanding failure context

- Doesn't consider error types, task nature, or situational factors

**ZFC-Compliant Approach**:

```ruby
def should_escalate_tier?(context, failure_history)
  # Gather all relevant context
  escalation_context = {
    current_tier: current_tier,
    max_tier: max_tier,
    failure_history: failure_history,
    task_context: context,
    available_models: @registry.models_by_tier
  }

  # Ask AI if escalation is warranted
  decision = ai_model.call(
    prompt: "Should we escalate to a more capable model?",
    context: escalation_context,
    schema: EscalationDecisionSchema
  )

  # Structural validation
  validate_escalation_decision(decision)

  # Execute mechanically
  if decision[:should_escalate]
    escalate_tier(reason: decision[:reasoning])
  end
end

```

**Impact**: High - Affects cost, quality, and model selection strategy

---

### Major Violations (5)

#### 3. Semantic Condition Detection

**File**: `lib/aidp/harness/condition_detector.rb` (lines 155-738)

**Violation**: 150+ regex patterns for semantic classification

**Current Implementation**:

```ruby
RATE_LIMIT_PATTERNS = [
  /rate limit/i,
  /quota exceeded/i,
  /too many requests/i,
  /429/i,
  /throttled/i,
  # ... 20+ more patterns
].freeze

def is_rate_limited?(message)
  # ZFC VIOLATION: Pattern matching for semantic meaning
  RATE_LIMIT_PATTERNS.any? { |pattern| message =~ pattern }
end

COMPLETION_INDICATORS = [
  /all steps completed/i,
  /workflow complete/i,
  /task finished/i,
  /successfully completed/i,
  # ... 30+ more patterns
].freeze

def is_work_complete?(message)
  # ZFC VIOLATION: Infers completion from keywords
  indicator_count = COMPLETION_INDICATORS.count { |p| message =~ p }
  indicator_count >= 2 || progress >= 0.80
end

```

**Why This Violates ZFC**:

- Hard-codes semantic understanding of text

- Brittle - fails on new phrasing or synonyms

- Doesn't understand context (e.g., "rate limit" in a discussion vs actual error)

**ZFC-Compliant Approach**:

```ruby
def detect_conditions(message, context)
  # Ask AI to classify the message
  classification = ai_model.call(
    prompt: "Classify this provider response",
    message: message,
    context: context,
    schema: ConditionClassificationSchema  # Type-safe
  )

  # Structural validation only
  validate_classification(classification)

  # Return AI's classification mechanically
  classification
end

```

**Impact**: Very High - Used throughout the system for critical decisions

---

#### 4. Health Scoring

**File**: `lib/aidp/providers/base.rb` (lines 280-320)

**Violation**: Weighted formula judges provider quality

**Current Implementation**:

```ruby
def health_score
  # ZFC VIOLATION: Hard-coded weights and formula
  success_component = (success_rate * 50).round(2)
  rate_limit_component = ((1 - rate_limit_ratio) * 30).round(2)
  response_time_component = (response_time_score * 0.2).round(2)

  total = success_component + rate_limit_component + response_time_component
  total.clamp(0.0, 100.0)
end

```

**Why This Violates ZFC**:

- Encodes opinion about what "health" means

- Weights are arbitrary (success = 50, rate_limit = 30, response = 0.2)

- Doesn't consider context (some tasks need speed, others need reliability)

**ZFC-Compliant Approach**:

```ruby
def assess_provider_health(provider_stats, context)
  # Let AI judge health considering context
  assessment = ai_model.call(
    prompt: "Assess this provider's health for the given context",
    provider_stats: provider_stats,
    context: context,
    schema: HealthAssessmentSchema
  )

  validate_assessment(assessment)
  assessment
end

```

**Impact**: Medium - Used for monitoring and failover decisions

---

#### 5. Project Analysis Confidence Scoring

**File**: `lib/aidp/init/project_analyzer.rb` (lines 189-230)

**Violation**: Hard-coded weights for framework detection

**Current Implementation**:

```ruby
def calculate_confidence
  # ZFC VIOLATION: Hard-coded weight formula
  file_detection_score = detected_files.size * 0.3
  pattern_match_score = matched_patterns.size * 0.7

  (file_detection_score + pattern_match_score).clamp(0.0, 1.0)
end

def detect_framework
  # ZFC VIOLATION: Pattern matching for semantic detection
  return :rails if File.exist?("Gemfile") && File.exist?("config/routes.rb")
  return :nextjs if File.exist?("next.config.js")
  # ... more pattern matching
end

```

**Why This Violates ZFC**:

- Hard-codes what constitutes "confidence"

- Pattern matching is brittle (false positives/negatives)

- Doesn't understand project context holistically

**ZFC-Compliant Approach**:

```ruby
def analyze_project(project_dir)
  # Gather raw facts
  file_list = Dir.glob("#{project_dir}/**/*")
  sample_files = read_sample_files(file_list)

  # Ask AI to analyze
  analysis = ai_model.call(
    prompt: "Analyze this project structure and detect frameworks",
    file_list: file_list,
    file_samples: sample_files,
    schema: ProjectAnalysisSchema
  )

  validate_analysis(analysis)
  analysis
end

```

**Impact**: Medium - Affects initialization and project understanding

---

#### 6. Error Classification & Recovery

**File**: `lib/aidp/harness/condition_detector.rb` (lines 813-1010)

**Violation**: 40+ patterns classify errors and decide recovery strategy

**Current Implementation**:

```ruby
def classify_error_type(error_message)
  # ZFC VIOLATION: Pattern-based semantic classification
  return :rate_limit if error_message =~ /429|rate limit/i
  return :timeout if error_message =~ /timeout|timed out/i
  return :auth if error_message =~ /unauthorized|forbidden/i
  # ... 40+ more patterns
end

def is_recoverable?(error_type)
  # ZFC VIOLATION: Hard-coded recoverability decisions
  case error_type
  when :rate_limit, :timeout, :network
    true
  when :auth, :validation, :internal
    false
  else
    false
  end
end

def calculate_severity(error_type, context)
  # ZFC VIOLATION: Hard-coded severity mapping
  base_severity = SEVERITY_MAP[error_type] || 5
  base_severity * context[:retry_count]
end

```

**Why This Violates ZFC**:

- Pattern matching misses nuanced error messages

- Recoverability is context-dependent (AI understands this better)

- Severity calculations don't consider full context

**ZFC-Compliant Approach**:

```ruby
def analyze_error(error, context)
  # Delegate error understanding to AI
  analysis = ai_model.call(
    prompt: "Analyze this error and recommend recovery strategy",
    error_message: error.message,
    error_type: error.class.name,
    context: context,
    schema: ErrorAnalysisSchema
  )

  validate_error_analysis(analysis)
  analysis  # Contains: type, severity, recoverable, retry_strategy
end

```

**Impact**: High - Affects reliability and error handling throughout system

---

#### 7. Workflow Selection & Routing

**Files**:

- `lib/aidp/execute/workflow_selector.rb` (lines 45-180)

- `lib/aidp/skills/router.rb` (lines 90-250)

**Violation**: Pattern matching and priority rules route to skills

**Current Implementation**:

```ruby
def select_workflow(task_description)
  # ZFC VIOLATION: Hard-coded routing priority
  workflow = nil

  # Priority 1: Combined patterns
  workflow ||= match_combined_pattern(task_description)

  # Priority 2: Path-based
  workflow ||= match_path_pattern(task_description)

  # Priority 3: Task-based
  workflow ||= match_task_pattern(task_description)

  # Priority 4: Default
  workflow ||= :default_workflow
end

def match_path_pattern(description)
  # ZFC VIOLATION: Regex pattern matching for routing
  return :file_operations if description =~ /file|directory|path/i
  return :code_review if description =~ /review|pr|pull request/i
  # ... more patterns
end

```

**Why This Violates ZFC**:

- Hard-codes routing logic instead of letting AI decide

- Pattern matching is brittle and misses intent

- Priority order is arbitrary

**ZFC-Compliant Approach**:

```ruby
def select_workflow(task_description, context)
  # Ask AI to select the appropriate workflow
  selection = ai_model.call(
    prompt: "Select the most appropriate workflow for this task",
    task: task_description,
    context: context,
    available_workflows: @workflow_registry.all,
    schema: WorkflowSelectionSchema
  )

  validate_workflow_selection(selection)
  selection[:workflow_name]
end

```

**Impact**: Medium - Affects task routing and skill selection

---

### Minor Violations (2)

#### 8. Completion Checker

**File**: `lib/aidp/harness/completion_checker.rb`

**Violation**: Assumes test passing = work complete

**Impact**: Low - Relatively straightforward heuristic

---

#### 9. Test Command Detection

**File**: `lib/aidp/harness/completion_checker.rb`

**Violation**: Pattern matching to identify test commands

**Impact**: Low - Could benefit from AI but not critical

---

## ZFC Compliance Summary

### Violation Breakdown

| Severity | Count | Examples |
|----------|-------|----------|
| Critical | 2 | Provider selection, tier escalation |
| Major | 5 | Condition detection, health scoring, error classification |
| Minor | 2 | Completion checking, test detection |
| **Total** | **9** | |

### Compliance Status

**ZFC-Compliant Areas** ✅:

- State management (checkpoints, journaling)

- Schema validation (configuration, API responses)

- Policy enforcement (rate limits, budgets)

- I/O operations (file handling, git operations)

- Structural transforms (YAML rendering, formatting)

**ZFC-Violation Areas** ❌:

- Decision logic (provider selection, routing)

- Semantic analysis (condition detection, error classification)

- Quality judgments (health scoring, confidence calculation)

- Heuristic thresholds (escalation triggers, completion detection)

---

## Impact Analysis

### Benefits of ZFC Compliance

1. **Increased Resilience**
   - AI handles edge cases better than hard-coded patterns
   - System adapts to new error messages, phrasing, providers without code changes
   - Fewer brittle failure modes

2. **Simpler Codebase**
   - Remove 1000+ lines of pattern matching
   - Eliminate scoring formulas and weight tuning
   - Orchestration layer becomes purely mechanical

3. **Better Decision Quality**
   - AI considers full context, not just isolated metrics
   - Understands nuance (e.g., "rate limit" in discussion vs error)
   - Adapts to new situations without retraining code

4. **Easier Maintenance**
   - No need to update regex patterns for new phrasings
   - No weight tuning when priorities change
   - AI improves as models improve - no code changes needed

### Costs of ZFC Compliance

1. **Increased API Calls**
   - Current: ~10-20 AI calls per work loop
   - ZFC-compliant: ~50-100 AI calls per work loop (5-10x increase)
   - Additional calls for: provider selection, condition detection, error analysis, routing, etc.

2. **Higher Latency**
   - Pattern matching: <1ms
   - AI classification: 100-500ms
   - Total added latency: 5-10 seconds per work loop

3. **Higher Costs**
   - Assuming $3/MTok for standard tier
   - ~500 tokens per decision call
   - 50 extra calls/loop = 25K tokens = $0.075/loop
   - 100 loops/day = $7.50/day = $225/month additional

### Cost Mitigation: Model Pyramids

**The Thinking Depth feature (#157) provides the foundation for cost-optimized ZFC!**

**Strategy**:

- Use `mini` tier (cheap, fast) for simple classifications

- Use `standard` tier for medium complexity decisions

- Use `thinking` tier only for complex reasoning

**Example Cost Optimization**:

```yaml
thinking:
  overrides:
    decision.condition_detection: mini        # Simple: rate limit? completion?
    decision.provider_selection: mini         # Simple: pick from healthy providers
    decision.error_classification: standard   # Medium: understand error context
    decision.escalation_judgment: thinking    # Complex: should we use more power?
    decision.workflow_selection: standard     # Medium: route to appropriate skill

```

**Estimated Costs with Pyramids**:

- 60% of decisions at `mini` tier: $0.15/MTok (80% cheaper)

- 30% of decisions at `standard` tier: $3/MTok (baseline)

- 10% of decisions at `thinking` tier: $15/MTok (5x cost, but only 10% of calls)

**New cost estimate**: $0.075/loop → $0.020/loop (73% reduction)

**Monthly**: $225 → $60 (affordable)

### Critical Rule: Default to `mini` Tier for ZFC Operations

**ZFC operations should ALWAYS use the fastest, cheapest tier unless there's a specific reason not to.**

**Rationale**:

- Most ZFC decisions are simple: "Is this a rate limit error?" → Yes/No
- Simple classifications don't need expensive models
- Volume is high (50-100 calls per work loop) → costs compound rapidly
- Speed matters: pattern matching was <1ms, we need to stay fast

**Default Tier Selection**:

| ZFC Operation | Recommended Tier | Reasoning |
|--------------|-----------------|-----------|
| Condition detection | `mini` | Binary/multi-class classification |
| Error classification | `mini` | Pattern recognition (rate limit, auth, etc.) |
| Completion detection | `mini` | Simple semantic check |
| Provider selection | `mini` | Choose from 3-5 options |
| Health assessment | `mini` | Simple status evaluation |
| Workflow routing | `mini` | Route to one of N workflows |
| Project analysis | `mini` | One-time, but keep cheap |
| Tier escalation | `mini` | Fast decision: escalate or not? |

**When to Use Higher Tiers**:

- `standard`: Only if `mini` tier shows poor accuracy (<90%)
- `thinking`: Only for recursive/complex reasoning (never for simple classification)
- `pro`/`max`: Never for ZFC operations (overkill for decision logic)

**Implementation Pattern**:

```ruby
# Always specify tier explicitly for ZFC operations
def detect_condition(response_text)
  ai_model.call(
    prompt: "Classify this response condition",
    context: { response: response_text },
    schema: ConditionSchema,
    tier: "mini"  # ← EXPLICIT: Keep costs low
  )
end
```

**Cost Impact with mini Tier**:

- Using `mini` ($0.15/MTok) vs `standard` ($3/MTok) = **95% cost reduction**
- 50 calls/loop × 500 tokens × $0.15/MTok = **$0.0037/loop** (vs $0.075)
- Monthly: **$11** vs $225 (20x cheaper)

**Summary Comparison**:

| Approach | API Calls/Loop | Cost/Loop | Monthly Cost (100 loops/day) |
|----------|---------------|-----------|------------------------------|
| Current (patterns only) | 10-20 | $0 | $0 |
| ZFC with `standard` tier | 50-100 | $0.075 | $225 |
| ZFC with mixed pyramid | 50-100 | $0.020 | $60 |
| **ZFC with `mini` tier** | **50-100** | **$0.0037** | **$11** |

**Recommendation**: Use `mini` tier for all ZFC operations. The cost is negligible ($11/month) and makes ZFC adoption financially viable.

---

## Recommendations

### Phase 1: Foundation (Low-Hanging Fruit)

**Priority**: High

**Effort**: 2-3 days

**Impact**: Immediate resilience improvements

1. **Replace Condition Detection with AI Classification**
   - File: `lib/aidp/harness/condition_detector.rb`
   - Remove 150+ regex patterns
   - Use `mini` tier for cost-effective classification
   - Estimated savings: ~800 lines of brittle code

2. **AI-Based Error Analysis**
   - File: Error handling in `condition_detector.rb`
   - Replace 40+ error patterns with AI analysis
   - **Use `mini` tier** - error classification is simple pattern matching
   - Better recovery strategy recommendations

3. **Simple Completion Detection**
   - File: `lib/aidp/harness/completion_checker.rb`
   - Ask AI: "Is this work complete?"
   - Use `mini` tier (cheap, simple yes/no)

### Phase 2: Decision Logic (Core ZFC)

**Priority**: High

**Effort**: 1-2 weeks

**Impact**: Major resilience and maintainability gains

1. **AI-Driven Provider Selection**
   - File: `lib/aidp/harness/provider_manager.rb`
   - Remove load calculation formula
   - Ask AI: "Which provider should handle this request?"
   - **Use `mini` tier** with cached decisions for cost optimization

2. **AI-Driven Tier Escalation**
   - File: `lib/aidp/harness/thinking_depth_manager.rb`
   - Remove heuristic thresholds
   - Ask AI: "Should we escalate to a more capable model?"
   - **Use `mini` tier** for fast, cheap escalation decisions

3. **AI-Based Workflow Routing**
   - Files: `workflow_selector.rb`, `skills/router.rb`
   - Remove pattern matching
   - Ask AI: "Which workflow/skill is best for this task?"
   - **Use `mini` tier** for routing decisions

### Phase 3: Quality Judgments (Polish)

**Priority**: Medium

**Effort**: 3-5 days

**Impact**: Cleaner code, better context-aware decisions

1. **AI-Driven Health Assessment**
   - File: `lib/aidp/providers/base.rb`
   - Remove scoring formula
   - Ask AI: "How healthy is this provider for the current context?"
   - **Use `mini` tier** with periodic refresh

2. **AI-Based Project Analysis**
   - File: `lib/aidp/init/project_analyzer.rb`
   - Remove pattern matching and confidence formulas
   - Ask AI: "Analyze this project structure"
   - **Use `mini` tier** (one-time cost at init, but keep it cheap)

### Phase 4: Documentation & Patterns

**Priority**: Medium

**Effort**: 2-3 days

**Impact**: Prevents future ZFC violations

1. **Create ZFC Guidelines**
   - Document: `docs/ZFC_GUIDELINES.md`
   - Provide examples of compliant vs violated patterns
   - Add to onboarding docs

2. **Add Linting/Checks**
   - Detect pattern matching in decision code
   - Flag hard-coded weights and scoring formulas
   - CI check: "Does this PR introduce ZFC violations?"

---

## Implementation Strategy

### Approach: Incremental Migration

**Don't rewrite everything at once**. Migrate incrementally, measuring impact:

1. **Start with high-impact, low-risk changes** (condition detection, completion checking)

2. **Measure resilience improvements** (fewer panics, better edge case handling)

3. **Monitor costs** (use model pyramids aggressively)

4. **Iterate** based on cost/benefit data

### Success Metrics

**Track these to measure ZFC adoption impact**:

- **Resilience**:
  - Panic rate (should decrease)
  - Edge case handling (should improve)
  - False positive/negative rate (should decrease)

- **Costs**:
  - API calls per work loop
  - Total $ spent on AI decisions
  - Cost per decision type

- **Code Quality**:
  - Lines of pattern matching removed
  - Scoring formula count
  - Code complexity metrics

- **Performance**:
  - Latency per work loop
  - Time spent in decision-making vs execution

### Feature Flag Strategy

**Use feature flags for gradual rollout**:

```yaml
zfc:
  enabled: true

  decisions:
    condition_detection:
      enabled: true
      tier: mini

    provider_selection:
      enabled: false  # Not ready yet
      tier: mini

    tier_escalation:
      enabled: false  # Testing
      tier: thinking

```

This allows A/B testing and rollback if issues arise.

---

## ZFC Integration with Thinking Depth

**The recently completed Thinking Depth feature (#157) is a perfect enabler for ZFC!**

### How They Work Together

1. **ZFC increases AI call frequency** (5-10x more calls)

2. **Thinking Depth provides cost control** (use cheap models for simple decisions)

3. **Model pyramids make ZFC affordable** (60% of decisions at mini tier)

### Configuration Example

```yaml
thinking:
  default_tier: standard
  max_tier: pro

  # ZFC-specific overrides for decision delegation
  overrides:
    # Simple classifications - use mini tier
    decision.is_rate_limited: mini
    decision.is_complete: mini
    decision.is_recoverable: mini
    decision.select_provider: mini

    # Medium complexity - use standard tier
    decision.classify_error: standard
    decision.assess_health: standard
    decision.route_workflow: standard

    # Complex reasoning - use thinking tier
    decision.should_escalate: thinking
    decision.recovery_strategy: thinking

```

### Cost Projection

**Current (pre-ZFC)**: ~10 AI calls/loop × $3/MTok = $0.10/loop

**ZFC without pyramids**: ~100 AI calls/loop × $3/MTok = $1.00/loop (10x cost)

**ZFC with pyramids**: ~100 calls but 60% at mini tier:

- 60 calls × $0.15/MTok = $0.03

- 30 calls × $3/MTok = $0.30

- 10 calls × $15/MTok = $0.50

- **Total**: $0.83/loop

**ZFC with aggressive caching**: ~$0.20-0.40/loop (2-4x current cost, but much more resilient)

---

## Conclusion

**AIDP has 9 significant ZFC violations** that make the system more brittle than it needs to be. Moving toward ZFC compliance would:

✅ **Improve resilience** by delegating reasoning to AI
✅ **Simplify codebase** by removing 1000+ lines of brittle patterns
✅ **Better handle edge cases** that hard-coded logic misses

❌ **Increase costs** by 2-10x without mitigation
❌ **Add latency** of 5-10 seconds per work loop

**Recommendation**: **Pursue ZFC adoption incrementally**, starting with high-impact violations like condition detection. Use the **Thinking Depth model pyramid** to keep costs manageable. The recently completed #157 implementation provides the perfect foundation for cost-effective ZFC compliance.

**Next Steps**:

1. Discuss with team: Is the cost/benefit tradeoff worth it?

2. If yes: Start with Phase 1 (condition detection) as a proof-of-concept

3. Measure impact on resilience and costs

4. Iterate based on data

---

## Appendices

### A. Pattern Matching Statistics

**Total regex patterns across codebase**: ~200+

- Condition detection: 150 patterns

- Error classification: 40 patterns

- Workflow routing: 20 patterns

- Completion detection: 10 patterns

**Lines of code dedicated to pattern matching**: ~1,500 lines

### B. Hard-Coded Formulas

**Scoring formulas identified**: 5

1. Provider load calculation

2. Health score formula

3. Confidence score formula

4. Severity calculation

5. Completion progress threshold (80%)

### C. Decision Points Inventory

**Total decision points where AI could be consulted**: ~30

- Provider selection: 2 decision points

- Condition detection: 8 decision points

- Error handling: 5 decision points

- Workflow routing: 4 decision points

- Tier escalation: 2 decision points

- Health assessment: 3 decision points

- Project analysis: 2 decision points

- Completion checking: 2 decision points

- Others: 2 decision points

### D. Related Issues

- **#157**: Thinking Depth (COMPLETE) - Provides model pyramid foundation

- **#165**: This issue - ZFC integration decision

### E. References

- [Steve Yegge's ZFC Article](https://steve-yegge.medium.com/zero-framework-cognition-a-way-to-build-resilient-ai-applications-56b090ed3e69)

- [Issue #165](https://github.com/viamin/aidp/issues/165)
