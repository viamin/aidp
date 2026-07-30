# frozen_string_literal: true

module Aidp
  module StrategyExecution
    class StrategySpec
      DEFAULT_MAX_DEPTH = 1
      DEFAULT_FANOUT = 1
      DEFAULT_MERGE_POLICY = "highest_score"

      attr_reader :name, :max_depth, :fanout, :agents, :evaluators, :merge_policy, :constraints, :timeouts

      def self.from_hash(data)
        new(data.transform_keys(&:to_sym))
      end

      def initialize(data)
        @name = fetch_name(data)
        @max_depth = positive_integer(data[:max_depth], DEFAULT_MAX_DEPTH)
        @fanout = positive_integer(data[:fanout], DEFAULT_FANOUT)
        @agents = normalize_agents(data[:agents] || {})
        @evaluators = normalize_evaluators(data[:evaluators] || [])
        @merge_policy = (data[:merge_policy] || DEFAULT_MERGE_POLICY).to_s
        @constraints = (data[:constraints] || {}).transform_keys(&:to_sym)
        @timeouts = (data[:timeouts] || {}).transform_keys(&:to_sym)
        ensure_runnable!
      end

      def to_h
        {
          name: name,
          max_depth: max_depth,
          fanout: fanout,
          agents: agents,
          evaluators: evaluators,
          merge_policy: merge_policy,
          constraints: constraints,
          timeouts: timeouts
        }
      end

      def branch_commands
        commands = candidate_agent_commands
        Array.new(fanout) do |index|
          command = commands[index % commands.length]
          {
            key: "branch_#{index}",
            name: command[:name],
            command: command[:command]
          }
        end
      end

      def evaluator_definitions
        evaluators
      end

      private

      def fetch_name(data)
        value = data[:name].to_s.strip
        raise ArgumentError, "strategy name is required" if value.empty?

        value
      end

      def positive_integer(value, fallback)
        number = value.to_i
        number.positive? ? number : fallback
      end

      def normalize_agents(agents)
        agents.each_with_object({}) do |(role, value), normalized|
          normalized[role.to_sym] = case value
          when Array
            value.map { |item| normalize_agent_entry(role, item) }
          else
            normalize_agent_entry(role, value)
          end
        end
      end

      def normalize_agent_entry(role, value)
        case value
        when Hash
          {
            name: (value[:name] || value["name"] || role).to_s,
            command: (value[:command] || value["command"]).to_s
          }
        else
          {
            name: role.to_s,
            command: value.to_s
          }
        end
      end

      def normalize_evaluators(evaluators)
        Array(evaluators).map do |entry|
          case entry
          when Hash
            {
              name: (entry[:name] || entry["name"]).to_s,
              command: (entry[:command] || entry["command"] || entry[:name] || entry["name"]).to_s
            }
          else
            {
              name: entry.to_s,
              command: entry.to_s
            }
          end
        end
      end

      def candidate_agent_commands
        raw = agents[:coder] || agents[:execution] || agents.values
        commands = raw.is_a?(Hash) ? [raw] : Array(raw).flatten
        commands.reject { |entry| entry[:command].to_s.empty? }
      end

      def ensure_runnable!
        return unless candidate_agent_commands.empty?

        raise ArgumentError, "strategy '#{name}' requires at least one agent with a non-empty command"
      end
    end
  end
end
