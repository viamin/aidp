# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"
require_relative "../../strategy_execution/strategy_spec"

module Aidp
  module Temporal
    module Workflows
      class StrategyBranchWorkflow < BaseWorkflow
        def execute(input)
          initialize_state(input)
          @run = start_run

          agent_result = execute_agent
          evaluations = execute_evaluators(agent_result)
          artifacts = record_artifacts(agent_result, evaluations)

          output = build_output(agent_result, evaluations, artifacts)
          complete_run("completed", output)

          output
        rescue => e
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
            **activity_options(start_to_close_timeout: activity_timeout(:agent, 900))
          )
        end

        def execute_evaluators(agent_result)
          @strategy.evaluator_definitions.map do |evaluator|
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
              **activity_options(start_to_close_timeout: activity_timeout(:evaluator, 300))
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
            **activity_options(start_to_close_timeout: 60)
          )
        end

        def activity_timeout(role, fallback)
          value = @strategy.timeouts[role]
          number = value.to_i
          number.positive? ? number : fallback
        end
      end
    end
  end
end
