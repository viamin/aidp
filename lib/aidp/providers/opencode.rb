# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Opencode < Base
      include Aidp::DebugMixin

      # Model name pattern for OpenAI models (since OpenCode uses OpenAI)
      MODEL_PATTERN = /^gpt-[\d.o-]+(?:-turbo)?(?:-mini)?$/i

      def self.available?
        !!Aidp::Util.which("opencode")
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
      # Note: OpenCode CLI doesn't have a standard model listing command
      # Returns registry-based models that match OpenAI patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        discover_models_from_registry(MODEL_PATTERN, "opencode")
      end

      # Get firewall requirements for OpenCode provider
      def self.firewall_requirements
        {
          domains: [
            "api.opencode.ai",
            "auth.opencode.ai"
          ],
          ip_ranges: []
        }
      end

      def name
        "opencode"
      end

      def display_name
        "OpenCode"
      end

      def send_message(prompt:, session: nil, options: {})
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

            update_spinner_status(spinner, elapsed, "🔄 opencode")
          end
        end

        begin
          # Use debug_execute_command for better debugging
          # opencode run command with prompt and model
          model = ENV["OPENCODE_MODEL"] || "github-copilot/claude-3.5-sonnet"
          result = debug_execute_command("opencode", args: ["run", "-m", model, prompt], timeout: timeout_seconds)

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
    end
  end
end
