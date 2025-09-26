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

      def send(prompt:, session: nil)
        raise "opencode not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("opencode", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to opencode (length: #{prompt.length})", level: :info)

        # Check if prompt is too large and warn
        if prompt.length > 3000
          debug_log("⚠️  Large prompt detected (#{prompt.length} chars) - this may cause rate limiting", level: :warn)
        end

        # Set up activity monitoring
        setup_activity_monitoring("opencode", method(:activity_callback))
        record_activity("Starting opencode execution")

        # Start activity display thread with timeout
        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            print_activity_status(elapsed)
          end
        end

        begin
          # Use debug_execute_command for better debugging
          # opencode run command with prompt and model
          model = ENV["OPENCODE_MODEL"] || "github-copilot/claude-3.5-sonnet"
          result = debug_execute_command("opencode", args: ["run", "-m", model, prompt], timeout: timeout_seconds)

          # Log the results
          debug_command("opencode", args: ["run", "-m", model, prompt], input: nil, output: result.out, error: result.err, exit_code: result.exit_status)

          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("opencode failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("opencode failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "opencode failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status
          mark_failed("opencode execution failed: #{e.message}")
          debug_error(e, {provider: "opencode", prompt_length: prompt.length})
          raise
        end
      end

      private

      def print_activity_status(elapsed)
        # Print activity status during opencode execution with elapsed time
        minutes = (elapsed / 60).to_i
        seconds = (elapsed % 60).to_i

        if minutes > 0
          print "\r🔄 opencode is running... (#{minutes}m #{seconds}s)"
        else
          print "\r🔄 opencode is running... (#{seconds}s)"
        end
      end

      def clear_activity_status
        # Clear the activity status line
        print "\r" + " " * 50 + "\r"
      end

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          puts "⚡ Quick mode enabled - 2 minute timeout"
          return 120
        end

        if ENV["AIDP_OPENCODE_TIMEOUT"]
          return ENV["AIDP_OPENCODE_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          puts "🧠 Using adaptive timeout: #{step_timeout} seconds"
          return step_timeout
        end

        # Default timeout (5 minutes for interactive use)
        puts "📋 Using default timeout: 5 minutes"
        300
      end

      def get_adaptive_timeout
        # Timeout recommendations based on step type patterns
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        case step_name
        when /REPOSITORY_ANALYSIS/
          180  # 3 minutes - repository analysis can be quick
        when /ARCHITECTURE_ANALYSIS/
          600  # 10 minutes - architecture analysis needs more time
        when /TEST_ANALYSIS/
          300  # 5 minutes - test analysis is moderate
        when /FUNCTIONALITY_ANALYSIS/
          600  # 10 minutes - functionality analysis is complex
        when /DOCUMENTATION_ANALYSIS/
          300  # 5 minutes - documentation analysis is moderate
        when /STATIC_ANALYSIS/
          450  # 7.5 minutes - static analysis can be intensive
        when /REFACTORING_RECOMMENDATIONS/
          600  # 10 minutes - refactoring recommendations are complex
        else
          nil  # Use default
        end
      end

      def activity_callback(state, message, provider)
        # This is now handled by the animated display thread
        # Only print static messages for state changes
        case state
        when :starting
          puts "🚀 Starting opencode execution..."
        when :completed
          puts "✅ opencode execution completed"
        when :failed
          puts "❌ opencode execution failed: #{message}"
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
