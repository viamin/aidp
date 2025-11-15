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

        begin
          require_relative "../harness/model_registry"
          registry = Aidp::Harness::ModelRegistry.new

          # Get all OpenAI models from registry
          models = registry.all_families.filter_map do |family|
            next unless supports_model_family?(family)

            info = registry.get_model_info(family)
            next unless info

            {
              name: family,
              family: family,
              tier: info["tier"],
              capabilities: info["capabilities"] || [],
              context_window: info["context_window"],
              provider: "kilocode"
            }
          end

          Aidp.log_info("kilocode_provider", "using registry models", count: models.size)
          models
        rescue => e
          Aidp.log_debug("kilocode_provider", "discovery failed", error: e.message)
          []
        end
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

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Display streaming enabled - output buffering reduced", type: :info)
        end

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
          result = debug_execute_command("kilocode", args: args, input: prompt, timeout: timeout_seconds, streaming: streaming_enabled, env: env_vars)

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

        if ENV["AIDP_KILOCODE_TIMEOUT"]
          return ENV["AIDP_KILOCODE_TIMEOUT"].to_i
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
          display_message("🚀 Starting kilocode execution...", type: :info)
        when :completed
          display_message("✅ kilocode execution completed", type: :success)
        when :failed
          display_message("❌ kilocode execution failed: #{message}", type: :error)
        end
      end

      def setup_activity_monitoring(provider_name, callback)
        @activity_callback = callback
        @activity_state = :starting
        @activity_start_time = Time.now
      end

      def record_activity(message)
        @activity_state = :running
        @activity_callback&.call(:running, message, "kilocode")
      end

      def mark_completed
        @activity_state = :completed
        @activity_callback&.call(:completed, "Execution completed", "kilocode")
      end

      def mark_failed(reason)
        @activity_state = :failed
        @activity_callback&.call(:failed, reason, "kilocode")
      end
    end
  end
end
