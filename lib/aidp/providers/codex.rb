# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Codex < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("codex")
      end

      def name
        "codex"
      end

      def available?
        return false unless self.class.available?

        # Additional check to ensure the CLI is properly configured
        begin
          result = Aidp::Util.execute_command("codex", ["--version"], timeout: 10)
          result.exit_status == 0
        rescue
          false
        end
      end

      def send(prompt:, session: nil)
        raise "codex CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("codex", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to codex (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("codex", method(:activity_callback))
        record_activity("Starting codex execution")

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
          # Use non-interactive mode (exec) for automation
          args = ["exec", prompt]

          # Add session support if provided (codex may support session/thread continuation)
          if session && !session.empty?
            args += ["--session", session]
          end

          # Use debug_execute_command for better debugging
          result = debug_execute_command("codex", args: args, timeout: timeout_seconds)

          # Log the results
          debug_command("codex", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("codex failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("codex failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "codex failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status
          mark_failed("codex execution failed: #{e.message}")
          debug_error(e, {provider: "codex", prompt_length: prompt.length})
          raise
        end
      end

      # Enhanced send method with additional options
      def send_with_options(prompt:, session: nil, model: nil, ask_for_approval: false)
        args = ["exec", prompt]

        # Add session support
        if session && !session.empty?
          args += ["--session", session]
        end

        # Add model selection
        if model
          args += ["--model", model]
        end

        # Add approval flag
        if ask_for_approval
          args += ["--ask-for-approval"]
        end

        # Use the enhanced version of send
        send_with_custom_args(prompt: prompt, args: args)
      end

      # Override health check for Codex specific considerations
      def harness_healthy?
        return false unless super

        # Additional health checks specific to Codex CLI
        # Check if we can access the CLI (basic connectivity test)
        begin
          result = Aidp::Util.execute_command("codex", ["--help"], timeout: 5)
          result.exit_status == 0
        rescue
          false
        end
      end

      private

      def send_with_custom_args(prompt:, args:)
        timeout_seconds = calculate_timeout

        debug_provider("codex", "Starting execution", {timeout: timeout_seconds, args: args})
        debug_log("📝 Sending prompt to codex with custom args", level: :info)

        setup_activity_monitoring("codex", method(:activity_callback))
        record_activity("Starting codex execution with custom args")

        begin
          result = debug_execute_command("codex", args: args, timeout: timeout_seconds)
          debug_command("codex", args: args, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("codex failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("codex failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "codex failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          mark_failed("codex execution failed: #{e.message}")
          debug_error(e, {provider: "codex", prompt_length: prompt.length})
          raise
        end
      end

      def print_activity_status(elapsed)
        # Print activity status during execution with elapsed time
        minutes = (elapsed / 60).to_i
        seconds = (elapsed % 60).to_i

        if minutes > 0
          print "\r🤖 Codex CLI is running... (#{minutes}m #{seconds}s)"
        else
          print "\r🤖 Codex CLI is running... (#{seconds}s)"
        end
      end

      def clear_activity_status
        # Clear the activity status line
        print "\r" + " " * 60 + "\r"
      end

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          display_message("⚡ Quick mode enabled - 2 minute timeout", type: :highlight)
          return 120
        end

        if ENV["AIDP_CODEX_TIMEOUT"]
          return ENV["AIDP_CODEX_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          display_message("🧠 Using adaptive timeout: #{step_timeout} seconds", type: :info)
          return step_timeout
        end

        # Default timeout (5 minutes for interactive use)
        display_message("📋 Using default timeout: 5 minutes", type: :info)
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
        # Handle activity state changes
        case state
        when :stuck
          display_message("\n⚠️  Codex CLI appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ Codex CLI completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ Codex CLI failed: #{message}", type: :error)
        end
      end
    end
  end
end
