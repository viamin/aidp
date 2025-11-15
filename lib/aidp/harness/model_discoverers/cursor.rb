# frozen_string_literal: true

require_relative "base"
require_relative "../../util"
require_relative "../../providers/cursor"

module Aidp
  module Harness
    module ModelDiscoverers
      # Discovers available models for Cursor AI
      #
      # Cursor doesn't have a public model listing API, so we rely on:
      # 1. The static registry of known Cursor-supported models
      # 2. Cursor's SUPPORTED_MODELS mapping
      class Cursor < Base
        def initialize
          super("cursor")
        end

        def available?
          Aidp::Providers::Cursor.available?
        end

        def discover_models
          unless available?
            Aidp.log_debug("cursor_discoverer", "cursor-agent not available")
            return []
          end

          # Cursor doesn't expose a model listing command
          # Return models from the static provider mapping
          models = Aidp::Providers::Cursor::SUPPORTED_MODELS.map do |cursor_name, family|
            build_model_info(cursor_name, family)
          end

          Aidp.log_info("cursor_discoverer", "using static model list", count: models.size)
          models
        rescue => e
          Aidp.log_error("cursor_discoverer", "unexpected error",
            error: e.message, backtrace: e.backtrace.first(3))
          []
        end

        private

        def build_model_info(cursor_name, family)
          # Classify tier
          tier = classify_tier(cursor_name)

          # Extract capabilities
          capabilities = extract_capabilities(cursor_name)

          {
            name: cursor_name,
            family: family,
            tier: tier,
            capabilities: capabilities,
            provider: "cursor"
          }
        end
      end
    end
  end
end
