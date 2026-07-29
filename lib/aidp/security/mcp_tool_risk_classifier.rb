# frozen_string_literal: true

require "json"
require "time"
require_relative "../harness/provider_factory"
require_relative "../harness/provider_info"
require_relative "../harness/thinking_depth_manager"
require_relative "mcp_risk_profile"

module Aidp
  module Security
    # Generates an MCP tool risk profile using an AI call at configuration time.
    class McpToolRiskClassifier
      GENERATION_PROMPT = <<~PROMPT
        You are classifying MCP tools for Rule-of-Two security enforcement.

        For each MCP tool, determine which risk flags should be enabled when that
        tool is available to an agent:
        - untrusted_input: processes or imports untrusted external/user-controlled content
        - private_data: can access secrets, credentials, local files, repos, databases, or other sensitive data
        - egress: can communicate externally, push data, call remote services, or send messages off-machine

        Also assign a risk_level of low, medium, or high based on the combined impact.

        Tools to classify:
        {{tools_json}}

        Respond with ONLY valid JSON in this format:
        {
          "tools": [
            {
              "name": "filesystem",
              "flags": ["private_data"],
              "risk_level": "medium",
              "rationale": "Can read and write local files that may contain secrets."
            }
          ]
        }
      PROMPT

      attr_reader :config, :project_dir, :provider_factory

      def initialize(config, project_dir:, provider_factory: nil, provider_info_class: nil, time_source: Time)
        @config = config
        @project_dir = project_dir
        @provider_factory = provider_factory || Aidp::Harness::ProviderFactory.new(config)
        @provider_info_class = provider_info_class || Aidp::Harness::ProviderInfo
        @time_source = time_source
      end

      def generate!(providers: nil, tier: "mini", force_refresh: false)
        tools = collect_tools(providers: providers, force_refresh: force_refresh)
        return write_empty_profile if tools.empty?

        provider_name, model_name = select_model(tier)
        response = call_ai(provider_name, model_name, build_prompt(tools))
        profile = build_profile(response, model_name)
        profile.save!(project_dir)
        profile
      rescue => e
        Aidp.log_error("security.mcp_classifier", "generation_failed",
          error: e.message,
          error_class: e.class.name)
        raise
      end

      def collect_tools(providers: nil, force_refresh: false)
        provider_names = Array(providers || config.configured_providers).map(&:to_s)

        provider_names.each_with_object({}) do |provider_name, tools|
          provider_info = @provider_info_class.new(provider_name, project_dir)
          info = provider_info.info(force_refresh: force_refresh)
          next unless info&.dig(:mcp_support)

          Array(info[:mcp_servers]).each do |server|
            next unless server[:name]

            entry = (tools[server[:name].to_s] ||= {
              name: server[:name].to_s,
              descriptions: [],
              providers: []
            })
            description = server[:description].to_s.strip
            entry[:descriptions] << description unless description.empty?
            entry[:providers] << provider_name
          end
        end.values.map do |tool|
          tool[:descriptions].uniq!
          tool[:providers].uniq!
          tool
        end.sort_by { |tool| tool[:name] }
      end

      private

      def write_empty_profile
        profile = McpRiskProfile.new(
          generated_at: @time_source.now.utc.iso8601,
          generator_model: "none",
          tools: {}
        )
        profile.save!(project_dir)
        profile
      end

      def select_model(tier)
        thinking_manager = Aidp::Harness::ThinkingDepthManager.new(config)
        provider_name, model_name, = thinking_manager.select_model_for_tier(
          tier,
          provider: config.respond_to?(:default_provider) ? config.default_provider : nil
        )
        [provider_name, model_name]
      end

      def build_prompt(tools)
        prompt = GENERATION_PROMPT.dup
        prompt.gsub!("{{tools_json}}", JSON.pretty_generate(tools))
        prompt
      end

      def call_ai(provider_name, model_name, prompt)
        provider = provider_factory.create_provider(provider_name, model: model_name, output: nil, prompt: nil)
        provider.send_message(prompt: prompt, session: nil)
      end

      def build_profile(response, model_name)
        parsed = parse_response(response)
        tools_hash = Array(parsed[:tools]).each_with_object({}) do |tool, hash|
          name = tool[:name].to_s.strip
          next if name.empty?

          hash[name] = {
            flags: Array(tool[:flags]),
            risk_level: tool[:risk_level],
            rationale: tool[:rationale]
          }
        end

        McpRiskProfile.new(
          generated_at: @time_source.now.utc.iso8601,
          generator_model: model_name,
          tools: tools_hash
        )
      end

      def parse_response(response)
        text = response.is_a?(String) ? response : response.to_s
        json_match = text.match(/\{.*\}/m)
        raise "No JSON found in AI response" unless json_match

        JSON.parse(json_match[0], symbolize_names: true)
      rescue JSON::ParserError => e
        raise "Invalid JSON in AI response: #{e.message}"
      end
    end
  end
end
