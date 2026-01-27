# frozen_string_literal: true

require "temporalio/workflow"
require_relative "base_workflow"

module Aidp
  module Temporal
    module Workflows
      # Workflow that orchestrates the full issue-to-PR pipeline
      # Handles: issue analysis, planning, implementation, testing, and PR creation
      #
      # State machine:
      # INIT → ANALYZE → PLAN → IMPLEMENT → TEST → {PASS → CREATE_PR | FAIL → IMPLEMENT} → COMPLETE
      class IssueToPrWorkflow < BaseWorkflow
        # Query handlers for workflow state
        workflow_query
        def current_state
          @state
        end

        workflow_query
        def iteration_count
          @iteration
        end

        workflow_query
        def progress
          {
            state: @state,
            iteration: @iteration,
            max_iterations: @max_iterations,
            issue_number: @issue_number,
            started_at: @started_at,
            last_activity: @last_activity
          }
        end

        # Signal handlers for external control
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

        workflow_signal
        def inject_instruction(instruction)
          @injected_instructions ||= []
          @injected_instructions << instruction
          log_workflow("instruction_injected", instruction_length: instruction.length)
        end

        # Main workflow execution
        def execute(input)
          initialize_state(input)
          log_workflow("started",
            issue_number: @issue_number,
            project_dir: @project_dir,
            max_iterations: @max_iterations)

          begin
            # Phase 1: Analyze the issue
            transition_to(:analyzing)
            analysis = run_analysis_phase

            return build_error_result("Analysis failed") unless analysis[:success]

            # Phase 2: Create implementation plan
            transition_to(:planning)
            plan = run_planning_phase(analysis)

            return build_error_result("Planning failed") unless plan[:success]

            # Phase 3: Implementation loop (fix-forward pattern)
            transition_to(:implementing)
            implementation = run_implementation_loop(plan)

            return build_error_result("Implementation failed: max iterations reached") unless implementation[:success]

            # Phase 4: Create PR
            transition_to(:creating_pr)
            pr_result = run_create_pr_phase(implementation)

            transition_to(:completed)
            build_success_result(pr_result)
          rescue Temporalio::Error::CanceledError
            log_workflow("canceled", state: @state, iteration: @iteration)
            transition_to(:canceled)
            build_canceled_result
          end
        end

        private

        def initialize_state(input)
          @project_dir = input[:project_dir]
          @issue_number = input[:issue_number]
          @issue_url = input[:issue_url]
          @max_iterations = input[:max_iterations] || 50
          @options = input[:options] || {}

          @state = :init
          @iteration = 0
          @paused = false
          @started_at = Time.now.iso8601
          @last_activity = nil
          @injected_instructions = []
        end

        def transition_to(new_state)
          old_state = @state
          @state = new_state
          log_workflow("state_transition", from: old_state, to: new_state)
        end

        def run_analysis_phase
          @last_activity = :analyze_issue

          result = Temporalio::Workflow.execute_activity(
            Activities::AnalyzeIssueActivity,
            {
              project_dir: @project_dir,
              issue_number: @issue_number,
              issue_url: @issue_url
            },
            **activity_options(start_to_close_timeout: 300)
          )

          log_workflow("analysis_complete", success: result[:success])
          result
        end

        def run_planning_phase(analysis)
          @last_activity = :create_plan

          result = Temporalio::Workflow.execute_activity(
            Activities::CreatePlanActivity,
            {
              project_dir: @project_dir,
              issue_number: @issue_number,
              analysis: analysis[:result]
            },
            **activity_options(start_to_close_timeout: 300)
          )

          log_workflow("planning_complete", success: result[:success])
          result
        end

        def run_implementation_loop(plan)
          loop do
            # Check for pause signal
            while @paused
              workflow_sleep(1)
            end

            # Check for cancellation
            return build_canceled_result if cancellation_requested?

            @iteration += 1
            log_workflow("implementation_iteration", iteration: @iteration, max: @max_iterations)

            if @iteration > @max_iterations
              return {success: false, reason: "max_iterations_exceeded", iteration: @iteration}
            end

            # Run single implementation iteration
            @last_activity = :run_work_loop_iteration

            iteration_input = {
              project_dir: @project_dir,
              issue_number: @issue_number,
              plan: plan[:result],
              iteration: @iteration,
              injected_instructions: drain_injected_instructions
            }

            result = Temporalio::Workflow.execute_activity(
              Activities::RunWorkLoopIterationActivity,
              iteration_input,
              **activity_options(
                start_to_close_timeout: 900,  # 15 minutes per iteration
                heartbeat_timeout: 120         # 2 minute heartbeat
              )
            )

            log_workflow("iteration_complete",
              iteration: @iteration,
              success: result[:success],
              tests_passing: result[:tests_passing])

            # Check completion
            if result[:success] && result[:tests_passing]
              return {
                success: true,
                iterations: @iteration,
                result: result[:result]
              }
            end

            # Continue to next iteration (fix-forward)
          end
        end

        def run_create_pr_phase(implementation)
          @last_activity = :create_pr

          result = Temporalio::Workflow.execute_activity(
            Activities::CreatePrActivity,
            {
              project_dir: @project_dir,
              issue_number: @issue_number,
              implementation: implementation[:result],
              iterations: implementation[:iterations]
            },
            **activity_options(start_to_close_timeout: 300)
          )

          log_workflow("pr_created",
            success: result[:success],
            pr_url: result[:pr_url])

          result
        end

        def drain_injected_instructions
          instructions = @injected_instructions.dup
          @injected_instructions.clear
          instructions
        end

        def activity_options(overrides = {})
          self.class.activity_options(overrides)
        end

        def build_success_result(pr_result)
          {
            status: "completed",
            issue_number: @issue_number,
            pr_url: pr_result[:pr_url],
            pr_number: pr_result[:pr_number],
            iterations: @iteration,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end

        def build_error_result(message)
          {
            status: "error",
            issue_number: @issue_number,
            error: message,
            state: @state,
            iteration: @iteration,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end

        def build_canceled_result
          {
            status: "canceled",
            issue_number: @issue_number,
            state: @state,
            iteration: @iteration,
            started_at: @started_at,
            completed_at: Time.now.iso8601
          }
        end
      end
    end
  end
end
