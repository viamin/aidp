# frozen_string_literal: true

module Aidp
  # Mixin module for easy debug integration across the codebase
  module DebugMixin
    # Debug levels
    DEBUG_OFF = 0
    DEBUG_BASIC = 1 # Commands and stderr
    DEBUG_VERBOSE = 2 # Everything including prompts and stdout

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Class-level debug configuration
      def debug_enabled?
        ENV["DEBUG"] && ENV["DEBUG"].to_i > 0
      end

      def debug_level
        ENV["DEBUG"]&.to_i || DEBUG_OFF
      end
    end

    # Shared logger instance across all classes using DebugMixin
    def self.shared_logger
      Aidp.logger
    end

    # Instance-level debug methods
    def debug_enabled?
      self.class.debug_enabled?
    end

    def debug_level
      self.class.debug_level
    end

    def debug_basic?
      debug_level >= DEBUG_BASIC
    end

    def debug_verbose?
      debug_level >= DEBUG_VERBOSE
    end

    # Get or create debug logger instance (shared across all instances)
    def debug_logger
      Aidp::DebugMixin.shared_logger
    end

    # Log debug information with automatic level detection
    def debug_log(message, level: :info, data: nil)
      return unless debug_enabled?

      debug_logger.log(level, component_name, message, **data) if data
      debug_logger.log(level, component_name, message) unless data
    end

    # Log command execution with debug details
    def debug_command(cmd, args: [], input: nil, output: nil, error: nil, exit_code: nil)
      return unless debug_basic?

      command_str = [cmd, *args].join(" ")

      debug_logger.info(component_name, "🔧 Executing command: #{command_str}")

      if input
        if input.is_a?(String) && input.length > 200
          # If input is long, show first 100 chars and indicate it's truncated
          debug_logger.info(component_name, "📝 Input (truncated): #{input[0..100]}...")
        elsif input.is_a?(String) && File.exist?(input)
          debug_logger.info(component_name, "📝 Input file: #{input}")
        else
          debug_logger.info(component_name, "📝 Input: #{input}")
        end
      end

      if error && !error.empty?
        debug_logger.error(component_name, "❌ Error output: #{error}")
      end

      if debug_verbose?
        if output && !output.empty?
          debug_logger.debug(component_name, "📤 Output: #{output}")
        end

        if exit_code
          debug_logger.debug(component_name, "🏁 Exit code: #{exit_code}")
        end
      end
    end

    # Log step execution with context
    def debug_step(step_name, action, details = {})
      return unless debug_basic?

      message = "🔄 #{action}: #{step_name}"
      debug_logger.info(component_name, message, **details)
    end

    # Log provider interaction
    def debug_provider(provider_name, action, details = {})
      return unless debug_basic?

      message = "🤖 #{action}"
      debug_logger.info("provider_#{provider_name}", message, **details)
    end

    # Log error with debug context
    def debug_error(error, context = {})
      return unless debug_basic?

      error_message = "💥 Error: #{error.class.name}: #{error.message}"
      debug_logger.error(component_name, error_message, error: error.class.name, **context)

      if debug_verbose? && error.backtrace
        debug_logger.debug(component_name, "📍 Backtrace: #{error.backtrace.first(5).join("\n")}")
      end
    end

    # Log timing information
    def debug_timing(operation, duration, details = {})
      return unless debug_verbose?

      message = "⏱️  #{operation}: #{duration.round(2)}s"
      debug_logger.debug(component_name, message, duration: duration, **details)
    end

    # Execute command with debug logging
    def debug_execute_command(cmd, args: [], input: nil, timeout: nil, streaming: false, **options)
      require "tty-command"

      command_str = [cmd, *args].join(" ")
      start_time = Time.now

      debug_logger.info(component_name, "🚀 Starting command execution: #{command_str}")

      begin
        # Configure printer based on streaming mode
        if streaming
          # Use progress printer for real-time output
          cmd_obj = TTY::Command.new(printer: :progress)
          debug_log("📺 Streaming mode enabled - showing real-time output", level: :info)
        else
          cmd_obj = TTY::Command.new(printer: :null) # Disable TTY::Command's own output
        end

        # Prepare input
        input_data = nil
        if input
          if input.is_a?(String) && File.exist?(input)
            input_data = File.read(input)
            debug_log("📁 Reading input from file: #{input}", level: :info)
          else
            input_data = input
          end
        end

        # Execute command
        result = cmd_obj.run(cmd, *args, input: input_data, timeout: timeout, **options)

        duration = Time.now - start_time

        # Log results
        debug_command(cmd, args: args, input: input, output: result.out, error: result.err, exit_code: result.exit_status)
        debug_timing("Command execution", duration, {exit_code: result.exit_status})

        result
      rescue => e
        duration = Time.now - start_time
        debug_error(e, {command: command_str, duration: duration})
        raise
      end
    end

    private

    # Safely derive a component name for logging (memoized).
    # Handles anonymous classes and modules gracefully.
    def component_name
      @component_name ||= begin
        klass = self.class
        name = klass.name
        return "anonymous" unless name && !name.empty?
        # Take the last constant segment, normalize to snake-ish lowercase
        segment = name.split("::").last
        segment.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
      rescue
        "anonymous"
      end
    end
  end
end
