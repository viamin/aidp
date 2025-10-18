# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Opencode < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("opencode")
      end

      def name
        "opencode"
      end

      def display_name
        "OpenCode"
      end

      def send(prompt:, session: nil)
        raise "opencode not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("opencode", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to opencode (length: #{prompt.length})", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Display streaming enabled - output buffering reduced (opencode does not support true streaming)", type: :info)
        end

        # Check if prompt is too large and warn
        if prompt.length > 3000
          debug_log("⚠️  Large prompt detected (#{prompt.length} chars) - this may cause rate limiting", level: :warn)
        end

        # Set up activity monitoring
        setup_activity_monitoring("opencode", method(:activity_callback))
        record_activity("Starting opencode execution")

        # Create a spinner for activity display
        spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        spinner.auto_spin

        # Start activity display thread with timeout
        # ACCEPTABLE: UI progress update thread for spinner display
        # Using sleep is fine here for periodic UI updates with break conditions for cancellation
        # See: docs/CONCURRENCY_PATTERNS.md - Category E: Periodic/Interval-Based
        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            update_spinner_status(spinner, elapsed, "🔄 opencode")
          end
        end

        begin
          # Use debug_execute_command for better debugging
          # opencode run command with prompt and model
          model = ENV["OPENCODE_MODEL"] || "github-copilot/claude-3.5-sonnet"
          result = debug_execute_command("opencode", args: ["run", "-m", model, prompt], timeout: timeout_seconds, streaming: streaming_enabled)

          # Log the results
          debug_command("opencode", args: ["run", "-m", model, prompt], input: nil, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("opencode failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("opencode failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "opencode failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("opencode execution failed: #{e.message}")
          debug_error(e, {provider: "opencode", prompt_length: prompt.length})
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

        if ENV["AIDP_OPENCODE_TIMEOUT"]
          return ENV["AIDP_OPENCODE_TIMEOUT"].to_i
        end

        if adaptive_timeout
          display_message("🧠 Using adaptive timeout: #{adaptive_timeout} seconds", type: :info)
          return adaptive_timeout
        end

        # Default timeout
        display_message("📋 Using default timeout: #{TIMEOUT_DEFAULT / 60} minutes", type: :info)
        TIMEOUT_DEFAULT
      end

      def adaptive_timeout
        @adaptive_timeout ||= begin
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
            nil # Use default
          end
        end
      end

      def activity_callback(state, message, provider)
        # This is now handled by the animated display thread
        # Only print static messages for state changes
        case state
        when :starting
          display_message("🚀 Starting opencode execution...", type: :info)
        when :completed
          display_message("✅ opencode execution completed", type: :success)
        when :failed
          display_message("❌ opencode execution failed: #{message}", type: :error)
        end
      end

      def setup_activity_monitoring(provider_name, callback)
        @activity_callback = callback
        @activity_state = :starting
        @activity_start_time = Time.now
      end

      def record_activity(message)
        @activity_state = :running
        @activity_callback&.call(:running, message, "opencode")
      end

      def mark_completed
        @activity_state = :completed
        @activity_callback&.call(:completed, "Execution completed", "opencode")
      end

      def mark_failed(reason)
        @activity_state = :failed
        @activity_callback&.call(:failed, reason, "opencode")
      end
    end
  end
end
