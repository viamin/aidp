# frozen_string_literal: true

require "fileutils"
require_relative "deterministic_unit"
require_relative "../logger"

module Aidp
  module Execute
    class WorkLoopUnitScheduler
      Unit = Struct.new(:type, :name, :definition, keyword_init: true) do
        def agentic?
          type == :agentic
        end

        def deterministic?
          type == :deterministic
        end
      end

      attr_reader :last_agentic_summary

      def initialize(units_config, project_dir:, clock: Time)
        @clock = clock
        @project_dir = project_dir
        @deterministic_definitions = build_deterministic_definitions(units_config[:deterministic])
        @defaults = default_options.merge(units_config[:defaults] || {})
        @pending_units = []
        @initial_unit_requests = read_initial_unit_requests
        @deterministic_history = []
        @deterministic_state = Hash.new { |h, key| h[key] = default_deterministic_state }
        @agentic_runs = []
        @last_agentic_summary = nil
        @consecutive_deciders = 0
        @completed = false
        apply_initial_requests
        @started = @pending_units.any?
      end

      def next_unit
        return nil if @completed

        unless @started
          @started = true
          queue_requested_unit(@defaults[:initial_unit] || :agentic)
        end

        unit = @pending_units.shift
        return unit if unit

        queue_requested_unit(@defaults[:on_no_next_step] || :agentic)

        @pending_units.shift
      end

      def record_agentic_result(result, requested_next: nil, summary: nil, completed: false)
        @last_agentic_summary = summarize(summary)
        @agentic_runs << {timestamp: @clock.now, result: result}

        queue_requested_unit(requested_next) if requested_next

        mark_completed if completed && !requested_next
      end

      def record_deterministic_result(definition, result)
        state = @deterministic_state[definition.name]
        state[:last_run_at] = result.finished_at

        state[:current_backoff] = if result.success? || result.status == :event
          definition.min_interval_seconds
        else
          [
            state[:current_backoff] * definition.backoff_multiplier,
            definition.max_backoff_seconds
          ].min
        end

        @deterministic_history << {
          name: definition.name,
          status: result.status,
          output_path: result.output_path,
          finished_at: result.finished_at,
          data: result.data
        }

        requested = definition.next_for(result.status)
        queue_requested_unit(requested) if requested
      end

      def deterministic_context(limit: 5)
        @deterministic_history.last(limit)
      end

      def completed?
        @completed
      end

      private

      def summarize(summary)
        return nil unless summary
        content = summary.to_s.strip
        return nil if content.empty?
        (content.length > 500) ? "#{content[0...500]}…" : content
      end

      def mark_completed
        @completed = true
        @pending_units.clear
      end

      def queue_requested_unit(identifier)
        return if identifier.nil?

        case identifier.to_sym
        when :agentic
          enqueue_agentic(:primary)
        when :decide_whats_next
          enqueue_agentic(:decide_whats_next)
        else
          enqueue_deterministic(identifier.to_s)
        end
      rescue NoMethodError
        enqueue_agentic(:primary)
      end

      def enqueue_agentic(name)
        if name == :decide_whats_next
          if @consecutive_deciders >= @defaults[:max_consecutive_deciders]
            enqueue_agentic(:primary)
            return
          end
          @consecutive_deciders += 1
        else
          @consecutive_deciders = 0
        end

        @pending_units << Unit.new(type: :agentic, name: name)
      end

      def enqueue_deterministic(name)
        definition = @deterministic_definitions[name]
        unless definition
          enqueue_agentic((@defaults[:fallback_agentic] || :agentic).to_sym)
          return
        end
        return unless definition.enabled

        state = @deterministic_state[definition.name]
        state[:current_backoff] ||= definition.min_interval_seconds

        if cooldown_remaining(definition).positive?
          enqueue_agentic((@defaults[:fallback_agentic] || :agentic).to_sym)
          return
        end

        @pending_units << Unit.new(type: :deterministic, name: definition.name, definition: definition)
      end

      def cooldown_remaining(definition)
        state = @deterministic_state[definition.name]
        state[:current_backoff] ||= definition.min_interval_seconds

        return 0 unless state[:last_run_at]

        next_allowed_at = state[:last_run_at] + state[:current_backoff]
        remaining = next_allowed_at - @clock.now
        remaining.positive? ? remaining : 0
      end

      def build_deterministic_definitions(config_list)
        Array(config_list).each_with_object({}) do |config, mapping|
          definition = DeterministicUnits::Definition.new(config.transform_keys(&:to_sym))
          mapping[definition.name] = definition
        rescue KeyError, ArgumentError => e
          Aidp.logger.warn("work_loop", "Skipping invalid deterministic unit configuration",
            name: config[:name], error: e.message)
        end
      end

      def read_initial_unit_requests
        return [] unless @project_dir

        path = File.join(@project_dir, ".aidp", "work_loop", "initial_units.txt")
        return [] unless File.exist?(path)

        requests = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
        File.delete(path)
        requests
      rescue => e
        Aidp.logger.warn("work_loop", "Failed to read initial work loop requests", error: e.message)
        []
      end

      def apply_initial_requests
        Array(@initial_unit_requests).each do |request|
          queue_requested_unit(request.to_sym)
        end
        @initial_unit_requests = []
      end

      def default_deterministic_state
        {last_run_at: nil, current_backoff: nil}
      end

      def default_options
        {
          initial_unit: :agentic,
          on_no_next_step: :agentic,
          fallback_agentic: :decide_whats_next,
          max_consecutive_deciders: 1
        }
      end
    end
  end
end
