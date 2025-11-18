# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Kilocode < Base
      include Aidp::DebugMixin

      # Model name pattern for OpenAI models (since Kilocode uses OpenAI)
      MODEL_PATTERN = /^gpt-[\d.o-]+(?:-turbo)?(?:-mini)?$/i

      def self.available?
        !!Aidp::Util.which("kilocode")
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
      # Note: Kilocode CLI doesn't have a standard model listing command
      # Returns registry-based models that match OpenAI patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        discover_models_from_registry(MODEL_PATTERN, "kilocode")
      end

      # Get firewall requirements for Kilocode provider
      def self.firewall_requirements
        {
          domains: [
            "kilocode.ai",
            "api.kilocode.ai"
          ],
          ip_ranges: []
        }
      end

      def name
        "kilocode"
      end

      def display_name
        "Kilocode"
      end

      def send_message(prompt:, session: nil)
        raise "kilocode not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("kilocode", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to kilocode (length: #{prompt.length})", level: :info)

        # Check if prompt is too large and warn
        if prompt.length > 3000
          debug_log("⚠️  Large prompt detected (#{prompt.length} chars) - this may cause rate limiting", level: :warn)
        end

        # Set up activity monitoring
        setup_activity_monitoring("kilocode", method(:activity_callback))
        record_activity("Starting kilocode execution")

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

            update_spinner_status(spinner, elapsed, "🔄 kilocode")
          end
        end

        begin
          # Build kilocode command arguments
          args = ["--auto"]

          # Add model if specified
          model = ENV["KILOCODE_MODEL"]
          if model
            args.concat(["-m", model])
          end

          # Add workspace detection if needed
          if Dir.exist?(".git") && ENV["KILOCODE_WORKSPACE"]
            args.concat(["--workspace", ENV["KILOCODE_WORKSPACE"]])
          end

          # Set authentication via environment variable
          env_vars = {}
          if ENV["KILOCODE_TOKEN"]
            env_vars["KILOCODE_TOKEN"] = ENV["KILOCODE_TOKEN"]
          end

          # Use debug_execute_command for better debugging
          result = debug_execute_command("kilocode", args: args, input: prompt, timeout: timeout_seconds, env: env_vars)

          # Log the results
          debug_command("kilocode", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("kilocode failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("kilocode failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "kilocode failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("kilocode execution failed: #{e.message}")
          debug_error(e, {provider: "kilocode", prompt_length: prompt.length})
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
          display_message("🚀 Starting kilocode execution...", type: :info)
        when :completed
          display_message("✅ kilocode execution completed", type: :success)
        when :failed
          display_message("❌ kilocode execution failed: #{message}", type: :error)
        end
      end
    end
  end
end
