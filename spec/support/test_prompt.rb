# frozen_string_literal: true

# Mock menu class for TTY::Prompt select blocks
class MockMenu
  attr_reader :choices

  def initialize
    @choices = []
  end

  def choice(label, value = nil)
    @choices << {label: label, value: value || label}
  end
end

# Test prompt class - implements TTY::Prompt interface for testing
# This provides a mock/spy implementation that records all interactions
# for testing TTY::Prompt-based classes without actual user interaction.
class TestPrompt
  attr_reader :messages, :selections, :inputs, :responses

  def initialize(responses: {})
    @responses = responses
    @messages = []
    @selections = []
    @inputs = []
  end

  def select(title, items = nil, **options, &block)
    if block_given?
      # Handle block-style select (like TTY::Prompt)
      menu = MockMenu.new
      block.call(menu)
      @selections << {title: title, items: menu.choices, options: options, block: true}
      # Priority: explicit map, then sequence array, then single value, else first menu choice
      if @responses[:select_map]
        # Exact match first
        if @responses[:select_map].key?(title)
          val = @responses[:select_map][title]
          return val.is_a?(Array) ? val.shift : val
        end
        # Fallback prefix match (handles dynamic suffixes like " (current: xyz)")
        key = @responses[:select_map].keys.find { |k| title.start_with?(k) }
        if key
          val = @responses[:select_map][key]
          return val.is_a?(Array) ? val.shift : val
        end
      end
      if @responses[:select].is_a?(Array)
        return @responses[:select].shift
      end
      @responses[:select] || menu.choices.first[:value]
    else
      @selections << {title: title, items: items, options: options}
      if @responses[:select_map]
        if @responses[:select_map].key?(title)
          val = @responses[:select_map][title]
          return val.is_a?(Array) ? val.shift : val
        end
        key = @responses[:select_map].keys.find { |k| title.start_with?(k) }
        if key
          val = @responses[:select_map][key]
          return val.is_a?(Array) ? val.shift : val
        end
      end
      if @responses[:select].is_a?(Array)
        return @responses[:select].shift
      end
      @responses[:select] || (items.is_a?(Hash) ? items.values.first : items.first)
    end
  end

  def multi_select(title, items = nil, **options)
    if block_given?
      menu = MockMenu.new
      yield menu
      @selections << {title: title, items: menu.choices, options: options, multi: true, block: true}
    else
      @selections << {title: title, items: items, options: options, multi: true}
    end
    if @responses[:multi_select_map]&.key?(title)
      mapped = @responses[:multi_select_map][title]
      return mapped.is_a?(Array) ? mapped : Array(mapped)
    end
    if @responses[:multi_select].is_a?(Array)
      return @responses[:multi_select]
    end
    @responses[:multi_select] || []
  end

  def ask(message, **options, &block)
    @inputs << {message: message, options: options}

    # Handle multiple responses by cycling through them
    response = if @responses[:ask].is_a?(Array)
      @responses[:ask][@inputs.length - 1] || @responses[:ask].last
    else
      @responses[:ask] || ""
    end

    # If a block is provided, simulate the conversion logic
    if block
      # Create a mock question object that can handle conversion
      question_mock = Object.new
      question_mock.define_singleton_method(:convert) do |type|
        case type
        when :int
          response = response.to_i
        when :float
          response = response.to_f
        end
      end
      question_mock.define_singleton_method(:validate) do |pattern, message|
        # Skip validation for test purposes
      end
      block.call(question_mock)
    end

    response
  end

  def yes?(message, **options)
    @inputs << {message: message, options: options, type: :yes}
    if @responses[:yes_map]&.key?(message)
      val = @responses[:yes_map][message]
      return val.is_a?(Array) ? val.shift : val
    end
    if @responses[:yes?].is_a?(Array)
      return @responses[:yes?].shift
    end
    @responses.key?(:yes?) ? @responses[:yes?] : true
  end

  def no?(message, **options)
    @inputs << {message: message, options: options, type: :no}
    if @responses[:no_map]&.key?(message)
      val = @responses[:no_map][message]
      return val.is_a?(Array) ? val.shift : val
    end
    if @responses[:no?].is_a?(Array)
      return @responses[:no?].shift
    end
    @responses.key?(:no?) ? @responses[:no?] : false
  end

  # Patterns for noisy messages that should be suppressed in test output
  SUPPRESS_PATTERNS = [
    # Work loop messages
    /🔄 Starting hybrid work loop/,
    /Flow: Deterministic/,
    /State machine:/,
    /Iteration \d+/,
    /Required checks failed/,
    /\[DIAGNOSE\]/,
    /\[NEXT_PATCH\]/,
    /\[STYLE_GUIDE\]/,
    /⚠️  Max iterations/,
    /✅ Step /,
    /📊 Fix-Forward State Summary/,
    /Total iterations:/,
    /State transitions:/,
    /All checks passed but/,
    /💡 Using tier:/,
    /Created PROMPT\.md/,
    /Created optimized PROMPT\.md/,

    # Provider/model messages
    /🔄 Provider switch:/,
    /🔄 Model switch:/,
    /🔴 Circuit breaker opened/,
    /🟢 Circuit breaker reset/,
    /❌ No providers available/,
    /❌ No models available/,
    /📊 Execution Summary/,

    # Workstream execution messages
    /▶️  \[/,
    /✅ \[/,
    /❌ \[/,

    # GitHub/Issue messages
    /🏷️  Updated labels:/,
    /🏷️  Removed .* label/,
    /🏷️  Replaced .* with .* label/,
    /🧠 Generating plan/,
    /💬 Posted plan comment/,
    /💬 Posted.*comment/,
    /💬 Posted clarification request/,
    /🎉 Posted completion comment/,
    /🎉 Posted success comment/,
    /📝 Updated plan comment/,
    /📝 Processing change request/,
    /📝 Processing \d+ .* files/,
    /💾 Writing knowledge base/,

    # Checkpoint messages
    /📊 Checkpoint - Iteration/,
    /📜 Checkpoint History/,
    /Progress: \[=+\s*\]/,

    # Workstream messages
    /🔄 Reusing existing workstream:/,
    /🛠️  Starting implementation/,
    /🛠️  Running deterministic unit:/,
    /🌿 Creating workstream:/,
    /🌿 Checked out branch:/,
    /✅ Workstream created/,
    /ℹ️  Workstream .* preserved/,
    /📝 Wrote PROMPT\.md/,
    /💾 Created commit:/,
    /⬆️  Pushed branch/,
    /⬆️  Pushed changes to/,
    /ℹ️  Skipping PR creation/,
    /❌ Implementation failed/,
    /⚠️  Build failure recorded/,
    /⚠️  No recorded plan/,
    /⚠️  Completion criteria unmet/,
    /⚠️  Implementation produced no changes/,
    /ℹ️  No file changes detected/,

    # CLI/Startup messages
    /AIDP initializing\.\.\./,
    /Press Ctrl\+C to stop/,
    /✅ Harness completed successfully/,
    /All steps finished automatically/,
    /Usage: aidp \[COMMAND\]/,
    /AI Development Pipeline/,

    # Watch mode safety messages
    /⚠️  Watch mode running outside container/,
    /Consider using a containerized environment/,
    /✅ Watch mode safety checks passed/,
    /⚠️  Watch mode enabled for PUBLIC repository/,
    /Ensure you trust all contributors/,
    /⚠️  Watch mode safety checks BYPASSED/,
    /⏭️  Skipping issue.*not authorized/,

    # Configuration messages
    /Failed to load configuration file/,

    # Formatting
    /────+/,  # Separator lines
    /====+/   # Separator lines
  ].freeze

  def say(message, **options)
    message_str = message.to_s

    # Suppress noisy messages in test output but still record them
    @messages << {message: message, options: options, type: :say}

    # Don't print to stdout if it matches suppression patterns
    return @responses[:say] if SUPPRESS_PATTERNS.any? { |pattern| message_str.match?(pattern) }

    @responses[:say]
  end

  def warn(message, **options)
    @messages << {message: message, options: options, type: :warn}
    @responses[:warn]
  end

  def error(message, **options)
    @messages << {message: message, options: options, type: :error}
    @responses[:error]
  end

  def ok(message, **options)
    @messages << {message: message, options: options, type: :ok}
    @responses[:ok]
  end

  def keypress(message, **options)
    @inputs << {message: message, options: options, type: :keypress}
    @responses[:keypress] || "\n"
  end

  # Additional methods that some classes might use
  def mask(message, **options)
    @inputs << {message: message, options: options, type: :mask}
    @responses[:mask] || ""
  end

  def confirm(message, **options)
    @inputs << {message: message, options: options, type: :confirm}
    @responses.key?(:confirm) ? @responses[:confirm] : true
  end

  def expand(message, choices, **options)
    @selections << {message: message, choices: choices, options: options, type: :expand}
    @responses[:expand] || choices.first[:value]
  end

  def slider(message, **options)
    @inputs << {message: message, options: options, type: :slider}
    @responses[:slider] || (options[:default] || 5)
  end

  def enum_select(message, choices, **options)
    @selections << {message: message, choices: choices, options: options, type: :enum_select}
    @responses[:enum_select] || choices.first
  end

  # Reset all recorded interactions - useful for testing multiple interactions
  def reset!
    @messages.clear
    @selections.clear
    @inputs.clear
  end

  # Convenience methods for testing
  def last_message
    @messages.last
  end

  def last_selection
    @selections.last
  end

  def last_input
    @inputs.last
  end

  def message_count
    @messages.length
  end

  def selection_count
    @selections.length
  end

  def input_count
    @inputs.length
  end
end
