# AIDP Style Guide

Coding standards, architectural patterns, and best practices for the AI Dev Pipeline (AIDP) project.

## Table of Contents

- [Code Organization](#code-organization)
- [Sandi Metz's Rules](#sandi-metzs-rules)
- [Ruby Conventions](#ruby-conventions)
- [Ruby Version Management](#ruby-version-management)
- [Zero Framework Cognition (ZFC)](#zero-framework-cognition-zfc)
- [TTY Toolkit Guidelines](#tty-toolkit-guidelines)
- [Pending Specs Policy](#pending-specs-policy)
- [Testing Guidelines](#testing-guidelines)
- [Error Handling](#error-handling)
- [Concurrency & Threads](#concurrency--threads)
- [Performance](#performance)
- [Security & Safety](#security--safety)
- [Commit Hygiene](#commit-hygiene)
- [Code Review Guidelines](#code-review-guidelines)
- [Prompt Optimization (Intelligent Fragment Selection)](#prompt-optimization-intelligent-fragment-selection)
- [Project-Specific Knowledge Management](#project-specific-knowledge-management)

## Code Organization

### Class Structure

**Prefer small, focused classes over large, complex ones.**

- Break up large classes (like the 2,380-line `UserInterface`) into focused components
- Each class should have a single, well-defined responsibility
- Use composition over inheritance when possible
- Create service objects for complex business logic

### File Organization

```text
lib/aidp/
├── cli.rb                    # Main CLI interface
├── harness/                  # Harness system components
│   ├── runner.rb            # Main orchestrator
│   ├── state_manager.rb     # State management
│   ├── user_interface.rb    # UI components
│   └── providers/           # Provider-specific logic
├── analyze/                 # Analysis mode components
├── execute/                 # Execution mode components
└── providers/               # AI provider integrations
```

### Naming Conventions

- **Classes**: PascalCase (`UserInterface`, `StateManager`)
- **Methods**: snake_case (`collect_feedback`, `handle_error`)
- **Constants**: SCREAMING_SNAKE_CASE (`STATES`, `MAX_RETRIES`)
- **Files**: snake_case (`user_interface.rb`, `state_manager.rb`)

## Sandi Metz's Rules

Follow these rules to maintain clean, maintainable code. **These are guidelines, not hard limits** - it's okay to break them when appropriate or unavoidable, but always consider if the code could be improved by following them.

### 1. Classes Should Be Small

- **About 100 lines per class** (use static analysis tools to enforce hard limits where needed)
- If a class exceeds 100 lines, consider breaking it into smaller, focused classes
- Each class should have one reason to change
- **Exception**: Some classes (like data structures or configuration) may naturally be larger

### 2. Methods Should Be Small

- **About 5 lines per method** (use static analysis tools to enforce hard limits where needed)
- If a method exceeds 5 lines, extract logic into private methods or separate classes
- Methods should do one thing well
- **Exception**: Some methods (like complex algorithms) may naturally be longer

### 3. Parameter Limits

- **Maximum 4 parameters per method**
- If you need more than 4 parameters, consider using a parameter object or hash
- Use keyword arguments for clarity when appropriate
- **Exception**: Some methods (like constructors with many configuration options) may need more parameters

### 4. Controller Simplicity

- **Controllers should instantiate only one object**
- Keep controllers thin - delegate business logic to service objects
- Controllers should only handle HTTP/CLI concerns
- **Exception**: Some controllers may need to coordinate multiple objects for complex workflows

### Example: Breaking Up a Large Method

**Before (violates rules):** 25-line method doing multiple things
**After (follows rules):** 5-line method delegating to focused private methods

```ruby
def collect_feedback(questions, context = nil)
  display_feedback_intro(questions, context)
  responses = process_questions(questions)
  display_completion_summary(responses, questions)
  responses
end
```

## Ruby Conventions

### General Ruby Style

- Follow [StandardRB](https://github.com/testdouble/standard) guidelines
- Use `frozen_string_literal: true` at the top of all files
- Prefer `require_relative` over `require` for local files
- Use meaningful variable and method names
- **No commented-out or dead code** - delete cleanly without explanatory comments
- **No TODO comments** without an issue reference (e.g., `# TODO: Fix edge case - GH#123`)

### Method Design

- Use clear, descriptive method names (`validate_user_input` not `process`)
- Use keyword arguments for clarity (`create_user(name:, email:)`)
- **Avoid `get_` and `set_` prefixes** - use Ruby's idiomatic style:
  - ❌ `get_name`, `set_name(value)`
  - ✅ `name`, `name=(value)` or `name(value)`
- **Avoid boolean flag parameters** that branch behavior - split into separate methods instead
- Follow StandardRB guidelines

### Error Handling

- Use specific error types, not generic `rescue => e`
- Provide meaningful error messages
- Let it crash for internal errors, handle external dependency errors gracefully
- Every `rescue` block must call `rescue_log(:warn, error, context)` to record the failure and preserve troubleshooting context

### Logging Practices

**Use structured logging extensively to make execution traces readable and debuggable.** The project includes a comprehensive `Aidp::Logger` class with automatic secret redaction and structured output.

#### Logging API

```ruby
# Component-based structured logging (preferred)
Aidp.log_debug("component", "message", key: "value", count: 42)
Aidp.log_info("component", "message", user_id: id)
Aidp.log_warn("component", "message", error: e.message)
Aidp.log_error("component", "message", error: e.message, context: data)

# Direct logger access (when needed)
Aidp.logger.debug("component", "message", metadata...)
Aidp.logger.info("component", "message", metadata...)
```

#### When to Log

Log at these key points to create readable execution traces:

- **Method entries**: Log when entering important methods (with key parameters)
- **State transitions**: Log when changing modes, states, or workflows
- **External interactions**: Log API calls, HTTP requests, provider interactions
- **File operations**: Log reads, writes, deletes with filenames
- **Decision points**: Log branching logic and why paths were chosen
- **Loop iterations**: Log progress with counts/identifiers (not every iteration)
- **Completions**: Log when multi-step operations finish

#### Logging Levels

- **`debug`**: Method calls, internal state changes, detailed execution flow
- **`info`**: Significant events, operation completions, user-initiated actions
- **`warn`**: Recoverable errors, degraded functionality, retry attempts
- **`error`**: Failures, exceptions, critical issues that need attention

#### What to Include in Logs

**DO include as metadata:**

- Identifiers (user IDs, job IDs, slugs, names)
- Counts and sizes (file count, byte size, iteration number)
- Status codes and result types
- Filenames and paths (if not sensitive)
- Timing information (elapsed time, duration)

**DON'T log:**

- Secrets, tokens, passwords, API keys (auto-redacted but avoid)
- Full request/response payloads (use summaries: token count, status code)
- Inside tight loops without throttling
- Redundant information already in the message

#### Code Examples

```ruby
# Good: Entry logging with context
def execute_step(step_name)
  Aidp.log_debug("harness", "Executing step", step: step_name)

  result = perform_step(step_name)

  Aidp.log_debug("harness", "Step completed", step: step_name, status: result.status)
  result
end

# Good: State transitions
def switch_workstream(slug)
  Aidp.log_debug("workstream", "Switching context", from: current_workstream, to: slug)
  @current_workstream = slug
  Aidp.log_info("workstream", "Switched to workstream", slug: slug)
end

# Good: External interactions
def fetch_from_provider(prompt)
  Aidp.log_debug("provider", "Making request", provider: @name, prompt_length: prompt.length)

  response = @client.chat(prompt)

  Aidp.log_info("provider", "Received response", provider: @name, tokens: response.tokens)
  response
rescue ProviderError => e
  Aidp.log_error("provider", "Request failed", provider: @name, error: e.message)
  raise
end

# Good: Processing with progress
def process_files(files)
  Aidp.log_debug("processor", "Starting file processing", count: files.size)

  files.each_with_index do |file, idx|
    Aidp.log_debug("processor", "Processing file", index: idx + 1, total: files.size, file: file)
    process_file(file)
  end

  Aidp.log_info("processor", "Completed processing", count: files.size)
end

# Good: Decision point logging
def select_provider(preferences)
  Aidp.log_debug("harness", "Selecting provider", preferences: preferences)

  provider = if preferences[:fast]
    Aidp.log_debug("harness", "Using fast provider")
    FastProvider.new
  else
    Aidp.log_debug("harness", "Using quality provider")
    QualityProvider.new
  end

  Aidp.log_info("harness", "Provider selected", provider: provider.name)
  provider
end
```

#### Log Message Style

- **Concise but actionable**: "Executing step" not "Now we are going to execute the step"
- **Use metadata hash**: Don't interpolate into message string - use metadata hash
- **Consistent component names**: "harness", "provider", "workstream", "cli", "processor", etc.
- **Present tense action verbs**: "Executing", "Processing", "Switching", "Requesting"
- **Include context**: Add metadata that helps trace the execution flow

```ruby
# Good: Metadata in hash
Aidp.log_debug("harness", "Executing step", step: step_name, iteration: 3)

# Bad: Interpolation in message
Aidp.log_debug("harness", "Executing step #{step_name} at iteration 3")
```

#### Common Components

Use these consistent component names across the codebase:

- `harness` - Orchestration and workflow
- `provider` - AI provider interactions
- `workstream` - Parallel workstream operations
- `cli` - Command-line interface
- `repl` - REPL and macros
- `state` - State management
- `processor` - File/data processing
- `kb` - Knowledge base operations
- `analyzer` - Code analysis
- `init` - Project initialization

#### Automatic Secret Redaction

The logger automatically redacts common secret patterns:

- API keys and tokens
- Bearer tokens
- GitHub tokens (ghp_, ghs_)
- AWS keys (AKIA...)
- Password/secret key-value pairs

However, **avoid logging secrets in the first place** - redaction is a safety net, not a primary strategy.

## Ruby Version Management

### mise Usage

**This project uses [mise](https://mise.jdx.dev/) for Ruby version management.** All commands that run Ruby or Bundler must use mise to ensure the correct Ruby version is used.

#### Required Commands

```bash
# ✅ CORRECT: Use mise exec for Ruby commands
mise exec -- ruby script.rb
mise exec -- bundle install
mise exec -- bundle exec rspec
mise exec -- bundle exec aidp --setup-config

# ❌ INCORRECT: Never use system Ruby directly
ruby script.rb                    # Uses system Ruby (wrong version)
bundle install                    # Uses system Ruby's bundler
bundle exec rspec                  # Uses system Ruby
```

#### Why mise?

- **Version consistency**: Ensures all developers and CI use the same Ruby version
- **Project isolation**: Different projects can use different Ruby versions
- **Automatic switching**: mise automatically switches to the correct Ruby version when entering the project directory
- **Tool management**: Can also manage other development tools beyond Ruby

#### Development Workflow

```bash
# Install mise (if not already installed)
curl https://mise.run | sh

# Install project Ruby version (defined in .mise.toml)
mise install

# Run commands through mise
mise exec -- bundle install
mise exec -- bundle exec rspec
mise exec -- ruby bin/aidp --help
```

#### Troubleshooting

If you encounter Ruby version issues:

1. **Check mise is installed**: `mise --version`
2. **Verify Ruby version**: `mise exec -- ruby --version`
3. **Install project Ruby**: `mise install`
4. **Check mise configuration**: `cat .mise.toml`

**Never bypass mise** - it ensures consistent Ruby versions across all environments.

## Zero Framework Cognition (ZFC)

**Zero Framework Cognition (ZFC)** is an architectural principle for AI-powered applications: delegate all reasoning, decision-making, and semantic analysis to AI models, while keeping orchestration code "dumb" - purely mechanical.

### The Golden Rule

> If it requires understanding meaning, ask the AI. If it's purely mechanical, keep it in code.

### ZFC-Compliant Operations

✅ **ALLOWED** - Keep these in code:

- **Pure orchestration**: I/O, plumbing, file operations
- **Structural safety checks**: Schema validation, required fields, timeouts
- **Policy enforcement**: Budgets, rate-limits, confidence thresholds, approval gates
- **Mechanical transforms**: Parameter substitution, formatting, compilation
- **State management**: Lifecycle tracking, progress monitoring, journaling
- **Typed error handling**: Using SDK error types (not message parsing)

### ZFC Violations

❌ **FORBIDDEN** - Delegate these to AI:

- **Local reasoning/decision logic**: Ranking, scoring, selection in client code
- **Plan/composition/scheduling**: Order, dependencies, retries decided outside model
- **Semantic analysis**: Heuristic classification, inference about output
- **Quality judgments**: Opinions baked into code rather than delegated to model
- **Pattern matching for meaning**: Regex/keyword detection for semantic content

### Decision Tree: Should This Be AI or Code?

```text
Is this operation analyzing meaning or making a judgment?
├─ YES → Use AI (ZFC-compliant)
│   ├─ Examples:
│   │   • "Is this an authentication error?"
│   │   • "Which provider is best for this request?"
│   │   • "Is the work complete?"
│   │   • "What type of project is this?"
│   │   • "Should we escalate to a more powerful model?"
│   └─ Implementation: AIDecisionEngine.decide(...)
│
└─ NO → Is it purely structural/mechanical?
    ├─ YES → Keep in code (ZFC-compliant)
    │   ├─ Examples:
    │   │   • Validate JSON schema
    │   │   • Check required fields present
    │   │   • Enforce rate limits
    │   │   • Track state transitions
    │   │   • Format output
    │   └─ Implementation: Normal Ruby code
    │
    └─ NO → Reconsider - probably needs AI
```

### Anti-Patterns (ZFC Violations)

❌ **Pattern Matching for Semantic Meaning**

```ruby
# ❌ BAD: Hard-coded semantic patterns
def detect_rate_limit?(error_message)
  error_message =~ /rate limit|too many requests|quota exceeded/i
end

# ✅ GOOD: Ask AI to classify
def detect_condition(error_message)
  AIDecisionEngine.decide(:condition_detection,
    context: { error: error_message },
    schema: ConditionSchema,
    tier: "mini"
  )
end
```

❌ **Hard-Coded Scoring/Ranking Formulas**

```ruby
# ❌ BAD: Hard-coded provider ranking
def calculate_provider_score(provider)
  (1 - provider.success_rate) * 100 +
    provider.avg_response_time +
    provider.current_usage
end

# ✅ GOOD: Ask AI to select
def select_provider(context)
  AIDecisionEngine.decide(:provider_selection,
    context: gather_provider_context,
    schema: ProviderSelectionSchema,
    tier: "mini",
    cache_ttl: 300  # Cache for 5 minutes
  )
end
```

❌ **Heuristic Thresholds for Decisions**

```ruby
# ❌ BAD: Hard-coded escalation logic
def should_escalate?
  @failure_count > 3 || @task_complexity > 0.7
end

# ✅ GOOD: Ask AI to decide
def should_escalate?(context)
  AIDecisionEngine.decide(:tier_escalation,
    context: {
      failures: @failure_count,
      task: @task_description,
      current_tier: @current_tier
    },
    schema: EscalationSchema,
    tier: "mini"
  )
end
```

❌ **Keyword Matching for Completion**

```ruby
# ❌ BAD: Brittle keyword matching
def work_complete?(response)
  response =~ /done|finished|complete|ended/i
end

# ✅ GOOD: Ask AI to determine
def work_complete?(response)
  result = AIDecisionEngine.decide(:completion_detection,
    context: { response: response, task: @task },
    schema: CompletionSchema,
    tier: "mini"
  )
  result[:complete]
end
```

### Implementation Pattern

Use `AIDecisionEngine` for all ZFC decisions:

```ruby
module Aidp
  module Harness
    class AIDecisionEngine
      # Core interface for ZFC decisions
      def decide(decision_type, context:, schema:, tier: "mini", cache_ttl: nil)
        # 1. Check cache (if cache_ttl specified)
        # 2. Build prompt from decision_type template
        # 3. Call AI with schema validation
        # 4. Validate response structure
        # 5. Cache result (if cache_ttl)
        # 6. Return structured decision
      end
    end
  end
end
```

**Usage**:

```ruby
# Classify error condition
result = engine.decide(:condition_detection,
  context: { error: error_message },
  schema: {
    type: "object",
    properties: {
      condition: {
        type: "string",
        enum: ["rate_limit", "auth_error", "timeout", "success", "other"]
      },
      confidence: { type: "number", minimum: 0.0, maximum: 1.0 }
    },
    required: ["condition", "confidence"]
  },
  tier: "mini"
)

if result[:condition] == "rate_limit"
  handle_rate_limit
end
```

### Cost Management

**CRITICAL**: Always use the cheapest tier unless explicitly justified.

```ruby
# ✅ GOOD: Explicit mini tier for simple decision
AIDecisionEngine.decide(:condition_detection,
  context: context,
  schema: schema,
  tier: "mini"  # Fast and cheap
)

# ❌ BAD: Using expensive tier for simple classification
AIDecisionEngine.decide(:condition_detection,
  context: context,
  schema: schema,
  tier: "thinking"  # Wasteful - simple classification doesn't need deep reasoning
)
```

**Tier Selection Guide**:

| Decision Type | Recommended Tier | Reasoning |
|--------------|-----------------|-----------|
| Condition detection | `mini` | Binary/multi-class classification |
| Error classification | `mini` | Pattern recognition |
| Completion detection | `mini` | Simple semantic check |
| Provider selection | `mini` | Choose from 3-5 options |
| Health assessment | `mini` | Simple status evaluation |
| Workflow routing | `mini` | Route to one of N workflows |
| Tier escalation | `mini` | Fast decision: escalate or not? |

**Only escalate to higher tiers if**:

- `mini` tier shows <90% accuracy on validation set
- Decision requires recursive reasoning (rare)
- Explicit requirement for deeper analysis

### Caching Strategy

Cache repeated decisions aggressively:

```ruby
# Example: Provider selection doesn't change every second
AIDecisionEngine.decide(:provider_selection,
  context: context,
  schema: schema,
  tier: "mini",
  cache_ttl: 300  # 5 minutes - providers don't change that fast
)

# Example: Condition detection is request-specific, no cache
AIDecisionEngine.decide(:condition_detection,
  context: context,
  schema: schema,
  tier: "mini"
  # No cache_ttl - each error is unique
)
```

### Testing ZFC Code

Test AI decisions with mock responses:

```ruby
RSpec.describe "ZFC compliance" do
  it "delegates condition detection to AI" do
    mock_engine = instance_double(AIDecisionEngine)
    allow(mock_engine).to receive(:decide).with(
      :condition_detection,
      context: { error: "Rate limit exceeded" },
      schema: ConditionSchema,
      tier: "mini"
    ).and_return({ condition: "rate_limit", confidence: 0.95 })

    result = detector.detect_condition("Rate limit exceeded")
    expect(result[:condition]).to eq("rate_limit")
  end
end
```

### Code Review Checklist

When reviewing code, check for ZFC violations:

- [ ] No regex patterns for semantic analysis
- [ ] No hard-coded scoring/ranking formulas
- [ ] No heuristic thresholds for decisions
- [ ] No keyword matching for meaning
- [ ] All decisions use `AIDecisionEngine.decide`
- [ ] All AI decisions use `mini` tier by default
- [ ] Schemas defined for all AI responses
- [ ] Appropriate caching for repeated decisions
- [ ] Fallback logic when AI unavailable

### Migration Strategy

When converting legacy code to ZFC:

1. **Identify the decision**: What semantic judgment is being made?
2. **Define the schema**: What structured output do you need?
3. **Gather context**: What information does the AI need?
4. **Choose tier**: Almost always `mini` for decisions
5. **Add caching**: If the decision is repeated frequently
6. **Test both approaches**: A/B test ZFC vs legacy
7. **Add feature flag**: Enable gradual rollout
8. **Remove legacy code**: Once proven stable

### Further Reading

- [ZFC Compliance Assessment](ZFC_COMPLIANCE_ASSESSMENT.md) - Detailed analysis of current violations
- [ZFC Implementation Plan](ZFC_IMPLEMENTATION_PLAN.md) - Migration roadmap
- [Steve Yegge's ZFC Article](https://steve-yegge.medium.com/zero-framework-cognition-a-way-to-build-resilient-ai-applications-56b090ed3e69) - Original concept

## TTY Toolkit Guidelines

### Overview

**Use the [TTY Toolkit](https://ttytoolkit.org/) for all terminal user interface (TUI) elements instead of writing custom TTY methods.** The TTY toolkit provides battle-tested, cross-platform components that handle terminal complexities, edge cases, and user interactions properly.

### Core TTY Components

**Use TTY components instead of custom TTY code:**

```ruby
require "tty-prompt"
require "tty-progressbar"
require "tty-spinner"
require "tty-table"
require "tty-config"
require "tty-logger"
require "pastel"

prompt = TTY::Prompt.new
pastel = Pastel.new

# User-facing output (preferred)
prompt.say("Welcome to the application!")
prompt.say(pastel.green("Success message"))
prompt.say(pastel.red("Error message"))

# Interactive elements
choice = prompt.select("Choose mode", ["Analyze", "Execute"])
selected = prompt.multi_select("Select templates", ["PRD", "Architecture"])
name = prompt.ask("Project name?") { |q| q.required true }

# Progress indicators
bar = TTY::ProgressBar.new("Processing [:bar] :percent", total: 100)
spinner = TTY::Spinner.new("Loading...", format: :dots)

# Data display
table = TTY::Table.new(["Name", "Status"], [["Step 1", "Complete"]])
puts table.render(:unicode)

# Configuration and logging
config = TTY::Config.new
logger = TTY::Logger.new
```

### User Output Best Practices

**For user-facing terminal output:**

```ruby
# ✅ Preferred: TTY::Prompt.say() for user messages
prompt = TTY::Prompt.new
prompt.say("Welcome to the application!")
prompt.say(pastel.green("Success!"))

# ✅ Acceptable: puts + Pastel for simple output
puts pastel.red("Error occurred")

# ❌ Avoid: TTY::Logger for user output (it's for application logging)
logger = TTY::Logger.new
logger.info("This goes to log files, not user terminal")
```

**When to use each:**

- **`TTY::Prompt.say()`** - User-facing messages, status updates, interactive feedback
- **`puts + Pastel`** - Simple output, data display, fallback when TTY::Prompt not available
- **`TTY::Logger`** - Application logging, debugging, error tracking (not user-facing)

### What NOT to Do

**Don't write custom TTY methods** - use TTY components instead:

```ruby
# Bad: Custom implementations
def custom_select(items) # Use tty-prompt instead
def custom_progress_bar(current, total) # Use tty-progressbar instead
def custom_table(data) # Use tty-table instead
```

### Avoid puts and Common Output Methods

**Always use TTY::Prompt for user communication instead of puts, print, or other common methods.**

```ruby
# ❌ Bad: Using puts, print, or other common methods
puts "Welcome to the application!"
print "Enter your name: "
$stdout.puts "Debug message"
STDOUT.puts "Status update"

# ✅ Good: Using TTY::Prompt methods
prompt = TTY::Prompt.new
prompt.say("Welcome to the application!")
name = prompt.ask("Enter your name: ")
prompt.say("Debug message", color: :yellow)
prompt.say("Status update", color: :green)
```

**Why use TTY::Prompt instead of puts?**

- **Consistent styling**: TTY::Prompt provides consistent colors, formatting, and styling
- **Better UX**: Interactive elements with arrow key navigation, validation, and error handling
- **Cross-platform compatibility**: Handles terminal differences across operating systems
- **Accessibility**: Built-in support for screen readers and accessibility features
- **Testing**: Easier to mock and test than raw output methods

**When TTY::Prompt is not available (rare cases):**

```ruby
# Only use puts + Pastel as a fallback when TTY::Prompt is not available
require "pastel"
pastel = Pastel.new
puts pastel.green("Success message")
puts pastel.red("Error message")
```

### Testing Interactive TUI Elements

**Use `expect` for testing interactive TUI elements** since `bundle exec aidp` requires live user interaction that cannot be automated with standard RSpec.

### Testing with tmux

**Use tmux for testing TUIs and long-running processes** to enable programmatic interaction and inspection.

#### When to Use tmux for Testing

- **TUI applications**: Capture and verify terminal output programmatically
- **Long-running processes**: Servers, daemons, watch modes
- **Interactive CLIs**: Applications requiring user input
- **Integration tests**: End-to-end testing of terminal applications

#### tmux Testing Pattern

```bash
# Create a new tmux session for testing
tmux new-session -d -s test_session

# Send multiple commands efficiently (batched)
tmux send-keys -t test_session "cd /workspace/aidp" Enter \
  "bundle exec aidp" Enter \
  "1" Enter  # Select first option

# Capture output for verification
tmux capture-pane -t test_session -p > output.txt

# Verify expected content
grep "Expected output" output.txt

# Clean up
tmux kill-session -t test_session
```

#### Batch Commands with send-keys

**Always batch commands when possible** to reduce overhead and improve test reliability:

```bash
# ✅ Good: Batch multiple commands
tmux send-keys -t test_session \
  "export API_KEY=test" Enter \
  "bundle exec rails server" Enter \
  "C-c" \
  "exit" Enter

# ❌ Bad: Multiple send-keys calls
tmux send-keys -t test_session "export API_KEY=test" Enter
tmux send-keys -t test_session "bundle exec rails server" Enter
tmux send-keys -t test_session "C-c"
tmux send-keys -t test_session "exit" Enter
```

**Benefits of batching:**

- Faster execution (fewer IPC calls to tmux)
- More reliable (atomic operation)
- Easier to read and maintain
- Reduces race conditions

#### Long-Running Processes

**Use tmux for servers and background processes** to enable easy interaction and cleanup:

```bash
# Start server in tmux session
tmux new-session -d -s app_server "bundle exec rails server"

# Run tests against the server
bundle exec rspec spec/integration/

# Check server logs
tmux capture-pane -t app_server -p | tail -n 50

# Send Ctrl-C to stop server
tmux send-keys -t app_server C-c

# Wait for graceful shutdown
sleep 2

# Kill session if still alive
tmux kill-session -t app_server 2>/dev/null || true
```

#### Verifying TUI Output

```bash
# Start TUI application
tmux new-session -d -s tui_test "bundle exec aidp"

# Interact with TUI
tmux send-keys -t tui_test "1" Enter  # Select option 1

# Wait for rendering
sleep 0.5

# Capture and verify output
tmux capture-pane -t tui_test -p > /tmp/tui_output.txt

if grep -q "Expected menu item" /tmp/tui_output.txt; then
  echo "✓ Test passed"
else
  echo "✗ Test failed"
  cat /tmp/tui_output.txt
  exit 1
fi

# Cleanup
tmux kill-session -t tui_test
```

#### Integration with RSpec

```ruby
# spec/system/tui_tmux_spec.rb
RSpec.describe "TUI with tmux" do
  let(:session_name) { "test_#{Process.pid}" }

  after do
    system("tmux kill-session -t #{session_name} 2>/dev/null")
  end

  it "displays the main menu" do
    # Start TUI in tmux
    system("tmux new-session -d -s #{session_name} 'bundle exec aidp'")
    sleep 0.5

    # Capture output
    output = `tmux capture-pane -t #{session_name} -p`

    # Verify menu is displayed
    expect(output).to include("Choose your mode")
    expect(output).to include("Analyze")
    expect(output).to include("Execute")
  end

  it "handles mode selection" do
    # Start and interact with TUI
    system("tmux new-session -d -s #{session_name} 'bundle exec aidp'")
    system("tmux send-keys -t #{session_name} '1' Enter")
    sleep 1

    output = `tmux capture-pane -t #{session_name} -p`
    expect(output).to include("Starting in Analyze Mode")
  end
end
```

#### tmux Testing Best Practices

1. **Use unique session names**: Include PID or timestamp to avoid conflicts
2. **Always cleanup**: Use `after` hooks or ensure blocks to kill sessions
3. **Add sleep delays**: Allow time for rendering and processing
4. **Batch commands**: Use single send-keys with multiple commands
5. **Capture strategically**: Use `-p` for printing, `-S` for scrollback
6. **Handle failures gracefully**: Use `2>/dev/null || true` for cleanup commands

#### Common tmux Commands for Testing

```bash
# Create session
tmux new-session -d -s <name> [command]

# Send keys (batch multiple with backslash)
tmux send-keys -t <name> "command" Enter "another" Enter

# Capture pane output
tmux capture-pane -t <name> -p              # Print to stdout
tmux capture-pane -t <name> -p -S -1000     # Include scrollback

# List sessions
tmux list-sessions

# Kill session
tmux kill-session -t <name>

# Send signal
tmux send-keys -t <name> C-c  # Ctrl-C
tmux send-keys -t <name> C-d  # Ctrl-D (EOF)
```

### AI Coding Agent TUI Testing Guidelines

**Important**: AI agents **cannot** test by running `bundle exec aidp` directly (requires live user interaction). Use these approaches instead:

#### 1. Unit Testing with Dependency Injection

```ruby
# Use TestPrompt for testing TTY components
let(:test_prompt) { TestPrompt.new }
let(:ui) { described_class.new(prompt: test_prompt) }

# Test interactions by checking recorded messages
ui.display_menu("Choose mode", items)
expect(test_prompt.messages.any? { |msg| msg[:message].include?("Choose mode") }).to be true
```

#### 2. Integration Testing with expect Scripts

```expect
#!/usr/bin/expect -f
spawn bundle exec aidp
expect "Choose your mode"
send "\r"
expect "Starting in Analyze Mode"
send "\003"
expect eof
```

#### 3. Testing TUI Logic

```ruby
# Mock TUI interactions
allow(tui).to receive(:single_select).and_return("Web Application")
allow(tui).to receive(:ask).and_return("my-app")
result = selector.select_workflow(harness_mode: false, mode: :execute)
```

#### Key Principles for AI Agents

1. **Never test by running `bundle exec aidp`** - requires live user interaction
2. **Mock TTY components** - use `instance_double` and `allow().to receive()`
3. **Test logic, not interaction** - focus on business logic and state management
4. **Use expect scripts** - for integration testing of full user flows
5. **Use tmux** - for programmatic TUI testing and long-running processes
6. **Test error handling** - ensure graceful handling of interrupts

#### Testing with tmux

**Use tmux for testing TUIs and long-running processes** to enable programmatic interaction and inspection.

##### When to Use tmux for Testing

- **TUI applications**: Capture and verify terminal output programmatically
- **Long-running processes**: Servers, daemons, watch modes
- **Interactive CLIs**: Applications requiring user input
- **Integration tests**: End-to-end testing of terminal applications

##### tmux Testing Pattern

```bash
# Create a new tmux session for testing
tmux new-session -d -s test_session

# Send multiple commands efficiently (batched)
tmux send-keys -t test_session "cd /workspace/aidp" Enter \
  "bundle exec aidp" Enter \
  "1" Enter  # Select first option

# Capture output for verification
tmux capture-pane -t test_session -p > output.txt

# Verify expected content
grep "Expected output" output.txt

# Clean up
tmux kill-session -t test_session
```

##### Batch Commands with send-keys

**Always batch commands when possible** to reduce overhead and improve test reliability:

```bash
# ✅ Good: Batch multiple commands
tmux send-keys -t test_session \
  "export API_KEY=test" Enter \
  "bundle exec rails server" Enter \
  "C-c" \
  "exit" Enter

# ❌ Bad: Multiple send-keys calls
tmux send-keys -t test_session "export API_KEY=test" Enter
tmux send-keys -t test_session "bundle exec rails server" Enter
tmux send-keys -t test_session "C-c"
tmux send-keys -t test_session "exit" Enter
```

**Benefits of batching:**

- Faster execution (fewer IPC calls to tmux)
- More reliable (atomic operation)
- Easier to read and maintain
- Reduces race conditions

##### Long-Running Processes

**Use tmux for servers and background processes** to enable easy interaction and cleanup:

```bash
# Start server in tmux session
tmux new-session -d -s app_server "bundle exec rails server"

# Run tests against the server
bundle exec rspec spec/integration/

# Check server logs
tmux capture-pane -t app_server -p | tail -n 50

# Send Ctrl-C to stop server
tmux send-keys -t app_server C-c

# Wait for graceful shutdown
sleep 2

# Kill session if still alive
tmux kill-session -t app_server 2>/dev/null || true
```

##### Verifying TUI Output

```bash
# Start TUI application
tmux new-session -d -s tui_test "bundle exec aidp"

# Interact with TUI
tmux send-keys -t tui_test "1" Enter  # Select option 1

# Wait for rendering
sleep 0.5

# Capture and verify output
tmux capture-pane -t tui_test -p > /tmp/tui_output.txt

if grep -q "Expected menu item" /tmp/tui_output.txt; then
  echo "✓ Test passed"
else
  echo "✗ Test failed"
  cat /tmp/tui_output.txt
  exit 1
fi

# Cleanup
tmux kill-session -t tui_test
```

##### Integration with RSpec

```ruby
# spec/system/tui_tmux_spec.rb
RSpec.describe "TUI with tmux" do
  let(:session_name) { "test_#{Process.pid}" }

  after do
    system("tmux kill-session -t #{session_name} 2>/dev/null")
  end

  it "displays the main menu" do
    # Start TUI in tmux
    system("tmux new-session -d -s #{session_name} 'bundle exec aidp'")
    sleep 0.5

    # Capture output
    output = `tmux capture-pane -t #{session_name} -p`

    # Verify menu is displayed
    expect(output).to include("Choose your mode")
    expect(output).to include("Analyze")
    expect(output).to include("Execute")
  end

  it "handles mode selection" do
    # Start and interact with TUI
    system("tmux new-session -d -s #{session_name} 'bundle exec aidp'")
    system("tmux send-keys -t #{session_name} '1' Enter")
    sleep 1

    output = `tmux capture-pane -t #{session_name} -p`
    expect(output).to include("Starting in Analyze Mode")
  end
end
```

##### tmux Testing Best Practices

1. **Use unique session names**: Include PID or timestamp to avoid conflicts
2. **Always cleanup**: Use `after` hooks or ensure blocks to kill sessions
3. **Add sleep delays**: Allow time for rendering and processing
4. **Batch commands**: Use single send-keys with multiple commands
5. **Capture strategically**: Use `-p` for printing, `-S` for scrollback
6. **Handle failures gracefully**: Use `2>/dev/null || true` for cleanup commands

##### Common tmux Commands for Testing

```bash
# Create session
tmux new-session -d -s <name> [command]

# Send keys (batch multiple with backslash)
tmux send-keys -t <name> "command" Enter "another" Enter

# Capture pane output
tmux capture-pane -t <name> -p              # Print to stdout
tmux capture-pane -t <name> -p -S -1000     # Include scrollback

# List sessions
tmux list-sessions

# Kill session
tmux kill-session -t <name>

# Send signal
tmux send-keys -t <name> C-c  # Ctrl-C
tmux send-keys -t <name> C-d  # Ctrl-D (EOF)
```

#### Setting Up expect Tests

```bash
# Install expect (macOS)
brew install expect

# Install expect (Ubuntu/Debian)
sudo apt-get install expect
```

#### Example expect Test Script

```expect
#!/usr/bin/expect -f

# Test the mode selection interface
spawn bundle exec aidp

# Wait for the prompt
expect "Choose your mode"

# Send down arrow to select second option
send "\033\[B"

# Send enter to confirm selection
send "\r"

# Wait for the next prompt or completion
expect "Starting in Execute Mode"

# Exit cleanly
send "\003"
expect eof
```

#### Integration with RSpec

```ruby
# spec/system/tui_interaction_spec.rb
RSpec.describe "TUI Interactions" do
  describe "mode selection" do
    it "allows user to select analyze mode" do
      result = system("expect -f spec/support/expect_scripts/select_analyze_mode.exp")
      expect(result).to be true
    end

    it "allows user to select execute mode" do
      result = system("expect -f spec/support/expect_scripts/select_execute_mode.exp")
      expect(result).to be true
    end

    it "handles Ctrl+C gracefully" do
      result = system("expect -f spec/support/expect_scripts/ctrl_c_exit.exp")
      expect(result).to be true
    end
  end
end
```

#### expect Script Best Practices

```expect
# Good: Clear, descriptive expect scripts
#!/usr/bin/expect -f

# Test multiselect with space bar
spawn bundle exec aidp

expect "Select templates to use"

# Navigate to first item and select with space
send "\033\[B"  # Down arrow
send " "        # Space to select

# Navigate to third item and select with space
send "\033\[B"  # Down arrow
send "\033\[B"  # Down arrow
send " "        # Space to select

# Confirm selection
send "\r"

expect "Selected: 2 items"
```

### TTY Component Selection Guide

| Use Case | TTY Component | Example |
|----------|---------------|---------|
| Single selection | `tty-prompt#select` | Mode selection, file picking |
| Multi-selection | `tty-prompt#multi_select` | Template selection, feature flags |
| Text input | `tty-prompt#ask` | Project name, API keys |
| Confirmation | `tty-prompt#yes?` | Destructive operations |
| Progress tracking | `tty-progressbar` | File processing, API calls |
| Indeterminate progress | `tty-spinner` | Loading states |
| Data tables | `tty-table` | Results display, status reports |
| Rich text | `tty-markdown` | Documentation, help text |
| Configuration | `tty-config` | Settings management |
| File operations | `tty-file` | Template copying, file creation |
| Cursor control | `tty-cursor` | Custom layouts (use sparingly) |
| Screen info | `tty-screen` | Responsive layouts |
| Structured logging | `tty-logger` | Application logging |

### TUI Component Organization

**Organize TUI components by responsibility, using TTY components as building blocks:**

```ruby
class QuestionCollector
  def initialize(tty_components = {})
    @prompt = tty_components[:prompt] || TTY::Prompt.new
    @logger = tty_components[:logger] || TTY::Logger.new
  end

  def collect_questions(questions)
    questions.map.with_index do |question, index|
      case question[:type]
      when "choice"
        @prompt.select("Question #{index + 1}: #{question[:text]}", question[:options])
      when "multiselect"
        @prompt.multi_select("Question #{index + 1}: #{question[:text]}", question[:options])
      else
        @prompt.ask("Question #{index + 1}: #{question[:text]}")
      end
    end
  end
end
```

### TUI State Management

**Keep UI state separate from business logic:**

```ruby
class TUIState
  attr_reader :current_step, :user_responses, :is_paused

  def initialize
    @current_step = nil
    @user_responses = {}
    @is_paused = false
  end

  def update_step(step_name)
    @current_step = step_name
  end

  def add_response(question_id, response)
    @user_responses[question_id] = response
  end
end
```

### Benefits of Using TTY Toolkit

1. **Cross-platform compatibility**: Works on all major operating systems and terminal emulators
2. **Battle-tested**: Handles edge cases, terminal quirks, and user interactions properly
3. **Consistent UX**: Provides familiar, polished user experiences
4. **Maintainable**: Reduces custom TTY code that's difficult to test and maintain
5. **Accessible**: Built-in support for screen readers and accessibility features
6. **Performance**: Optimized for terminal performance and memory usage
7. **Composable**: Components can be easily combined to create complex interfaces
8. **Testable**: TTY components are designed with testing in mind

### Testing TUIs with tmux

For comprehensive testing of TUI applications, see the [Testing with tmux](#testing-with-tmux) section in Testing Guidelines.

## Test Coverage Philosophy

### Coverage Goals

**Target 85-100% line coverage for business logic**, but accept pragmatic limits based on code architecture:

- **Business logic**: 85-100% (core classes, service objects, domain logic)
- **External boundaries**: Test interface, not internals
- **Forked child processes**: Accept lower coverage (often untestable)
- **Exec calls**: Test orchestration, not subprocess internals

### What NOT to Test

**Inherently untestable code** (accept coverage gaps):

- Code inside forked child processes (runs in different process)
- Code after `exec()` calls (replaces current process)
- External library internals (trust the library tests)

**Example** ([background_runner.rb:45-77](lib/aidp/jobs/background_runner.rb#L45-L77)):

```ruby
pid = fork do
  Process.daemon(true)       # Runs in child process
  $stdout.reopen(log_file)   # Untestable from parent

  # All code here runs in child - can't test from parent process
  runner = Harness::Runner.new(@project_dir, mode)
  result = runner.run
  mark_job_completed(job_id, result)
end
```

**What to test instead**: Orchestration and metadata

```ruby
it "creates job metadata file" do
  job_id = runner.start(:exploration)

  metadata_file = File.join(jobs_dir, job_id, "metadata.yml")
  expect(File.exist?(metadata_file)).to be true

  metadata = YAML.safe_load_file(metadata_file)
  expect(metadata[:mode]).to eq(:exploration)
  expect(metadata[:status]).to eq("running")
end
```

### What TO Test

**Core application logic** (aim for 100%):

- All public API paths
- Error handling (rescue blocks, failure modes)
- Edge cases (nil inputs, empty arrays, boundary values)
- Complex private methods with multiple branches

### Testing Private Methods

**When to test private methods**: Complex logic with multiple branches that need coverage.

**How**: Use `send(:method_name)` to access private methods.

**Example** ([completion_checker_spec.rb:73-82](spec/aidp/harness/completion_checker_spec.rb#L73-L82)):

```ruby
describe "#detect_test_commands (Ruby)" do
  it "returns rspec command when Gemfile includes rspec" do
    File.write(File.join(project_dir, "Gemfile"), "gem 'rspec'")
    FileUtils.mkdir_p(File.join(project_dir, "spec"))
    checker = described_class.new(project_dir)

    # Access private method with send()
    commands = checker.send(:detect_test_commands)
    expect(commands).to include("bundle exec rspec")
  end
end
```

**Still mock only external boundaries** (File, Process, YAML) - not internal application code.

### Coverage Analysis Workflow

#### 1. Read the implementation file

Understand what the code does before writing tests.

#### 2. Check existing test coverage

```bash
COVERAGE=1 mise exec -- bundle exec rspec spec/path/to/file_spec.rb
open coverage/index.html  # View detailed report
```

#### 3. Categorize uncovered lines

- **Testable**: Business logic, error paths, edge cases
- **Untestable**: Forked processes, exec calls, external library internals

#### 4. Write tests for testable gaps

Focus on missing paths, error handling, edge cases.

#### 5. Accept untestable gaps

Document why certain lines can't be tested (e.g., "lines 45-77 run in forked child process").

## Time and Concurrency Testing

### Avoid Sleep-Based Tests

**ANTI-PATTERN**: Tests that use `sleep` to wait for time-based behavior are flaky and slow.

```ruby
# ❌ BAD: Flaky and slow
it "sorts by most recent" do
  item1 = create_item(name: "first")
  sleep 0.1  # Flaky - timing-dependent
  item2 = create_item(name: "second")

  items = repository.list_by_recency
  expect(items.first).to eq(item2)
end
```

**PATTERN**: Stub `Time.now` for deterministic, fast tests.

```ruby
# ✅ GOOD: Fast and reliable
it "sorts by most recent" do
  time1 = Time.parse("2025-01-01 10:00:00")
  time2 = Time.parse("2025-01-01 10:05:00")

  allow(Time).to receive(:now).and_return(time1)
  item1 = create_item(name: "first")

  allow(Time).to receive(:now).and_return(time2)
  item2 = create_item(name: "second")

  items = repository.list_by_recency
  expect(items.first).to eq(item2)  # Always passes - no timing dependency
end
```

### Process Loop Testing

**PATTERN**: Count exact number of calls in retry/wait loops.

```ruby
# Code: Wait for process to terminate with 10-second timeout
10.times do
  sleep 0.5
  break unless process_running?(pid)
end

# Test: Count exact calls needed
it "waits up to 10 seconds for process to terminate" do
  # Initial check + 10 loop iterations + final check = 12 total
  running_checks = [true] * 12 + [false]
  allow(runner).to receive(:process_running?).and_return(*running_checks)

  runner.stop_job(job_id)

  expect(runner).to have_received(:process_running?).exactly(12).times
end
```

**Why this works**: Precise call counting ensures loop logic is correct without timing dependencies.

## Forked Process Testing Patterns

### Test Orchestration, Not Child Process Code

**ANTI-PATTERN**: Trying to test code inside forked child processes.

```ruby
# ❌ BAD: Can't test child process internals from parent
it "logs to output file in child process" do
  runner.start(:exploration)

  # This won't work - logs happen in child process
  expect(File.read(log_file)).to include("Starting exploration")
end
```

**PATTERN**: Test orchestration and side effects visible to parent.

```ruby
# ✅ GOOD: Test parent process orchestration
it "creates log file for background job" do
  job_id = runner.start(:exploration)

  # Wait for daemon to initialize
  sleep 0.1

  log_file = File.join(jobs_dir, job_id, "output.log")
  expect(File.exist?(log_file)).to be true
end
```

### Stub Fork and Process Boundaries

**PATTERN**: Stub forking and I/O redirection to test orchestration logic.

```ruby
it "forks and detaches daemon process" do
  allow(Process).to receive(:fork).and_yield.and_return(12345)
  allow(Process).to receive(:daemon)
  allow(Process).to receive(:detach)
  allow($stdout).to receive(:reopen)
  allow($stderr).to receive(:reopen)

  job_id = runner.start(:exploration)

  expect(Process).to have_received(:fork)
  expect(Process).to have_received(:detach).with(12345)
end
```

### Accept Lower Coverage for Child Process Code

**Example**: [background_runner.rb](lib/aidp/jobs/background_runner.rb) achieves 86.62% coverage with 19 lines untestable inside the forked child block.

**Document the gap**:

```ruby
# spec/aidp/jobs/background_runner_spec.rb
# Note: Lines 45-77 run in forked child process and cannot be tested from parent.
# We test orchestration (job metadata, PID files) instead of child internals.
```

## String Encoding Edge Cases

### Always Handle Encoding Explicitly

**PATTERN**: Convert to UTF-8 before string operations that expect specific encoding.

```ruby
# ✅ GOOD: Explicit encoding handling
def extract_placeholders(text)
  return [] if text.nil? || text.empty?

  # Ensure UTF-8 encoding before regex operations
  text = text.encode("UTF-8", invalid: :replace, undef: :replace)
    unless text.encoding == Encoding::UTF_8

  text.scan(/\{\{(\w+)\}\}/).flatten
end
```

**Why**: String operations like regex can fail or produce unexpected results with non-UTF-8 encodings.

**Test both UTF-8 and non-UTF-8 inputs**:

```ruby
it "handles UTF-8 content" do
  result = composer.send(:extract_placeholders, "{{emoji}} 🎉")
  expect(result).to eq(["emoji"])
end

it "converts non-UTF-8 text to UTF-8" do
  text = "{{test}}".encode("ASCII-8BIT")
  result = composer.send(:extract_placeholders, text)
  expect(result).to eq(["test"])
end
```

## Pending Specs Policy

### Philosophy

The test suite is a living contract with the behavior of the system. Marking specs *pending* (or commenting them out) hides regressions and erodes confidence. Therefore:

**Previously passing specs must NOT be marked as pending or commented out to “make the build green.” Fix the regression or deliberately delete the spec (with rationale) – never silently defer it.**

### When Pending Is Acceptable

Use `pending` (or `xit` / `skip`) only for:

- Clearly identified future work that has not yet begun (a true TODO / planned feature)
- Documented spikes / exploratory work where behavior isn’t finalized
- Upstream dependency issues temporarily blocking implementation (include link/reference)

### When Pending Is NOT Acceptable

Do NOT mark a spec pending if:

- It previously passed and now fails (that’s a regression)
- The code path is in active development (write / adjust the test to the emerging behavior instead)
- You are uncertain how to fix it (open an issue and keep the failing spec to maintain visibility)

### Required Annotation

Every pending spec MUST include a short reason plus (when possible) a tracking reference (issue ID, PR link, ticket).

Example:

```ruby
pending("Add retry backoff logic - tracked in GH#123")
```

### Workflow for Regressions

1. Failing spec detected
2. Decide: fast fix vs. deeper refactor
3. If deeper refactor needed – create an issue, *leave the spec failing*, and (optionally) quarantine via a focused tag + build allowlist only if absolutely necessary (avoid unless build blocking)
4. Track resolution visibly – never hide it behind `pending`

### Deleting a Spec

It is acceptable to delete a spec ONLY if the covered behavior is intentionally removed. The PR must state explicitly: “Removing spec X – feature Y deprecated / removed.”

### Quick Checklist

| Action | Allowed? | Notes |
|--------|----------|-------|
| Mark previously green spec as `pending` | ❌ | Fix or intentionally remove instead |
| Add new pending spec for planned feature | ✅ | Include reason + reference |
| Comment out failing spec | ❌ | Never – loses history / intent |
| Skip due to flaky external API | ⚠️ | Only with issue + retry strategy |

Maintaining strict discipline around pending specs keeps the suite honest and actionable.
8. **Testable**: TTY components are designed with testing in mind

## Testing Guidelines

### Test Structure and Readability

**Make tests as readable as possible for code review.**

#### Test Descriptions

- Use clear, unambiguous titles that describe expected behavior
- Good: `"enqueues an email after successful validation"`
- Bad: `"works"` or `"does the thing"`

#### Context and Describe Blocks

- Use descriptive context and describe blocks
- Good: `context "when the user has filled the optional age dropdown"`
- Bad: `context "age entered"`

#### Before Callbacks with Metadata

- Use descriptive metadata for before callbacks
- Good: `before(with_logged_in_user: true) { login(:user) }`
- Bad: `before { login(:user) }`

### Test Organization

- Use `let` for test data setup
- Group related tests with `context` blocks
- Use descriptive test names
- Keep helper methods in `private` section

#### Single Spec File Per Class

**Consolidate all examples for a class into the canonical spec file that mirrors the class path.**

- Use the file path to map class name to spec location (`Aidp::Harness::Runner` → `spec/aidp/harness/runner_spec.rb`). Keep unit coverage for that class **only** in that file.
- When adding new behaviors, prefer organizing with nested `describe`/`context` blocks (e.g., `context "when the user cancels"`), rather than starting a new spec file.
- If you discover multiple spec files targeting the same class, fold them back into the primary spec file as part of the change you are making. Preserve the original contexts and expectations so history stays readable.
- **Exceptions**: Higher-level integration specs (`spec/system/**`, `spec/features/**`) may exercise the same class as part of a workflow, but do not duplicate unit expectations. Keep the actual unit specs centralized.
- When the class has complex modes or collaborators, add shared helper methods or shared examples within the primary file (or `spec/support`) so the contexts stay readable instead of spreading logic across files.

### Mocking and Stubbing

**Only mock external dependencies** - never mock application code. User input can be considered an external dependency.

```ruby
# Good: Mock external dependencies
allow(mock_provider).to receive(:make_request).and_return(success_response)
allow(Readline).to receive(:readline).and_return("user response")

# Bad: Mocking application code
allow(user_interface).to receive(:validate_question).and_return(true) # Don't do this!
```

### Never Put Mock Methods in Production Code

**CRITICAL: Mocking should only be done in tests, never in production code.**

```ruby
# ❌ BAD: Mock methods in production code
class UserInterface
  def initialize
    if defined?(RSpec) || ENV["RSPEC_RUNNING"]
      @prompt = create_mock_prompt  # Never do this!
    else
      @prompt = TTY::Prompt.new
    end
  end

  private

  def create_mock_prompt
    # Mock implementation in production code - NEVER DO THIS!
  end
end

# ✅ GOOD: Use dependency injection for testability
class UserInterface
  def initialize(prompt: nil)
    @prompt = prompt || TTY::Prompt.new
  end
end

# In tests:
let(:mock_prompt) { instance_double(TTY::Prompt) }
let(:ui) { UserInterface.new(prompt: mock_prompt) }
```

**Why this matters:**

- **Production code should be production-ready** - no test-specific logic
- **Separation of concerns** - tests handle mocking, production code handles business logic
- **Maintainability** - easier to understand and modify when concerns are separated
- **Reliability** - production code paths are cleaner and more predictable

**Proper approach:**

1. **Use dependency injection** - allow tests to inject mocks via constructor parameters
2. **Keep mocking in tests** - all mock setup should be in spec files only
3. **Test the real behavior** - production code should only contain real implementation

### Testing Interactive Elements and External Services

**Use dependency injection pattern for testing components that interact with users or external services.**

This pattern is essential for testing classes that use:

- **Interactive prompts** (TTY::Prompt, user input)
- **External APIs** (HTTP requests, third-party services)
- **File system operations** (reading/writing files)
- **Network operations** (database connections, web requests)

#### Pattern: Constructor Dependency Injection

```ruby
# ✅ GOOD: Production class with dependency injection
class UserInterface
  def initialize(prompt: TTY::Prompt.new)
    @prompt = prompt
  end

  def ask_user(question)
    @prompt.ask(question)
  end

  def show_menu(options)
    @prompt.select("Choose an option:", options)
  end
end

class ApiClient
  def initialize(http_client: Net::HTTP)
    @http_client = http_client
  end

  def fetch_data(url)
    @http_client.get(url)
  end
end
```

#### Testing with Mock Objects

Create test doubles that implement the same interface as the real dependencies:

```ruby
# ✅ GOOD: Test with mock objects
RSpec.describe UserInterface do
  # Create a test double that implements TTY::Prompt interface
  class TestPrompt
    attr_reader :questions_asked, :menus_shown

    def initialize(responses: {})
      @responses = responses
      @questions_asked = []
      @menus_shown = []
    end

    def ask(question)
      @questions_asked << question
      @responses[:ask] || "default response"
    end

    def select(title, options)
      @menus_shown << { title: title, options: options }
      @responses[:select] || options.first
    end
  end

  let(:test_prompt) { TestPrompt.new(responses: { ask: "user input" }) }
  let(:ui) { UserInterface.new(prompt: test_prompt) }

  it "asks the user a question" do
    result = ui.ask_user("What's your name?")

    expect(result).to eq("user input")
    expect(test_prompt.questions_asked).to include("What's your name?")
  end

  it "shows a menu to the user" do
    ui.show_menu(["Option 1", "Option 2"])

    expect(test_prompt.menus_shown.length).to eq(1)
    expect(test_prompt.menus_shown.first[:title]).to eq("Choose an option:")
  end
end
```

#### Benefits of This Pattern

1. **Fast Tests** - No actual user interaction or network calls during testing
2. **Reliable Tests** - Tests don't depend on external services being available
3. **Comprehensive Testing** - Can test error conditions and edge cases easily
4. **Clean Production Code** - No test-specific logic in production classes
5. **Easy Debugging** - Test doubles can record interactions for verification

#### Shared Test Utilities

For commonly mocked dependencies, create shared test utilities:

```ruby
# spec/support/test_prompt.rb
class TestPrompt
  # Comprehensive test double for TTY::Prompt
  # (See actual implementation in spec/support/test_prompt.rb)
end

# Use in multiple specs
RSpec.describe SomeClass do
  let(:test_prompt) { TestPrompt.new }
  let(:instance) { SomeClass.new(prompt: test_prompt) }
  # ...
end
```

### Sandi Metz's Testing Rules

Focus on testing the interface, not the implementation:

#### Message Types

- **Queries**: Return something, change nothing (getters)
- **Commands**: Return nothing, change something (setters)

#### What to Test

- **Incoming query messages**: Assert what they return
- **Incoming command messages**: Assert direct public side effects

#### What NOT to Test

- Private methods (messages sent from within the object)
- Outgoing query messages (no public side effects)
- Outgoing command messages (use mocks instead)

#### Mocking Strategy

- **Command messages**: Should be mocked
- **Query messages**: Should be stubbed

## Error Handling

### When to Crash vs. When to Handle

**It's okay to crash if it won't cause:**

- Data loss, corruption, or security vulnerabilities
- Silent failures that mask bugs

**Exception Guidelines:**

- **Don't swallow exceptions** that indicate bugs
- **Do handle exceptions** from external dependencies
- **Do crash** on invalid configuration or internal state corruption

### Error Classes

```ruby
module Aidp
  module Errors
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end
    class ValidationError < StandardError; end
    class StateError < StandardError; end
    class UserError < StandardError; end
  end
end
```

### Error Handling Patterns

```ruby
# Good: Let it crash for internal errors
def execute_step(step_name)
  validate_step_name(step_name)  # Will crash if invalid - that's good!
  run_step_logic(step_name)
end

# Good: Handle external dependency errors gracefully
def make_provider_request(prompt)
  provider.make_request(prompt)
rescue ProviderError => e
  if e.message.include?("rate limit")
    handle_rate_limit(e)
  else
    raise  # Re-raise unexpected errors
  end
end

# Bad: Swallowing exceptions
def process_data(data)
  # ... processing logic ...
rescue => e
  puts "Something went wrong"  # Don't do this!
end
```

## Concurrency & Threads

### Thread Management

- **Always clean up threads** in `ensure` blocks or cleanup methods
- **Avoid global mutable state** without proper synchronization
- **Make intervals configurable** for testing (don't hardcode sleeps/waits)

```ruby
# Good: Proper thread cleanup
def start_background_worker
  @worker_thread = Thread.new do
    loop do
      process_queue
      sleep(interval)
    end
  end
ensure
  @worker_thread&.kill
  @worker_thread&.join(timeout: 5)
end

# Good: Configurable intervals
def initialize(check_interval: 60)
  @check_interval = check_interval
end

# Bad: Hardcoded sleeps make testing slow
def monitor
  loop do
    check_status
    sleep 60  # Can't override in tests
  end
end
```

## Performance

### Avoid Quadratic Complexity

- **Avoid O(n²) operations** over large datasets
- **Batch I/O operations** instead of making individual calls
- **Stream data** when processing large files

### Caching

- **Cache expensive operations** like parsing or API calls
- **Use existing cache utilities** in the codebase
- **Consider cache invalidation** strategies

```ruby
# Good: Cache expensive parsing
def parsed_file(path)
  @parsed_cache ||= {}
  @parsed_cache[path] ||= parse_file(path)
end

# Bad: Re-parsing on every call
def parsed_file(path)
  parse_file(path)  # Slow for repeated calls
end
```

## Security & Safety

### Code Execution

- **Never execute untrusted code** or eval user input
- **Validate file paths** to prevent directory traversal
- **Sanitize inputs** before shell interpolation

### Secrets Management

- **Don't log secrets** (API keys, tokens, passwords)
- **Use environment variables** for sensitive configuration
- **Mask sensitive data** in error messages and logs

```ruby
# Good: Sanitized logging
logger.info("API request failed", user_id: user.id, endpoint: endpoint)

# Bad: Leaking secrets
logger.error("Request failed: #{request.inspect}")  # May contain auth headers
```

### Input Validation

- **Validate file paths** before file operations
- **Whitelist allowed values** for enums/options
- **Escape shell arguments** or avoid shell altogether

```ruby
# Good: Whitelist validation
ALLOWED_MODES = [:analyze, :execute].freeze
raise ArgumentError unless ALLOWED_MODES.include?(mode)

# Good: Avoid shell interpolation
system("git", "commit", "-m", user_message)  # Safe from injection

# Bad: Shell interpolation risk
system("git commit -m '#{user_message}'")  # Dangerous!
```

## Commit Hygiene

### Commit Structure

- **One logical change per commit** (or tightly coupled set)
- **Include rationale** when refactoring or changing behavior
- **Reference issue IDs** for non-trivial changes (e.g., `Fix rate limiting - GH#123`)
- **Write descriptive commit messages** that explain the "why", not just the "what"

### Commit Messages

```text
# Good: Clear intent and context
Add retry logic for provider rate limits

Providers can temporarily return 429 errors during high load.
This adds exponential backoff retry logic (3 attempts max) to
handle transient failures gracefully.

Fixes #123
```

```text
# Bad: No context
Fix bug
```

## Code Review Guidelines

### What to Look For

- **Sandi Metz's Rules**: Classes < 100 lines, methods < 5 lines, max 4 parameters
- **Test Readability**: Clear descriptions, proper context blocks, descriptive metadata
- **Error Handling**: Specific error types, proper error messages
- **TTY Toolkit Usage**: Using TTY components instead of custom TTY code

### Review Checklist

- [ ] Classes follow size limits (100 lines max)
- [ ] Methods follow size limits (5 lines max)
- [ ] Test descriptions are clear and behavior-focused
- [ ] Error handling is specific and informative
- [ ] Code follows StandardRB guidelines
- [ ] No external dependencies in tests (all mocked)

---

## Prompt Optimization (Intelligent Fragment Selection)

AIDP uses **Zero Framework Cognition** to intelligently select only the most relevant fragments from style guides, templates, and source code when building prompts. This section explains how to write documentation that works well with this system.

See [PROMPT_OPTIMIZATION.md](PROMPT_OPTIMIZATION.md) for complete details.

### Why Fragment-Friendly Documentation Matters

The optimizer parses this style guide by markdown headings and scores each section for relevance to the current task. Well-structured documentation helps the AI select the right context, resulting in:

- **30-50% token savings** - Only relevant sections included
- **Better AI focus** - Less noise, clearer reasoning
- **Faster iterations** - Smaller prompts, faster responses

### Writing Fragment-Friendly Sections

#### 1. Use Clear, Specific Headings

Headings should clearly indicate the topic. The AI uses these to understand what each section covers.

```markdown
✅ Good Examples:
## Testing: RSpec Best Practices
## Security: OAuth Token Handling
## API Design: REST Endpoints
## Performance: Database Query Optimization

❌ Poor Examples:
## Miscellaneous Guidelines
## Other Considerations
## Additional Notes
## Tips and Tricks
```

#### 2. Add Semantic Tags to Headings (Optional)

You can add tags in parentheses to help the AI understand when a section is relevant:

```markdown
## API Design Principles (rest, graphql, endpoints, json)
## Testing: Integration Tests (rspec, testing, e2e, fixtures)
## Security: Authentication (oauth, jwt, tokens, sessions)
## Database: Migrations (schema, activerecord, sql)
```

Common useful tags:

- **Task types**: `feature`, `bugfix`, `refactor`, `test`, `analysis`
- **Technologies**: `api`, `database`, `security`, `performance`, `cli`, `ui`
- **Patterns**: `service-object`, `factory`, `observer`, `strategy`, `command`
- **Concerns**: `error-handling`, `validation`, `logging`, `caching`, `monitoring`
- **Testing**: `rspec`, `coverage`, `mocking`, `integration`, `e2e`, `fixtures`

#### 3. Keep Sections Focused and Self-Contained

Each section should:

- Cover **one clear topic**
- Be **3-10 paragraphs** (not too short, not too long)
- Be **self-contained** (understandable without reading other sections)
- Include **examples** when helpful

**Good Structure:**

```markdown
## Error Handling: Custom Exceptions

When creating custom exceptions, inherit from StandardError and provide
clear error messages that help with debugging.

Example:
[code example]

This approach allows callers to rescue specific errors and provides
clear context about what went wrong.
```

**Bad Structure:**

```markdown
## Guidelines

Error handling: Use custom exceptions.
Testing: Write comprehensive tests.
Performance: Optimize database queries.
Security: Validate all input.
```

#### 4. Use Semantic Keywords Naturally

Include relevant keywords in the content to help the AI understand context. Don't force keywords - just write naturally about the topic and they'll appear organically.

For a section on testing:

```markdown
When writing **feature tests**, ensure you cover the happy path and edge cases.
Use **RSpec** contexts to organize different scenarios. Mock external dependencies
to keep tests fast and reliable.
```

Keywords like "feature", "tests", "RSpec", "mock" help the AI score this section highly for testing-related tasks.

### How the Selection Algorithm Works

When you start a work loop, the optimizer:

1. **Indexes** all fragments (this guide, templates, source code)
2. **Scores** each fragment 0.0-1.0 based on:
   - **Task type match** (30%): Is this a feature, bugfix, refactor, or test?
   - **Tag match** (25%): Do the tags align with the task?
   - **File match** (25%): Is this relevant to the files being modified?
   - **Step match** (20%): Does this match the current work loop step?
3. **Selects** highest-scoring fragments within token budget
4. **Builds** the optimized PROMPT.md

**Critical sections** (score ≥ 0.9) are **always included**, regardless of budget.

### Example: How Scoring Works

Imagine you're adding OAuth authentication to a User model:

```text
Task: Add OAuth authentication
Type: feature
Files: lib/user.rb, lib/auth/oauth.rb
Step: implementation
Tags: security, api, oauth
```

The optimizer scores each section:

```text
## Security: OAuth Token Handling (oauth, tokens, jwt)
  Task type: 0.85 (feature → security relevant)
  Tags:      0.95 (perfect match: security, oauth)
  Files:     0.60 (not file-specific, but auth-related)
  Step:      0.70 (implementation matches)
  → Final Score: 0.79 (SELECTED - above 0.75 threshold)

## Testing: Unit Test Patterns (rspec, mocking)
  Task type: 0.88 (feature → testing relevant)
  Tags:      0.30 (low match: no testing tags)
  Files:     0.50 (not file-specific)
  Step:      0.60 (implementation → testing somewhat relevant)
  → Final Score: 0.60 (EXCLUDED - below 0.75 threshold)

## Performance: Database Optimization (sql, queries)
  Task type: 0.40 (feature → performance less relevant)
  Tags:      0.20 (low match: no performance tags)
  Files:     0.30 (no database files)
  Step:      0.50 (implementation → performance somewhat relevant)
  → Final Score: 0.35 (EXCLUDED - below 0.75 threshold)
```

### What This Means for Developers

When you work with AIDP:

- **You won't see everything** - Only sections relevant to your current task appear in PROMPT.md
- **Trust the selection** - The AI chose what matters based on your task context
- **Inspect decisions** - Use `/prompt explain` to see what was selected and why
- **Provide feedback** - If important sections are missing, that helps us improve scoring

### Adjusting Selection Behavior

You can tune selection thresholds in `.aidp/config.yml`:

```yaml
prompt_optimization:
  enabled: true
  max_tokens: 16000
  include_threshold:
    style_guide: 0.75  # Lower = more inclusive (0.5-0.9)
    templates: 0.8
    source: 0.7
```

**Threshold guidance:**

- **0.5-0.6**: Very inclusive, most fragments selected
- **0.7-0.8**: Balanced (recommended)
- **0.9+**: Very selective, only critical fragments

### Best Practices Summary

1. ✅ Use clear, specific headings that indicate the topic
2. ✅ Add semantic tags to headings when helpful
3. ✅ Keep sections focused (one topic per section)
4. ✅ Make sections self-contained (3-10 paragraphs)
5. ✅ Use keywords naturally in content
6. ✅ Include examples and code snippets
7. ❌ Avoid generic headings ("Miscellaneous", "Other")
8. ❌ Don't mix multiple topics in one section
9. ❌ Don't make sections too long (> 20 paragraphs)

### Further Reading

For complete details on the optimization system:

- [PROMPT_OPTIMIZATION.md](PROMPT_OPTIMIZATION.md) - Full documentation
- [LLM_STYLE_GUIDE.md](LLM_STYLE_GUIDE.md) - Concise version for AI consumption
- Issue #175 - Original feature specification

---

**Good code is not just code that works, but code that is easy to understand, modify, and extend.**

---

## Project-Specific Knowledge Management

### Overview

AIDP's prompt optimization system intelligently selects style guide fragments based on task context. To maximize this feature, structure project-specific knowledge as dedicated style guide sections rather than using external memory systems.

**Principle**: Context is precious - use AIDP's existing optimization rather than adding external dependencies.

### When to Add Project-Specific Sections

Add project-specific sections to `docs/LLM_STYLE_GUIDE.md` when you make decisions that should persist across sessions:

**Good candidates**:

- ✅ Architectural choices and rationale
- ✅ User preferences and coding style
- ✅ Framework/library selections
- ✅ Authentication/authorization patterns
- ✅ Database design conventions
- ✅ API design patterns
- ✅ Error handling strategies

**Poor candidates** (already handled elsewhere):

- ❌ Implementation details (in code comments)
- ❌ Temporary decisions (in commit messages)
- ❌ Task tracking (use [persistent tasklist](PERSISTENT_TASKLIST.md))
- ❌ Build instructions (in README)

### Format for Project-Specific Sections

Use this template in `docs/LLM_STYLE_GUIDE.md`:

```markdown
## Project-Specific Patterns

### Authentication (Decided: YYYY-MM-DD)

**Decision**: Using OAuth 2.0 with Auth0

**Rationale**: Client requires Google/GitHub login support; Auth0 provides managed OAuth flow

**Implementation Details**:

- PKCE flow for security (no client secret)
- Sliding window token refresh (15 min access, 7 day refresh)
- Tokens stored in HTTP-only cookies

**Related Commits**: abc123, def456

**Last Updated**: YYYY-MM-DD
```

### Key Elements

**1. Decision Date** - Track when decisions were made

**2. Rationale** - Document *why*, not just *what*

**3. Examples** - Include code snippets showing the pattern

**4. Related References** - Link to commits, files, or external docs

**5. Update Tracking** - Track when sections are reviewed/updated

### Benefits Over External Memory Systems

**Zero context overhead**:

- Style guide sections are already in prompt budget
- AIDP's fragment selector includes them when relevant
- No additional tokens consumed

**Git-versioned**:

- Changes tracked alongside code
- Reviewable in pull requests
- Merge-friendly

**Human-readable**:

- Easy to browse
- Searchable with standard tools
- No special tooling required

**Prompt-optimized**:

- Fragment selector scores relevance automatically
- Only included when task context matches
- No manual querying needed

### Comparison to External Memory Systems

| Aspect | Style Guide Sections | External Memory (memory-bank-mcp) |
|--------|---------------------|-----------------------------------|
| Context Cost | 0 tokens (already in budget) | +1,500 tokens (+18% overhead) |
| Setup | 0 minutes (add to existing file) | 30-60 minutes (Docker + config) |
| Maintenance | Git workflow (commit/merge) | Separate database, backups |
| Prompt Integration | Automatic (fragment selector) | Manual querying or integration |
| Failure Mode | Always available | Service outage = no memory |

**Verdict**: Style guide sections are superior for most use cases.

### Summary

**Best practice**: Document project-specific decisions in `docs/LLM_STYLE_GUIDE.md` sections.

**Benefits**:

- ✅ Zero context overhead
- ✅ Zero external dependencies
- ✅ Git-versioned and reviewable
- ✅ Automatically included by prompt optimizer

**Avoid**: External memory systems (memory-bank-mcp) unless you have specific needs they address.

**See Also**:

- [Prompt Optimization Guide](PROMPT_OPTIMIZATION.md)
- [Optional External Tools](OPTIONAL_TOOLS.md)
- [Persistent Tasklist](PERSISTENT_TASKLIST.md)

---

## Persistent Tasklist: Cross-Session Task Tracking

AIDP includes a built-in persistent tasklist that tracks tasks across sessions via git-committable `.aidp/tasklist.jsonl` files.

### Overview

**Purpose**: Track discovered tasks, future work, and technical debt without losing context between sessions.

**Storage**: `.aidp/tasklist.jsonl` (JSONL format - one JSON object per line)

**Benefits**:

- ✅ Zero context overhead (tasks loaded on-demand)
- ✅ Git-tracked history alongside code changes
- ✅ Resume work across sessions without memory loss
- ✅ Agents can file tasks during implementation

### Task Filing Signal Pattern

Agents should file tasks using this signal pattern in their output:

```text
File task: "description" [priority: high|medium|low] [tags: tag1,tag2]
```

**Examples**:

```text
File task: "Add rate limiting to /auth/token" priority: high
File task: "Update API docs with OAuth flow" priority: medium tags: docs,api
File task: "Refactor error handling in UserService" tags: refactor,backend
File task: "Add integration tests for checkout flow" priority: high tags: testing
```

### When to File Tasks

**DO file tasks for**:

- Sub-tasks discovered during implementation
- Future work that shouldn't be forgotten
- Technical debt identified during development
- Follow-up items after completing current work
- Security issues that need attention
- Performance optimizations for later

**DON'T file tasks for**:

- Work you can complete immediately
- Trivial changes (typo fixes, formatting)
- Tasks already tracked in the issue tracker
- Work outside the project scope

### Task Properties

**Status** (automatic):

- `pending` - Not yet started (default for new tasks)
- `in_progress` - Currently being worked on
- `done` - Completed successfully
- `abandoned` - No longer relevant or needed

**Priority** (optional):

- `high` - Security issues, critical bugs, blocking work
- `medium` - Normal priority (default)
- `low` - Nice-to-have improvements

**Tags** (optional):

- Use for categorization and filtering
- Common tags: `docs`, `testing`, `refactor`, `security`, `performance`, `api`, `ui`

**Metadata** (automatic):

- `id` - Unique identifier (timestamp + random hex)
- `created_at` - When task was created
- `updated_at` - Last modification time
- `session` - Work loop session where task was discovered
- `discovered_during` - Context of discovery

### REPL Commands

**List tasks**:

```bash
/tasks list              # All tasks
/tasks list pending      # Only pending
/tasks list in_progress  # Only in-progress
/tasks list done         # Completed tasks
```

**Task details**:

```bash
/tasks show task_1730099445_a3f2
```

**Update status**:

```bash
/tasks done task_1730099445_a3f2
/tasks abandon task_1730099445_b8d1 "Feature requirement changed"
```

**Statistics**:

```bash
/tasks stats
```

### Task Filing Best Practices

**1. Be Specific** (1-200 characters):

- ❌ "Fix bug"
- ✅ "Fix null pointer error in UserService.authenticate()"
- ❌ "Update docs"
- ✅ "Add API documentation for OAuth endpoints"

**2. Use Appropriate Priority**:

- High: Security vulnerabilities, data loss risks, blocking issues
- Medium: Standard features, non-blocking bugs (default)
- Low: Cosmetic improvements, optimizations

**3. Tag Meaningfully**:

- Use consistent tag names across the project
- Limit to 2-3 relevant tags per task
- Examples: `security,api`, `testing,integration`, `docs,user-facing`

**4. File During Implementation**:

- File tasks as you discover them
- Include context about why it's needed
- Don't wait until the end (you'll forget)

**5. Review Pending Tasks**:

- Check pending tasks at session start
- Mark obsolete tasks as abandoned (with reason)
- Update priorities as project evolves

### Integration with Work Loops

**Session Start**:
Work loops automatically display pending tasks:

```text
📋 Pending Tasks from Previous Sessions:
  ⚠️  Fix authentication race condition (2d ago)
  ○  Update API documentation (1d ago)
  ·  Refactor error handling (today)
```

**Automatic Filing**:
When agents output task filing signals, tasks are automatically created:

```text
📋 Filed task: Add rate limiting to /auth/token (task_1730099445_a3f2)
```

### JSONL File Format

Tasks are stored in append-only JSONL format (one JSON object per line):

```jsonl
{"id":"task_001","description":"Add rate limiting","status":"done","priority":"high","created_at":"2025-10-27T10:30:00Z","updated_at":"2025-10-27T14:20:00Z","completed_at":"2025-10-27T14:20:00Z"}
{"id":"task_002","description":"Update docs","status":"pending","priority":"medium","created_at":"2025-10-27T10:35:00Z","updated_at":"2025-10-27T10:35:00Z"}
```

**Why JSONL?**:

- Line-based format (git-friendly diffs)
- Merge-friendly (append-only reduces conflicts)
- Human-readable for debugging
- Fast to parse and query

**Append-Only Behavior**:

- Updates append new versions (keeps history)
- Latest version of each task ID is used
- Full task history preserved in file

### Example Workflow

**Friday afternoon - Discovery**:

```text
Agent: "Implementing OAuth flow. I notice we'll need rate limiting."
Agent: File task: "Add rate limiting to /auth/token" priority: high
System: 📋 Filed task: Add rate limiting to /auth/token (task_170310_a3f2)

Agent: "Also need to update the API documentation."
Agent: File task: "Update API docs with OAuth endpoints" priority: medium tags: docs,api
System: 📋 Filed task: Update API docs with OAuth endpoints (task_170315_b8d1)

[Agent completes OAuth implementation]
[Commit includes code + .aidp/tasklist.jsonl]
```

**Monday morning - Resume**:

```bash
$ aidp execute

📋 Pending Tasks from Previous Sessions:
  ⚠️  Add rate limiting to /auth/token (3d ago)
  ○  Update API docs with OAuth endpoints (3d ago)

Agent: "I see pending tasks. Let me work on rate limiting first."
[Picks up exactly where Friday left off]
```

**Later - Management**:

```bash
# Check status
/tasks list pending

# Mark completed
/tasks done task_170310_a3f2

# View statistics
/tasks stats
```

### Anti-Patterns

**❌ Don't overuse**:

- Filing 50 tasks in one session (overwhelming)
- Filing tasks for every minor thought
- Duplicating existing issue tracker

**❌ Don't underuse**:

- Discovering sub-tasks but not filing them
- Forgetting to file technical debt
- Losing context between sessions

**❌ Don't misuse**:

- Using as a general note-taking system
- Filing tasks for other projects
- Skipping descriptions ("TODO: fix this")

**✅ Balance**:

- File 2-5 tasks per significant work session
- Focus on actionable, specific work items
- Use for cross-session continuity

### Troubleshooting

**Tasks not appearing**:

- Check `.aidp/tasklist.jsonl` exists
- Verify task status (only `pending` shown by default)
- Try `/tasks list` to see all tasks

**Merge conflicts**:

- Accept both changes (append-only format)
- Remove any duplicate entries
- Consider running `/tasks list` to verify state

**Corrupted JSONL**:

- Malformed lines are automatically skipped
- Check logs for parsing errors
- Manually fix or remove invalid JSON lines

### Related Documentation

- [REPL Reference](REPL_REFERENCE.md#tasks-subcommand-args) - Complete `/tasks` command docs
- [Persistent Tasklist PRD](PERSISTENT_TASKLIST.md) - Full technical specification
- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Integration with work loops
