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

      def display_name
        "Codex CLI"
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

      def send_message(prompt:, session: nil)
        raise "codex CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("codex", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to codex (length: #{prompt.length})", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Streaming mode enabled - output will appear in real-time", type: :info)
        end

        # Set up activity monitoring
        setup_activity_monitoring("codex", method(:activity_callback))
        record_activity("Starting codex execution")

        # Create a spinner for activity display
        spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        spinner.auto_spin

        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            update_spinner_status(spinner, elapsed, "🤖 Codex CLI")
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
          result = debug_execute_command("codex", args: args, timeout: timeout_seconds, streaming: streaming_enabled)

          # Log the results
          debug_command("codex", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("codex failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("codex failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "codex failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("codex execution failed: #{e.message}")
          debug_error(e, {provider: "codex", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
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

        # Add approval flag - but warn about interactive behavior
        if ask_for_approval
          debug_log("⚠️  WARNING: --ask-for-approval flag may cause interactive prompts that could hang AIDP", level: :warn)
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

      # Internal helper for send_with_options - executes with custom arguments
      def send_with_custom_args(prompt:, args:)
        timeout_seconds = calculate_timeout

        debug_provider("codex", "Starting execution", {timeout: timeout_seconds, args: args})
        debug_log("📝 Sending prompt to codex with custom args", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Display streaming enabled - output buffering reduced (codex CLI does not support true streaming)", type: :info)
        end

        setup_activity_monitoring("codex", method(:activity_callback))
        record_activity("Starting codex execution with custom args")

        begin
          result = debug_execute_command("codex", args: args, timeout: timeout_seconds, streaming: streaming_enabled)
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

        if ENV["AIDP_CODEX_TIMEOUT"]
          return ENV["AIDP_CODEX_TIMEOUT"].to_i
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
