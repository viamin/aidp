# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Codex < Base
      include Aidp::DebugMixin

      # Model name pattern for OpenAI models (since Codex uses OpenAI)
      MODEL_PATTERN = /^gpt-[\d.o-]+(?:-turbo)?(?:-mini)?$/i
      LONG_PROMPT_THRESHOLD = 8000
      LONG_PROMPT_TIMEOUT = 900 # 15 minutes for large prompts

      def self.available?
        !!Aidp::Util.which("codex")
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if it matches OpenAI model pattern
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from registry
      #
      # Note: Codex CLI doesn't have a standard model listing command
      # Returns registry-based models that match OpenAI patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        discover_models_from_registry(MODEL_PATTERN, "codex")
      end

      # Get firewall requirements for Codex provider
      # Codex uses OpenAI APIs
      def self.firewall_requirements
        {
          domains: [
            "api.openai.com",
            "auth.openai.com",
            "openai.com",
            "chat.openai.com",
            "chatgpt.com",
            "cdn.openai.com",
            "oaiusercontent.com"
          ],
          ip_ranges: []
        }
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

        # Smart timeout calculation (store prompt length for adaptive logic)
        @current_codex_prompt_length = prompt.length
        timeout_seconds = calculate_timeout

        debug_provider("codex", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to codex (length: #{prompt.length})", level: :info)

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

          # Add model if configured
          if @model && !@model.empty?
            args += ["--model", @model]
          end

          # Add session support if provided (codex may support session/thread continuation)
          if session && !session.empty?
            args += ["--session", session]
          end

          # In devcontainer, ensure sandbox mode and approval policy are set
          # These are already set via environment variables in devcontainer.json
          # but we verify and log them here for visibility
          if in_devcontainer_or_codespace?
            unless ENV["CODEX_SANDBOX_MODE"] == "danger-full-access"
              ENV["CODEX_SANDBOX_MODE"] = "danger-full-access"
              debug_log("🔓 Set CODEX_SANDBOX_MODE=danger-full-access for devcontainer", level: :info)
            end
            unless ENV["CODEX_APPROVAL_POLICY"] == "never"
              ENV["CODEX_APPROVAL_POLICY"] = "never"
              debug_log("🔓 Set CODEX_APPROVAL_POLICY=never for devcontainer", level: :info)
            end
          end

          # Use debug_execute_command for better debugging
          result = debug_execute_command("codex", args: args, timeout: timeout_seconds)

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
          @current_codex_prompt_length = nil
        end
      end

      # Enhanced send method with additional options
      def send_with_options(prompt:, session: nil, model: nil, ask_for_approval: false)
        args = ["exec", prompt]

        # Add session support
        if session && !session.empty?
          args += ["--session", session]
        end

        # Add model selection (from parameter or configured model)
        model_to_use = model || @model
        if model_to_use
          args += ["--model", model_to_use]
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
        @current_codex_prompt_length = prompt.length
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
        ensure
          @current_codex_prompt_length = nil
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

      def calculate_timeout
        env_override = ENV["AIDP_CODEX_TIMEOUT"]
        return env_override.to_i if env_override&.match?(/^\d+$/)

        base_timeout = super

        prompt_length = @current_codex_prompt_length
        return base_timeout unless prompt_length && prompt_length >= LONG_PROMPT_THRESHOLD

        extended_timeout = [base_timeout, LONG_PROMPT_TIMEOUT].max
        if extended_timeout > base_timeout
          display_message("⏱️  Codex prompt length #{prompt_length} detected - extending timeout to #{extended_timeout} seconds", type: :info)
        end
        extended_timeout
      end
    end
  end
end
