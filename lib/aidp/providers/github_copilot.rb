# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class GithubCopilot < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("copilot")
      end

      def name
        "github_copilot"
      end

      def available?
        return false unless self.class.available?

        # Additional check to ensure the CLI is properly configured
        begin
          result = Aidp::Util.execute_command("copilot", ["--version"], timeout: 10)
          result.exit_status == 0
        rescue
          false
        end
      end

      def send(prompt:, session: nil)
        raise "copilot CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("copilot", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to copilot (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("copilot", method(:activity_callback))
        record_activity("Starting copilot execution")

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
          # Use non-interactive mode for automation
          args = ["-p", prompt, "--allow-all-tools"]

          # Add session support if provided
          if session && !session.empty?
            args += ["--resume", session]
          end

          # Use debug_execute_command for better debugging (no input since prompt is in args)
          result = debug_execute_command("copilot", args: args, timeout: timeout_seconds)

          # Log the results
          debug_command("copilot", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("copilot failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("copilot failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "copilot failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          # Stop activity display
          activity_display_thread.kill if activity_display_thread.alive?
          activity_display_thread.join(0.1) # Give it 100ms to finish
          clear_activity_status
          mark_failed("copilot execution failed: #{e.message}")
          debug_error(e, {provider: "github_copilot", prompt_length: prompt.length})
          raise
        end
      end

      # Enhanced send method with additional options
      def send_with_options(prompt:, session: nil, tools: nil, log_level: nil, config_file: nil, directories: nil)
        args = ["-p", prompt]

        # Add session support
        if session && !session.empty?
          args += ["--resume", session]
        end

        # Add tool permissions
        if tools && !tools.empty?
          if tools.include?("all")
            args += ["--allow-all-tools"]
          else
            tools.each do |tool|
              args += ["--allow-tool", tool]
            end
          end
        else
          # Default to allowing all tools for automation
          args += ["--allow-all-tools"]
        end

        # Add logging level
        if log_level
          args += ["--log-level", log_level]
        end

        # Add allowed directories
        if directories && !directories.empty?
          directories.each do |dir|
            args += ["--add-dir", dir]
          end
        end

        # Use the enhanced version of send
        send_with_custom_args(prompt: prompt, args: args)
      end

      # Override health check for GitHub Copilot specific considerations
      def harness_healthy?
        return false unless super

        # Additional health checks specific to GitHub Copilot CLI
        # Check if we can access GitHub (basic connectivity test)
        begin
          result = Aidp::Util.execute_command("copilot", ["--help"], timeout: 5)
          result.exit_status == 0
        rescue
          false
        end
      end

      private

      def send_with_custom_args(prompt:, args:)
        timeout_seconds = calculate_timeout

        debug_provider("copilot", "Starting execution", {timeout: timeout_seconds, args: args})
        debug_log("📝 Sending prompt to copilot with custom args", level: :info)

        setup_activity_monitoring("copilot", method(:activity_callback))
        record_activity("Starting copilot execution with custom args")

        begin
          result = debug_execute_command("copilot", args: args, timeout: timeout_seconds)
          debug_command("copilot", args: args, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("copilot failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("copilot failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "copilot failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          mark_failed("copilot execution failed: #{e.message}")
          debug_error(e, {provider: "github_copilot", prompt_length: prompt.length})
          raise
        end
      end

      def print_activity_status(elapsed)
        # Print activity status during execution with elapsed time
        minutes = (elapsed / 60).to_i
        seconds = (elapsed % 60).to_i

        if minutes > 0
          print "\r🤖 GitHub Copilot CLI is running... (#{minutes}m #{seconds}s)"
        else
          print "\r🤖 GitHub Copilot CLI is running... (#{seconds}s)"
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

        if ENV["AIDP_GITHUB_COPILOT_TIMEOUT"]
          return ENV["AIDP_GITHUB_COPILOT_TIMEOUT"].to_i
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
          display_message("\n⚠️  GitHub Copilot CLI appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ GitHub Copilot CLI completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ GitHub Copilot CLI failed: #{message}", type: :error)
        end
      end
    end
  end
end
