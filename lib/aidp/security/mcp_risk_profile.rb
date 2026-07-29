# frozen_string_literal: true

require "yaml"
require "time"
require_relative "../config_paths"

module Aidp
  module Security
    # Deterministic MCP tool risk profile generated once during configuration.
    class McpRiskProfile
      VERSION = 1
      VALID_FLAGS = %w[untrusted_input private_data egress].freeze
      VALID_RISK_LEVELS = %w[low medium high].freeze

      attr_reader :generated_at, :generator_model, :version, :tools

      def self.load(project_dir = Dir.pwd)
        path = Aidp::ConfigPaths.mcp_risk_profile_file(project_dir)
        return new(tools: {}) unless File.exist?(path)

        data = YAML.safe_load_file(path, permitted_classes: [Symbol], symbolize_names: true) || {}
        new(
          generated_at: data[:generated_at],
          generator_model: data[:generator_model],
          version: data[:version] || VERSION,
          tools: data[:tools] || {}
        )
      rescue Psych::Exception => e
        Aidp.log_error("security.mcp_risk_profile", "load_failed", path: path, error: e.message)
        new(tools: {})
      end

      def initialize(generated_at: nil, generator_model: nil, version: VERSION, tools: {})
        @generated_at = generated_at
        @generator_model = generator_model
        @version = version
        @tools = normalize_tools(tools)
      end

      def save!(project_dir = Dir.pwd)
        Aidp::ConfigPaths.ensure_security_dir(project_dir)
        File.write(Aidp::ConfigPaths.mcp_risk_profile_file(project_dir), YAML.dump(to_h))
      end

      def tool(tool_name)
        tools[tool_name.to_s]
      end

      def flags_for(tool_name)
        tool(tool_name)&.fetch(:flags, []) || []
      end

      def risk_level_for(tool_name)
        tool(tool_name)&.fetch(:risk_level, nil)
      end

      def empty?
        tools.empty?
      end

      def to_h
        {
          "generated_at" => generated_at,
          "generator_model" => generator_model,
          "version" => version,
          "tools" => tools.transform_values do |tool_data|
            {
              "flags" => tool_data[:flags],
              "risk_level" => tool_data[:risk_level],
              "rationale" => tool_data[:rationale]
            }
          end
        }
      end

      private

      def normalize_tools(raw_tools)
        raw_tools.each_with_object({}) do |(name, tool_data), normalized|
          data = symbolize(tool_data || {})
          normalized[name.to_s] = {
            flags: normalize_flags(data[:flags]),
            risk_level: normalize_risk_level(data[:risk_level]),
            rationale: data[:rationale].to_s
          }
        end
      end

      def normalize_flags(flags)
        Array(flags).map(&:to_s).select { |flag| VALID_FLAGS.include?(flag) }.uniq.sort
      end

      def normalize_risk_level(level)
        risk_level = level.to_s
        VALID_RISK_LEVELS.include?(risk_level) ? risk_level : "low"
      end

      def symbolize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, inner), hash| hash[key.to_sym] = symbolize(inner) }
        when Array
          value.map { |item| symbolize(item) }
        else
          value
        end
      end
    end
  end
end
