# AIDP Evaluation & Feedback System

The evaluation system enables users to rate generated outputs (prompts, work units, full work loops) as good, neutral, or bad while capturing rich execution context.

## Overview

Evaluations help track the quality of AI-generated outputs over time, enabling:

- Quality metrics and trend analysis
- Feedback collection for improvement
- Context-aware rating with execution metadata

## Usage

### CLI Commands

#### List Evaluations

```bash
# List recent evaluations
aidp eval list

# List with options
aidp eval list --limit 20
aidp eval list --rating good
aidp eval list --type work_unit
```

#### View Evaluation Details

```bash
aidp eval view <evaluation_id>
```

#### Show Statistics

```bash
aidp eval stats
```

#### Add Evaluation

```bash
# Add rating only
aidp eval add good

# Add rating with comment
aidp eval add bad "Generated code had bugs"

# Neutral rating with explanation
aidp eval add neutral "Acceptable but could be improved"
```

#### Clear Evaluations

```bash
# With confirmation
aidp eval clear

# Force without confirmation
aidp eval clear --force
```

### Watch Mode Evaluations

Rate outputs from watch mode processors (plans, reviews, builds, etc.):

```bash
# Rate a generated plan
aidp eval watch plan owner/repo 123 good "Clear and actionable plan"

# Rate a code review
aidp eval watch review owner/repo 456 bad "Too many false positives"

# Rate a build/implementation
aidp eval watch build owner/repo 123 neutral "Works but could be cleaner"

# Rate a CI fix
aidp eval watch ci_fix owner/repo 789 good "Fixed the issue correctly"

# Rate change request handling
aidp eval watch change_request owner/repo 456 good
```

**Watch target types:**
- `plan` - Issue planning outputs
- `review` - PR review findings
- `build` - Implementation/PR creation
- `ci_fix` - CI failure fixes
- `change_request` - PR change implementations

### REPL Commands

During an interactive work loop, use the `/rate` command:

```
/rate good
/rate bad "The generated code was incorrect"
/rate neutral "Works but not optimal"
```

## Ratings

| Rating | Meaning | Symbol |
|--------|---------|--------|
| good | Helpful, correct, high quality | + |
| neutral | Acceptable, functional but not exceptional | ~ |
| bad | Incorrect, unhelpful, or dysfunctional | - |

## Context Capture

Each evaluation automatically captures rich context:

### Environment Context

- Ruby version
- Platform (OS)
- Git branch
- Git commit (short hash)
- Devcontainer status
- AIDP version

### Work Loop Context

- Current step name
- Iteration number
- Checkpoint data (if available)
  - Status (PASS/FAIL)
  - Metrics

### Prompt Context

- Has prompt file
- Prompt length
- Step name

### Provider Context

- Provider name (if specified)
- Model name (if specified)

## Storage

Evaluations are stored in `.aidp/evaluations/`:

```
.aidp/
  evaluations/
    index.json                    # Quick lookup index
    eval_20241115_123456_abc1.json  # Individual evaluations
    eval_20241115_123512_def2.json
```

### Storage Format

Each evaluation file contains:

```json
{
  "id": "eval_20241115_123456_abc1",
  "rating": "good",
  "comment": "Generated clean, well-structured code",
  "target_type": "work_unit",
  "target_id": "01_INIT",
  "context": {
    "environment": {
      "ruby_version": "3.3.6",
      "platform": "x86_64-linux",
      "branch": "feature-branch",
      "commit": "abc1234"
    },
    "work_loop": {
      "step_name": "01_INIT",
      "iteration": 3
    },
    "timestamp": "2024-11-15T12:34:56Z"
  },
  "created_at": "2024-11-15T12:34:56Z"
}
```

## Configuration

Add to your `.aidp/aidp.yml`:

```yaml
evaluations:
  enabled: true                    # Enable/disable evaluations
  prompt_after_work_loop: false    # Prompt for rating after work loop
  capture_full_context: true       # Capture full context (vs minimal)
  directory: ".aidp/evaluations"   # Storage directory
```

## Target Types

| Type | Description |
|------|-------------|
| prompt | Individual prompt evaluation |
| work_unit | Single work unit execution |
| work_loop | Full work loop cycle |
| step | Specific workflow step |
| plan | Watch mode: issue plan generation |
| review | Watch mode: PR review findings |
| build | Watch mode: implementation/PR creation |
| ci_fix | Watch mode: CI failure fixes |
| change_request | Watch mode: PR change implementation |

## API Usage

```ruby
require "aidp/evaluations"

# Create a record
record = Aidp::Evaluations::EvaluationRecord.new(
  rating: "good",
  comment: "Clean code generated",
  target_type: "work_unit",
  target_id: "01_INIT"
)

# Store it
storage = Aidp::Evaluations::EvaluationStorage.new
result = storage.store(record)

# List evaluations
evaluations = storage.list(limit: 10, rating: "good")

# Get statistics
stats = storage.stats
puts "Good: #{stats[:by_rating][:good]}"
puts "Bad: #{stats[:by_rating][:bad]}"

# Capture context
capture = Aidp::Evaluations::ContextCapture.new
context = capture.capture(step_name: "01_INIT", iteration: 3)
```

## Best Practices

1. **Rate promptly** - Rate outputs soon after generation while context is fresh
2. **Add comments** - Include comments for bad or neutral ratings to provide context
3. **Review stats** - Periodically review `aidp eval stats` to identify patterns
4. **Use target types** - Specify target_type when rating specific components

## Integration with Work Loops

Evaluations integrate with the work loop system:

- Context automatically captures checkpoint data
- Step and iteration information is recorded
- Git branch/commit tracked for reproducibility
