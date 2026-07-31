# frozen_string_literal: true

require_relative "base_activity"
require_relative "../../strategy_execution/cli_protocol"

module Aidp
  module Temporal
    module Activities
      class ExecuteCliCommandActivity < BaseActivity
        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            command = input[:command]
            role = input[:role]
            request = input[:request] || {}

            runner = Aidp::StrategyExecution::CliProtocol::Runner.new(project_dir: project_dir)

            # The CLI invocation blocks for the full duration of the external
            # agent/evaluator (often minutes). Heartbeat on a background thread so
            # Temporal does not mark the activity timed out and retry the
            # side-effecting command while the original subprocess is still running.
            heartbeat_thread = start_heartbeat_thread(role: role)
            begin
              runner.execute(command: command, role: role, request: request)
            ensure
              heartbeat_thread&.kill
            end
          end
        end

        private

        # Interval between heartbeats; kept well below the workflow's
        # heartbeat_timeout so a missed beat does not time out the activity.
        def heartbeat_interval_seconds
          30
        end

        def start_heartbeat_thread(role:)
          Thread.new do
            loop do
              sleep heartbeat_interval_seconds
              heartbeat(role: role, status: "running")
            end
          end
        end
      end
    end
  end
end
