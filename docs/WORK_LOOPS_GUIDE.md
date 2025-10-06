# Ralph-Style Work Loops Guide

## Overview

AIDP now supports **work loops** - an iterative execution pattern inspired by [Geoffrey Huntley's Ralph technique](https://ghuntley.com/ralph). This transforms AIDP from single-pass step execution into an autonomous loop where the AI agent iteratively works toward completion with automatic testing and linting feedback.

## What are Work Loops?

Work loops enable an AI agent to:

1. **Work iteratively** on a task until it's 100% complete
2. **Self-manage** the PROMPT.md file to track progress
3. **Receive feedback** from automated tests and linters
4. **Self-correct** when tests fail
5. **Iterate** until all acceptance criteria are met

This is fundamentally different from traditional "one-shot" prompting where you send a prompt once and hope for the best.

## How It Works

### The Work Loop Cycle

```
1. AIDP creates PROMPT.md with:
   ├── Task template
   ├── PRD content
   ├── User input/answers
   ├── LLM_STYLE_GUIDE
   └── Instructions for agent

2. Loop until complete:
   ├── Agent reads PROMPT.md
   ├── Agent does work
   ├── Agent updates PROMPT.md itself
   ├── AIDP runs tests
   ├── AIDP runs linters
   ├── If failures: append to PROMPT.md for next iteration
   ├── If success: check if agent marked work complete
   └── If complete + all tests pass: done!

3. Archive PROMPT.md for future reference
```

### Agent Responsibilities

The AI agent is responsible for:

- **Reading** PROMPT.md to understand current state
- **Completing** the work described
- **Editing** PROMPT.md to:
  - Remove completed items
  - Update current status
  - Keep it concise
  - Mark COMPLETE when done
- **Self-correcting** based on test/lint failures

### AIDP's Responsibilities

AIDP (the work loop runner) is responsible for:

- **Creating** initial PROMPT.md
- **Running** tests after each iteration
- **Running** linters after each iteration
- **Appending** failures to PROMPT.md (only failures!)
- **Checking** for completion
- **Archiving** PROMPT.md when done

## Configuration

### Enable Work Loops

Add to your `aidp.yml`:

```yaml
harness:
  work_loop:
    enabled: true
    max_iterations: 50
    test_commands:
      - "bundle exec rspec"
      - "npm test"
    lint_commands:
      - "bundle exec standardrb"
      - "npm run lint"
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable work loops |
| `max_iterations` | integer | `50` | Safety limit for iterations |
| `test_commands` | array | `[]` | Commands to run tests |
| `lint_commands` | array | `[]` | Commands to run linters |

### Test and Lint Commands

- Commands run in your project directory
- Only **failures** are sent back to the agent
- Successful runs don't add to PROMPT.md (keeps it concise)
- Commands can be anything that returns exit code 0 for success

## PROMPT.md Structure

### Initial PROMPT.md

When a work loop starts, AIDP creates PROMPT.md with:

```markdown
# Work Loop: [step_name]

## Instructions
You are working in a Ralph-style work loop. Your responsibilities:
1. Read this PROMPT.md file to understand what needs to be done
2. Complete the work described below
3. **IMPORTANT**: Edit this PROMPT.md file yourself to:
   - Remove completed items
   - Update with current status
   - Keep it concise (remove unnecessary context)
   - Mark the step COMPLETE when 100% done
4. After you finish, tests and linters will run automatically
5. If tests/linters fail, you'll see the errors in the next iteration

## Completion Criteria
Mark this step COMPLETE by adding this line to PROMPT.md:
```

STATUS: COMPLETE

```

## User Input
[Any user answers to questions]

## LLM Style Guide
[Project-specific style guide content]

## Product Requirements (PRD)
[PRD content if available]

## Task Template
[The specific task for this step]
```

### Agent Updates

After each iteration, the agent should update PROMPT.md to reflect:

- ✅ What's been completed (then removed from list)
- 🚧 What's in progress
- 📋 What remains to be done
- ❌ Any blockers or issues

### Completion Marker

The agent signals completion by adding:

```markdown
STATUS: COMPLETE
```

AIDP looks for this marker (case-insensitive) to know the agent considers the work done.

## Example Workflow

### Iteration 1

**PROMPT.md (initial):**

```markdown
# Work Loop: 00_PRD

## Instructions
[Standard instructions...]

## Task Template
Create a Product Requirements Document for the new feature...
Requirements:
- Problem statement
- User stories
- Acceptance criteria
[...]
```

**Agent:** Creates initial PRD, updates PROMPT.md:

```markdown
# Work Loop: 00_PRD

Completed:
- ✅ Problem statement
- ✅ User stories

Remaining:
- Acceptance criteria
- Technical constraints
```

**AIDP:** Runs tests → all pass, runs linters → some failures

### Iteration 2

**PROMPT.md (with failures appended):**

```markdown
# Work Loop: 00_PRD

Completed:
- ✅ Problem statement
- ✅ User stories

Remaining:
- Acceptance criteria
- Technical constraints

---

## Linter Failures
Command: bundle exec standardrb
Exit Code: 1
--- Output ---
docs/prd.md:15:81: Line too long (95 > 80)
```

**Agent:** Fixes linting issues, completes remaining work:

```markdown
# Work Loop: 00_PRD

STATUS: COMPLETE

All PRD sections completed:
- ✅ Problem statement
- ✅ User stories
- ✅ Acceptance criteria
- ✅ Technical constraints
```

**AIDP:** Tests pass ✅, Linters pass ✅, COMPLETE marker found ✅ → Done!

## Comparison: Traditional vs Work Loops

### Traditional Single-Pass

```
User → Send prompt → Agent works → Get result → Hope it's right
                                              ↓
                                        (Often not quite right)
                                              ↓
                                    User manually fixes or re-prompts
```

### Work Loops

```
User → Configure workflow → AIDP creates PROMPT.md
                                      ↓
                            ┌─────────┴─────────┐
                            ↓                   ↑
                       Agent works         Tests fail
                            ↓                   ↑
                     Updates PROMPT.md    Append failures
                            ↓                   ↑
                       AIDP runs tests          │
                            ↓                   ↑
                    All pass + COMPLETE?────────┘
                            ↓
                           Done! ✅
```

## Best Practices

### 1. Keep PROMPT.md Concise

The agent should actively **remove** completed work and unnecessary context to avoid filling up the context window.

**Bad:**

```markdown
# Work Loop: Implementation

Here's everything we discussed...
[10 pages of context]
Still need to implement feature X
```

**Good:**

```markdown
# Work Loop: Implementation

Current: Implementing feature X
Remaining: Tests for feature X

STATUS: COMPLETE when tests pass
```

### 2. Provide Clear Test Commands

Make sure your test commands:

- Run quickly (or use subsets for iteration)
- Have clear failure messages
- Return proper exit codes

```yaml
test_commands:
  - "bundle exec rspec --fail-fast"  # Stop on first failure
  - "npm test -- --bail"             # Stop on first failure
```

### 3. Use Meaningful Step Names

Step names appear in archived PROMPT.md files:

```
.aidp/prompt_archive/
├── 20250105_143022_00_PRD_PROMPT.md
├── 20250105_151133_01_ARCHITECTURE_PROMPT.md
└── 20250105_163044_02_IMPLEMENTATION_PROMPT.md
```

### 4. Set Appropriate max_iterations

- Simple steps: 10-20 iterations
- Complex steps: 30-50 iterations
- Exploratory work: 50-100 iterations

### 5. Create a Good LLM_STYLE_GUIDE

The LLM_STYLE_GUIDE is critical for work loop success. It should be:

- Project-specific
- Concise and scannable
- Full of do's and don'ts
- Based on actual code patterns

## Troubleshooting

### Work Loop Never Completes

**Symptoms:** Max iterations reached without completion

**Causes:**

- Tests are flaky
- Requirements are ambiguous
- Agent doesn't understand task

**Solutions:**

1. Check test reliability
2. Clarify requirements in template
3. Add examples to PROMPT.md
4. Reduce scope of step

### Tests Keep Failing

**Symptoms:** Same test failures across iterations

**Causes:**

- Test requires human input
- Test requires external service
- Agent misunderstands error

**Solutions:**

1. Mock external dependencies
2. Add clearer error messages to tests
3. Update LLM_STYLE_GUIDE with patterns
4. Skip flaky tests temporarily

### PROMPT.md Gets Too Large

**Symptoms:** Performance degrades, agent loses context

**Causes:**

- Agent not removing completed work
- Too much context included initially
- Failure messages accumulating

**Solutions:**

1. Improve agent instructions about conciseness
2. Reduce initial template size
3. Only include recent failures
4. Lower max_iterations

### Agent Marks Complete Prematurely

**Symptoms:** COMPLETE marker added but work not done

**Causes:**

- Acceptance criteria unclear
- Agent doesn't understand scope

**Solutions:**

1. Add explicit checklist to template
2. Make completion criteria more specific
3. Add validation tests

## Advanced Usage

### Custom Completion Detection

Beyond the STATUS: COMPLETE marker, you can check other signals:

- All TODO items removed from PROMPT.md
- Specific files exist (PRD.md, etc.)
- All acceptance criteria checked off

### Iteration Budgets per Step

Different steps may need different iteration limits:

```yaml
# Could be extended to support per-step config
harness:
  work_loop:
    enabled: true
    step_overrides:
      "00_PRD":
        max_iterations: 10
      "16_IMPLEMENTATION":
        max_iterations: 100
```

*(Note: Per-step overrides not yet implemented)*

### Partial Test Runs

For faster iteration, run only relevant tests:

```yaml
test_commands:
  - "bundle exec rspec spec/models"  # Just models for now
  # - "bundle exec rspec"            # Full suite later
```

## Implementation Details

### Key Classes

- **`Aidp::Execute::PromptManager`** - Handles PROMPT.md I/O and archiving
- **`Aidp::Execute::WorkLoopRunner`** - Main loop orchestration
- **`Aidp::Harness::TestRunner`** - Executes tests and linters

### Files Created

| File/Directory | Purpose |
|---------------|---------|
| `PROMPT.md` | Active work prompt (deleted after completion) |
| `.aidp/prompt_archive/` | Archived prompts with timestamps |
| `docs/LLM_STYLE_GUIDE.md` | Project-specific style guide |

### Configuration Schema

Defined in `lib/aidp/harness/config_schema.rb`:

```ruby
work_loop: {
  type: :hash,
  properties: {
    enabled: { type: :boolean, default: true },
    max_iterations: { type: :integer, default: 50, min: 1, max: 200 },
    test_commands: { type: :array, items: { type: :string } },
    lint_commands: { type: :array, items: { type: :string } }
  }
}
```

## References

- [Geoffrey Huntley's Ralph Post](https://ghuntley.com/ralph) - Original Ralph technique
- [GitHub Issue #77](https://github.com/viamin/aidp/issues/77) - Work loops implementation
- [AIDP Configuration Guide](harness-configuration.md) - Full config options

## Summary

Work loops transform AIDP from a linear workflow tool into an autonomous development assistant that iteratively refines its work until completion. By combining:

- **Self-managing prompts** (agent edits PROMPT.md)
- **Automatic testing** (only failures sent back)
- **Iterative refinement** (loop until perfect)

You get a system that can tackle complex, multi-step development tasks with minimal human intervention while maintaining high quality through automated validation.
