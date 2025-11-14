# frozen_string_literal: true

require "tty-prompt"

module Aidp
  # Mixin providing a consistent display_message helper across classes.
  # Usage:
  #   include Aidp::MessageDisplay
  #   display_message("Hello", type: :success)
  # Supports color types: :error, :success, :warning, :info, :highlight, :muted
  module MessageDisplay
    COLOR_MAP = {
      error: :red,
      success: :green,
      warning: :yellow,
      warn: :yellow,
      info: :blue,
      highlight: :cyan,
      muted: :bright_black
    }.freeze

    def self.included(base)
      base.extend(ClassMethods)
    end

    # Instance helper for displaying a colored message via TTY::Prompt
    def display_message(message, type: :info)
      return if suppress_display_message?(message)
      # Ensure message is UTF-8 encoded to handle emoji and special characters
      message_str = message.to_s
      message_str = message_str.force_encoding("UTF-8") if message_str.encoding.name == "ASCII-8BIT"
      message_str = message_str.encode("UTF-8", invalid: :replace, undef: :replace)
      prompt = message_display_prompt
      prompt.say(message_str, color: COLOR_MAP.fetch(type, :white))
    end

    # Provide a memoized prompt per including instance (if it defines @prompt)
    def message_display_prompt
      if instance_variable_defined?(:@prompt) && @prompt
        @prompt
      else
        @__message_display_prompt ||= TTY::Prompt.new
      end
    end

    # Check if specific display message should be suppressed in test/CI environments
    def suppress_display_message?(message)
      return false unless in_test_environment?

      message_str = message.to_s
      # Only suppress specific automated status messages, not CLI output
      message_str.include?("🔄 Provider switch:") ||
        message_str.include?("🔄 Model switch:") ||
        message_str.include?("🔴 Circuit breaker opened") ||
        message_str.include?("🟢 Circuit breaker reset") ||
        message_str.include?("❌ No providers available") ||
        message_str.include?("❌ No models available") ||
        message_str.include?("📊 Execution Summary") ||
        message_str.include?("▶️  [") ||  # Workstream execution messages
        message_str.include?("✅ [") ||    # Workstream success messages
        message_str.include?("❌ [")       # Workstream failure messages
    end

    def in_test_environment?
      ENV["RSPEC_RUNNING"] || ENV["CI"] || ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
    end

    module ClassMethods
      # Class-level display helper (uses fresh prompt to respect $stdout changes)
      def display_message(message, type: :info)
        return if suppress_display_message?(message)
        # Ensure message is UTF-8 encoded to handle emoji and special characters
        message_str = message.to_s
        message_str = message_str.force_encoding("UTF-8") if message_str.encoding.name == "ASCII-8BIT"
        message_str = message_str.encode("UTF-8", invalid: :replace, undef: :replace)
        class_message_display_prompt.say(message_str, color: COLOR_MAP.fetch(type, :white))
      end

      private

      # Check if specific display message should be suppressed in test/CI environments
      def suppress_display_message?(message)
        return false unless in_test_environment?

        message_str = message.to_s
        # Only suppress specific automated status messages, not CLI output
        message_str.include?("🔄 Provider switch:") ||
          message_str.include?("🔄 Model switch:") ||
          message_str.include?("🔴 Circuit breaker opened") ||
          message_str.include?("🟢 Circuit breaker reset") ||
          message_str.include?("❌ No providers available") ||
          message_str.include?("❌ No models available") ||
          message_str.include?("📊 Execution Summary") ||
          message_str.include?("▶️  [") ||  # Workstream execution messages
          message_str.include?("✅ [") ||    # Workstream success messages
          message_str.include?("❌ [")       # Workstream failure messages
      end

      def in_test_environment?
        ENV["RSPEC_RUNNING"] || ENV["CI"] || ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"
      end

      # Don't memoize - create fresh prompt each time to respect $stdout redirection in tests
      def class_message_display_prompt
        TTY::Prompt.new
      end
    end
  end
end
