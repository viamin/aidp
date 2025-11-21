# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Aider < Base
      include Aidp::DebugMixin

      # Model name pattern for Aider (supports various models via OpenRouter)
      # Aider can use any model, but we'll match common patterns
      MODEL_PATTERN = /^(gpt-|claude-|gemini-|deepseek-|qwen-|o1-)/i
      LONG_PROMPT_THRESHOLD = 8000
      LONG_PROMPT_TIMEOUT = 900 # 15 minutes for large prompts

      def self.available?
        !!Aidp::Util.which("aider")
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if it matches common model patterns
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from registry
      #
      # Note: Aider uses its own configuration for models
      # Returns registry-based models that match common patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        discover_models_from_registry(MODEL_PATTERN, "aider")
      end

      # Get firewall requirements for Aider provider
      # Aider uses aider.chat for updates, openrouter.ai for API access,
      # and pypi.org for version checking
      def self.firewall_requirements
        {
          domains: [
            "aider.chat",
            "openrouter.ai",
            "api.openrouter.ai",
            "pypi.org"
          ],
          ip_ranges: []
        }
      end

      # Get instruction file path for Aider
      def self.instruction_file_path
        ".aider/instructions.md"
      end

      def name
        "aider"
      end

      def display_name
        "Aider"
      end

      def available?
        return false unless self.class.available?

        # Additional check to ensure the CLI is properly configured
        begin
          result = Aidp::Util.execute_command("aider", ["--version"], timeout: 10)
          result.exit_status == 0
        rescue
          false
        end
      end

      def send_message(prompt:, session: nil, options: {})
        raise "aider CLI not available" unless self.class.available?

        # Smart timeout calculation (store prompt length for adaptive logic)
        @current_aider_prompt_length = prompt.length
        timeout_seconds = calculate_timeout

        debug_provider("aider", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to aider (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("aider", method(:activity_callback))
        record_activity("Starting aider execution")

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

            update_spinner_status(spinner, elapsed, "🤖 Aider")
          end
        end

        begin
          # Use non-interactive mode with --yes-always flag and --message
          # --yes-always is equivalent to Claude's --dangerously-skip-permissions
          args = ["--yes-always", "--message", prompt]

          # Disable aider's auto-commits by default - let AIDP handle commits
          # based on work_loop.version_control.behavior configuration
          args += ["--no-auto-commits"]

          # Add model if configured
          if @model && !@model.empty?
            args += ["--model", @model]
          end

          # Add session support if provided (aider supports chat history)
          if session && !session.empty?
            args += ["--restore-chat-history"]
          end

          # In devcontainer, aider should run in non-interactive mode
          if in_devcontainer_or_codespace?
            debug_log("🔓 Running aider in non-interactive mode with --yes-always (devcontainer)", level: :info)
          end

          # Use debug_execute_command for better debugging
          result = debug_execute_command("aider", args: args, timeout: timeout_seconds)

          # Log the results
          debug_command("aider", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("aider failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("aider failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "aider failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("aider execution failed: #{e.message}")
          debug_error(e, {provider: "aider", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
          @current_aider_prompt_length = nil
        end
      end

      # Enhanced send method with additional options
      def send_with_options(prompt:, session: nil, model: nil, auto_commits: false)
        args = ["--yes-always", "--message", prompt]

        # Disable auto-commits by default (let AIDP handle commits)
        # unless explicitly enabled via auto_commits parameter
        args += if auto_commits
          ["--auto-commits"]
        else
          ["--no-auto-commits"]
        end

        # Add session support
        if session && !session.empty?
          args += ["--restore-chat-history"]
        end

        # Add model selection (from parameter or configured model)
        model_to_use = model || @model
        if model_to_use
          args += ["--model", model_to_use]
        end

        # Use the enhanced version of send
        send_with_custom_args(prompt: prompt, args: args)
      end

      # Override health check for Aider specific considerations
      def harness_healthy?
        return false unless super

        # Additional health checks specific to Aider
        # Check if we can access the CLI (basic connectivity test)
        begin
          result = Aidp::Util.execute_command("aider", ["--help"], timeout: 5)
          result.exit_status == 0
        rescue
          false
        end
      end

      private

      # Internal helper for send_with_options - executes with custom arguments
      def send_with_custom_args(prompt:, args:)
        @current_aider_prompt_length = prompt.length
        timeout_seconds = calculate_timeout

        debug_provider("aider", "Starting execution", {timeout: timeout_seconds, args: args})
        debug_log("📝 Sending prompt to aider with custom args", level: :info)

        setup_activity_monitoring("aider", method(:activity_callback))
        record_activity("Starting aider execution with custom args")

        begin
          result = debug_execute_command("aider", args: args, timeout: timeout_seconds)
          debug_command("aider", args: args, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("aider failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("aider failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "aider failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          mark_failed("aider execution failed: #{e.message}")
          debug_error(e, {provider: "aider", prompt_length: prompt.length})
          raise
        ensure
          @current_aider_prompt_length = nil
        end
      end

      def activity_callback(state, message, provider)
        # Handle activity state changes
        case state
        when :stuck
          display_message("\n⚠️  Aider appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ Aider completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ Aider failed: #{message}", type: :error)
        end
      end

      def calculate_timeout
        env_override = ENV["AIDP_AIDER_TIMEOUT"]
        return env_override.to_i if env_override&.match?(/^\d+$/)

        base_timeout = super

        prompt_length = @current_aider_prompt_length
        return base_timeout unless prompt_length && prompt_length >= LONG_PROMPT_THRESHOLD

        extended_timeout = [base_timeout, LONG_PROMPT_TIMEOUT].max
        if extended_timeout > base_timeout
          display_message("⏱️  Aider prompt length #{prompt_length} detected - extending timeout to #{extended_timeout} seconds", type: :info)
        end
        extended_timeout
      end
    end
  end
end
