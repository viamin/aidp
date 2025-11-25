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

        discover_models_from_registry(MODEL_PATTERN, "gemini")
      end

      # Get firewall requirements for Gemini provider
      def self.firewall_requirements
        {
          domains: [
            "generativelanguage.googleapis.com",
            "oauth2.googleapis.com",
            "accounts.google.com",
            "www.googleapis.com"
          ],
          ip_ranges: []
        }
      end

      def name
        "gemini"
      end

      def display_name
        "Google Gemini"
      end

      def send_message(prompt:, session: nil, options: {})
        raise "gemini CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("gemini", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to gemini...", level: :info)

        begin
          command_args = ["--prompt", prompt]
          result = debug_execute_command("gemini", args: command_args, timeout: timeout_seconds)

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
    end
  end
end
