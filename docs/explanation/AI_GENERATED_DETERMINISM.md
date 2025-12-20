# AI-Generated Determinism (AGD)

## Overview

**AI-Generated Determinism (AGD)** is a pattern where AI is used **once during configuration** to generate deterministic code, patterns, or rules that execute **without AI at runtime**.

This is distinct from [Zero Framework Cognition (ZFC)](./ZFC_PATTERN.md), which uses AI for every evaluation at runtime.

## The Two AI Patterns

| Aspect | ZFC (Zero Framework Cognition) | AGD (AI-Generated Determinism) |
| ------ | ------------------------------ | ------------------------------ |
| **When AI runs** | Every time, at runtime | Once, at configuration time |
| **Runtime cost** | API calls per evaluation | Zero - deterministic execution |
| **Output** | Decision/classification | Code, patterns, or rules |
| **Use case** | Semantic analysis of varying input | Structured output from known tools |
| **Latency** | Higher (AI call per use) | None at runtime |
| **Example** | Classify error severity | Generate regex patterns for test output |

## When to Use AGD

Use AGD when:

1. **The input format is stable** - Tool output follows consistent patterns
2. **Configuration happens infrequently** - Setup wizard, initial config, tool updates
3. **Runtime performance matters** - Work loops, high-frequency operations
4. **Patterns can be extracted** - Regular expressions, section markers, keywords
5. **AI understands the domain** - It can analyze example output and derive rules

## When NOT to Use AGD

Use ZFC instead when:

1. **Input is highly variable** - Natural language, user intent, semantic meaning
2. **Context changes frequently** - Each evaluation needs fresh AI reasoning
3. **Rules cannot be expressed deterministically** - Judgment calls, nuanced decisions
4. **Training data is insufficient** - AI needs to reason, not pattern-match

## Implementation Pattern

### 1. Define the Generated Artifact

Create a value object to hold what AI generates:

```ruby
# frozen_string_literal: true

module Aidp
  module Harness
    # Value object holding AI-generated patterns for deterministic execution
    # @see AIFilterFactory for generation
    class FilterDefinition
      attr_reader :summary_patterns, :error_patterns, :location_patterns

      def initialize(summary_patterns:, error_patterns:, **)
        @summary_patterns = compile_patterns(summary_patterns)
        @error_patterns = compile_patterns(error_patterns)
        freeze  # Immutable after creation
      end

      # Deterministic check - no AI needed
      def error_line?(line)
        @error_patterns.any? { |pattern| line.match?(pattern) }
      end

      # Serializable for config storage
      def to_h
        { summary_patterns: @summary_patterns.map(&:source), ... }
      end

      def self.from_hash(hash)
        new(**hash.transform_keys(&:to_sym))
      end
    end
  end
end
```

### 2. Create the AI Factory

The factory uses AI to generate the artifact:

```ruby
# frozen_string_literal: true

module Aidp
  module Harness
    # Uses AI ONCE to generate deterministic filter patterns
    # Generated patterns are stored in config and applied without AI
    class AIFilterFactory
      GENERATION_PROMPT = <<~PROMPT
        Analyze this tool output and generate regex patterns for filtering.

        Tool: {{tool_name}}
        Command: {{tool_command}}
        Sample output:
        {{sample_output}}

        Return JSON with these fields:
        - summary_patterns: regexes matching summary/result lines
        - error_patterns: regexes matching error/failure indicators
        ...
      PROMPT

      def generate_filter(tool_name:, tool_command:, sample_output:, tier:)
        response = call_ai(build_prompt(tool_name, tool_command, sample_output), tier)
        parsed = parse_and_validate(response)
        FilterDefinition.new(**parsed)
      end
    end
  end
end
```

### 3. Create Deterministic Strategy

Apply the generated artifact without AI:

```ruby
# frozen_string_literal: true

module Aidp
  module Harness
    # Deterministic filter using AI-generated patterns
    # NO AI calls at runtime - just pattern matching
    class GeneratedFilterStrategy < FilterStrategy
      def initialize(definition)
        @definition = definition
      end

      def filter(output, filter_instance)
        # Pure deterministic logic using pre-generated patterns
        lines = output.lines
        summary = lines.select { |l| @definition.summary_line?(l) }
        errors = lines.select { |l| @definition.error_line?(l) }
        format_output(summary, errors)
      end
    end
  end
end
```

### 4. Integrate with Configuration

Trigger generation during setup, store in config:

```ruby
# In setup wizard
def configure_filter_generation
  return unless prompt.yes?("Generate filter definitions?")

  factory = AIFilterFactory.new(config)
  definition = factory.generate_from_command(
    tool_command: test_command,
    project_dir: project_dir,
    tier: "mini"  # Use cheap tier - only runs once
  )

  # Store in YAML config for deterministic runtime use
  set([:output_filtering, :filter_definitions, :unit_test], definition.to_h)
end
```

### 5. Load and Use at Runtime

```ruby
# At runtime - no AI calls
def filter_output(raw_output)
  if config.filter_definitions[:unit_test]
    definition = FilterDefinition.from_hash(config.filter_definitions[:unit_test])
    strategy = GeneratedFilterStrategy.new(definition)
    strategy.filter(raw_output, self)  # Deterministic!
  else
    raw_output  # Fallback
  end
end
```

## AGD Checklist

When implementing AGD:

- [ ] **Define the artifact** - What does AI generate? (patterns, rules, code)
- [ ] **Make it serializable** - Can it be stored in YAML/JSON config?
- [ ] **Make it immutable** - Freeze after creation, no runtime modification
- [ ] **Validate AI output** - Check generated patterns are valid (regex syntax, etc.)
- [ ] **Provide regeneration** - Users should be able to regenerate if tool changes
- [ ] **Use cheap AI tier** - Generation is one-time, use "mini" tier to save costs
- [ ] **Log generation** - Record when/what was generated for debugging
- [ ] **Handle missing definitions** - Graceful fallback if not configured

## Examples in AIDP

### 1. Output Filtering (Implemented)

**Problem**: Filter test/lint output to reduce tokens in work loops.

**AGD Solution**:

- `AIFilterFactory` generates `FilterDefinition` during `aidp setup`
- Patterns stored in `.aidp/config.yml`
- `GeneratedFilterStrategy` applies patterns at runtime (no AI)

**Files**:

- `lib/aidp/harness/filter_definition.rb`
- `lib/aidp/harness/ai_filter_factory.rb`
- `lib/aidp/harness/generated_filter_strategy.rb`

### 2. Error Classification (Proposed)

**Problem**: Classify errors from CLI tools when AI agent is unavailable.

**AGD Solution**:

- Generate error classification rules during setup
- Match error patterns deterministically at runtime
- Map to recovery strategies without AI calls

### 3. Commit Message Templates (Proposed)

**Problem**: Generate consistent commit messages matching project style.

**AGD Solution**:

- AI analyzes recent commits during setup
- Generates templates/patterns for conventional commits
- Apply templates deterministically during work loops

## Naming Convention

Files implementing AGD should follow this pattern:

```text
lib/aidp/<domain>/
├── <artifact>_definition.rb      # The generated artifact (value object)
├── ai_<artifact>_factory.rb      # AI-powered generator (runs at config time)
├── generated_<artifact>_strategy.rb  # Deterministic applier (runs at runtime)
```

## Relationship to ZFC

AGD and ZFC are complementary:

```text
┌─────────────────────────────────────────────────────────────┐
│                        AI Usage in AIDP                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Configuration Time                    Runtime               │
│  ─────────────────                    ───────               │
│                                                              │
│  ┌─────────────────┐                 ┌──────────────────┐   │
│  │ AGD             │                 │ Deterministic    │   │
│  │ AI generates    │ ───────────────>│ Code executes    │   │
│  │ patterns/rules  │   stored in     │ without AI       │   │
│  └─────────────────┘   config        └──────────────────┘   │
│                                                              │
│                                       ┌──────────────────┐   │
│                                       │ ZFC              │   │
│                                       │ AI evaluates     │   │
│                                       │ every time       │   │
│                                       └──────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Use AGD when**: Pattern can be extracted once, applied many times.
**Use ZFC when**: Every evaluation requires fresh AI reasoning.

## Testing AGD Components

```ruby
# Test the artifact (unit test)
RSpec.describe FilterDefinition do
  it "matches error lines deterministically" do
    definition = described_class.new(error_patterns: ["ERROR", "FAIL"])

    expect(definition.error_line?("ERROR: failed")).to be true
    expect(definition.error_line?("success")).to be false
  end
end

# Test the factory (mock AI)
RSpec.describe AIFilterFactory do
  it "generates valid definition from AI response" do
    allow(provider).to receive(:send_message).and_return(valid_json)

    definition = factory.generate_filter(tool_name: "pytest", ...)

    expect(definition).to be_a(FilterDefinition)
    expect(definition.summary_patterns).not_to be_empty
  end
end

# Test the strategy (no mocks needed - deterministic)
RSpec.describe GeneratedFilterStrategy do
  it "filters output using definition patterns" do
    definition = FilterDefinition.new(summary_patterns: ["\\d+ passed"])
    strategy = described_class.new(definition)

    result = strategy.filter("5 passed\nother stuff", filter)

    expect(result).to include("5 passed")
    expect(result).not_to include("other stuff")
  end
end
```

## Summary

**AI-Generated Determinism (AGD)** front-loads AI usage to configuration time, generating deterministic artifacts that execute without AI at runtime. This provides:

- **Zero runtime AI cost** - No API calls during work loops
- **Predictable behavior** - Same input always produces same output
- **Lower latency** - No waiting for AI responses
- **Flexibility** - Works for any tool, not just pre-defined ones
- **Transparency** - Generated patterns are visible in config

Use AGD for structured, pattern-based problems. Use ZFC for semantic, judgment-based problems.
