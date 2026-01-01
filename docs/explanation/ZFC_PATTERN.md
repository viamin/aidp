# Zero Framework Cognition (ZFC)

## Overview

**Zero Framework Cognition (ZFC)** is an architectural principle for AI-powered applications: delegate all reasoning, decision-making, and semantic analysis to AI models, while keeping orchestration code "dumb" - purely mechanical.

The term comes from [Steve Yegge's article](https://steve-yegge.medium.com/zero-framework-cognition-a-way-to-build-resilient-ai-applications-56b090ed3e69) describing how to build resilient AI applications.

## The Golden Rule

> **If it requires understanding meaning, ask the AI. If it's purely mechanical, keep it in code.**

This simple rule determines where logic should live:

- **Meaning/semantics/judgment** → AI model
- **Mechanical/structural/deterministic** → Code

## ZFC-Compliant Operations

### Allowed in Code

These operations are purely mechanical and belong in code:

- **File operations**: Read, write, parse, format
- **API orchestration**: Request/response handling, routing, retries
- **Data transformation**: JSON mapping, schema validation, type conversion
- **State management**: Lifecycle tracking, progress monitoring, journaling
- **Typed error handling**: Using SDK error types (not message parsing)

### Requires AI (Forbidden in Code)

These operations require understanding meaning and must be delegated to AI:

- **Regex for semantic analysis** - e.g., detecting error types from messages
- **Scoring formulas** - e.g., calculating provider "load" or "quality"
- **Heuristic thresholds** - e.g., "if token count > X, then Y"
- **Keyword matching** - e.g., "if message contains 'error', classify as failure"
- **Natural language classification** - e.g., categorizing user intent

## Decision Tree

```text
Is this operation analyzing meaning or making a judgment?
├─ YES → Use AI (ZFC-compliant)
│   ├─ Examples:
│   │   • "Is this an authentication error?"
│   │   • "Which provider is best for this request?"
│   │   • "Should we retry this operation?"
│   │   • "What's the severity of this issue?"
│   └─ Implementation: AIDecisionEngine.decide(...)
│
└─ NO → Is it purely structural/mechanical?
    ├─ YES → Keep in code (ZFC-compliant)
    │   ├─ Examples:
    │   │   • Validate JSON schema
    │   │   • Check required fields present
    │   │   • Transform data format
    │   │   • Route to correct handler
    │   └─ Implementation: Standard Ruby code
    │
    └─ NO → Reconsider - probably needs AI
```

## Anti-Patterns (ZFC Violations)

### Pattern Matching for Semantic Meaning

```ruby
# ❌ WRONG: Using regex to detect error types
def authentication_error?(error)
  error.message =~ /auth|token|credential|401|forbidden/i
end

# ✅ CORRECT: Ask AI to classify the error
def authentication_error?(error)
  AIDecisionEngine.decide(
    :classify_error,
    context: { message: error.message, code: error.code },
    schema: { type: "boolean" }
  )
end
```

### Scoring Formulas

```ruby
# ❌ WRONG: Hardcoded formula to calculate load
def provider_load(provider)
  (tokens_used.to_f / token_limit) * 0.6 +
    (request_count.to_f / rate_limit) * 0.4
end

# ✅ CORRECT: Let AI assess provider status
def best_provider(request_context)
  AIDecisionEngine.decide(
    :select_provider,
    context: {
      providers: available_providers,
      request: request_context,
      current_usage: usage_stats
    },
    schema: { provider_id: "string", reasoning: "string" }
  )
end
```

### Heuristic Thresholds

```ruby
# ❌ WRONG: Magic number thresholds
def needs_higher_tier?(context)
  context.complexity_score > 7 ||
    context.token_estimate > 50_000 ||
    context.requires_reasoning
end

# ✅ CORRECT: AI evaluates tier requirements
def recommended_tier(context)
  AIDecisionEngine.decide(
    :select_tier,
    context: context.to_h,
    schema: { tier: "string", confidence: "float" }
  )
end
```

### Keyword Matching

```ruby
# ❌ WRONG: Keyword detection for intent
REFACTOR_KEYWORDS = %w[refactor cleanup improve optimize].freeze

def refactoring_task?(task_description)
  REFACTOR_KEYWORDS.any? { |kw| task_description.downcase.include?(kw) }
end

# ✅ CORRECT: AI understands task intent
def task_category(task_description)
  AIDecisionEngine.decide(
    :categorize_task,
    context: { description: task_description },
    schema: { category: "string", subcategory: "string" }
  )
end
```

## Implementation Pattern

Use `AIDecisionEngine` for all ZFC decisions:

```ruby
module Aidp
  module Harness
    class AIDecisionEngine
      # Core interface for ZFC decisions
      def decide(decision_type, context:, schema:, tier: "mini", cache_ttl: nil)
        # 1. Check cache (if cache_ttl specified)
        # 2. Build prompt from decision_type template
        # 3. Call AI with structured output schema
        # 4. Validate response matches schema
        # 5. Cache result (if cache_ttl specified)
        # 6. Return typed result
      end
    end
  end
end
```

### Usage Example

```ruby
class ProviderSelector
  def initialize(decision_engine: AIDecisionEngine.new)
    @decision_engine = decision_engine
  end

  def select_for(request)
    result = @decision_engine.decide(
      :select_provider,
      context: {
        request_type: request.type,
        complexity: request.estimated_complexity,
        available_providers: Provider.available.map(&:to_context),
        user_preferences: request.user&.provider_preferences
      },
      schema: {
        provider_id: { type: "string", required: true },
        reasoning: { type: "string", required: true },
        confidence: { type: "float", minimum: 0, maximum: 1 }
      },
      tier: "mini",
      cache_ttl: 60  # Cache similar decisions for 60 seconds
    )

    Provider.find(result[:provider_id])
  end
end
```

## Testing ZFC Code

Test AI decisions with mock responses:

```ruby
RSpec.describe "ZFC compliance" do
  let(:mock_engine) { instance_double(AIDecisionEngine) }
  let(:selector) { ProviderSelector.new(decision_engine: mock_engine) }

  it "delegates provider selection to AI" do
    allow(mock_engine).to receive(:decide).with(
      :select_provider,
      context: hash_including(:request_type, :available_providers),
      schema: anything,
      tier: "mini",
      cache_ttl: 60
    ).and_return({
      provider_id: "claude",
      reasoning: "Best for complex analysis",
      confidence: 0.92
    })

    result = selector.select_for(complex_request)

    expect(result.id).to eq("claude")
    expect(mock_engine).to have_received(:decide).once
  end
end
```

## Code Review Checklist

When reviewing code, check for ZFC violations:

- [ ] No regex patterns for semantic analysis
- [ ] No hard-coded scoring/ranking formulas
- [ ] No magic number thresholds for decisions
- [ ] No keyword matching for intent detection
- [ ] No if/case statements for semantic classification
- [ ] All judgment calls use `AIDecisionEngine.decide(...)`
- [ ] Appropriate tier selection (usually "mini" for decisions)
- [ ] Caching for repeated similar decisions

## ZFC vs AGD

ZFC and [AI-Generated Determinism (AGD)](AI_GENERATED_DETERMINISM.md) are complementary patterns:

| Aspect | ZFC | AGD |
| ------ | --- | --- |
| **When AI runs** | Every time, at runtime | Once, at configuration time |
| **Runtime cost** | API calls per evaluation | Zero - deterministic execution |
| **Output** | Decision/classification | Code, patterns, or rules |
| **Use case** | Semantic analysis of varying input | Structured output from known tools |
| **Latency** | Higher (AI call per use) | None at runtime |

### When to Use Each

| Use ZFC | Use AGD |
| ------- | ------- |
| Input varies (natural language, user intent) | Input format is stable (tool output) |
| One-off decisions | High-frequency runtime (work loops) |
| Every evaluation needs fresh AI | Patterns can be extracted once |
| Configuration happens infrequently | Runtime performance matters |
| Provider access is expected | May not have provider access at runtime |

**Rule of thumb**: Use ZFC when input semantics change often or when deterministic rules would be brittle. Use AGD when you can extract durable patterns once and need zero AI latency later.

## Migration Strategy

When converting legacy code to ZFC:

1. **Identify the decision**: What semantic judgment is being made?
2. **Define the schema**: What structured output do you need?
3. **Gather context**: What information does the AI need?
4. **Choose tier**: Almost always `mini` for decisions
5. **Add caching**: If the decision is repeated frequently
6. **Test both approaches**: A/B test ZFC vs legacy
7. **Add feature flag**: Enable gradual rollout
8. **Remove legacy code**: Once proven stable

## Benefits

- **Accuracy**: AI understands nuance that regex/heuristics miss
- **Maintainability**: No fragile pattern lists to maintain
- **Adaptability**: AI handles edge cases naturally
- **Consistency**: Same decision logic applies everywhere
- **Observability**: All decisions are logged and auditable

## Costs

- **Latency**: Each decision requires an AI call (~100-500ms)
- **API costs**: Usage-based billing for AI providers
- **Availability**: Depends on AI provider uptime

Mitigate costs with:

- **Caching**: Similar decisions return cached results
- **Batching**: Group multiple decisions into one call
- **Tier selection**: Use "mini" tier for simple decisions
- **AGD hybrid**: Pre-generate patterns for stable inputs

## Related Documentation

- [AI-Generated Determinism (AGD)](AI_GENERATED_DETERMINISM.md) - Complementary pattern
- [LLM Style Guide](../LLM_STYLE_GUIDE.md) - Coding standards for AI agents
- [Style Guide - ZFC Section](../STYLE_GUIDE.md#zero-framework-cognition-zfc) - Detailed rationale
