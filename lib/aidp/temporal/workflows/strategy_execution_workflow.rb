# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"
require_relative "../../strategy_execution/strategy_spec"
require_relative "../../strategy_execution/cli_protocol"

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
          log_workflow("execute_started",
            strategy: @strategy.name,
            depth: @depth,
            task_id: @task[:id])

          @strategy_record = register_strategy
          log_workflow("strategy_registered", strategy_id: @strategy_record[:id])

          @task_record = ensure_task
          log_workflow("task_ensured", task_id: @task_record[:id])

          @run = start_run
          log_workflow("run_started", run_id: @run[:id])

          transition_to(:fanout)
          branches = launch_branches
          log_workflow("branches_launched", count: branches.length)

          @winning_branch = select_winning_branch(branches)
          log_workflow("winning_branch_selected",
            branch_key: @winning_branch&.fetch(:branch_key, nil),
            aggregate_score: @winning_branch&.fetch(:aggregate_score, nil))

          transition_to(:merge)
          merged_children = execute_subtasks(@winning_branch)
          log_workflow("subtasks_completed", count: merged_children.length)

          result = build_result(branches, merged_children)

          complete_run("completed", result)
          log_workflow("execute_completed", run_id: @run[:id])
          result
        rescue Temporalio::Error::CanceledError
          raise
        rescue Aidp::StrategyExecution::CliProtocol::ProtocolError,
          Aidp::Database::Error => e
          Aidp.log_error("strategy_execution_workflow", "execute_failed",
            run_id: @run&.fetch(:id, nil),
            depth: @depth,
            error: e.message,
            error_class: e.class.name)
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
          @strategy_record = nil
          @task_record = nil
          @run = nil
        end

        def register_strategy
          execute_store(
            "register_strategy",
            strategy: @strategy.to_h
          )
        end

        def ensure_task
          existing_task = existing_task_record
          return existing_task if existing_task

          execute_store(
            "create_task",
            title: @task[:title],
            description: @task[:description],
            input_payload: @task[:input_payload] || {},
            context: @task[:context] || {},
            source_run_id: @task[:source_run_id]
          )
        end

        def existing_task_record
          task_id = @task[:id]
          return nil unless task_id

          execute_store("task_details", task_id: task_id)
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
            log_workflow("branch_launching",
              branch_key: branch[:key],
              branch_index: index,
              run_id: @run[:id])

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
          winning = case @strategy.merge_policy
          when "highest_score", "critic_vote_then_merge"
            branches.max_by { |branch| branch[:aggregate_score].to_f }
          else
            branches.first
          end

          log_workflow("merge_policy_applied",
            merge_policy: @strategy.merge_policy,
            candidates: branches.length,
            winning_branch_key: winning&.fetch(:branch_key, nil),
            run_id: @run[:id],
            depth: @depth)

          winning
        end

        def execute_subtasks(winning_branch)
          subtasks = Array(winning_branch[:subtasks])
          return [] if subtasks.empty?
          return [] if @depth >= @strategy.max_depth

          log_workflow("recursive_fanout_starting",
            subtask_count: subtasks.length,
            run_id: @run[:id],
            depth: @depth)

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
          log_workflow("run_completed",
            run_id: @run[:id],
            status: status,
            depth: @depth,
            branch_key: @winning_branch&.fetch(:branch_key, nil))
        end

        def execute_store(operation, payload)
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

        def child_workflow_options
          {
            task_queue: workflow_info.task_queue,
            execution_timeout: 3600
          }
        end

        def store_activity_options(operation)
          options = activity_options(start_to_close_timeout: 60)
          return options unless %w[create_task start_run].include?(operation)

          options.merge(retry_policy: options.fetch(:retry_policy, {}).merge(maximum_attempts: 1))
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
          previous = @state
          @state = state
          log_workflow("state_transition",
            from: previous,
            to: state,
            run_id: @run&.fetch(:id, nil),
            depth: @depth)
        end

        def activity_options(overrides = {})
          self.class.activity_options(overrides)
        end
      end
    end
  end
end
