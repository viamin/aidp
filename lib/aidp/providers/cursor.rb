# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Cursor < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("cursor-agent")
      end

      def name
        "cursor"
      end

      def display_name
        "Cursor AI"
      end

      def send(prompt:, session: nil)
        raise "cursor-agent not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("cursor", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to cursor-agent (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("cursor-agent", method(:activity_callback))
        record_activity("Starting cursor-agent execution")

        # Create a spinner for activity display
        spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        spinner.auto_spin

        # Start activity display thread with timeout
        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            update_spinner_status(spinner, elapsed, "🔄 cursor-agent")
          end
        end

        begin
          # Use debug_execute_command for better debugging
          # Try agent command first (better for large prompts), fallback to -p mode
          begin
            result = debug_execute_command("cursor-agent", args: ["agent"], input: prompt, timeout: timeout_seconds)
          rescue => e
            # Fallback to -p mode if agent command fails
            debug_log("🔄 Falling back to -p mode: #{e.message}", level: :warn)
            result = debug_execute_command("cursor-agent", args: ["-p"], input: prompt, timeout: timeout_seconds)
          end

          # Log the results
          debug_command("cursor-agent", args: ["-p"], input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("cursor-agent failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("cursor-agent failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "cursor-agent failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("cursor-agent execution failed: #{e.message}")
          debug_error(e, {provider: "cursor", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
        end
      end

      private

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          display_message("⚡ Quick mode enabled - #{TIMEOUT_QUICK_MODE / 60} minute timeout", type: :highlight)
          return TIMEOUT_QUICK_MODE
        end

        if ENV["AIDP_CURSOR_TIMEOUT"]
          return ENV["AIDP_CURSOR_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          display_message("🧠 Using adaptive timeout: #{step_timeout} seconds", type: :info)
          return step_timeout
        end

        # Default timeout
        display_message("📋 Using default timeout: #{TIMEOUT_DEFAULT / 60} minutes", type: :info)
        TIMEOUT_DEFAULT
      end

      def get_adaptive_timeout
        # Timeout recommendations based on step type patterns
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        case step_name
        when /REPOSITORY_ANALYSIS/
          TIMEOUT_REPOSITORY_ANALYSIS
        when /ARCHITECTURE_ANALYSIS/
          TIMEOUT_ARCHITECTURE_ANALYSIS
        when /TEST_ANALYSIS/
          TIMEOUT_TEST_ANALYSIS
        when /FUNCTIONALITY_ANALYSIS/
          TIMEOUT_FUNCTIONALITY_ANALYSIS
        when /DOCUMENTATION_ANALYSIS/
          TIMEOUT_DOCUMENTATION_ANALYSIS
        when /STATIC_ANALYSIS/
          TIMEOUT_STATIC_ANALYSIS
        when /REFACTORING_RECOMMENDATIONS/
          TIMEOUT_REFACTORING_RECOMMENDATIONS
        else
          nil  # Use default
        end
      end

      def activity_callback(state, message, provider)
        # This is now handled by the animated display thread
        # Only print static messages for state changes
        case state
        when :stuck
          display_message("\n⚠️  cursor appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ cursor completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ cursor failed: #{message}", type: :error)
        end
      end
    end
  end
end
