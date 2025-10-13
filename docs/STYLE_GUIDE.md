# AIDP Style Guide

Coding standards, architectural patterns, and best practices for the AI Dev Pipeline (AIDP) project.

## Table of Contents

- [Code Organization](#code-organization)
- [Sandi Metz's Rules](#sandi-metzs-rules)
- [Ruby Conventions](#ruby-conventions)
- [Ruby Version Management](#ruby-version-management)
- [TTY Toolkit Guidelines](#tty-toolkit-guidelines)
- [Testing Guidelines](#testing-guidelines)
- [Error Handling](#error-handling)

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

### Method Design

- Use clear, descriptive method names (`validate_user_input` not `process`)
- Use keyword arguments for clarity (`create_user(name:, email:)`)
- Follow StandardRB guidelines

### Error Handling

- Use specific error types, not generic `rescue => e`
- Provide meaningful error messages
- Let it crash for internal errors, handle external dependency errors gracefully

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
5. **Test error handling** - ensure graceful handling of interrupts

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

**Good code is not just code that works, but code that is easy to understand, modify, and extend.**
