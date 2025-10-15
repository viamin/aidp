# frozen_string_literal: true

require "yaml"
require_relative "../message_display"
require_relative "../rescue_logging"
require_relative "../util"

module Aidp
  module Execute
    module DeterministicUnits
      # Represents a deterministic unit configured in aidp.yml.
      # Definitions are immutable and provide helper accessors used by the scheduler.
      class Definition
        VALID_TYPES = [:command, :wait].freeze
        NEXT_KEY_ALIASES = {
          if_pass: :success,
          if_success: :success,
          if_fail: :failure,
          if_failure: :failure,
          if_error: :failure,
          if_timeout: :timeout,
          if_wait: :waiting,
          if_new_item: :event,
          if_event: :event
        }.freeze

        attr_reader :name, :type, :command, :output_file, :next_map,
          :min_interval_seconds, :max_backoff_seconds, :backoff_multiplier,
          :enabled, :metadata

        def initialize(config)
          @name = config.fetch(:name)
          @type = normalize_type(config[:type]) || default_type_for(config)
          validate_type!

          @command = config[:command]
          @output_file = config[:output_file]
          @next_map = normalize_next_config(config[:next] || {})
          @min_interval_seconds = config.fetch(:min_interval_seconds, 60)
          @max_backoff_seconds = config.fetch(:max_backoff_seconds, 900)
          @backoff_multiplier = config.fetch(:backoff_multiplier, 2.0)
          @enabled = config.fetch(:enabled, true)
          @metadata = config.fetch(:metadata, {}).dup
        end

        def command?
          type == :command
        end

        def wait?
          type == :wait
        end

        def next_for(result_status, default: nil)
          next_map[result_status.to_sym] || default || next_map[:else]
        end

        private

        def normalize_type(type)
          return nil if type.nil?
          symbol = type.to_sym
          VALID_TYPES.include?(symbol) ? symbol : nil
        end

        def default_type_for(config)
          return :command if config[:command]
          :wait
        end

        def validate_type!
          return if VALID_TYPES.include?(type)
          raise ArgumentError, "Unsupported deterministic unit type: #{type.inspect}"
        end

        def normalize_next_config(raw)
          return {} unless raw

          raw.each_with_object({}) do |(key, value), normalized|
            symbol_key = key.to_sym
            normalized[NEXT_KEY_ALIASES.fetch(symbol_key, symbol_key)] = value
          end
        end
      end

      # Result wrapper returned after executing a deterministic unit.
      class Result
        attr_reader :name, :status, :output_path, :started_at, :finished_at,
          :duration, :data, :error

        def initialize(name:, status:, output_path:, started_at:, finished_at:, data: {}, error: nil)
          @name = name
          @status = status.to_sym
          @output_path = output_path
          @started_at = started_at
          @finished_at = finished_at
          @duration = finished_at - started_at
          @data = data
          @error = error
        end

        def success?
          status == :success
        end

        def failure?
          status == :failure
        end

        def timeout?
          status == :timeout
        end
      end

      # Executes deterministic units by running commands or internal behaviours.
      class Runner
        include Aidp::MessageDisplay
        include Aidp::RescueLogging

        DEFAULT_TIMEOUT = 3600 # One hour ceiling for long-running commands

        def initialize(project_dir, command_runner: nil, clock: Time)
          @project_dir = project_dir
          @clock = clock
          @command_runner = command_runner || build_default_command_runner
        end

        def run(definition, context = {})
          raise ArgumentError, "Unit #{definition.name} is not enabled" unless definition.enabled

          case definition.type
          when :command
            execute_command_unit(definition, context)
          when :wait
            execute_wait_unit(definition, context)
          else
            raise ArgumentError, "Unsupported deterministic unit type: #{definition.type}"
          end
        end

        private

        def execute_command_unit(definition, context)
          started_at = @clock.now
          display_message("🛠️  Running deterministic unit: #{definition.name}", type: :info)

          result = @command_runner.call(definition.command, context)

          data = {
            exit_status: result[:exit_status],
            stdout: result[:stdout],
            stderr: result[:stderr]
          }

          status = result[:exit_status].to_i.zero? ? :success : :failure
          output_path = write_output(definition, data)

          display_message("✅ Deterministic unit #{definition.name} finished with status #{status}", type: :success) if status == :success
          display_message("⚠️  Deterministic unit #{definition.name} finished with status #{status}", type: :warning) if status != :success

          DeterministicUnits::Result.new(
            name: definition.name,
            status: status,
            output_path: output_path,
            started_at: started_at,
            finished_at: @clock.now,
            data: data
          )
        rescue => e
          finished_at = @clock.now
          log_rescue(e, component: "deterministic_runner", action: "execute_command_unit", fallback: "failure", unit: definition.name)
          display_message("❌ Deterministic unit #{definition.name} failed: #{e.message}", type: :error)

          output_path = write_output(definition, {error: e.message})

          DeterministicUnits::Result.new(
            name: definition.name,
            status: :failure,
            output_path: output_path,
            started_at: started_at,
            finished_at: finished_at,
            data: {error: e.message},
            error: e
          )
        end

        def execute_wait_unit(definition, context)
          started_at = @clock.now

          wait_seconds = definition.metadata.fetch(:interval_seconds, 60)
          backoff_seconds = definition.metadata.fetch(:backoff_seconds, wait_seconds)
          reason = context[:reason] || "Waiting for GitHub activity"

          display_message("🕒 Deterministic wait: #{definition.name} (#{reason})", type: :info)
          max_window = definition.max_backoff_seconds || backoff_seconds
          sleep_duration = backoff_seconds.clamp(1, max_window)

          sleep_handler = context[:sleep_handler] || method(:sleep)
          sleep_handler.call(sleep_duration)

          event_detected = context[:event_detected] == true

          payload = {
            message: "Waited #{sleep_duration} seconds",
            reason: reason,
            backoff_seconds: sleep_duration,
            event_detected: event_detected
          }

          output_path = write_output(definition, payload)

          DeterministicUnits::Result.new(
            name: definition.name,
            status: event_detected ? :event : :waiting,
            output_path: output_path,
            started_at: started_at,
            finished_at: @clock.now,
            data: payload
          )
        end

        def write_output(definition, payload)
          return nil unless definition.output_file

          path = File.join(@project_dir, definition.output_file)
          Aidp::Util.safe_file_write(path, payload.to_yaml)
          path
        end

        def build_default_command_runner
          lambda do |command, _context|
            require "tty-command"

            cmd = TTY::Command.new(printer: :quiet)
            result = cmd.run(command, chdir: @project_dir)

            {
              exit_status: result.exit_status,
              stdout: result.out,
              stderr: result.err
            }
          rescue TTY::Command::ExitError => e
            result = e.result
            {
              exit_status: result.exit_status,
              stdout: result.out,
              stderr: result.err
            }
          end
        end
      end
    end
  end
end
