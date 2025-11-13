# Implementation Guide: Intelligent Test/Linter Output Filtering (Issue #265)

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for reducing token consumption in work loop iterations through intelligent test and linter output filtering. The implementation follows SOLID principles, Domain-Driven Design (DDD), composition-first patterns, and maintains compatibility with AIDP's existing architecture.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [Testing Strategy](#testing-strategy)
7. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
8. [Error Handling Strategy](#error-handling-strategy)
9. [Configuration Schema](#configuration-schema)

---

## Architecture Overview

### Hexagonal Architecture Layers

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ WorkLoopRunner   │           │ Wizard           │        │
│  │ (Orchestration)  │           │ (Configuration)  │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────────────────────────────┐             │
│  │  TestRunner (ENHANCED)                     │             │
│  │  - Executes tests with filtering           │             │
│  │  - Formats output based on mode            │             │
│  │  - Detects framework-specific options      │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  OutputFilter (NEW)                        │             │
│  │  - Filters test/lint output by mode        │             │
│  │  - Parses framework-specific formats       │             │
│  │  - Extracts failure-only content           │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  ToolingDetector (ENHANCED)                │             │
│  │  - Detects test framework capabilities     │             │
│  │  - Suggests optimized commands             │             │
│  │  - Provides filtering recommendations      │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ Configuration    │           │ Shell Execution  │        │
│  │ (aidp.yml)       │           │ (Open3)          │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Composition Over Inheritance**: OutputFilter is composed into TestRunner, not inherited
2. **Single Responsibility**: Each class has one clear purpose
3. **Dependency Injection**: All dependencies injected for testability
4. **Strategy Pattern**: Different filtering strategies for different output modes
5. **Zero Framework Cognition**: Use mini-tier AI for framework detection when uncertain

---

## Domain Model

### Core Entities

#### TestResult (Value Object - Existing, Enhanced)

```ruby
# Represents the result of running tests
{
  success: Boolean,         # All tests passed
  output: String,          # Formatted output (FILTERED in iterations > 1)
  failures: Array<Hash>,   # Detailed failure information
  command: String,         # Command that was executed
  exit_code: Integer,      # Exit status
  mode: Symbol             # :full or :quick
}
```

#### OutputFilterConfig (Value Object - NEW)

```ruby
# Configuration for output filtering behavior
{
  mode: Symbol,              # :full, :failures_only, :minimal
  include_context: Boolean,  # Include surrounding lines for failures
  context_lines: Integer,    # Number of context lines (default: 3)
  max_lines: Integer,        # Maximum lines in output (default: 500)
  framework: Symbol          # :rspec, :minitest, :jest, :pytest, etc.
}
```

#### TestCommand (Value Object - NEW)

```ruby
# Represents a configured test command with its options
{
  command: String,          # Base command (e.g., "bundle exec rspec")
  framework: Symbol,        # Detected framework
  supports_filtering: Boolean,  # Framework has built-in filtering
  filter_flags: Array<String>,  # Framework-specific filter flags
  output_format: Symbol     # :verbose, :normal, :quiet, :minimal
}
```

### Domain Services

#### OutputFilter (NEW)

**Responsibility**: Filter and format test/linter output based on configured mode

**Design Pattern**: Strategy Pattern + Service Object

**Contract**:

```ruby
class Aidp::Harness::OutputFilter
  # @param config [OutputFilterConfig] Filtering configuration
  def initialize(config)
    # Preconditions:
    # - config must be a valid OutputFilterConfig
    # - config.mode must be one of [:full, :failures_only, :minimal]

    # Postconditions:
    # - Initializes with valid configuration
    # - Ready to filter output
  end

  # Filter output based on configuration
  # @param output [String] Raw test/linter output
  # @param framework [Symbol] Test framework identifier
  # @return [String] Filtered output
  def filter(output, framework: :unknown)
    # Preconditions:
    # - output must be a string (may be empty)
    # - framework should be recognized or :unknown

    # Postconditions:
    # - Returns filtered string
    # - Output respects max_lines limit
    # - Preserves critical failure information
  end

  private

  # Extract failure information from RSpec output
  def extract_rspec_failures(output)
  end

  # Extract failure information from Minitest output
  def extract_minitest_failures(output)
  end

  # Extract failure information from Jest output
  def extract_jest_failures(output)
  end

  # Generic failure extraction for unknown frameworks
  def extract_generic_failures(output)
  end
end
```

---

## Design Patterns

### 1. Strategy Pattern (NEW)

**Purpose**: Different filtering strategies for different output modes and frameworks

**Application**: `OutputFilter` uses strategies for each framework

**Benefits**:
- Easy to add new framework support
- Clear separation of filtering logic
- Testable in isolation

**Implementation**:

```ruby
class Aidp::Harness::OutputFilter
  STRATEGIES = {
    rspec: RSpecFilterStrategy,
    minitest: MinitestFilterStrategy,
    jest: JestFilterStrategy,
    pytest: PytestFilterStrategy,
    generic: GenericFilterStrategy
  }.freeze

  def filter(output, framework: :unknown)
    strategy = STRATEGIES[framework] || STRATEGIES[:generic]
    strategy.new(@config).filter(output)
  end
end
```

### 2. Service Object Pattern (Existing, Enhanced)

**Purpose**: Encapsulate test execution and output processing logic

**Application**: `TestRunner` service

**Benefits**:
- Single Responsibility Principle
- Reusable across work loops
- Easily testable

### 3. Composition Pattern (Enhanced)

**Purpose**: Compose complex behavior from simple components

**Application**: TestRunner composes OutputFilter

**Benefits**:
- Loose coupling
- Easy to swap implementations
- Clear dependencies

```ruby
class TestRunner
  def initialize(project_dir, config, output_filter: nil)
    @project_dir = project_dir
    @config = config
    @output_filter = output_filter || build_default_filter
  end

  private

  def build_default_filter
    filter_config = OutputFilterConfig.new(
      mode: @config.test_output_mode || :full,
      include_context: true,
      context_lines: 3,
      max_lines: 500,
      framework: detect_framework
    )
    OutputFilter.new(filter_config)
  end
end
```

### 4. Template Method Pattern (Enhanced)

**Purpose**: Define skeleton of test execution with filtering

**Application**: Test execution pipeline in TestRunner

**Current Structure**:

```ruby
def run_tests
  test_commands = resolved_test_commands
  return {success: true, output: "", failures: []} if test_commands.empty?

  results = test_commands.map { |cmd| execute_command(cmd, "test") }
  aggregate_results(results, "Tests")
end

private

def aggregate_results(results, category)
  failures = results.reject { |r| r[:success] }
  success = failures.empty?

  output = if success
    "#{category}: All passed"
  else
    format_failures(failures, category)  # ENHANCED: Now uses OutputFilter
  end

  {
    success: success,
    output: output,
    failures: failures
  }
end
```

### 5. Builder Pattern (NEW)

**Purpose**: Construct optimized test commands with filtering options

**Application**: Command construction in ToolingDetector

**Benefits**:
- Fluent interface for command building
- Encapsulates framework-specific logic
- Easy to test command construction

```ruby
class TestCommandBuilder
  def initialize(framework, base_command)
    @framework = framework
    @base_command = base_command
    @flags = []
  end

  def with_failures_only
    case @framework
    when :rspec
      @flags << "--only-failures"
    when :jest
      @flags << "--onlyFailures"
    when :pytest
      @flags << "--lf"  # last-failed
    end
    self
  end

  def with_quiet_output
    case @framework
    when :rspec
      @flags << "--format progress"
    when :jest
      @flags << "--silent"
    when :pytest
      @flags << "-q"
    end
    self
  end

  def build
    "#{@base_command} #{@flags.join(" ")}".strip
  end
end
```

### 6. Factory Pattern (NEW)

**Purpose**: Create appropriate filter strategies for different frameworks

**Application**: Strategy selection in OutputFilter

---

## Implementation Contract

### Design by Contract Principles

All public methods must specify:

1. **Preconditions**: What must be true before the method executes
2. **Postconditions**: What will be true after the method executes
3. **Invariants**: What remains true throughout the object's lifetime

### Example Contracts

#### OutputFilter#filter

```ruby
# Filter test/linter output based on configuration
#
# @param output [String] Raw output from test/linter command
# @param framework [Symbol] Framework identifier (:rspec, :jest, etc.)
# @return [String] Filtered output
#
# Preconditions:
#   - output must be a string (may be empty)
#   - framework must be a symbol
#   - self must be initialized with valid config
#
# Postconditions:
#   - Returns a string (never nil)
#   - Output length <= config.max_lines (unless in :full mode)
#   - Failure information is preserved
#   - Success messages may be abbreviated
#
# Invariants:
#   - @config remains unchanged
#   - No side effects on input
def filter(output, framework: :unknown)
  Aidp.log_debug("output_filter", "filtering_output",
    framework: framework,
    mode: @config.mode,
    input_lines: output.lines.count)

  # Implementation

  Aidp.log_debug("output_filter", "filtered_output",
    output_lines: result.lines.count,
    reduction_percent: reduction_percentage(output, result))

  result
end
```

#### TestRunner#format_failures

```ruby
# Format failure output with optional filtering
#
# @param failures [Array<Hash>] Array of failure results
# @param category [String] Category name (e.g., "Tests", "Linters")
# @param mode [Symbol] Output mode (:full, :failures_only, :minimal)
# @return [String] Formatted failure output
#
# Preconditions:
#   - failures must be an array of hashes
#   - each failure must have :command, :exit_code, :stdout, :stderr
#   - category must be a string
#   - mode must be one of [:full, :failures_only, :minimal]
#
# Postconditions:
#   - Returns formatted string with failure information
#   - Output is filtered based on mode
#   - Includes command, exit code, and relevant output
#   - In :failures_only mode, omits passing test details
#
# Side Effects:
#   - Logs filtering activity via Aidp.log_debug
def format_failures(failures, category, mode: :full)
  # Implementation
end
```

#### ToolingDetector.rspec

```ruby
# Detect RSpec configuration and suggest optimized commands
#
# @return [TestCommand] RSpec command configuration
#
# Preconditions:
#   - Called within a Ruby project context
#   - Gemfile exists and contains rspec gem
#
# Postconditions:
#   - Returns TestCommand with framework-specific optimizations
#   - Suggests --only-failures for subsequent runs
#   - Recommends appropriate output format
#
# Example:
#   {
#     command: "bundle exec rspec",
#     framework: :rspec,
#     supports_filtering: true,
#     filter_flags: ["--only-failures", "--format progress"],
#     output_format: :normal
#   }
def self.rspec(root = Dir.pwd)
  # Implementation
end
```

---

## Component Design

### 1. OutputFilter (NEW)

#### File Location

`lib/aidp/harness/output_filter.rb`

#### Class Structure

```ruby
# frozen_string_literal: true

module Aidp
  module Harness
    # Filters test and linter output to reduce token consumption
    # Uses framework-specific strategies to extract relevant information
    class OutputFilter
      # Output modes
      MODES = {
        full: :full,                   # No filtering (default for first run)
        failures_only: :failures_only, # Only failure information
        minimal: :minimal              # Minimal failure info + summary
      }.freeze

      # @param config [Hash] Configuration options
      # @option config [Symbol] :mode Output mode (:full, :failures_only, :minimal)
      # @option config [Boolean] :include_context Include surrounding lines
      # @option config [Integer] :context_lines Number of context lines
      # @option config [Integer] :max_lines Maximum output lines
      def initialize(config = {})
        @mode = config[:mode] || :full
        @include_context = config.fetch(:include_context, true)
        @context_lines = config.fetch(:context_lines, 3)
        @max_lines = config.fetch(:max_lines, 500)

        validate_mode!

        Aidp.log_debug("output_filter", "initialized",
          mode: @mode,
          include_context: @include_context,
          max_lines: @max_lines)
      end

      # Filter output based on framework and mode
      # @param output [String] Raw output
      # @param framework [Symbol] Framework identifier
      # @return [String] Filtered output
      def filter(output, framework: :unknown)
        return output if @mode == :full
        return "" if output.nil? || output.empty?

        Aidp.log_debug("output_filter", "filtering_start",
          framework: framework,
          input_lines: output.lines.count)

        strategy = strategy_for_framework(framework)
        filtered = strategy.filter(output, self)

        truncated = truncate_if_needed(filtered)

        Aidp.log_debug("output_filter", "filtering_complete",
          output_lines: truncated.lines.count,
          reduction: reduction_stats(output, truncated))

        truncated
      end

      # Accessors for strategy use
      attr_reader :mode, :include_context, :context_lines, :max_lines

      private

      def validate_mode!
        unless MODES.key?(@mode)
          raise ArgumentError, "Invalid mode: #{@mode}. Must be one of #{MODES.keys}"
        end
      end

      def strategy_for_framework(framework)
        case framework
        when :rspec
          RSpecFilterStrategy.new
        when :minitest
          MinitestFilterStrategy.new
        when :jest
          JestFilterStrategy.new
        when :pytest
          PytestFilterStrategy.new
        else
          GenericFilterStrategy.new
        end
      end

      def truncate_if_needed(output)
        lines = output.lines
        return output if lines.count <= @max_lines

        truncated = lines.first(@max_lines).join
        truncated + "\n\n[Output truncated - #{lines.count - @max_lines} more lines omitted]"
      end

      def reduction_stats(input, output)
        input_size = input.bytesize
        output_size = output.bytesize
        reduction = ((input_size - output_size).to_f / input_size * 100).round(1)

        {
          input_bytes: input_size,
          output_bytes: output_size,
          reduction_percent: reduction
        }
      end
    end
  end
end
```

#### Filter Strategy Base

```ruby
module Aidp
  module Harness
    # Base class for framework-specific filtering strategies
    class FilterStrategy
      # @param output [String] Raw output
      # @param filter [OutputFilter] Filter instance for config access
      # @return [String] Filtered output
      def filter(output, filter_instance)
        raise NotImplementedError, "Subclasses must implement #filter"
      end

      protected

      # Extract lines around a match (for context)
      def extract_with_context(lines, index, context_lines)
        start_idx = [0, index - context_lines].max
        end_idx = [lines.length - 1, index + context_lines].min

        lines[start_idx..end_idx]
      end

      # Find failure markers in output
      def find_failure_markers(output)
        # Common failure patterns across frameworks
        patterns = [
          /FAILED/i,
          /ERROR/i,
          /FAIL:/i,
          /failures?:/i,
          /\d+\) /,  # Numbered failures
          /^  \d+\)/  # Indented numbered failures
        ]

        lines = output.lines
        markers = []

        lines.each_with_index do |line, index|
          if patterns.any? { |pattern| line.match?(pattern) }
            markers << index
          end
        end

        markers
      end
    end
  end
end
```

#### RSpec Filter Strategy

```ruby
module Aidp
  module Harness
    # RSpec-specific output filtering
    class RSpecFilterStrategy < FilterStrategy
      def filter(output, filter_instance)
        case filter_instance.mode
        when :failures_only
          extract_failures_only(output, filter_instance)
        when :minimal
          extract_minimal(output, filter_instance)
        else
          output
        end
      end

      private

      def extract_failures_only(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract summary line
        if summary = lines.find { |l| l.match?(/^\d+ examples?, \d+ failures?/) }
          parts << "RSpec Summary:"
          parts << summary
          parts << ""
        end

        # Extract failed examples
        in_failure = false
        failure_lines = []

        lines.each_with_index do |line, index|
          # Start of failure section
          if line.match?(/^Failures:/)
            in_failure = true
            failure_lines << line
            next
          end

          # End of failure section (start of pending/seed info)
          if in_failure && (line.match?(/^Finished in/) || line.match?(/^Pending:/))
            in_failure = false
            break
          end

          failure_lines << line if in_failure
        end

        if failure_lines.any?
          parts << failure_lines.join
        end

        parts.join("\n")
      end

      def extract_minimal(output, filter_instance)
        lines = output.lines
        parts = []

        # Extract only summary and failure locations
        if summary = lines.find { |l| l.match?(/^\d+ examples?, \d+ failures?/) }
          parts << summary
        end

        # Extract failure locations (file:line references)
        failure_locations = lines.select { |l| l.match?(/# \.\/\S+:\d+/) }
        if failure_locations.any?
          parts << ""
          parts << "Failed examples:"
          parts.concat(failure_locations.map(&:strip))
        end

        parts.join("\n")
      end
    end
  end
end
```

#### Generic Filter Strategy

```ruby
module Aidp
  module Harness
    # Generic filtering for unknown frameworks
    class GenericFilterStrategy < FilterStrategy
      def filter(output, filter_instance)
        case filter_instance.mode
        when :failures_only
          extract_failure_lines(output, filter_instance)
        when :minimal
          extract_summary(output, filter_instance)
        else
          output
        end
      end

      private

      def extract_failure_lines(output, filter_instance)
        lines = output.lines
        failure_indices = find_failure_markers(output)

        return output if failure_indices.empty?

        # Extract failures with context
        relevant_lines = Set.new
        failure_indices.each do |index|
          if filter_instance.include_context
            range = extract_with_context(lines, index, filter_instance.context_lines)
            range.each { |line_idx| relevant_lines.add(line_idx) }
          else
            relevant_lines.add(index)
          end
        end

        selected = relevant_lines.to_a.sort.map { |idx| lines[idx] }
        selected.join
      end

      def extract_summary(output, filter_instance)
        lines = output.lines

        # Take first line, last line, and any lines with numbers/statistics
        parts = []
        parts << lines.first if lines.first

        summary_lines = lines.select do |line|
          line.match?(/\d+/) || line.match?(/summary|total|passed|failed/i)
        end

        parts.concat(summary_lines.uniq)
        parts << lines.last if lines.last && !parts.include?(lines.last)

        parts.join("\n")
      end
    end
  end
end
```

### 2. TestRunner Enhancements

#### Updated format_failures Method

```ruby
def format_failures(failures, category, mode: :full)
  output = ["#{category} Failures:", ""]

  failures.each do |failure|
    output << "Command: #{failure[:command]}"
    output << "Exit Code: #{failure[:exit_code]}"
    output << "--- Output ---"

    # Apply filtering based on mode and framework
    filtered_stdout = filter_output(failure[:stdout], mode, detect_framework_from_command(failure[:command]))
    filtered_stderr = filter_output(failure[:stderr], mode, :unknown)

    output << filtered_stdout unless filtered_stdout.strip.empty?
    output << filtered_stderr unless filtered_stderr.strip.empty?
    output << ""
  end

  output.join("\n")
end

private

def filter_output(raw_output, mode, framework)
  return raw_output if mode == :full || raw_output.nil? || raw_output.empty?

  filter_config = {
    mode: mode,
    include_context: true,
    context_lines: 3,
    max_lines: 500
  }

  filter = OutputFilter.new(filter_config)
  filter.filter(raw_output, framework: framework)
rescue => e
  Aidp.log_warn("test_runner", "filter_failed",
    error: e.message,
    framework: framework)
  raw_output  # Fallback to unfiltered on error
end

def detect_framework_from_command(command)
  case command
  when /rspec/
    :rspec
  when /minitest/
    :minitest
  when /jest/
    :jest
  when /pytest/
    :pytest
  else
    :unknown
  end
end
```

#### Add Output Mode Support

```ruby
def run_tests
  test_commands = resolved_test_commands
  return {success: true, output: "", failures: []} if test_commands.empty?

  # Use appropriate mode based on iteration count (if available)
  mode = determine_output_mode

  results = test_commands.map { |cmd| execute_command(cmd, "test") }
  aggregate_results(results, "Tests", mode: mode)
end

private

def determine_output_mode
  # First iteration: full output
  # Subsequent iterations: failures only
  if @config.respond_to?(:test_output_mode)
    @config.test_output_mode
  elsif defined?(@iteration_count) && @iteration_count && @iteration_count > 1
    :failures_only
  else
    :full
  end
end
```

### 3. ToolingDetector Enhancements

#### Enhanced RSpec Detection

```ruby
def rspec
  return nil unless rspec?

  base_command = bundle_prefix("rspec")

  # Check if RSpec supports --only-failures (requires rspec-core >= 3.3)
  supports_only_failures = check_rspec_version_support

  filter_flags = []
  filter_flags << "--only-failures" if supports_only_failures
  filter_flags << "--format progress"  # Quieter than default

  {
    command: base_command,
    framework: :rspec,
    supports_filtering: supports_only_failures,
    filter_flags: filter_flags,
    output_format: :normal,
    suggested_full_command: "#{base_command} && #{base_command} --only-failures"
  }
end

private

def check_rspec_version_support
  # Check Gemfile.lock for rspec-core version
  lockfile = File.join(@root, "Gemfile.lock")
  return false unless File.exist?(lockfile)

  content = File.read(lockfile)
  if match = content.match(/rspec-core \((\d+\.\d+)/)
    version = Gem::Version.new(match[1])
    version >= Gem::Version.new("3.3")
  else
    false
  end
rescue
  false
end
```

#### Add Framework Detection Suggestions

```ruby
def detect_with_suggestions
  result = detect

  # Add optimization suggestions for each detected command
  enhanced_result = result.dup
  enhanced_result[:test_commands] = result[:test_commands].map do |cmd|
    enhance_command_with_suggestions(cmd)
  end

  enhanced_result
end

private

def enhance_command_with_suggestions(command)
  framework = detect_framework(command)

  case framework
  when :rspec
    suggest_rspec_optimizations(command)
  when :jest
    suggest_jest_optimizations(command)
  when :pytest
    suggest_pytest_optimizations(command)
  else
    {command: command, framework: :unknown, suggestions: []}
  end
end

def suggest_rspec_optimizations(command)
  {
    command: command,
    framework: :rspec,
    suggestions: [
      "Consider using --only-failures for subsequent runs",
      "Use --format progress for quieter output",
      "Add --fail-fast to stop on first failure"
    ],
    optimized_command: "#{command} --format progress",
    retry_command: "#{command} --only-failures"
  }
end
```

### 4. WorkLoopRunner Integration

#### Update prepare_next_iteration

```ruby
def prepare_next_iteration(test_results, lint_results, diagnostic = nil)
  failures = []

  failures << "## Fix-Forward Iteration #{@iteration_count}"
  failures << ""

  # Re-inject LLM_STYLE_GUIDE at regular intervals
  if should_reinject_style_guide?
    failures << reinject_style_guide_reminder
    failures << ""
  end

  if diagnostic
    failures << "### Diagnostic Summary"
    diagnostic[:failures].each do |failure_info|
      failures << "- #{failure_info[:type].capitalize}: #{failure_info[:count]} failures"
    end
    failures << ""
  end

  # NEW: Apply output filtering for failures
  unless test_results[:success]
    failures << "### Test Failures"
    # test_results[:output] is already filtered by TestRunner
    failures << test_results[:output]
    failures << ""
  end

  unless lint_results[:success]
    failures << "### Linter Failures"
    # lint_results[:output] is already filtered by TestRunner
    failures << lint_results[:output]
    failures << ""
  end

  strategy = build_failure_strategy(test_results, lint_results)
  failures.concat(strategy) unless strategy.empty?

  failures << "**Fix-forward instructions**: Do not rollback changes. Build on what exists and fix the failures above."
  failures << ""

  return if test_results[:success] && lint_results[:success]

  # Append filtered failures to PROMPT.md
  current_prompt = @prompt_manager.read
  updated_prompt = current_prompt + "\n\n---\n\n" + failures.join("\n")
  @prompt_manager.write(updated_prompt, step_name: @step_name)

  display_message("  [NEXT_PATCH] Added filtered failure reports to PROMPT.md", type: :warning)
  display_message("  [TOKEN OPTIMIZATION] Output filtered to reduce token consumption", type: :info)
end
```

### 5. Wizard Configuration

#### Add Test/Lint Output Configuration

```ruby
def configure_test_commands
  existing = get([:work_loop, :test]) || {}

  unit = ask_with_default("Unit test command", existing[:unit] || detect_unit_test_command)
  integration = ask_with_default("Integration test command", existing[:integration])
  e2e = ask_with_default("End-to-end test command", existing[:e2e])

  timeout = ask_with_default("Test timeout (seconds)", (existing[:timeout_seconds] || 1800).to_s) { |value| value.to_i }

  # NEW: Ask about output filtering
  output_mode_choices = [
    ["Full output (verbose)", :full],
    ["Failures only (recommended for work loops)", :failures_only],
    ["Minimal (summary only)", :minimal]
  ]
  output_mode_default = existing[:output_mode] || :failures_only
  output_mode_default_label = output_mode_choices.find { |label, value| value == output_mode_default }&.first

  output_mode = prompt.select("Test output mode for work loop iterations:", default: output_mode_default_label) do |menu|
    output_mode_choices.each { |label, value| menu.choice label, value }
  end

  # NEW: Ask about quick mode (changed files only)
  enable_quick_mode = prompt.yes?(
    "Enable 'quick test' mode (run only tests for changed files)?",
    default: existing.fetch(:enable_quick_mode, false)
  )

  set([:work_loop, :test], {
    unit: unit,
    integration: integration,
    e2e: e2e,
    timeout_seconds: timeout,
    output_mode: output_mode,
    enable_quick_mode: enable_quick_mode
  }.compact)

  validate_command(unit)
  validate_command(integration)
  validate_command(e2e)

  # Display token optimization tip
  if output_mode == :failures_only || output_mode == :minimal
    prompt.say("\n💡 Token Optimization Enabled:")
    prompt.say("  Work loop iterations will use filtered output to reduce token consumption.")
    prompt.say("  First iteration uses full output; subsequent iterations show failures only.")
  end
end

def configure_linting
  existing = get([:work_loop, :lint]) || {}

  lint_cmd = ask_with_default("Lint command", existing[:command] || detect_lint_command)
  format_cmd = ask_with_default("Format command", existing[:format] || detect_format_command)
  autofix = prompt.yes?("Run formatter automatically?", default: existing.fetch(:autofix, false))

  # NEW: Linter output mode
  output_mode_choices = [
    ["Full output", :full],
    ["Errors only", :failures_only],
    ["Summary only", :minimal]
  ]
  output_mode_default = existing[:output_mode] || :failures_only
  output_mode_default_label = output_mode_choices.find { |label, value| value == output_mode_default }&.first

  output_mode = prompt.select("Linter output mode:", default: output_mode_default_label) do |menu|
    output_mode_choices.each { |label, value| menu.choice label, value }
  end

  set([:work_loop, :lint], {
    command: lint_cmd,
    format: format_cmd,
    autofix: autofix,
    output_mode: output_mode
  })

  validate_command(lint_cmd)
  validate_command(format_cmd)
end
```

---

## Configuration Schema

### Extended YAML Schema

```yaml
work_loop:
  test:
    unit: "bundle exec rspec"
    integration: "bundle exec rspec spec/integration"
    e2e: null
    timeout_seconds: 1800

    # NEW: Output filtering configuration
    output_mode: failures_only  # :full, :failures_only, :minimal
    max_output_lines: 500       # Maximum lines in filtered output
    include_context: true        # Include context around failures
    context_lines: 3            # Number of context lines

    # NEW: Quick mode (changed files only)
    enable_quick_mode: false
    quick_mode_command: "bundle exec rspec --only-failures"

    # NEW: Framework-specific options
    framework_options:
      rspec:
        format: progress          # :progress, :documentation, :json
        fail_fast: false          # Stop on first failure
        only_failures: true       # Run only previously failed specs
      jest:
        silent: true              # Suppress verbose output
        only_failures: true       # --onlyFailures flag
      pytest:
        verbosity: quiet          # :quiet, :normal, :verbose
        last_failed: true         # --lf flag

  lint:
    command: "bundle exec standardrb"
    format: "bundle exec standardrb --fix"
    autofix: false

    # NEW: Linter output filtering
    output_mode: failures_only    # :full, :failures_only, :minimal
    max_output_lines: 300         # Linters typically have shorter output
```

### Configuration Accessor Methods

Add to `Configuration` class:

```ruby
# Get test output mode
def test_output_mode
  work_loop_config.dig(:test, :output_mode) || :full
end

# Get max output lines for tests
def test_max_output_lines
  work_loop_config.dig(:test, :max_output_lines) || 500
end

# Check if quick mode is enabled
def test_quick_mode_enabled?
  work_loop_config.dig(:test, :enable_quick_mode) == true
end

# Get quick mode command
def test_quick_mode_command
  work_loop_config.dig(:test, :quick_mode_command)
end

# Get framework-specific options
def test_framework_options(framework)
  work_loop_config.dig(:test, :framework_options, framework.to_sym) || {}
end

# Get lint output mode
def lint_output_mode
  work_loop_config.dig(:lint, :output_mode) || :full
end

# Get max output lines for linters
def lint_max_output_lines
  work_loop_config.dig(:lint, :max_output_lines) || 300
end
```

---

## Testing Strategy

### Unit Tests

#### OutputFilter Specs

**File**: `spec/aidp/harness/output_filter_spec.rb`

```ruby
RSpec.describe Aidp::Harness::OutputFilter do
  describe "#initialize" do
    it "accepts valid configuration" do
      config = {
        mode: :failures_only,
        include_context: true,
        context_lines: 5,
        max_lines: 100
      }

      expect { described_class.new(config) }.not_to raise_error
    end

    it "raises error for invalid mode" do
      config = {mode: :invalid_mode}

      expect { described_class.new(config) }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "uses default values when not specified" do
      filter = described_class.new

      expect(filter.mode).to eq(:full)
      expect(filter.max_lines).to eq(500)
    end
  end

  describe "#filter" do
    let(:filter) { described_class.new(mode: :failures_only, max_lines: 100) }

    context "with RSpec output" do
      let(:rspec_output) do
        <<~OUTPUT
          .....F...F.

          Failures:

          1) User validates email format
             Failure/Error: expect(user.valid?).to be_truthy

               expected: truthy value
                    got: false

             # ./spec/models/user_spec.rb:45:in `block (3 levels) in <top (required)>'

          2) User requires password
             Failure/Error: expect(user.errors[:password]).to be_empty

               expected: []
                    got: ["can't be blank"]

             # ./spec/models/user_spec.rb:67:in `block (3 levels) in <top (required)>'

          Finished in 2.34 seconds
          100 examples, 2 failures
        OUTPUT
      end

      it "extracts only failure information" do
        result = filter.filter(rspec_output, framework: :rspec)

        expect(result).to include("Failures:")
        expect(result).to include("1) User validates email format")
        expect(result).to include("2) User requires password")
        expect(result).to include("100 examples, 2 failures")
        expect(result).not_to include("Finished in 2.34 seconds")
      end

      it "reduces output size significantly" do
        result = filter.filter(rspec_output, framework: :rspec)

        expect(result.bytesize).to be < rspec_output.bytesize
      end
    end

    context "with full mode" do
      let(:full_filter) { described_class.new(mode: :full) }

      it "returns output unchanged" do
        output = "Some test output\nwith multiple lines"
        result = full_filter.filter(output, framework: :rspec)

        expect(result).to eq(output)
      end
    end

    context "with minimal mode" do
      let(:minimal_filter) { described_class.new(mode: :minimal) }

      it "returns only summary information" do
        rspec_output = <<~OUTPUT
          ..F..

          Failures:
          (lots of failure details)

          100 examples, 1 failure
          # ./spec/models/user_spec.rb:45
        OUTPUT

        result = minimal_filter.filter(rspec_output, framework: :rspec)

        expect(result).to include("100 examples, 1 failure")
        expect(result).to include("./spec/models/user_spec.rb:45")
        expect(result).not_to include("lots of failure details")
      end
    end

    context "when output exceeds max_lines" do
      let(:filter) { described_class.new(mode: :failures_only, max_lines: 5) }

      it "truncates output" do
        long_output = (1..100).map { |i| "Line #{i}\n" }.join
        result = filter.filter(long_output, framework: :unknown)

        expect(result.lines.count).to be <= 6  # 5 lines + truncation message
        expect(result).to include("[Output truncated")
      end
    end
  end
end
```

#### RSpecFilterStrategy Specs

**File**: `spec/aidp/harness/rspec_filter_strategy_spec.rb`

```ruby
RSpec.describe Aidp::Harness::RSpecFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:rspec_output) do
        <<~OUTPUT
          Randomized with seed 12345

          ........F......F....

          Failures:

          1) UserService#create_user with valid params creates a user
             Failure/Error: expect(user).to be_persisted

               expected #<User id: nil> to be persisted

             # ./spec/services/user_service_spec.rb:23:in `block (4 levels) in <top (required)>'

          2) UserService#create_user with invalid params returns error
             Failure/Error: expect(result[:errors]).to be_present

               expected `nil.present?` to be truthy, got false

             # ./spec/services/user_service_spec.rb:45:in `block (4 levels) in <top (required)>'

          Finished in 3.14 seconds (files took 2.7 seconds to load)
          20 examples, 2 failures

          Failed examples:

          rspec ./spec/services/user_service_spec.rb:20 # UserService#create_user with valid params creates a user
          rspec ./spec/services/user_service_spec.rb:42 # UserService#create_user with invalid params returns error

          Randomized with seed 12345
        OUTPUT
      end

      it "extracts failures section" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).to include("RSpec Summary:")
        expect(result).to include("20 examples, 2 failures")
        expect(result).to include("Failures:")
        expect(result).to include("1) UserService#create_user")
        expect(result).to include("2) UserService#create_user")
      end

      it "omits timing and seed information" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).not_to include("Finished in 3.14 seconds")
        expect(result).not_to include("Randomized with seed")
      end

      it "includes failure details and locations" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).to include("Failure/Error:")
        expect(result).to include("./spec/services/user_service_spec.rb:23")
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }

      it "returns only summary and locations" do
        rspec_output = <<~OUTPUT
          ..F..

          Failures:
          (detailed failure output)

          5 examples, 1 failure

          Failed examples:
          rspec ./spec/models/user_spec.rb:45
        OUTPUT

        result = strategy.filter(rspec_output, minimal_instance)

        expect(result).to include("5 examples, 1 failure")
        expect(result).to include("./spec/models/user_spec.rb:45")
        expect(result).not_to include("detailed failure output")
      end
    end

    context "with all passing tests" do
      let(:passing_output) do
        <<~OUTPUT
          ....................

          Finished in 1.23 seconds
          20 examples, 0 failures
        OUTPUT
      end

      it "returns summary only" do
        result = strategy.filter(passing_output, filter_instance)

        expect(result).to include("20 examples, 0 failures")
        expect(result.lines.count).to be < 5
      end
    end
  end
end
```

#### TestRunner Integration Specs

**File**: `spec/aidp/harness/test_runner_spec.rb` (additions)

```ruby
RSpec.describe Aidp::Harness::TestRunner do
  describe "#format_failures with output filtering" do
    let(:project_dir) { "/tmp/test_project" }
    let(:config) { double("config", test_output_mode: :failures_only, lint_output_mode: :failures_only) }
    let(:runner) { described_class.new(project_dir, config) }

    let(:failures) do
      [
        {
          command: "bundle exec rspec",
          exit_code: 1,
          stdout: long_rspec_output,
          stderr: ""
        }
      ]
    end

    let(:long_rspec_output) do
      # Simulate 1000 lines of RSpec output
      (["."] * 500).join + "\n\n" +
      "Failures:\n\n" +
      (1..50).map { |i| "#{i}) Failure details line #{i}\n" }.join +
      "\n100 examples, 50 failures\n"
    end

    it "filters output in failures_only mode" do
      result = runner.send(:format_failures, failures, "Tests", mode: :failures_only)

      # Filtered output should be much shorter
      expect(result.lines.count).to be < long_rspec_output.lines.count

      # Should still contain failure information
      expect(result).to include("Failures:")
      expect(result).to include("100 examples, 50 failures")
    end

    it "respects max_lines limit" do
      allow(config).to receive(:test_max_output_lines).and_return(10)

      result = runner.send(:format_failures, failures, "Tests", mode: :failures_only)

      # Should not exceed configured limit (plus some overhead for headers)
      expect(result.lines.count).to be <= 20
    end

    it "falls back to full output if filtering fails" do
      # Simulate filter error
      allow_any_instance_of(Aidp::Harness::OutputFilter).to receive(:filter).and_raise("Filter error")

      result = runner.send(:format_failures, failures, "Tests", mode: :failures_only)

      # Should include full output as fallback
      expect(result).to include(long_rspec_output)
    end
  end

  describe "#determine_output_mode" do
    let(:project_dir) { "/tmp/test_project" }

    context "with explicit configuration" do
      let(:config) { double("config", test_output_mode: :minimal, respond_to?: ->(m) { m == :test_output_mode }) }
      let(:runner) { described_class.new(project_dir, config) }

      it "uses configured mode" do
        expect(runner.send(:determine_output_mode)).to eq(:minimal)
      end
    end

    context "without explicit configuration" do
      let(:config) { double("config", respond_to?: ->(_) { false }) }
      let(:runner) { described_class.new(project_dir, config) }

      it "defaults to full mode" do
        expect(runner.send(:determine_output_mode)).to eq(:full)
      end
    end
  end
end
```

### Integration Tests

#### Work Loop Integration Spec

**File**: `spec/integration/work_loop_output_filtering_spec.rb`

```ruby
RSpec.describe "Work Loop Output Filtering", type: :integration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_path) { File.join(temp_dir, ".aidp", "aidp.yml") }

  before do
    # Set up minimal test project
    FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
    FileUtils.mkdir_p(File.join(temp_dir, "spec"))

    # Create config with output filtering
    config = {
      "work_loop" => {
        "test" => {
          "unit" => "bundle exec rspec",
          "output_mode" => "failures_only",
          "max_output_lines" => 100
        }
      }
    }
    File.write(config_path, YAML.dump(config))

    # Create failing spec
    spec_file = File.join(temp_dir, "spec", "example_spec.rb")
    File.write(spec_file, <<~RUBY)
      RSpec.describe "Example" do
        it "fails" do
          expect(1).to eq(2)
        end

        it "passes" do
          expect(1).to eq(1)
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  it "applies output filtering in work loop iterations" do
    # Simulate work loop execution
    config = Aidp::Harness::Configuration.new(temp_dir)
    runner = Aidp::Harness::TestRunner.new(temp_dir, config)

    result = runner.run_tests

    # Should have failures
    expect(result[:success]).to be false
    expect(result[:failures]).not_to be_empty

    # Output should be filtered
    output = result[:output]
    expect(output).to include("Failures:")
    expect(output.lines.count).to be < 50  # Much less than full RSpec output
  end

  it "includes failure details in filtered output" do
    config = Aidp::Harness::Configuration.new(temp_dir)
    runner = Aidp::Harness::TestRunner.new(temp_dir, config)

    result = runner.run_tests
    output = result[:output]

    # Should include actionable failure information
    expect(output).to include("expect(1).to eq(2)")
    expect(output).to match(/spec\/example_spec\.rb:\d+/)
  end
end
```

---

## Pattern-to-Use-Case Matrix

| Use Case | Primary Pattern | Supporting Patterns | Rationale |
|----------|----------------|---------------------|-----------|
| Filter test output | Strategy | Factory, Service Object | Different strategies per framework |
| Compose filtering into TestRunner | Composition | Dependency Injection | Loose coupling, testable |
| Build optimized commands | Builder | Template Method | Fluent interface for command construction |
| Detect framework capabilities | Service Object | Strategy | Single responsibility, reusable |
| Configure output filtering | Configuration | Repository | Centralized config management |
| Handle filtering errors | Error Handling | Null Object | Graceful degradation, observability |
| Extract failure information | Template Method | Strategy | Reuse structure, customize per framework |
| Truncate long output | Decorator | - | Add behavior without modifying original |

---

## Error Handling Strategy

### Principle: Fail Fast for Bugs, Graceful Degradation for External Issues

#### Fail Fast (Raise Errors)

- Invalid configuration (unknown mode, negative limits)
- Programming errors (nil checks, type mismatches)
- Invalid framework identifiers in strategy selection

#### Graceful Degradation (Log and Continue)

- Filtering failures (return unfiltered output)
- Framework detection failures (use generic strategy)
- Command execution failures (already handled by TestRunner)

### Error Handling Implementation

```ruby
def filter(output, framework: :unknown)
  # Validate preconditions - fail fast
  raise ArgumentError, "output must be a string" unless output.is_a?(String)

  return output if @mode == :full
  return "" if output.empty?

  begin
    strategy = strategy_for_framework(framework)
    filtered = strategy.filter(output, self)
    truncate_if_needed(filtered)
  rescue StandardError => e
    # External failure - graceful degradation
    Aidp.log_error("output_filter", "filtering_failed",
      framework: framework,
      mode: @mode,
      error: e.message,
      error_class: e.class.name)

    # Return original output as fallback
    output
  end
end
```

### Logging Strategy

**Use `Aidp.log_*` extensively**:

```ruby
# Method entry
Aidp.log_debug("output_filter", "filtering_start",
  framework: framework,
  mode: mode,
  input_lines: output.lines.count)

# Success with metrics
Aidp.log_info("output_filter", "filtering_complete",
  framework: framework,
  output_lines: result.lines.count,
  reduction_percent: reduction,
  duration_ms: duration)

# Graceful degradation
Aidp.log_warn("output_filter", "unknown_framework",
  framework: framework,
  fallback: "generic strategy")

# Error conditions
Aidp.log_error("output_filter", "strategy_failed",
  framework: framework,
  error: e.message,
  using_fallback: true)
```

---

## Summary

This implementation guide provides:

1. **Architectural Foundation**: Hexagonal architecture with clear layers and boundaries
2. **Design Patterns**: Strategy, Composition, Builder, Service Object, Template Method
3. **Contracts**: Preconditions, postconditions, and invariants for all public methods
4. **Component Design**: Detailed implementation for OutputFilter, TestRunner, ToolingDetector, and Wizard
5. **Testing Strategy**: Comprehensive unit and integration test specifications
6. **Error Handling**: Fail-fast for bugs, graceful degradation for external failures
7. **Configuration Schema**: Extended YAML configuration with sensible defaults
8. **Observability**: Extensive logging and metrics recommendations

The implementation follows AIDP's engineering principles:

- **SOLID Principles**: Single responsibility, composition, dependency inversion
- **Domain-Driven Design**: Clear domain models, value objects, and services
- **Composition First**: Favor composition over inheritance throughout
- **Design by Contract**: Explicit preconditions, postconditions, and invariants
- **Instrumentation**: Extensive logging with `Aidp.log_debug/info/warn/error`
- **Testability**: Dependency injection, clear interfaces, comprehensive specs

This guide enables implementation with confidence, clarity, and adherence to AIDP's standards.
