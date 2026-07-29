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
            runner.execute(command: command, role: role, request: request)
          end
        end
      end
    end
  end
end
