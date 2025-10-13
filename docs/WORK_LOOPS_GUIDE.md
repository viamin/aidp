# Work Loops Guide

## Overview

AIDP now supports **work loops** - an iterative execution pattern inspired by [Geoffrey Huntley's Ralph technique](https://ghuntley.com/ralph). This transforms AIDP from single-pass step execution into an autonomous loop where the AI agent iteratively works toward completion with automatic testing and linting feedback.

## Autonomous Orchestration Layer

Work loops power the new [Fully Automatic Watch Mode](FULLY_AUTOMATIC_MODE.md), an orchestration tier that monitors GitHub issues and launches end-to-end implementation cycles when the `aidp-plan` / `aidp-build` label workflow is used. The watch mode reuses the same fix-forward loop described in this guide while adding:

- Continuous issue monitoring and plan drafting
- Automatic branch creation and seeding of `PROMPT.md`
- Hands-free execution of the `16_IMPLEMENTATION` step
- Pull request creation plus success/failure reporting back to the issue

If you are enabling autonomous operation, review the safety considerations in the watch mode guide before relying on unattended workflows.

## Pre-Loop Setup

Run `aidp init` before the first autonomous loop to generate
`docs/LLM_STYLE_GUIDE.md`, `docs/PROJECT_ANALYSIS.md`, and `docs/CODE_QUALITY_PLAN.md`.
These documents capture project conventions and tooling so every subsequent work
loop has consistent guidance. See [INIT_MODE](INIT_MODE.md) for a full
walkthrough of the bootstrapping process. Use `aidp config --interactive` (see
[SETUP_WIZARD](SETUP_WIZARD.md)) to define the test, lint, and guard settings
that the work loop relies on.

## Guided Workflows (Copilot Mode)

**NEW:** AIDP now includes a **Guided Workflow** feature that acts as your AI copilot to help you choose the right workflow for your needs.

### What is Guided Workflow?

Instead of manually choosing between Analyze and Execute modes and picking specific workflows, the Guided Workflow uses AI to:

1. **Understand your goal** through a conversational interface
2. **Match your intent** to AIDP's capabilities
3. **Recommend the best workflow** with clear reasoning
4. **Handle custom needs** by suggesting step combinations or identifying gaps

### How to Use Guided Workflow

When you start AIDP, you'll see three options:

```
🤖 Guided Workflow (Copilot) - AI helps you choose the right workflow
🔬 Analyze Mode - Analyze your codebase for insights and recommendations
🏗️ Execute Mode - Build new features with guided development workflow
```

Select "Guided Workflow" and simply describe what you want to do:

**Examples:**

- "Build a user authentication feature"
- "Understand how this codebase handles payments"
- "Improve test coverage in my API layer"
- "Create a quick prototype for data export"
- "Modernize this legacy Rails app"

The AI will analyze your request and recommend the most appropriate workflow, explaining why it fits your needs.

### How It Works

1. **You describe your goal** in natural language
2. **AI analyzes** against AIDP's capabilities (documented in `docs/AIDP_CAPABILITIES.md`)
3. **Recommendation** includes:
   - Mode (analyze, execute, or hybrid)
   - Specific workflow
   - Reasoning for the choice
   - Any additional custom steps needed
4. **Confirmation** - You approve or choose an alternative
5. **Details collection** - Guided questions gather any missing information
6. **Workflow execution** - Proceeds with the selected workflow

### Example Session

```
What would you like to do?
> Build a REST API for user authentication

🔍 Analyzing your request...

✨ Recommendation
────────────────────────────────────────────────────────────
Mode: Execute
Workflow: Feature Development

Standard feature that needs architecture design and testing

Reasoning: This is a production feature requiring proper architecture,
security considerations, and comprehensive testing.

This workflow includes:
  • Product requirements
  • Architecture design
  • Testing strategy
  • Static analysis
  • Implementation

Does this workflow fit your needs? (Y/n)
```

### When to Use Guided Workflow

✅ **Use Guided Workflow when:**

- You're new to AIDP and unsure which workflow to choose
- Your task doesn't clearly fit analyze or execute
- You want expert guidance on the right approach
- You need a custom combination of steps

❌ **Use direct mode selection when:**

- You know exactly which workflow you need
- You're running automated/scripted workflows
- You want maximum control over step selection

### Behind the Scenes

The Guided Workflow:

- Uses your configured AI provider (Claude, Gemini, etc.)
- Leverages AIDP's capabilities documentation
- Runs through the existing harness and workflow systems
- Follows all the same rules (LLM_STYLE_GUIDE, work loops, etc.)
- Preserves your context window by keeping prompts concise

### Customization

The AI can recommend:

- **Standard workflows** from Analyze or Execute modes
- **Hybrid workflows** mixing analysis and development
- **Custom step combinations** when standard workflows don't fit
- **New templates** when gaps are identified (you'll be prompted to create them)

All recommendations respect your project's configuration, available providers, and AIDP's core strengths.

## What are Work Loops?

Work loops enable an AI agent to:

1. **Work iteratively** on a task until it's 100% complete
2. **Self-manage** the PROMPT.md file to track progress
3. **Receive feedback** from automated tests and linters
4. **Self-correct** when tests fail
5. **Iterate** until all acceptance criteria are met

This is fundamentally different from traditional "one-shot" prompting where you send a prompt once and hope for the best.

## Fix-Forward Pattern

AIDP uses a **fix-forward** model during implementation. When tests fail, it continues debugging, patching, and re-testing until the Implementation Contract is met — **never rolling back, only moving forward**.

### Fix-Forward Principles

1. **No Rollbacks**: Changes are never reverted. If something breaks, we fix it forward.
2. **Autonomous Iteration**: The system iterates automatically until all tests pass.
3. **Diagnostic Feedback**: Each failure includes diagnostic information to help the agent understand what went wrong.
4. **Cumulative Progress**: Each iteration builds on the previous one, with failures appended as guidance.
5. **Style Guide Reinforcement**: Every 5 iterations, the LLM_STYLE_GUIDE is re-injected to prevent drift from project conventions and ensure failures aren't due to missed adherence to coding standards.

### Fix-Forward State Machine

```
┌─────────────────────────────────────────────────────────────┐
│                    Fix-Forward Work Loop                     │
└─────────────────────────────────────────────────────────────┘

    READY
      │
      ├──────────> APPLY_PATCH
      │              (Agent makes changes)
      │                     │
      │                     v
      │                   TEST
      │          (Run tests & linters)
      │                     │
      │            ┌────────┴────────┐
      │            │                 │
      │           PASS              FAIL
      │            │                 │
      │            │                 v
      │            │             DIAGNOSE
      │            │        (Analyze failures)
      │            │                 │
      │            │                 v
      │            │            NEXT_PATCH
      │            │        (Append failures
      │            │         to PROMPT.md)
      │            │                 │
      │            │                 └─────> (loop back to READY)
      │            │
      │      [Work complete?]
      │            │
      │           YES
      │            │
      │            v
      │          DONE
      │
      └────> (Safety: max iterations)
```

### State Descriptions

| State | Description |
|-------|-------------|
| **READY** | Starting a new iteration, ready to apply changes |
| **APPLY_PATCH** | Agent reads PROMPT.md and applies changes to code |
| **TEST** | Running automated tests and linters |
| **PASS** | Tests passed - check if work is complete |
| **FAIL** | Tests failed - need to diagnose and fix |
| **DIAGNOSE** | Analyzing test failures to provide helpful feedback |
| **NEXT_PATCH** | Appending failure information to PROMPT.md for next iteration |
| **DONE** | All tests pass and agent marked work complete |

### Example Fix-Forward Iteration

**Iteration 1:**

```
READY → APPLY_PATCH → TEST → FAIL → DIAGNOSE → NEXT_PATCH
Agent implements feature → Tests fail → Analyze: 3 test failures → Append to PROMPT.md
```

**Iteration 2:**

```
READY → APPLY_PATCH → TEST → FAIL → DIAGNOSE → NEXT_PATCH
Agent fixes 2 tests → 1 test still fails → Analyze: 1 test failure → Append to PROMPT.md
```

**Iteration 3:**

```
READY → APPLY_PATCH → TEST → PASS → (work not complete) → NEXT_PATCH
Agent fixes last test → All tests pass → But feature incomplete → Continue
```

**Iteration 4:**

```
READY → APPLY_PATCH → TEST → PASS → (work complete) → DONE
Agent completes feature → All tests pass → STATUS: COMPLETE → Success!
```

**Iteration 5 (if needed):**

```
READY → APPLY_PATCH → TEST → FAIL → DIAGNOSE → NEXT_PATCH
[STYLE_GUIDE] Re-injecting LLM_STYLE_GUIDE to prevent drift
Agent sees style guide reminder → Realizes failures due to style violations → Fixes with proper style
```

Notice how we **never rolled back** — each iteration built on the previous work. At iteration 5, the system automatically reminds the agent of the LLM_STYLE_GUIDE to prevent drift from project conventions.

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

## Start from an Issue

AIDP can import GitHub issues to automatically create work loops with structured PROMPT.md files.

### Usage

```bash
# Import by URL
aidp issue import https://github.com/owner/repo/issues/123

# Import by number (when in a git repo)
aidp issue import 123

# Import using shorthand
aidp issue import owner/repo#123

# Start the work loop
aidp execute
```

### Prerequisites

| Method | Requirement | Access |
|--------|-------------|---------|
| **GitHub CLI** | `gh auth login` completed | Private & public repos |
| **Public API** | No authentication needed | Public repos only |

**Recommended**: Install GitHub CLI (`gh`) for full access to private repositories.

### Issue Import Process

1. **Issue Import**: Fetches GitHub issue metadata (title, body, labels, milestone, comments)
2. **PROMPT.md Creation**: Generates structured work loop prompt with:
   - Issue details and description
   - Implementation checklist
   - Completion criteria (`STATUS: COMPLETE`)
   - Reference to original issue URL
3. **Work Loop Ready**: Run `aidp execute` to start autonomous implementation

### Branch Strategy & Checkpoints

When you import a GitHub issue, AIDP can automatically bootstrap your development environment with:

1. **Branch Creation**: Creates feature branch using naming convention `aidp/iss-{number}-{slug}`
2. **Checkpoint Tagging**: Creates initial checkpoint tag `aidp-start/{number}`
3. **Tooling Detection**: Automatically detects and documents test/lint commands in PROMPT.md

#### Branch Bootstrap Process

```bash
# Import issue triggers automatic bootstrap
aidp issue import 123

# Automatically creates:
# - Branch: aidp/iss-123-add-user-authentication
# - Tag: aidp-start/123 (marks starting point)
# - Detects: "bundle exec rspec", "npm test", etc.
```

#### Checkpoint Usage

The initial checkpoint tag serves as a recovery point:

```bash
# Return to starting point if needed
git checkout aidp-start/123

# Create new branch from checkpoint  
git checkout -b aidp/iss-123-alternative aidp-start/123

# Compare current state with start
git diff aidp-start/123..HEAD
```

#### Bootstrap Configuration

Bootstrap behavior can be controlled via environment or configuration:

```bash
# Disable bootstrap temporarily
AIDP_DISABLE_BOOTSTRAP=1 aidp issue import 123

# Or configure in aidp.yml
issue_import:
  bootstrap:
    enabled: false
    branch_prefix: "feature"  # Custom prefix instead of "aidp"
    tag_prefix: "start"       # Custom tag prefix
```

#### Recovery Workflows

If your work loop goes off track, use checkpoints for recovery:

```bash
# Review what changed since start
git log --oneline aidp-start/123..HEAD

# Reset to checkpoint (destructive)
git reset --hard aidp-start/123

# Create recovery branch from checkpoint
git checkout -b aidp/iss-123-recovery aidp-start/123

# Cherry-pick specific commits
git cherry-pick <commit-hash>
```

The bootstrap feature ensures you always have a clean starting point and clear development path for each GitHub issue.

### Generated PROMPT.md Structure

```markdown
# Work Loop: GitHub Issue #123

## Instructions
You are working on a GitHub issue imported into AIDP...

## GitHub Issue Details
**Issue #123**: Feature Request Title
**URL**: https://github.com/owner/repo/issues/123
**State**: OPEN
**Labels**: enhancement, priority-high

## Issue Description
[Original issue body content]

## Implementation Plan
1. [ ] Analyze the requirements
2. [ ] Plan implementation approach
3. [ ] Implement functionality
4. [ ] Add/update tests
5. [ ] Update documentation
6. [ ] Mark STATUS: COMPLETE
```

### Issue Detection

- **Automatic repo detection**: When using issue numbers, AIDP detects the current GitHub repository from git remotes
- **Multiple formats**: Supports URLs, numbers, and shorthand notation
- **Error handling**: Clear messages for invalid identifiers or missing repositories

## Work Loop Configuration

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

**Note**: Style guide reinforcement happens automatically every 5 iterations (hardcoded) to prevent the agent from drifting away from project conventions during long fix-forward loops.

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
You are working in a work loop. Your responsibilities:
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

```text
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

```text
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

**Note:** Per-step overrides not yet implemented

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

## Interactive Control

### Fully Interactive REPL (Async Live Control)

AIDP supports **fully interactive async REPL** during work loop execution. The work loop runs in a background thread while the REPL remains responsive, allowing you to:

- **Pause/Resume/Cancel** work loops in real-time
- **Inject instructions** that merge into next iteration
- **Update configuration** without stopping execution
- **Modify plans** mid-loop with intelligent merging
- **Rollback commits** when needed
- **View streaming output** as work progresses

See [INTERACTIVE_REPL.md](INTERACTIVE_REPL.md) for complete documentation.

**Quick Example:**

```bash
# Work loop running...
aidp[10]> /pause
Work loop paused at iteration 10

aidp[10|PAUSED]> /inject Add error handling for timeout edge case
Instruction queued for next iteration

aidp[10|PAUSED]> /resume
Work loop resumed - instruction will merge at iteration 11
```

### Enable Interactive REPL

In `.aidp.yml`:

```yaml
harness:
  work_loop:
    enabled: true
    interactive_repl: true  # Enable async interactive mode
```

### Running Modes

Work loops can run in different modes depending on your needs:

| Mode | Description | Use Case |
|------|-------------|----------|
| **Interactive** | Full REPL with live control | Active development, debugging |
| **Background** | Autonomous daemon process | Long-running tasks, CI/CD |
| **Attached** | REPL attached to background daemon | Monitor/control running daemon |

See [NON_INTERACTIVE_MODE.md](NON_INTERACTIVE_MODE.md) for background daemon mode and [INTERACTIVE_REPL.md](INTERACTIVE_REPL.md) for interactive features.

---

## REPL Workflow

AIDP's work loops implement a **REPL-style development experience** (Read-Eval-Print-Loop), where you continuously interact with your codebase through AI-driven iterations.

### REPL Workflow Walkthrough

The REPL workflow follows this pattern:

1. **Read**: Agent reads PROMPT.md and current codebase state
2. **Eval**: Agent evaluates what needs to be done and executes changes
3. **Print**: Agent updates PROMPT.md with progress and completion status
4. **Loop**: System runs tests/linters and feeds results back to agent

#### Step-by-Step REPL Process

```text
┌─────────────────────────────────────────────────────────────┐
│                     AIDP REPL Workflow                       │
└─────────────────────────────────────────────────────────────┘

1. READ Phase
   ├── Agent reads PROMPT.md
   ├── Agent scans current codebase
   ├── Agent reviews any previous iteration feedback
   └── Agent understands current task state

2. EVAL Phase
   ├── Agent plans what to implement/fix
   ├── Agent makes code changes
   ├── Agent creates/updates tests
   └── Agent updates documentation

3. PRINT Phase
   ├── Agent updates PROMPT.md with progress
   ├── Agent removes completed items
   ├── Agent notes any discoveries or blockers
   └── Agent marks COMPLETE when done

4. LOOP Phase
   ├── AIDP runs test commands
   ├── AIDP runs lint commands
   ├── AIDP appends any failures to PROMPT.md
   ├── AIDP checks for COMPLETE marker
   └── If not complete: return to READ phase
```

### Interactive REPL Commands

During a work loop session, you can interact with the REPL:

```bash
# Start interactive REPL session
aidp execute --repl

# Monitor progress in real-time
aidp status --watch

# Pause the loop for inspection
aidp pause

# Resume after inspection
aidp resume

# Inject additional requirements
aidp inject "Also add error handling for edge case X"

# Force completion check
aidp check-complete
```

### REPL Benefits

- **Continuous feedback**: Immediate visibility into what's happening
- **Iterative refinement**: Each loop improves on the previous attempt
- **Self-correcting**: Failures automatically feed into next iteration
- **Maintainable state**: PROMPT.md tracks the complete conversation
- **Resumable**: Can pause and resume work loops across sessions

## Fix-Forward Loop Diagram

The Fix-Forward pattern ensures continuous progress without rollbacks:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Fix-Forward Loop                                  │
└─────────────────────────────────────────────────────────────────────────────┘

                            START
                              │
                              ▼
                        ┌──────────┐
                        │  READY   │ ◄────────────────┐
                        └─────┬────┘                  │
                              │                       │
                              ▼                       │
                      ┌──────────────┐                │
                      │ APPLY_PATCH  │                │
                      │ (Agent work) │                │
                      └──────┬───────┘                │
                             │                        │
                             ▼                        │
                       ┌───────────┐                  │
                       │   TEST    │                  │
                       │(Run tests)│                  │
                       └─────┬─────┘                  │
                             │                        │
                    ┌────────┴────────┐               │
                    ▼                 ▼               │
             ┌─────────────┐   ┌─────────────┐        │
             │    PASS     │   │    FAIL     │        │
             └─────┬───────┘   └─────┬───────┘        │
                   │                 │                │
                   ▼                 ▼                │
            ┌─────────────┐   ┌─────────────┐        │
            │Work Complete│   │  DIAGNOSE   │        │
            │   Check?    │   │(Analyze err)│        │
            └─────┬───────┘   └─────┬───────┘        │
                  │                 │                │
          ┌───────┴───────┐         ▼                │
          ▼               ▼   ┌─────────────┐        │
    ┌─────────┐     ┌─────────┐ │ NEXT_PATCH │        │
    │  DONE   │     │ CONTINUE│ │(Append err)│        │
    │   ✓     │     │   WORK  │ └─────┬───────┘        │
    └─────────┘     └─────┬───┘       │                │
                          │           │                │
                          └───────────┴────────────────┘

Legend:
  READY       → Agent prepares for next iteration
  APPLY_PATCH → Agent reads PROMPT.md and makes changes
  TEST        → Automated testing and linting
  PASS        → All tests passed
  FAIL        → Tests failed, need to fix
  DIAGNOSE    → Analyze failures for helpful feedback
  NEXT_PATCH  → Append failure info to PROMPT.md
  DONE        → Work complete and all tests pass
```

### Fix-Forward Guarantees

1. **Never rollback**: Code changes always move forward
2. **Accumulative progress**: Each iteration builds on previous work
3. **Failure learning**: Failures become input for next iteration
4. **Style consistency**: LLM_STYLE_GUIDE re-injected every 5 iterations
5. **Bounded loops**: Safety limit prevents infinite iterations

## Branch/Checkpoint Examples

Work loops support branching and checkpointing for experimental development:

### Checkpoint Strategy

```bash
# Start a work loop with checkpoints enabled
aidp execute --checkpoints

# Automatic checkpoints created at key points:
# - Before each major iteration
# - After successful test runs
# - Before risky refactoring operations
```

### Checkpoint Structure

```text
.aidp/checkpoints/
├── 20250115_143022_iteration_01_ready/
│   ├── code_snapshot.tar.gz
│   ├── PROMPT.md
│   └── metadata.json
├── 20250115_143115_iteration_02_test_pass/
│   ├── code_snapshot.tar.gz
│   ├── PROMPT.md
│   └── metadata.json
└── 20250115_143230_iteration_05_pre_refactor/
    ├── code_snapshot.tar.gz
    ├── PROMPT.md
    └── metadata.json
```

### Branch Workflows

#### Experimental Feature Branch

```bash
# Create experimental branch for risky changes
aidp execute --branch experimental-auth

# Work loop continues on branch
# - All checkpoints saved to branch context
# - Can merge back to main when stable
# - Can abandon branch if experiment fails
```

#### Parallel Development

```bash
# Start multiple work loops on different branches
aidp execute 16_IMPLEMENTATION --branch feature-a &
aidp execute 16_IMPLEMENTATION --branch feature-b &

# Monitor both branches
aidp status --all-branches
```

#### Recovery Examples

```bash
# List available checkpoints
aidp checkpoints list

# Restore to specific checkpoint
aidp restore checkpoint_20250115_143115

# Create branch from checkpoint
aidp branch-from-checkpoint checkpoint_20250115_143115 --name recovery-branch

# Continue work loop from checkpoint
aidp execute --resume-from checkpoint_20250115_143115
```

### Branch Integration

```bash
# When work loop completes successfully
aidp integrate-branch feature-a

# This creates:
# 1. Clean merge commit
# 2. Summary of all changes made
# 3. Archive of complete work loop session
# 4. Links to all checkpoints for future reference
```

## PR Hand-off Instructions

When work loops complete, AIDP can automatically prepare pull request packages:

### Automated PR Preparation

```yaml
# In aidp.yml
pr_handoff:
  enabled: true
  auto_branch: true
  evidence_pack: true
  summary_format: "detailed"  # or "brief"
```

### PR Hand-off Process

1. **Work Loop Completion**
   - Agent marks STATUS: COMPLETE
   - All tests pass
   - Code meets style guide requirements

2. **Automatic Branch Creation**

   ```bash
   # AIDP creates feature branch
   git checkout -b aidp/feature-${timestamp}
   git add -A
   git commit -m "feat: ${work_loop_summary}"
   ```

3. **Evidence Pack Generation**
   - Complete work loop session archive
   - Test results and coverage reports
   - Code quality metrics
   - Performance benchmarks (if configured)

4. **PR Template Generation**

   ```markdown
   ## Work Loop Summary
   
   **Session**: ${session_id}
   **Duration**: ${total_time}
   **Iterations**: ${iteration_count}
   **Tests**: ✅ ${passing_tests} passing
   
   ## Changes Made
   
   - ${change_summary_1}
   - ${change_summary_2}
   - ${change_summary_3}
   
   ## Evidence Pack
   
   📁 `.aidp/evidence_packs/${session_id}/`
   - `session_archive.tar.gz` - Complete work loop session
   - `test_results.xml` - Full test suite results
   - `coverage_report.html` - Code coverage analysis
   - `quality_metrics.json` - Code quality scores
   - `prompt_history.md` - Complete PROMPT.md evolution
   
   ## Quality Assurance
   
   ✅ All tests passing (${test_count} tests)
   ✅ Code style compliant (${style_guide})
   ✅ Coverage above threshold (${coverage_percent}%)
   ✅ Performance benchmarks met
   ✅ Security scan clean
   
   ## Ready for Review
   
   This PR was generated by an AIDP work loop and includes complete
   evidence of the development process. Review the evidence pack for
   full context and validation of all changes.
   ```

### Manual PR Hand-off

```bash
# Generate PR package without auto-push
aidp generate-pr-package

# Review before creating PR
aidp review-pr-package

# Create PR manually with generated template
gh pr create --template .aidp/pr_template.md
```

### PR Hand-off Commands

```bash
# Check if ready for PR
aidp pr-ready-check

# Generate evidence pack only
aidp generate-evidence-pack

# Create PR branch without evidence pack
aidp create-pr-branch --minimal

# Hand-off to human for PR creation
aidp handoff --prepare-pr
```

## Artifact & Evidence Pack Description

AIDP generates comprehensive evidence packs that document the entire development process:

### Evidence Pack Structure

```text
.aidp/evidence_packs/${session_id}/
├── session_metadata.json
├── session_archive.tar.gz
├── development_artifacts/
│   ├── prompt_evolution.md
│   ├── code_changes.diff
│   ├── test_results.xml
│   ├── coverage_report.html
│   ├── lint_results.json
│   └── performance_metrics.json
├── quality_assurance/
│   ├── security_scan.json
│   ├── dependency_audit.json
│   ├── style_compliance.json
│   └── architecture_analysis.md
├── iteration_history/
│   ├── iteration_01_changes.diff
│   ├── iteration_02_changes.diff
│   ├── iteration_03_changes.diff
│   └── ...
└── final_state/
    ├── complete_codebase.tar.gz
    ├── final_tests.xml
    └── deployment_readiness.json
```

### Artifact Types

#### 1. Session Metadata

```json
{
  "session_id": "aidp_20250115_143022_auth_feature",
  "start_time": "2025-01-15T14:30:22Z",
  "end_time": "2025-01-15T16:45:33Z",
  "duration_minutes": 135,
  "iterations": 12,
  "work_loop_type": "16_IMPLEMENTATION",
  "agent_provider": "claude-3-5-sonnet",
  "final_status": "completed",
  "test_results": {
    "total_tests": 156,
    "passing": 156,
    "failing": 0,
    "coverage_percent": 94.2
  },
  "quality_metrics": {
    "style_violations": 0,
    "security_issues": 0,
    "performance_regressions": 0
  }
}
```

#### 2. Prompt Evolution

```markdown
# PROMPT.md Evolution - Session aidp_20250115_143022

## Iteration 1 (14:30:22)
### Initial State
- Task: Implement user authentication system
- Requirements: OAuth2, JWT tokens, user sessions
- Acceptance criteria: [detailed list]

### Agent Progress
- ✅ Created User model
- ✅ Set up OAuth2 configuration
- 🚧 Working on JWT token generation

## Iteration 2 (14:35:45)
### Previous Failures
- JWT secret not configured in test environment
- User validation tests failing

### Agent Progress
- ✅ Fixed JWT configuration
- ✅ All user model tests passing
- 🚧 Implementing session management

[... complete evolution history ...]

## Final State (16:45:33)
### STATUS: COMPLETE
- ✅ Full authentication system implemented
- ✅ All tests passing (156/156)
- ✅ Security audit clean
- ✅ Performance benchmarks met
```

#### 3. Code Quality Evidence

```json
{
  "quality_analysis": {
    "complexity_metrics": {
      "cyclomatic_complexity": 2.3,
      "cognitive_complexity": 1.8,
      "lines_of_code": 1247,
      "test_coverage": 94.2
    },
    "security_analysis": {
      "vulnerabilities": [],
      "security_hotspots": [],
      "security_rating": "A"
    },
    "maintainability": {
      "maintainability_rating": "A",
      "technical_debt_ratio": "0.1%",
      "code_smells": 2
    },
    "reliability": {
      "reliability_rating": "A",
      "bugs": 0,
      "test_success_rate": "100%"
    }
  }
}
```

#### 4. Performance Evidence

```json
{
  "performance_benchmarks": {
    "response_times": {
      "auth_endpoint_p95": "45ms",
      "token_validation_p95": "12ms",
      "session_lookup_p95": "8ms"
    },
    "throughput": {
      "concurrent_logins": 1000,
      "tokens_per_second": 5000
    },
    "resource_usage": {
      "memory_increase": "2.3MB",
      "cpu_overhead": "0.5%"
    }
  }
}
```

### Using Evidence Packs

#### For Code Review

```bash
# Extract evidence pack for review
aidp evidence extract ${session_id}

# Generate review checklist
aidp evidence review-checklist ${session_id}

# Compare with previous implementations
aidp evidence compare ${session_id} ${previous_session_id}
```

#### For Compliance

```bash
# Generate compliance report
aidp evidence compliance-report ${session_id}

# Export for audit
aidp evidence export ${session_id} --format audit-trail

# Verify evidence integrity
aidp evidence verify ${session_id}
```

#### For Documentation

```bash
# Generate development story
aidp evidence story ${session_id}

# Create architecture decision record
aidp evidence adr ${session_id}

# Export for knowledge base
aidp evidence export ${session_id} --format knowledge-base
```

### Evidence Pack Benefits

1. **Complete Traceability**: Every change is documented and justified
2. **Quality Assurance**: Comprehensive testing and validation evidence
3. **Audit Trail**: Full compliance trail for regulated environments
4. **Knowledge Transfer**: Complete context for future developers
5. **Debugging Aid**: Historical context for issue investigation
6. **Process Improvement**: Data for optimizing future work loops

## Future Work Backlog

During work loop execution, AIDP may encounter code that doesn't meet your project's LLM_STYLE_GUIDE, shows technical debt, or presents refactoring opportunities that are unrelated to the current feature being implemented.

Instead of fixing these issues immediately (which could expand scope), AIDP automatically records them in a **Future Work Backlog** for later review and action.

### What Gets Recorded

AIDP captures observations about:

- **Style Violations**: Code that doesn't follow your LLM_STYLE_GUIDE
- **Refactor Opportunities**: Code that could be improved or simplified
- **Technical Debt**: Known issues or workarounds that need addressing
- **TODOs**: Inline comments indicating future work
- **Performance Issues**: Potential bottlenecks or inefficiencies
- **Security Concerns**: Code that may need security review
- **Documentation Needs**: Missing or outdated documentation

### Backlog Storage

Future work items are stored in two formats:

```text
.aidp/
├── future_work.yml      # Machine-readable (for tooling)
└── future_work.md       # Human-readable (for review)
```

### Entry Structure

Each backlog entry includes:

```yaml
- id: fw-1634567890-a1b2c3d4
  type: style_violation
  file: lib/user_service.rb
  lines: "45-60"
  reason: "Method exceeds 15 lines, violates style guide"
  recommendation: "Extract validation logic into separate method"
  priority: medium
  context:
    work_loop: user_authentication
    step: implementation
  created_at: "2025-01-15T14:30:22Z"
  resolved: false
```

### Entry Types

| Type | Description |
|------|-------------|
| `style_violation` | Code doesn't follow LLM_STYLE_GUIDE |
| `refactor_opportunity` | Code could be improved |
| `technical_debt` | Known issues needing attention |
| `todo` | Inline TODO comments found |
| `performance` | Potential performance issues |
| `security` | Security concerns |
| `documentation` | Documentation needed |

### Priority Levels

- **Critical**: Immediate attention required
- **High**: Should be addressed soon
- **Medium**: Normal priority (default)
- **Low**: Nice to have

### When Entries Are Created

AIDP adds entries to the backlog when it detects:

1. **Style Guide Violations** (unrelated to current work)
   - Long methods
   - Complex conditionals
   - Naming convention issues
   - Formatting problems

2. **Code Smells**
   - Duplicated code
   - Large classes
   - Long parameter lists
   - Feature envy

3. **Inline TODOs/FIXMEs**
   - Existing TODO comments
   - FIXME markers
   - HACK comments

### Work Loop Integration

During a work loop, AIDP:

1. **Focuses on Current Feature**: Only fixes issues directly related to the feature being implemented
2. **Records Other Issues**: Adds unrelated issues to the backlog
3. **Avoids Scope Creep**: Doesn't let style fixes expand the work
4. **Summarizes at End**: Shows backlog summary when work loop completes

### Example: During Implementation

```text
Working on: User Authentication Feature

Encountered in lib/legacy_auth.rb:
  - Lines 50-80: Method too long (not part of current feature)
  - Action: Added to backlog as "refactor_opportunity"

Encountered in app/controllers/sessions_controller.rb:
  - Lines 25-30: Auth logic duplicated (affects current feature)
  - Action: Fixed immediately as part of authentication work

Encountered in lib/user.rb:
  - Line 100: TODO: Add email validation
  - Action: Added to backlog as "todo"
```

### Backlog Summary

At the end of a work loop, AIDP displays:

```text
================================================================================
📝 Future Work Backlog Summary
================================================================================

Total Items: 5
Files Affected: 3

By Type:
  Style Violation: 2
  Refactor Opportunity: 2
  TODO: 1

By Priority:
  HIGH: 1
  MEDIUM: 3
  LOW: 1

────────────────────────────────────────────────────────────────────────────────
Review backlog: .aidp/future_work.md
Convert to work loop: aidp backlog convert <entry-id>
================================================================================
```

### Converting Entries to Work Loops

Turn any backlog entry into a new work loop:

```bash
# List backlog entries
cat .aidp/future_work.md

# Convert specific entry to work loop
aidp backlog convert fw-1634567890-a1b2c3d4

# This creates PROMPT.md with:
# - Entry details
# - Recommended fix
# - Acceptance criteria
# - Reference to original context
```

### Example Backlog Entry (Markdown)

```markdown
#### fw-1634567890-a1b2 - lib/user_service.rb

**Lines**: 45-60

**Issue**: Method exceeds 15 lines, violates LLM_STYLE_GUIDE section on method length

**Recommendation**: Extract user validation logic into separate `validate_user_data` method

**Context**: Work Loop: user_authentication, Step: implementation

*Created: 2025-01-15T14:30:22Z*
```

### Managing the Backlog

#### Review Backlog

```bash
# View human-readable backlog
cat .aidp/future_work.md

# View machine-readable backlog
cat .aidp/future_work.yml
```

#### Filter and Query

Using the Ruby API:

```ruby
backlog = Aidp::Execute::FutureWorkBacklog.new(Dir.pwd)

# Filter by type
style_issues = backlog.filter(type: :style_violation)

# Filter by priority
critical_items = backlog.filter(priority: :critical)

# Group by file
by_file = backlog.by_file

# Get summary
summary = backlog.summary
```

#### Mark as Resolved

```bash
# After fixing an issue, mark it resolved
aidp backlog resolve fw-1634567890-a1b2 "Fixed in PR #123"

# Clear all resolved entries
aidp backlog clear-resolved
```

### Configuration

Control backlog behavior in `.aidp.yml`:

```yaml
harness:
  work_loop:
    # Future work backlog settings
    backlog:
      enabled: true
      auto_detect: true  # Automatically detect issues
      capture_todos: true  # Capture inline TODOs
      capture_style: true  # Capture style violations
      min_priority: low  # Minimum priority to record
```

### Backlog Best Practices

#### 1. Review Regularly

```bash
# After each work loop
cat .aidp/future_work.md

# Weekly backlog review
aidp backlog summary
```

#### 2. Prioritize Strategically

- **Critical/High**: Address in next work loop
- **Medium**: Schedule for upcoming sprint
- **Low**: Tackle during refactoring sessions

#### 3. Batch Similar Items

Group related backlog items:

```bash
# Find all style violations in a file
aidp backlog filter --file lib/user.rb --type style_violation

# Create single work loop to fix all
aidp backlog batch lib/user.rb
```

#### 4. Use as Refactoring Backlog

The backlog serves as a natural refactoring TODO list:

- Identifies problem areas
- Tracks technical debt
- Guides improvement efforts
- Documents known issues

#### 5. Reference in PRs

Include backlog summary in PR descriptions:

```markdown
## Implementation

Implemented user authentication feature.

## Future Work Captured

Added 3 items to backlog:
- Style violation in lib/legacy_auth.rb (fw-123-abc)
- Refactoring opportunity in lib/session.rb (fw-123-def)
- TODO in app/controllers/base.rb (fw-123-ghi)

See `.aidp/future_work.md` for details.
```

### LLM_STYLE_GUIDE Integration

The backlog system works closely with your LLM_STYLE_GUIDE:

1. **Style Guide as Reference**: AIDP uses LLM_STYLE_GUIDE to identify violations
2. **Contextual Decisions**: Only fixes style issues related to current work
3. **Systematic Improvement**: Backlog enables gradual style guide adoption
4. **Documentation**: Entry recommendations reference specific style guide sections

Example entry:

```yaml
type: style_violation
reason: "Method length exceeds 15 lines (LLM_STYLE_GUIDE: Methods section)"
recommendation: "Extract validation into separate method per style guide"
```

### Workflow Example

#### Day 1: Feature Implementation

```bash
aidp execute

# During work loop:
# - Implements authentication feature
# - Encounters 5 unrelated style issues
# - Records all 5 in backlog
# - Completes feature without scope creep

# At end:
# ✅ Feature complete
# 📝 5 items added to backlog
```

#### Day 2: Backlog Review

```bash
# Review backlog
cat .aidp/future_work.md

# High priority items identified:
# - fw-123-abc: Security concern in session handling
# - fw-123-def: Performance issue in query

# Create work loops for high priority items
aidp backlog convert fw-123-abc
aidp execute  # Fix security concern

aidp backlog convert fw-123-def
aidp execute  # Fix performance issue
```

#### Weekly: Batch Refactoring

```bash
# Review low-priority style items
aidp backlog filter --priority low --type style_violation

# Create single work loop for batch cleanup
aidp backlog batch-convert --priority low --max-items 10
aidp execute  # Fix 10 style issues at once
```

### Backlog Troubleshooting

#### Too Many Backlog Entries

**Problem**: Backlog grows too large

**Solutions**:

- Adjust `min_priority` to capture fewer items
- Disable `capture_todos` if too noisy
- Regular backlog grooming sessions
- Batch-fix low-priority items

#### Missing Important Issues

**Problem**: Expected issues not captured

**Solutions**:

- Check LLM_STYLE_GUIDE is comprehensive
- Lower `min_priority` threshold
- Enable more capture types
- Manually add entries

#### Duplicate Entries

**Problem**: Same issue recorded multiple times

**Solutions**:

- AIDP automatically deduplicates same file/line/reason
- Clear resolved entries regularly
- Review backlog between work loops

### Implementation Notes

The Future Work Backlog is implemented in:

- `lib/aidp/execute/future_work_backlog.rb` - Core backlog manager
- `.aidp/future_work.yml` - Machine-readable storage
- `.aidp/future_work.md` - Human-readable documentation

### Future Enhancements

Planned improvements:

- [ ] Automatic priority assignment based on code metrics
- [ ] Integration with issue trackers (GitHub, Jira)
- [ ] ML-based detection of refactoring opportunities
- [ ] Backlog analytics and trends
- [ ] Team-wide backlog aggregation
- [ ] Auto-scheduling of backlog work loops

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
