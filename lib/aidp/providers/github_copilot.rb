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

      def display_name
        "GitHub Copilot CLI"
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

      def send_message(prompt:, session: nil)
        raise "copilot CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("copilot", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to copilot (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("copilot", method(:activity_callback))
        record_activity("Starting copilot execution")

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

            update_spinner_status(spinner, elapsed, "🤖 GitHub Copilot CLI")
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

          # Detect authorization/access errors
          auth_error = result.err.to_s =~ /not authorized|requires an enterprise|access denied|permission denied|not enabled/i
          if auth_error
            spinner.error("✗")
            mark_failed("copilot authorization error: #{result.err}")
            @unavailable = true
            debug_error(StandardError.new("copilot authorization error"), {exit_code: result.exit_status, stderr: result.err})
            raise Aidp::Providers::ProviderUnavailableError.new("copilot authorization error: #{result.err}")
          end

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("copilot failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("copilot failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "copilot failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue Aidp::Providers::ProviderUnavailableError
          raise
        rescue => e
          spinner&.error("✗")
          mark_failed("copilot execution failed: #{e.message}")
          debug_error(e, {provider: "github_copilot", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
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
