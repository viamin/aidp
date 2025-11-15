# frozen_string_literal: true

require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Gemini < Base
      include Aidp::DebugMixin

      # Supported model families (without version suffixes)
      SUPPORTED_FAMILIES = [
        "gemini-1.5-pro",
        "gemini-1.5-flash",
        "gemini-2.0-flash"
      ].freeze

      # Track model versions (Gemini sometimes uses version suffixes)
      SUPPORTED_MODELS = {
        "gemini-1.5-pro" => "gemini-1.5-pro",
        "gemini-1.5-flash" => "gemini-1.5-flash",
        "gemini-2.0-flash" => "gemini-2.0-flash"
      }.freeze

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
        base_name = provider_model_name.sub(/-\d+$/, "")
        SUPPORTED_MODELS[base_name] || base_name
      end

      # Convert a model family name to the provider's preferred model name
      #
      # @param family_name [String] The model family name
      # @return [String] The provider-specific model name
      def self.provider_model_name(family_name)
        SUPPORTED_MODELS[family_name] || family_name
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if the family is supported
      def self.supports_model_family?(family_name)
        SUPPORTED_FAMILIES.include?(family_name)
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
