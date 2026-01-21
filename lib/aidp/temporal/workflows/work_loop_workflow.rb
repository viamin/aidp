# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"

module Aidp
  module Temporal
    module Workflows
      # Workflow that implements the fix-forward work loop pattern
      # Handles iterative implementation with test validation
      #
      # State machine:
      # READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH} → READY
      class WorkLoopWorkflow < BaseWorkflow
        workflow_type "work_loop"

        # Query handlers
        query_handler def current_state
          @state
        end

        query_handler def iteration_count
          @iteration
        end

        query_handler def test_results
          @last_test_results
        end

        query_handler def progress
          {
            state: @state,
            iteration: @iteration,
            max_iterations: @max_iterations,
            step_name: @step_name,
            consecutive_failures: @consecutive_failures,
            started_at: @started_at
          }
        end

        # Signal handlers
        signal_handler def pause
          @paused = true
          log_workflow("paused", iteration: @iteration)
        end

        signal_handler def resume
          @paused = false
          log_workflow("resumed", iteration: @iteration)
        end

        signal_handler def inject_instruction(instruction)
          @instruction_queue ||= []
          @instruction_queue << {
            content: instruction,
            type: :user_input,
            queued_at: Time.now.iso8601
          }
          log_workflow("instruction_queued", queue_size: @instruction_queue.length)
        end

        signal_handler def escalate_model
          @escalate_requested = true
          log_workflow("escalation_requested", current_iteration: @iteration)
        end

        # Main workflow execution
        def execute(input)
          initialize_state(input)
          log_workflow("started",
            step_name: @step_name,
            max_iterations: @max_iterations,
            project_dir: @project_dir)

          begin
            result = run_work_loop
            build_result(result)
          rescue Temporalio::Error::CanceledError
            log_workflow("canceled", state: @state, iteration: @iteration)
            build_canceled_result
          end
        end

        private

        def initialize_state(input)
          @project_dir = input[:project_dir]
          @step_name = input[:step_name]
          @step_spec = input[:step_spec]
          @context = input[:context] || {}
          @max_iterations = input[:max_iterations] || 50
          @checkpoint_interval = input[:checkpoint_interval] || 5

          @state = :ready
          @iteration = 0
          @paused = false
          @escalate_requested = false
          @consecutive_failures = 0
          @last_test_results = nil
          @instruction_queue = []
          @started_at = Time.now.iso8601
        end

        def run_work_loop
          # Create initial prompt
          transition_to(:initializing)
          prompt_result = create_initial_prompt

          unless prompt_result[:success]
            return {success: false, reason: "prompt_creation_failed", error: prompt_result[:error]}
          end

          loop do
            # Handle pause signal
            while @paused
              workflow_sleep(1)
            end

            # Check cancellation
            return {success: false, reason: "canceled"} if cancellation_requested?

            @iteration += 1
            log_workflow("iteration_start", iteration: @iteration)

            # Check iteration limit
            if @iteration > @max_iterations
              log_workflow("max_iterations_reached", max: @max_iterations)
              return {success: false, reason: "max_iterations", iterations: @iteration}
            end

            # APPLY_PATCH: Send prompt to agent
            transition_to(:apply_patch)
            agent_result = run_agent_activity

            unless agent_result[:success]
              @consecutive_failures += 1
              if @consecutive_failures >= 3
                handle_escalation
              end
              # Fix-forward: continue to next iteration
              next
            end

            # TEST: Run validation
            transition_to(:test)
            test_result = run_test_activity
            @last_test_results = test_result

            if test_result[:all_passing]
              # PASS → DONE
              transition_to(:done)
              log_workflow("completed", iterations: @iteration)
              return {
                success: true,
                iterations: @iteration,
                test_results: test_result
              }
            end

            # FAIL → DIAGNOSE
            transition_to(:diagnose)
            handle_failure(test_result)

            # Record checkpoint at intervals
            if (@iteration % @checkpoint_interval).zero?
              record_checkpoint
            end

            # Reset failure count on progress
            @consecutive_failures = 0 if test_result[:partial_pass]

            # NEXT_PATCH: Prepare for next iteration
            transition_to(:next_patch)
            prepare_next_iteration(test_result)

            transition_to(:ready)
          end
        end

        def transition_to(new_state)
          old_state = @state
          @state = new_state
          log_workflow("state_transition", from: old_state, to: new_state, iteration: @iteration)
        end

        def create_initial_prompt
          Temporalio::Workflow.execute_activity(
            Activities::CreatePromptActivity,
            {
              project_dir: @project_dir,
              step_name: @step_name,
              step_spec: @step_spec,
              context: @context
            },
            **activity_options(start_to_close_timeout: 120)
          )
        end

        def run_agent_activity
          instructions = drain_instruction_queue

          Temporalio::Workflow.execute_activity(
            Activities::RunAgentActivity,
            {
              project_dir: @project_dir,
              step_name: @step_name,
              iteration: @iteration,
              injected_instructions: instructions,
              escalate: @escalate_requested
            },
            **activity_options(
              start_to_close_timeout: 900,  # 15 minutes
              heartbeat_timeout: 120         # 2 minutes
            )
          )
        ensure
          @escalate_requested = false
        end

        def run_test_activity
          Temporalio::Workflow.execute_activity(
            Activities::RunTestsActivity,
            {
              project_dir: @project_dir,
              iteration: @iteration
            },
            **activity_options(
              start_to_close_timeout: 600,  # 10 minutes
              heartbeat_timeout: 60
            )
          )
        end

        def handle_failure(test_result)
          Temporalio::Workflow.execute_activity(
            Activities::DiagnoseFailureActivity,
            {
              project_dir: @project_dir,
              iteration: @iteration,
              test_result: test_result
            },
            **activity_options(start_to_close_timeout: 120)
          )
        end

        def prepare_next_iteration(test_result)
          Temporalio::Workflow.execute_activity(
            Activities::PrepareNextIterationActivity,
            {
              project_dir: @project_dir,
              iteration: @iteration,
              test_result: test_result,
              failures_only: true
            },
            **activity_options(start_to_close_timeout: 60)
          )
        end

        def record_checkpoint
          Temporalio::Workflow.execute_activity(
            Activities::RecordCheckpointActivity,
            {
              project_dir: @project_dir,
              step_name: @step_name,
              iteration: @iteration,
              state: @state,
              test_results: @last_test_results
            },
            **activity_options(start_to_close_timeout: 30)
          )
        end

        def handle_escalation
          log_workflow("escalating_model", consecutive_failures: @consecutive_failures)
          @escalate_requested = true
          @consecutive_failures = 0
        end

        def drain_instruction_queue
          instructions = @instruction_queue.dup
          @instruction_queue.clear
          instructions
        end

        def activity_options(overrides = {})
          self.class.activity_options(overrides)
        end

        def build_result(result)
          {
            status: result[:success] ? "completed" : "failed",
            step_name: @step_name,
            iterations: @iteration,
            success: result[:success],
            reason: result[:reason],
            test_results: result[:test_results],
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end

        def build_canceled_result
          {
            status: "canceled",
            step_name: @step_name,
            iterations: @iteration,
            state: @state,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end
      end
    end
  end
end
