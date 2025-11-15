# frozen_string_literal: true

require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Gemini < Base
      include Aidp::DebugMixin

      # Model name pattern for Gemini models
      MODEL_PATTERN = /^gemini-[\d.]+-(?:pro|flash|ultra)(?:-\d+)?$/i

      def self.available?
        !!Aidp::Util.which("gemini")
      end

      # Normalize a provider-specific model name to its model family
      #
      # Gemini may use version suffixes (e.g., "gemini-1.5-pro-001").
      # This method strips version suffixes to get the family name.
      #
      # @param provider_model_name [String] The model name
      # @return [String] The model family name
      def self.model_family(provider_model_name)
        # Strip version suffix: "gemini-1.5-pro-001" → "gemini-1.5-pro"
        provider_model_name.sub(/-\d+$/, "")
      end

      # Convert a model family name to the provider's preferred model name
      #
      # @param family_name [String] The model family name
      # @return [String] The provider-specific model name (same as family)
      def self.provider_model_name(family_name)
        family_name
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if it matches Gemini model pattern
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from Gemini
      #
      # Note: Gemini CLI doesn't have a standard model listing command
      # Returns registry-based models that match Gemini patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        begin
          require_relative "../harness/model_registry"
          registry = Aidp::Harness::ModelRegistry.new

          # Get all Gemini models from registry
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
              provider: "gemini"
            }
          end

          Aidp.log_info("gemini_provider", "using registry models", count: models.size)
          models
        rescue => e
          Aidp.log_debug("gemini_provider", "discovery failed", error: e.message)
          []
        end
      end

      def name
        "gemini"
      end

      def display_name
        "Google Gemini"
      end

      def send_message(prompt:, session: nil)
        raise "gemini CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("gemini", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to gemini...", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Display streaming enabled - output buffering reduced (gemini CLI does not support true streaming)", type: :info)
        end

        begin
          command_args = ["--prompt", prompt]
          # Use debug_execute_command with streaming support
          result = debug_execute_command("gemini", args: command_args, timeout: timeout_seconds, streaming: streaming_enabled)

          # Log the results
          debug_command("gemini", args: command_args, input: nil, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            result.out
          else
            debug_error(StandardError.new("gemini failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "gemini failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          debug_error(e, {provider: "gemini", prompt_length: prompt.length})
          raise
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

        if ENV["AIDP_GEMINI_TIMEOUT"]
          return ENV["AIDP_GEMINI_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          display_message("🧠 Using adaptive timeout: #{step_timeout} seconds", type: :info)
          return step_timeout
        end

        # Default timeout
        display_message("📋 Using default timeout: #{TIMEOUT_DEFAULT / 60} minutes", type: :info)
        TIMEOUT_DEFAULT
      end

      def get_adaptive_timeout
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
  end
end
