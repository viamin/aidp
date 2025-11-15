# frozen_string_literal: true

require_relative "base"
require_relative "../../util"
require_relative "../../providers/anthropic"

module Aidp
  module Harness
    module ModelDiscoverers
      # Discovers available Anthropic Claude models using the Claude CLI
      #
      # Uses the `claude models list` command to query available models.
      # Falls back to static registry if CLI is unavailable or command fails.
      class Anthropic < Base
        def initialize
          super("anthropic")
        end

        def available?
          Aidp::Providers::Anthropic.available?
        end

        def discover_models
          unless available?
            Aidp.log_debug("anthropic_discoverer", "CLI not available")
            return []
          end

          result = execute_command("claude", args: ["models", "list"])

          unless result[:success]
            Aidp.log_warn("anthropic_discoverer", "discovery failed",
              error: result[:error])
            return []
          end

          parse_claude_models_output(result[:output])
        rescue => e
          Aidp.log_error("anthropic_discoverer", "unexpected error",
            error: e.message, backtrace: e.backtrace.first(3))
          []
        end

        private

        def parse_claude_models_output(output)
          return [] if output.nil? || output.empty?

          models = []
          lines = output.lines.map(&:strip)

          # Skip header and separator lines
          lines.reject! { |line| line.empty? || line.match?(/^[-=]+$/) || line.match?(/^(Model|Name)/i) }

          lines.each do |line|
            # Try to parse various output formats from claude CLI
            model_info = parse_model_line(line)
            models << model_info if model_info
          end

          Aidp.log_info("anthropic_discoverer", "discovered models", count: models.size)
          models
        end

        def parse_model_line(line)
          # Format 1: Simple list of model names
          # claude-3-5-sonnet-20241022
          if line.match?(/^claude-\d/)
            model_name = line.split.first
            return build_model_info(model_name)
          end

          # Format 2: Table format with columns (Name | Version | etc)
          # claude-3-5-sonnet    20241022    ...
          parts = line.split(/\s{2,}/)
          if parts.size >= 1 && parts[0].match?(/^claude/)
            model_name = parts[0]
            # Add version suffix if available
            model_name = "#{model_name}-#{parts[1]}" if parts.size > 1 && parts[1].match?(/^\d{8}$/)
            return build_model_info(model_name)
          end

          # Format 3: JSON-like or key-value pairs
          # name: claude-3-5-sonnet-20241022
          if line.match?(/name:\s*(.+)/)
            model_name = $1.strip
            return build_model_info(model_name)
          end

          nil
        end

        def build_model_info(model_name)
          # Normalize to family name
          family = Aidp::Providers::Anthropic.model_family(model_name)

          # Classify tier
          tier = classify_tier(model_name)

          # Extract capabilities based on model name
          capabilities = extract_capabilities(model_name)

          # Get context window from known models
          context_window = infer_context_window(family)

          {
            name: model_name,
            family: family,
            tier: tier,
            capabilities: capabilities,
            context_window: context_window,
            provider: "anthropic"
          }
        end

        def infer_context_window(family)
          # Claude 3 and 3.5 models have 200K context
          return 200_000 if family.match?(/claude-3/)

          # Default for unknown models
          nil
        end
      end
    end
  end
end
