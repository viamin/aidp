# frozen_string_literal: true

module Aidp
  module Harness
    module ModelDiscoverers
      # Base class for provider-specific model discoverers
      #
      # Each provider implements a discoverer that queries the provider's API or CLI
      # to find available models. Discoverers should handle errors gracefully and
      # never crash the application.
      #
      # Subclasses must implement:
      #   - discover_models: Returns array of model hashes with name, tier, capabilities
      class Base
        DISCOVERY_TIMEOUT = 10 # seconds

        attr_reader :provider_name

        def initialize(provider_name)
          @provider_name = provider_name
        end

        # Discover available models from the provider
        #
        # @return [Array<Hash>] Array of model info hashes
        #   Each hash should contain:
        #     - name: Model name (String)
        #     - tier: Tier classification (String, optional - will be inferred if missing)
        #     - capabilities: Array of capability strings (optional)
        #     - context_window: Integer (optional)
        #     - description: String (optional)
        def discover_models
          raise NotImplementedError, "Subclasses must implement #discover_models"
        end

        # Check if the provider CLI/API is available
        #
        # @return [Boolean] True if the provider can be queried
        def available?
          raise NotImplementedError, "Subclasses must implement #available?"
        end

        protected

        # Execute a command safely with timeout protection
        #
        # @param command [String] The command to execute
        # @param args [Array<String>] Command arguments
        # @param timeout [Integer] Timeout in seconds
        # @return [Hash] Result with :success, :output, :error keys
        def execute_command(command, args: [], timeout: DISCOVERY_TIMEOUT)
          require "open3"
          require "timeout"

          Aidp.log_debug("model_discoverer", "executing command",
            provider: provider_name, command: command, args: args, timeout: timeout)

          output = ""
          error = ""
          success = false

          begin
            Timeout.timeout(timeout) do
              output, error, status = Open3.capture3(command, *args)
              success = status.success?
            end
          rescue Timeout::Error => e
            error = "Command timed out after #{timeout} seconds"
            Aidp.log_warn("model_discoverer", "timeout",
              provider: provider_name, command: command, timeout: timeout)
          rescue Errno::ENOENT => e
            error = "Command not found: #{command}"
            Aidp.log_debug("model_discoverer", "command not found",
              provider: provider_name, command: command)
          rescue => e
            error = "Command failed: #{e.message}"
            Aidp.log_error("model_discoverer", "command error",
              provider: provider_name, command: command, error: e.message)
          end

          {success: success, output: output, error: error}
        end

        # Classify a model into a tier based on its name and characteristics
        #
        # This provides intelligent tier assignment using heuristics:
        #   - Name patterns (opus/pro → advanced, haiku/mini/flash → mini, etc.)
        #   - Context window size (larger → higher tier)
        #
        # @param model_name [String] The model name
        # @param context_window [Integer, nil] Context window size
        # @return [String] Tier name (mini, standard, advanced)
        def classify_tier(model_name, context_window: nil)
          name_lower = model_name.downcase

          # Advanced tier indicators
          return "advanced" if name_lower.include?("opus")
          return "advanced" if name_lower.include?("pro") && !name_lower.include?("flash")
          return "advanced" if name_lower.include?("gpt-4") && !name_lower.include?("mini")
          return "advanced" if name_lower.include?("turbo") && name_lower.include?("gpt-4")

          # Mini tier indicators
          return "mini" if name_lower.include?("haiku")
          return "mini" if name_lower.include?("mini")
          return "mini" if name_lower.include?("fast")
          return "mini" if name_lower.include?("gpt-3.5")

          # Flash models are typically standard tier (balanced)
          return "standard" if name_lower.include?("flash")
          return "standard" if name_lower.include?("sonnet")

          # Use context window as a heuristic if available
          if context_window
            return "mini" if context_window < 50_000
            return "advanced" if context_window > 500_000
          end

          # Default to standard tier
          "standard"
        end

        # Extract capabilities from model name/description
        #
        # @param model_name [String] The model name
        # @param description [String, nil] Model description
        # @return [Array<String>] List of capabilities
        def extract_capabilities(model_name, description: nil)
          capabilities = ["chat"] # All models can chat

          name_and_desc = "#{model_name} #{description}".downcase

          capabilities << "code" if name_and_desc.match?(/code|programming|developer/)
          capabilities << "vision" if name_and_desc.match?(/vision|image|visual/)
          capabilities << "tool_use" if name_and_desc.match?(/tool|function|api/)

          capabilities
        end
      end
    end
  end
end
