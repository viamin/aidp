# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"
require_relative "../../strategy_execution/strategy_spec"

module Aidp
  module Temporal
    module Workflows
      class StrategyExecutionWorkflow < BaseWorkflow
        workflow_query
        def progress
          {
            state: @state,
            depth: @depth,
            strategy: @strategy&.name,
            task: @task&.fetch(:description, nil),
            run_id: @run&.fetch(:id, nil),
            winning_branch: @winning_branch&.fetch(:branch_key, nil)
          }
        end

        def execute(input)
          initialize_state(input)

          @strategy_record = register_strategy
          @task_record = ensure_task
          @run = start_run

          transition_to(:fanout)
          branches = launch_branches
          @winning_branch = select_winning_branch(branches)

          transition_to(:merge)
          merged_children = execute_subtasks(@winning_branch)
          result = build_result(branches, merged_children)

          complete_run("completed", result)
          result
        rescue => e
          complete_run("failed", {error: e.message}) if @run
          raise
        end

        private

        def initialize_state(input)
          @project_dir = input[:project_dir]
          @strategy = Aidp::StrategyExecution::StrategySpec.from_hash(input[:strategy])
          @task = normalize_task(input[:task])
          @depth = input[:depth] || 0
          @parent_run_id = input[:parent_run_id]
          @state = :init
          @winning_branch = nil
        end

        def register_strategy
          execute_store(
            "register_strategy",
            strategy: @strategy.to_h
          )
        end

        def ensure_task
          return @task if @task[:id]

          execute_store(
            "create_task",
            title: @task[:title],
            description: @task[:description],
            input_payload: @task[:input_payload] || {},
            context: @task[:context] || {},
            source_run_id: @task[:source_run_id]
          )
        end

        def start_run
          execute_store(
            "start_run",
            task_id: @task_record[:id],
            strategy_id: @strategy_record[:id],
            workflow_id: workflow_info.workflow_id,
            depth: @depth,
            input_payload: {task: @task, strategy: @strategy.to_h},
            parent_run_id: @parent_run_id,
            metadata: {workflow_type: self.class.name}
          )
        end

        def launch_branches
          @strategy.branch_commands.map.with_index do |branch, index|
            Temporalio::Workflow.execute_child_workflow(
              StrategyBranchWorkflow,
              {
                project_dir: @project_dir,
                task: @task_record,
                task_id: @task_record[:id],
                strategy: @strategy.to_h,
                strategy_id: @strategy_record[:id],
                branch: branch,
                depth: @depth,
                parent_run_id: @run[:id]
              },
              id: "#{workflow_info.workflow_id}-branch-#{index}",
              **child_workflow_options
            )
          end.map(&:result)
        end

        def select_winning_branch(branches)
          case @strategy.merge_policy
          when "highest_score", "critic_vote_then_merge"
            branches.max_by { |branch| branch[:aggregate_score].to_f }
          else
            branches.first
          end
        end

        def execute_subtasks(winning_branch)
          subtasks = Array(winning_branch[:subtasks])
          return [] if subtasks.empty?
          return [] if @depth >= @strategy.max_depth

          transition_to(:recursive_fanout)

          subtasks.map.with_index do |subtask, index|
            Temporalio::Workflow.execute_child_workflow(
              StrategyExecutionWorkflow,
              {
                project_dir: @project_dir,
                strategy: @strategy.to_h,
                task: normalize_subtask(subtask),
                depth: @depth + 1,
                parent_run_id: @run[:id]
              },
              id: "#{workflow_info.workflow_id}-subtask-#{index}",
              **child_workflow_options
            )
          end.map(&:result)
        end

        def build_result(branches, merged_children)
          {
            status: "completed",
            run_id: @run[:id],
            task_id: @task_record[:id],
            strategy: @strategy.name,
            depth: @depth,
            winning_branch: @winning_branch,
            branch_count: branches.length,
            branches: branches,
            merged_children: merged_children
          }
        end

        def complete_run(status, output)
          execute_store(
            "complete_run",
            run_id: @run[:id],
            status: status,
            output_payload: output,
            metadata: {
              state: @state,
              winning_branch: @winning_branch&.fetch(:branch_key, nil)
            }
          )
        end

        def execute_store(operation, payload)
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

        def child_workflow_options
          {
            task_queue: workflow_info.task_queue,
            execution_timeout: 3600
          }
        end

        def normalize_task(task)
          normalized = (task || {}).transform_keys(&:to_sym)
          description = normalized[:description].to_s
          raise ArgumentError, "task description is required" if description.empty?

          normalized
        end

        def normalize_subtask(subtask)
          data = case subtask
          when Hash then subtask.transform_keys(&:to_sym)
          else {description: subtask.to_s}
          end

          {
            title: data[:title],
            description: data[:description].to_s,
            input_payload: data[:input_payload] || {},
            context: data[:context] || {}
          }
        end

        def transition_to(state)
          @state = state
        end
      end
    end
  end
end
