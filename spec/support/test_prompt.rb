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
      @responses[:select] || menu.choices.first[:value]
    else
      @selections << {title: title, items: items, options: options}
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
    @responses[:yes?] || true
  end

  def no?(message, **options)
    @inputs << {message: message, options: options, type: :no}
    @responses[:no?] || false
  end

  def say(message, **options)
    @messages << {message: message, options: options, type: :say}
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
    @responses[:confirm] || true
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
