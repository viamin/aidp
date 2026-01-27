# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"

module Aidp
  module Temporal
    module Workflows
      # Child workflow for handling decomposed sub-tasks
      # Supports recursive decomposition when a task is too large
      #
      # Used by IssueToPrWorkflow to break down complex issues
      # into smaller, manageable sub-tasks executed in parallel
      class SubIssueWorkflow < BaseWorkflow
        # Maximum depth for recursive decomposition
        MAX_RECURSION_DEPTH = 3

        # Query handlers
        workflow_query
        def current_state
          @state
        end

        workflow_query
        def progress
          {
            state: @state,
            sub_issue_id: @sub_issue_id,
            parent_workflow_id: @parent_workflow_id,
            depth: @depth,
            iteration: @iteration,
            started_at: @started_at
          }
        end

        # Signal handlers
        workflow_signal
        def pause
          @paused = true
          log_workflow("paused")
        end

        workflow_signal
        def resume
          @paused = false
          log_workflow("resumed")
        end

        # Main workflow execution
        def execute(input)
          initialize_state(input)
          log_workflow("started",
            sub_issue_id: @sub_issue_id,
            depth: @depth,
            parent: @parent_workflow_id)

          # Check recursion depth limit
          if @depth >= MAX_RECURSION_DEPTH
            log_workflow("max_depth_reached", depth: @depth)
            return build_error_result("Maximum recursion depth reached")
          end

          begin
            # Analyze the sub-task
            transition_to(:analyzing)
            analysis = analyze_sub_task

            return build_error_result("Analysis failed") unless analysis[:success]

            # Check if further decomposition needed
            if needs_decomposition?(analysis)
              transition_to(:decomposing)
              result = execute_child_workflows(analysis)
            else
              # Execute directly
              transition_to(:implementing)
              result = execute_implementation(analysis)
            end

            transition_to(:completed)
            build_success_result(result)
          rescue Temporalio::Error::CanceledError
            log_workflow("canceled", state: @state)
            transition_to(:canceled)
            build_canceled_result
          end
        end

        private

        def initialize_state(input)
          @project_dir = input[:project_dir]
          @sub_issue_id = input[:sub_issue_id]
          @task_description = input[:task_description]
          @context = input[:context] || {}
          @parent_workflow_id = input[:parent_workflow_id]
          @depth = input[:depth] || 0
          @max_iterations = input[:max_iterations] || 20

          @state = :init
          @iteration = 0
          @paused = false
          @started_at = Time.now.iso8601
        end

        def transition_to(new_state)
          old_state = @state
          @state = new_state
          log_workflow("state_transition", from: old_state, to: new_state)
        end

        def analyze_sub_task
          Temporalio::Workflow.execute_activity(
            Activities::AnalyzeSubTaskActivity,
            {
              project_dir: @project_dir,
              sub_issue_id: @sub_issue_id,
              task_description: @task_description,
              context: @context
            },
            **activity_options(start_to_close_timeout: 120)
          )
        end

        def needs_decomposition?(analysis)
          # Heuristics for when to decompose further
          result = analysis[:result] || {}

          # Check estimated complexity
          estimated_iterations = result[:estimated_iterations] || 0
          return true if estimated_iterations > @max_iterations

          # Check if multiple independent tasks identified
          sub_tasks = result[:sub_tasks] || []
          return true if sub_tasks.length >= 3

          false
        end

        def execute_child_workflows(analysis)
          sub_tasks = analysis[:result][:sub_tasks] || []

          log_workflow("spawning_children",
            count: sub_tasks.length,
            depth: @depth + 1)

          # Start child workflows in parallel
          child_handles = sub_tasks.map.with_index do |task, idx|
            child_id = "#{@sub_issue_id}_sub_#{idx}"

            Temporalio::Workflow.execute_child_workflow(
              SubIssueWorkflow,
              {
                project_dir: @project_dir,
                sub_issue_id: child_id,
                task_description: task[:description],
                context: @context.merge(parent_task: @task_description),
                parent_workflow_id: workflow_info.workflow_id,
                depth: @depth + 1,
                max_iterations: task[:estimated_iterations] || 10
              },
              id: child_id,
              **child_workflow_options
            )
          end

          # Wait for all children to complete
          results = child_handles.map(&:result)

          # Aggregate results
          {
            strategy: :decomposed,
            child_count: results.length,
            all_successful: results.all? { |r| r[:status] == "completed" },
            child_results: results
          }
        end

        def execute_implementation(analysis)
          # Create work loop for this sub-task
          work_loop_result = Temporalio::Workflow.execute_child_workflow(
            WorkLoopWorkflow,
            {
              project_dir: @project_dir,
              step_name: "sub_issue_#{@sub_issue_id}",
              step_spec: {
                description: @task_description
              },
              context: @context.merge(analysis: analysis[:result]),
              max_iterations: @max_iterations
            },
            id: "workloop_#{@sub_issue_id}",
            **child_workflow_options
          ).result

          {
            strategy: :direct,
            work_loop_result: work_loop_result
          }
        end

        def activity_options(overrides = {})
          self.class.activity_options(overrides)
        end

        def child_workflow_options
          {
            task_queue: Temporalio::Workflow.info.task_queue,
            execution_timeout: 3600,  # 1 hour per child
            retry_policy: build_retry_policy(
              initial_interval: 1,
              maximum_attempts: 2
            )
          }
        end

        def build_success_result(result)
          {
            status: "completed",
            sub_issue_id: @sub_issue_id,
            depth: @depth,
            result: result,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end

        def build_error_result(message)
          {
            status: "error",
            sub_issue_id: @sub_issue_id,
            depth: @depth,
            error: message,
            state: @state,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end

        def build_canceled_result
          {
            status: "canceled",
            sub_issue_id: @sub_issue_id,
            depth: @depth,
            state: @state,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end
      end
    end
  end
end
