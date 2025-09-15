# AIDP Style Guide

This document outlines the coding standards, architectural patterns, and best practices for the AI Dev Pipeline (AIDP) project. Following these guidelines ensures code consistency, maintainability, and readability across the codebase.

## Table of Contents

- [Code Organization](#code-organization)
- [Sandi Metz's Rules](#sandi-metzs-rules)
- [Ruby Conventions](#ruby-conventions)
- [CLI UI Patterns](#cli-ui-patterns)
- [Testing Guidelines](#testing-guidelines)
- [Error Handling](#error-handling)
- [Documentation](#documentation)

## Code Organization

### Class Structure

**Prefer small, focused classes over large, complex ones.**

- Break up large classes (like the 2,380-line `UserInterface`) into focused components
- Each class should have a single, well-defined responsibility
- Use composition over inheritance when possible
- Create service objects for complex business logic

### File Organization

```
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

**Before (violates rules):**

```ruby
def collect_feedback(questions, context = nil)
  responses = {}

  if context
    display_feedback_context(context)
  end

  display_question_presentation_header(questions, context)

  questions.each_with_index do |question_data, index|
    question_number = question_data[:number] || (index + 1)
    display_numbered_question(question_data, question_number, index + 1, questions.length)
    response = get_question_response(question_data, question_number)

    if question_data[:required] != false && (response.nil? || response.to_s.strip.empty?)
      puts "❌ This question is required. Please provide a response."
      redo
    end

    responses["question_#{question_number}"] = response
    display_question_progress(index + 1, questions.length)
  end

  display_question_completion_summary(responses, questions)
  responses
end
```

**After (follows rules):**

```ruby
def collect_feedback(questions, context = nil)
  responses = {}

  display_feedback_intro(questions, context)
  responses = process_questions(questions)
  display_completion_summary(responses, questions)

  responses
end

private

def display_feedback_intro(questions, context)
  display_feedback_context(context) if context
  display_question_presentation_header(questions, context)
end

def process_questions(questions)
  questions.each_with_index.with_object({}) do |(question_data, index), responses|
    question_number = question_data[:number] || (index + 1)
    response = process_single_question(question_data, question_number, index, questions.length)
    responses["question_#{question_number}"] = response
  end
end

def process_single_question(question_data, question_number, index, total_questions)
  display_numbered_question(question_data, question_number, index + 1, total_questions)
  response = get_question_response(question_data, question_number)
  validate_required_response(question_data, response)
  display_question_progress(index + 1, total_questions)
  response
end
```

## Ruby Conventions

### General Ruby Style

- Follow [StandardRB](https://github.com/testdouble/standard) guidelines
- Use `frozen_string_literal: true` at the top of all files
- Prefer `require_relative` over `require` for local files
- Use meaningful variable and method names

### Method Design

```ruby
# Good: Clear, descriptive method names
def validate_user_input(input, options = {})
  # method body
end

# Good: Use keyword arguments for clarity
def create_user(name:, email:, role: :user)
  # method body
end

# Bad: Unclear method names
def process(data, opts)
  # method body
end
```

### Error Handling

```ruby
# Good: Specific error handling
def load_configuration(file_path)
  raise ArgumentError, "Configuration file path cannot be nil" if file_path.nil?
  raise FileNotFoundError, "Configuration file not found: #{file_path}" unless File.exist?(file_path)

  # load configuration
rescue JSON::ParserError => e
  raise ConfigurationError, "Invalid JSON in configuration file: #{e.message}"
end

# Bad: Generic error handling
def load_configuration(file_path)
  # load configuration
rescue => e
  puts "Error: #{e.message}"
end
```

## CLI UI Patterns

### Component Organization

When using CLI UI, organize components by responsibility:

```ruby
module Aidp
  module Harness
    module UI
      class QuestionCollector
        def initialize(ui_components = {})
          @prompt = ui_components[:prompt] || CLI::UI::Prompt
          @frame = ui_components[:frame] || CLI::UI::Frame
        end

        def collect_questions(questions)
          @frame.open("Collecting User Feedback") do
            questions.map.with_index do |question, index|
              collect_single_question(question, index + 1)
            end
          end
        end

        private

        def collect_single_question(question, number)
          @prompt.ask("Question #{number}: #{question[:text]}") do |handler|
            question[:options]&.each { |option| handler.option(option) }
          end
        end
      end
    end
  end
end
```

### State Management

Keep UI state separate from business logic:

```ruby
module Aidp
  module Harness
    class UIState
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

      def pause
        @is_paused = true
      end

      def resume
        @is_paused = false
      end
    end
  end
end
```

## Testing Guidelines

### Test Structure and Readability

**Make tests as readable as possible for code review.**

#### Test Descriptions

Each test should have a clear, unambiguous title that describes the expected behavior:

```ruby
# Good: Describes expected behavior
it "enqueues an email after successful validation" do
  # test body
end

it "returns error when configuration file is missing" do
  # test body
end

# Bad: Describes outcome
it "works" do
  # test body
end

it "does the thing" do
  # test body
end
```

#### Context and Describe Blocks

Use descriptive context and describe blocks:

```ruby
# Good: Clear, descriptive context
describe "UserInterface" do
  describe "#collect_feedback" do
    context "when the user has filled the optional age dropdown" do
      it "includes the age in the response hash" do
        # test body
      end
    end

    context "when no questions are provided" do
      it "returns an empty hash" do
        # test body
      end
    end
  end
end

# Bad: Unclear context
describe "UserInterface" do
  describe "#collect_feedback" do
    context "age entered" do
      it "works" do
        # test body
      end
    end
  end
end
```

#### Before Callbacks with Metadata

Use descriptive metadata for before callbacks:

```ruby
# Good: Clear metadata with descriptive names
before(with_logged_in_user: true) { login(:user) }
before(with_mock_provider: true) { setup_mock_provider }

context "when viewing a post", :with_logged_in_user do
  it "displays the post content" do
    # test body
  end
end

context "when provider is rate limited", :with_mock_provider do
  it "switches to fallback provider" do
    # test body
  end
end

# Bad: Unclear before callbacks
before { login(:user) }
before { setup_mock_provider }

context "show post" do
  it "works" do
    # test body
  end
end
```

### Test Organization

```ruby
# Good: Well-organized test file
RSpec.describe Aidp::Harness::UserInterface do
  let(:user_interface) { described_class.new }
  let(:sample_questions) { build_questions }

  describe "#collect_feedback" do
    context "with valid questions" do
      it "returns a hash of responses" do
        result = user_interface.collect_feedback(sample_questions)
        expect(result).to be_a(Hash)
      end

      it "includes all question responses" do
        result = user_interface.collect_feedback(sample_questions)
        expect(result.keys).to match_array(["question_1", "question_2"])
      end
    end

    context "with empty questions array" do
      it "returns an empty hash" do
        result = user_interface.collect_feedback([])
        expect(result).to eq({})
      end
    end
  end

  private

  def build_questions
    [
      { question: "What is your name?", type: "text", required: true },
      { question: "What is your age?", type: "number", required: false }
    ]
  end
end
```

### Mocking and Stubbing

**Only mock external dependencies** - never mock application code. User input can be considered an external dependency.

```ruby
# Good: Mock external dependencies only
describe "ProviderManager" do
  let(:mock_provider) { instance_double("Provider") }
  let(:provider_manager) { described_class.new }

  before do
    allow(mock_provider).to receive(:available?).and_return(true)
    allow(mock_provider).to receive(:make_request).and_return(success_response)
  end

  it "switches to fallback when primary provider fails" do
    allow(mock_provider).to receive(:make_request).and_raise(ProviderError)

    result = provider_manager.execute_request("test prompt")

    expect(result[:status]).to eq("completed")
    expect(result[:provider]).to eq("fallback")
  end
end

# Good: Mock user input (external dependency)
describe "UserInterface" do
  it "collects user responses" do
    allow(Readline).to receive(:readline).and_return("user response")

    result = user_interface.collect_feedback(questions)

    expect(result).to include("question_1" => "user response")
  end
end

# Bad: Mocking application code
describe "UserInterface" do
  it "processes questions" do
    allow(user_interface).to receive(:validate_question).and_return(true) # Don't do this!

    result = user_interface.collect_feedback(questions)

    expect(result).to be_present
  end
end
```

### Sandi Metz's Testing Rules

Based on [Sandi Metz's testing philosophy](https://gist.github.com/Integralist/7944948), focus on testing the interface, not the implementation:

#### Message Types

- **Queries**: Messages that "return something" and "change nothing" (getters)
- **Commands**: Messages that "return nothing" and "change something" (setters)

#### What to Test

- **Incoming query messages**: Make assertions about what they send back
- **Incoming command messages**: Make assertions about direct public side effects

#### What NOT to Test

- Messages sent from within the object itself (private methods)
- Outgoing query messages (they have no public side effects)
- Outgoing command messages (use mocks and set expectations on behavior)
- Incoming messages that have no dependents (just remove those tests)

#### Mocking Strategy

- **Command messages**: Should be mocked
- **Query messages**: Should be stubbed

```ruby
# Good: Testing incoming query message
describe "UserInterface" do
  it "returns collected responses" do
    result = user_interface.collect_feedback(questions)

    expect(result).to be_a(Hash)
    expect(result.keys).to include("question_1")
  end
end

# Good: Testing incoming command message by side effects
describe "StateManager" do
  it "saves state to file" do
    state_manager.save_state(test_state)

    expect(File.exist?(state_file)).to be true
    expect(File.read(state_file)).to include("test_data")
  end
end

# Good: Mocking outgoing command message
describe "ProviderManager" do
  it "logs provider switch" do
    expect(logger).to receive(:info).with("Switching from primary to fallback")

    provider_manager.switch_provider
  end
end
```

## Error Handling

### When to Crash vs. When to Handle

**It's okay for exceptions to cause a crash if the crash will NOT cause:**

- Data loss
- Unrecoverable state
- Data corruption
- Security vulnerabilities
- Silent failures that mask bugs

**Crashing is a good source of signal** - since this is a developer tool, we should not shy away from crashing when appropriate. Use good judgement and don't be overly eager to rescue exceptions.

**Exception Guidelines:**

- **Don't swallow exceptions** that could indicate a bug that should be fixed
- **Do handle exceptions** from external dependencies (unless they indicate user error or misconfiguration)
- **Do crash** when internal state becomes inconsistent
- **Do crash** when configuration is invalid
- **Do crash** when required resources are unavailable

### Error Classes

Create specific error classes for different error types:

```ruby
module Aidp
  module Errors
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end
    class ValidationError < StandardError; end
    class StateError < StandardError; end
    class UserError < StandardError; end  # For user input/configuration errors
  end
end
```

### Error Handling Patterns

```ruby
# Good: Let it crash for internal errors
def execute_step(step_name)
  validate_step_name(step_name)  # Will crash if invalid - that's good!
  result = run_step_logic(step_name)
  log_step_completion(step_name, result)
  result
end

# Good: Handle external dependency errors gracefully
def make_provider_request(prompt)
  provider.make_request(prompt)
rescue ProviderError => e
  if e.message.include?("rate limit")
    handle_rate_limit(e)
  elsif e.message.include?("authentication")
    raise UserError, "Invalid API key. Please check your configuration."
  else
    raise  # Re-raise unexpected provider errors
  end
end

# Good: Crash on configuration errors (user should fix these)
def load_configuration(file_path)
  raise ArgumentError, "Configuration file path cannot be nil" if file_path.nil?
  raise UserError, "Configuration file not found: #{file_path}" unless File.exist?(file_path)

  JSON.parse(File.read(file_path))
rescue JSON::ParserError => e
  raise UserError, "Invalid JSON in configuration file: #{e.message}"
end

# Bad: Swallowing exceptions that indicate bugs
def process_data(data)
  # ... processing logic ...
rescue => e
  puts "Something went wrong"  # Don't do this! We're hiding a potential bug
end

# Bad: Over-eager exception handling
def simple_calculation(a, b)
  a + b
rescue => e
  # Don't rescue basic operations - if this fails, we want to know why
  handle_error(e)
end
```

### Error Recovery Strategies

```ruby
# Good: Recover from external dependency failures
def execute_with_fallback(step_name)
  primary_provider.execute(step_name)
rescue ProviderError => e
  if fallback_provider.available?
    fallback_provider.execute(step_name)
  else
    raise UserError, "All providers unavailable. Please check your configuration."
  end
end

# Good: Don't recover from internal state corruption
def update_state(new_state)
  validate_state(new_state)  # Will crash if state is invalid - that's correct!
  @current_state = new_state
  save_state
end
```

## Documentation

### Code Documentation

```ruby
# Good: Clear, concise documentation
class UserInterface
  # Collects user feedback for a list of questions
  #
  # @param questions [Array<Hash>] Array of question hashes with :question, :type, :required keys
  # @param context [Hash, nil] Optional context information to display before questions
  # @return [Hash] Hash of responses keyed by question number
  # @raise [ValidationError] If questions array is invalid
  def collect_feedback(questions, context = nil)
    # method implementation
  end
end
```

### README Updates

When adding new features:

- Update the main README with usage examples
- Add new commands to the CLI help text
- Document any breaking changes in CHANGELOG.md

## Code Review Guidelines

### What to Look For

- **Sandi Metz's Rules**: Classes < 100 lines, methods < 5 lines, max 4 parameters
- **Test Readability**: Clear descriptions, proper context blocks, descriptive metadata
- **Error Handling**: Specific error types, proper error messages
- **Documentation**: Clear method documentation, updated README
- **CLI UI Patterns**: Proper component organization, state separation

### Review Checklist

- [ ] Classes follow size limits (100 lines max)
- [ ] Methods follow size limits (5 lines max)
- [ ] Test descriptions are clear and behavior-focused
- [ ] Error handling is specific and informative
- [ ] Documentation is updated
- [ ] Code follows StandardRB guidelines
- [ ] No external dependencies in tests (all mocked)

## Examples

### Good Example: Small, Focused Class

```ruby
# frozen_string_literal: true

module Aidp
  module Harness
    class QuestionValidator
      def initialize(question)
        @question = question
      end

      def valid?
        has_required_fields? && valid_type? && valid_options?
      end

      def error_message
        return "Missing required fields" unless has_required_fields?
        return "Invalid question type" unless valid_type?
        return "Invalid options for type" unless valid_options?
      end

      private

      def has_required_fields?
        @question[:question] && @question[:type]
      end

      def valid_type?
        %w[text choice confirmation file number email url].include?(@question[:type])
      end

      def valid_options?
        return true unless @question[:type] == "choice"
        @question[:options] && @question[:options].any?
      end
    end
  end
end
```

### Bad Example: Large, Complex Class

```ruby
# This violates multiple rules - too large, too many responsibilities
class UserInterface
  def initialize
    @input_history = []
    @file_selection_enabled = false
    @control_interface_enabled = true
    @pause_requested = false
    @stop_requested = false
    @resume_requested = false
    @control_thread = nil
    @control_mutex = Mutex.new
    # ... 2000+ more lines
  end

  # ... hundreds of methods doing different things
end
```

---

Remember: **Good code is not just code that works, but code that is easy to understand, modify, and extend.** Following these guidelines helps ensure that AIDP remains maintainable as it grows.
