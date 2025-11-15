# frozen_string_literal: true

require_relative "base"
require_relative "../../util"
require_relative "../../providers/gemini"

module Aidp
  module Harness
    module ModelDiscoverers
      # Discovers available Google Gemini models
      #
      # Note: Gemini CLI doesn't typically have a models list command.
      # Falls back to static registry of known Gemini models.
      class Gemini < Base
        def initialize
          super("gemini")
        end

        def available?
          Aidp::Providers::Gemini.available?
        end

        def discover_models
          unless available?
            Aidp.log_debug("gemini_discoverer", "gemini CLI not available")
            return []
          end

          # Gemini CLI doesn't have a standard models list command
          # Use static list from provider
          models = Aidp::Providers::Gemini::SUPPORTED_FAMILIES.map do |family|
            build_model_info(family)
          end

          Aidp.log_info("gemini_discoverer", "using static model list", count: models.size)
          models
        rescue => e
          Aidp.log_error("gemini_discoverer", "unexpected error",
            error: e.message, backtrace: e.backtrace.first(3))
          []
        end

        private

        def build_model_info(family)
          # Classify tier
          tier = classify_tier(family)

          # Extract capabilities
          capabilities = extract_capabilities(family, description: "Google Gemini model")

          # Infer context window
          context_window = infer_context_window(family)

          {
            name: family,
            family: family,
            tier: tier,
            capabilities: capabilities,
            context_window: context_window,
            provider: "gemini"
          }
        end

        def infer_context_window(family)
          # Gemini 1.5 and 2.0 models have 1M context
          return 1_000_000 if family.match?(/gemini-[12]\./)

          nil
        end
      end
    end
  end
end
