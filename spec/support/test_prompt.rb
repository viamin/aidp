# frozen_string_literal: true

# Test prompt class - implements TTY::Prompt interface for testing
# This provides a mock/spy implementation that records all interactions
# for testing TTY::Prompt-based classes without actual user interaction.
class TestPrompt
  attr_reader :messages, :selections, :inputs

  def initialize(responses: {})
    @responses = responses
    @messages = []
    @selections = []
    @inputs = []
  end

  def select(title, items, **options)
    @selections << {title: title, items: items, options: options}
    @responses[:select] || (items.is_a?(Hash) ? items.values.first : items.first)
  end

  def multi_select(title, items, **options)
    @selections << {title: title, items: items, options: options, multi: true}
    @responses[:multi_select] || []
  end

  def ask(message, **options)
    @inputs << {message: message, options: options}
    @responses[:ask] || ""
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
    @responses[:keypress] || ""
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
