# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"
require_relative "../../strategy_execution/strategy_spec"
require_relative "../../strategy_execution/cli_protocol"

module Aidp
  module Temporal
    module Workflows
      class StrategyBranchWorkflow < BaseWorkflow
        # Must exceed the 30s heartbeat interval in ExecuteCliCommandActivity
        # while staying below the agent/evaluator start_to_close budgets, so a
        # missed beat does not time out a long-running CLI invocation.
        HEARTBEAT_TIMEOUT = 120

        def execute(input)
          initialize_state(input)
          log_workflow("execute_started",
            branch_key: @branch&.dig(:key),
            strategy_id: @strategy_id,
            depth: @depth)

          @run = start_run
          log_workflow("run_started",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key))

          agent_result = execute_agent
          fail_branch!(agent_result) unless agent_result[:success]
          log_workflow("agent_completed",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key),
            artifact_count: Array(agent_result[:artifacts]).length)

          evaluations = execute_evaluators(agent_result)
          log_workflow("evaluator_completed",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key),
            evaluator_count: evaluations.length,
            aggregate_score: aggregate_score(
              evaluations.filter_map { |evaluation| evaluation[:score]&.to_f },
              evaluations
            ))

          artifacts = record_artifacts(agent_result, evaluations)
          log_workflow("artifacts_recorded",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key),
            artifact_count: artifacts.length)

          output = build_output(agent_result, evaluations, artifacts)
          complete_run("completed", output)

          log_workflow("run_completed",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key),
            status: "completed",
            aggregate_score: output[:aggregate_score])

          output
        rescue Temporalio::Error::CanceledError
          raise
        rescue Aidp::StrategyExecution::CliProtocol::ProtocolError,
          Aidp::Database::Error => e
          Aidp.log_error("strategy_branch_workflow", "execute_failed",
            run_id: @run&.dig(:id),
            branch_key: @branch&.dig(:key),
            error: e.message,
            error_class: e.class.name)
          complete_run("failed", {error: e.message}) if @run
          raise
        end

        private

        def initialize_state(input)
          @project_dir = input[:project_dir]
          @task = input[:task]
          @task_id = input[:task_id]
          @strategy = Aidp::StrategyExecution::StrategySpec.from_hash(input[:strategy])
          @strategy_id = input[:strategy_id]
          @branch = input[:branch]
          @depth = input[:depth] || 0
          @parent_run_id = input[:parent_run_id]
        end

        def start_run
          execute_activity(
            "start_run",
            task_id: @task_id,
            strategy_id: @strategy_id,
            workflow_id: workflow_info.workflow_id,
            depth: @depth,
            input_payload: {task: @task, branch: @branch},
            parent_run_id: @parent_run_id,
            branch_key: @branch[:key],
            metadata: {workflow_type: self.class.name}
          )
        end

        def execute_agent
          log_workflow("agent_started",
            run_id: @run[:id],
            branch_key: @branch&.dig(:key))

          Temporalio::Workflow.execute_activity(
            Activities::ExecuteCliCommandActivity,
            {
              project_dir: @project_dir,
              command: @branch[:command],
              role: "agent",
              request: {
                task: @task,
                branch: @branch,
                depth: @depth,
                strategy: @strategy.to_h
              }
            },
            **activity_options(
              start_to_close_timeout: activity_timeout(:agent, 900),
              heartbeat_timeout: activity_heartbeat_timeout
            )
          )
        end

        def fail_branch!(agent_result)
          message = agent_result[:error] || agent_result[:summary] || "agent execution reported failure"
          complete_run("failed", {error: message, agent_result: agent_result})
          raise Aidp::StrategyExecution::CliProtocol::ProtocolError, message
        end

        def execute_evaluators(agent_result)
          @strategy.evaluator_definitions.map do |evaluator|
            log_workflow("evaluator_started",
              run_id: @run[:id],
              branch_key: @branch&.dig(:key),
              evaluator_name: evaluator[:name])

            result = Temporalio::Workflow.execute_activity(
              Activities::ExecuteCliCommandActivity,
              {
                project_dir: @project_dir,
                command: evaluator[:command],
                role: "evaluator",
                request: {
                  task: @task,
                  candidate: agent_result,
                  evaluator: evaluator,
                  depth: @depth,
                  strategy: @strategy.to_h
                }
              },
              **activity_options(
                start_to_close_timeout: activity_timeout(:evaluator, 300),
                heartbeat_timeout: activity_heartbeat_timeout
              )
            )

            execute_activity(
              "record_evaluation",
              run_id: @run[:id],
              evaluator_name: evaluator[:name],
              score: result[:score],
              passed: result[:passed],
              summary: result[:summary],
              metadata: result[:metadata] || {}
            )

            result.merge(name: evaluator[:name])
          end
        end

        def record_artifacts(agent_result, evaluations)
          records = []

          Array(agent_result[:artifacts]).each do |path|
            execute_activity(
              "record_artifact",
              run_id: @run[:id],
              role: "agent",
              path: path,
              metadata: {branch: @branch[:key]}
            )
            records << {role: "agent", path: path}
          end

          evaluations.each do |evaluation|
            Array(evaluation[:artifacts]).each do |path|
              execute_activity(
                "record_artifact",
                run_id: @run[:id],
                role: evaluation[:name],
                path: path,
                metadata: {branch: @branch[:key]}
              )
              records << {role: evaluation[:name], path: path}
            end
          end

          records
        end

        def build_output(agent_result, evaluations, artifacts)
          scores = evaluations.filter_map { |evaluation| evaluation[:score]&.to_f }

          {
            status: "completed",
            run_id: @run[:id],
            branch_key: @branch[:key],
            branch_name: @branch[:name],
            output: agent_result[:output] || agent_result[:content],
            summary: agent_result[:summary],
            metadata: agent_result[:metadata] || {},
            subtasks: agent_result[:subtasks] || [],
            evaluations: evaluations,
            artifacts: artifacts,
            aggregate_score: aggregate_score(scores, evaluations)
          }
        end

        def aggregate_score(scores, evaluations)
          normalized = if scores.empty?
            pass_ratio(evaluations)
          else
            scores.sum / scores.length
          end
          bonus = evaluations.count { |evaluation| evaluation[:passed] } * 0.1
          normalized + bonus
        end

        def pass_ratio(evaluations)
          return 0.0 if evaluations.empty?

          evaluations.count { |evaluation| evaluation[:passed] }.to_f / evaluations.length
        end

        def complete_run(status, output)
          execute_activity(
            "complete_run",
            run_id: @run[:id],
            status: status,
            output_payload: output,
            metadata: {branch_key: @branch[:key]}
          )
        end

        def execute_activity(operation, payload)
          Temporalio::Workflow.execute_activity(
            Activities::ManageExperienceStoreActivity,
            {
              project_dir: @project_dir,
              operation: operation,
              payload: payload
            },
            **store_activity_options(operation)
          )
        end

        def activity_timeout(role, fallback)
          value = @strategy.timeouts[role]
          number = value.to_i
          number.positive? ? number : fallback
        end

        def store_activity_options(operation)
          options = activity_options(start_to_close_timeout: 60)
          return options unless %w[start_run record_evaluation record_artifact].include?(operation)

          options.merge(retry_policy: options.fetch(:retry_policy, {}).merge(maximum_attempts: 1))
        end

        def activity_heartbeat_timeout
          HEARTBEAT_TIMEOUT
        end

        def activity_options(overrides = {})
          self.class.activity_options(overrides)
        end
      end
    end
  end
end
