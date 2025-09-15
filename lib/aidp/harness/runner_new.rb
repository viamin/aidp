# frozen_string_literal: true

require "timeout"
require "json"
require_relative "configuration"
require_relative "state_manager_new"
require_relative "condition_detector"
require_relative "provider_manager"
require_relative "ui/user_interface_new"
require_relative "ui/workflow_controller"
require_relative "ui/job_monitor"
require_relative "ui/job_dashboard"
require_relative "error_handler"
require_relative "status_display"
require_relative "completion_checker"

module Aidp
  module Harness
    # Enhanced harness runner with TUI integration
    class RunnerNew
      # Harness execution states
      STATES = {
        idle: "idle",
        running: "running",
        paused: "paused",
        waiting_for_user: "waiting_for_user",
        waiting_for_rate_limit: "waiting_for_rate_limit",
        stopped: "stopped",
        completed: "completed",
        error: "error"
      }.freeze

      def initialize(project_dir, mode = :analyze, options = {})
        @project_dir = project_dir
        @mode = mode.to_sym
        @options = options
        @state = STATES[:idle]
        @start_time = nil
        @current_step = nil
        @current_provider = nil
        @user_input = options[:user_input] || {}
        @execution_log = []

        # Store workflow configuration
        @selected_steps = options[:selected_steps]
        @workflow_type = options[:workflow_type]

        # Initialize components
        @configuration = Configuration.new(project_dir)
        @state_manager = StateManagerNew.new(project_dir, @mode)
        @condition_detector = ConditionDetector.new
        @provider_manager = ProviderManager.new(@configuration)
        @error_handler = ErrorHandler.new(@provider_manager, @configuration)
        @status_display = StatusDisplay.new
        @completion_checker = CompletionChecker.new(@project_dir, @workflow_type)

        # Initialize new TUI components
        initialize_tui_components
      end

      # Main execution method - runs the harness loop with TUI
      def run
        @state = STATES[:running]
        @start_time = Time.now

        log_execution("Enhanced harness started", {mode: @mode, project_dir: @project_dir})

        begin
          # Start TUI components
          start_tui_components

          # Load existing state if resuming
          load_state if @state_manager.has_state?

          # Get the appropriate runner for the mode
          runner = get_mode_runner

          # Register main workflow job
          register_workflow_job

          # Main execution loop
          loop do
            break if should_stop?

            # Check for pause conditions
            if should_pause?
              handle_pause_condition
              next
            end

            # Get next step to execute
            next_step = get_next_step(runner)
            break unless next_step

            # Execute the step with TUI integration
            execute_step_with_tui(runner, next_step)

            # Update state
            update_state
          end

          # Mark workflow as completed
          complete_workflow_job

          # Check completion criteria
          if all_steps_completed?(runner)
            completion_status = @completion_checker.completion_status
            if completion_status[:all_complete]
              @state = STATES[:completed]
              @workflow_controller.complete_workflow("All steps completed successfully")
              log_execution("Harness completed successfully - all criteria met", completion_status)
            else
              log_execution("Steps completed but completion criteria not met", completion_status)
              handle_completion_criteria_not_met(completion_status)
            end
          end
        rescue => e
          @state = STATES[:error]
          @workflow_controller.stop_workflow("Error occurred: #{e.message}")
          log_execution("Harness error: #{e.message}", {error: e.class.name})
          handle_error(e)
        ensure
          # Save state before exiting
          save_state
          cleanup_tui_components
          cleanup
        end

        {status: @state, message: get_completion_message}
      end

      # Pause the harness execution with TUI
      def pause
        return unless @state == STATES[:running]

        @state = STATES[:paused]
        @workflow_controller.pause_workflow("User requested pause")
        log_execution("Harness paused by user")
        @status_display.show_paused_status
      end

      # Resume the harness execution with TUI
      def resume
        return unless @state == STATES[:paused]

        @state = STATES[:running]
        @workflow_controller.resume_workflow("User requested resume")
        log_execution("Harness resumed by user")
        @status_display.show_resumed_status
      end

      # Stop the harness execution with TUI
      def stop
        @state = STATES[:stopped]
        @workflow_controller.stop_workflow("User requested stop")
        log_execution("Harness stopped by user")
        @status_display.show_stopped_status
      end

      # Get current harness status with TUI integration
      def status
        {
          state: @state,
          mode: @mode,
          current_step: @current_step,
          current_provider: @current_provider,
          start_time: @start_time,
          duration: @start_time ? Time.now - @start_time : 0,
          user_input_count: @user_input.size,
          execution_log_count: @execution_log.size,
          progress: @state_manager.progress_summary,
          workflow_status: @workflow_controller.get_workflow_status,
          job_monitoring: @job_monitor.get_monitoring_summary
        }
      end

      # Get detailed status including all components
      def detailed_status
        {
          harness: status,
          configuration: {
            default_provider: @configuration.default_provider,
            fallback_providers: @configuration.fallback_providers,
            max_retries: @configuration.max_retries
          },
          provider_manager: @provider_manager.status,
          error_stats: @error_handler.error_stats,
          tui_components: {
            workflow_controller: @workflow_controller.get_workflow_status,
            job_monitor: @job_monitor.get_monitoring_summary,
            dashboard: @job_dashboard.get_dashboard_state
          }
        }
      end

      # Display TUI dashboard
      def show_dashboard(view = :overview)
        @job_dashboard.display_dashboard(view)
      end

      # Handle dashboard input
      def handle_dashboard_input(input)
        @job_dashboard.handle_dashboard_input(input)
      end

      private

      def initialize_tui_components
        # Initialize UI components with dependency injection
        ui_components = {
          status_manager: nil, # Will be set up
          frame_manager: nil,  # Will be set up
          formatter: nil       # Will be set up
        }

        @workflow_controller = WorkflowController.new(ui_components)
        @job_monitor = JobMonitor.new(ui_components)
        @job_dashboard = JobDashboard.new({
          job_monitor: @job_monitor,
          workflow_controller: @workflow_controller
        })

        # Set up UI component integration
        @user_interface = UserInterfaceNew.new({
          workflow_controller: @workflow_controller,
          job_monitor: @job_monitor
        })
      end

      def start_tui_components
        @workflow_controller.start_control_interface
        @job_monitor.start_monitoring
        @job_dashboard.start_dashboard
      end

      def cleanup_tui_components
        @job_dashboard.stop_dashboard
        @job_monitor.stop_monitoring
        @workflow_controller.stop_control_interface
      end

      def register_workflow_job
        job_data = {
          status: :running,
          priority: :normal,
          progress: 0,
          total_steps: @selected_steps&.size || 10,
          current_step: 0,
          metadata: {
            mode: @mode,
            project_dir: @project_dir,
            workflow_type: @workflow_type
          }
        }

        @job_monitor.register_job("main_workflow", job_data)
      end

      def complete_workflow_job
        @job_monitor.update_job_status("main_workflow", :completed, {
          progress: 100,
          completed_at: Time.now
        })
      end

      def get_mode_runner
        case @mode
        when :analyze
          Aidp::Analyze::Runner.new(@project_dir, self)
        when :execute
          Aidp::Execute::Runner.new(@project_dir, self)
        else
          raise ArgumentError, "Unsupported mode: #{@mode}"
        end
      end

      def get_next_step(runner)
        runner.next_step
      end

      def execute_step_with_tui(runner, step_name)
        @current_step = step_name
        log_execution("Executing step: #{step_name}")

        # Register step as a job
        step_job_id = "step_#{step_name}"
        step_job_data = {
          status: :running,
          priority: :normal,
          progress: 0,
          total_steps: 1,
          current_step: 0,
          metadata: {
            step_name: step_name,
            mode: @mode
          }
        }
        @job_monitor.register_job(step_job_id, step_job_data)

        # Mark step as in progress
        runner.mark_step_in_progress(step_name)

        # Update status display
        @status_display.update_current_step(step_name)

        # Get current provider
        @current_provider = @provider_manager.current_provider
        @status_display.update_current_provider(@current_provider)

        # Execute the step with error handling
        result = @error_handler.execute_with_retry do
          step_options = @options.merge(user_input: @user_input)
          runner.run_step(step_name, step_options)
        end

        # Update step job status
        if result && result[:status] == "completed"
          @job_monitor.update_job_status(step_job_id, :completed, {
            progress: 100,
            completed_at: Time.now
          })
          runner.mark_step_completed(step_name)
        else
          @job_monitor.update_job_status(step_job_id, :failed, {
            error_message: result&.dig(:error) || "Step execution failed"
          })
        end

        # Check for conditions that require user interaction
        if @condition_detector.needs_user_feedback?(result)
          handle_user_feedback_request_with_tui(result)
        end

        # Check for rate limiting
        if @condition_detector.is_rate_limited?(result)
          handle_rate_limit(result)
        end

        log_execution("Step completed: #{step_name}", {result: result})
        result
      end

      def handle_user_feedback_request_with_tui(result)
        @state = STATES[:waiting_for_user]
        @workflow_controller.pause_workflow("Waiting for user feedback")
        log_execution("Waiting for user feedback")

        # Extract questions from result
        questions = @condition_detector.extract_questions(result)

        # Collect user input using new TUI
        user_responses = @user_interface.collect_feedback(questions)

        # Store user input
        @user_input.merge!(user_responses)
        user_responses.each do |key, value|
          @state_manager.add_user_input(key, value)
        end

        @state = STATES[:running]
        @workflow_controller.resume_workflow("User feedback collected")
        log_execution("User feedback collected", {responses: user_responses.keys})
      end

      def handle_completion_criteria_not_met(completion_status)
        puts "\n⚠️  All steps completed but some completion criteria not met:"
        puts completion_status[:summary]

        # Use TUI for confirmation
        if @user_interface.get_confirmation("Continue anyway? This may indicate issues that should be addressed.", default: false)
          @state = STATES[:completed]
          @workflow_controller.complete_workflow("Completed with user override")
          log_execution("Harness completed with user override")
        else
          @state = STATES[:error]
          @workflow_controller.stop_workflow("Completion criteria not met")
          log_execution("Harness stopped due to unmet completion criteria")
        end
      end

      def handle_rate_limit(_result)
        @state = STATES[:waiting_for_rate_limit]
        log_execution("Rate limit detected, switching provider")

        # Mark current provider as rate limited
        @provider_manager.mark_rate_limited(@current_provider)

        # Switch to next provider
        next_provider = @provider_manager.switch_provider
        @current_provider = next_provider

        if next_provider
          @state = STATES[:running]
          log_execution("Switched to provider: #{next_provider}")
        else
          wait_for_rate_limit_reset
        end
      end

      def wait_for_rate_limit_reset
        reset_time = @provider_manager.next_reset_time
        if reset_time
          @status_display.show_rate_limit_wait(reset_time)
          sleep_until_reset(reset_time)
          @state = STATES[:running]
        else
          @state = STATES[:error]
          @workflow_controller.stop_workflow("All providers rate limited")
          raise "All providers rate limited with no reset time available"
        end
      end

      def sleep_until_reset(reset_time)
        while Time.now < reset_time && @state == STATES[:waiting_for_rate_limit]
          remaining = reset_time - Time.now
          @status_display.update_rate_limit_countdown(remaining)
          if ENV["RACK_ENV"] == "test" || defined?(RSpec)
            sleep(1)
          else
            Async::Task.current.sleep(1)
          end
        end
      end

      def should_stop?
        @state == STATES[:stopped] ||
          @state == STATES[:completed] ||
          @state == STATES[:error]
      end

      def should_pause?
        @state == STATES[:paused] ||
          @state == STATES[:waiting_for_user] ||
          @state == STATES[:waiting_for_rate_limit]
      end

      def handle_pause_condition
        case @state
        when STATES[:paused]
          # Wait for user to resume
          if ENV["RACK_ENV"] == "test" || defined?(RSpec)
            sleep(1)
          else
            Async::Task.current.sleep(1)
          end
        when STATES[:waiting_for_user]
          # User interface handles this
          nil
        when STATES[:waiting_for_rate_limit]
          # Rate limit handling
          nil
        end
      end

      def all_steps_completed?(runner)
        runner.all_steps_completed?
      end

      def update_state
        @state_manager.update_state({
          state: @state,
          current_step: @current_step,
          current_provider: @current_provider,
          user_input: @user_input,
          last_updated: Time.now
        })
      end

      def load_state
        if @state_manager.has_state?
          state_data = @state_manager.load_state
          @current_step = state_data[:current_step]
          @current_provider = state_data[:current_provider]
          @user_input = @state_manager.user_input
          log_execution("Loaded existing state", state_data)
        else
          log_execution("No existing state found, starting fresh")
        end
      end

      def save_state
        @state_manager.save_state({
          state: @state,
          current_step: @current_step,
          current_provider: @current_provider,
          user_input: @user_input,
          execution_log: @execution_log,
          last_saved: Time.now
        })

        @execution_log.each do |entry|
          @state_manager.add_execution_log(entry)
        end
      end

      def handle_error(error)
        @error_handler.handle_error(error, self)
      end

      def cleanup
        @status_display.cleanup
        log_execution("Enhanced harness cleanup completed")
      end

      def log_execution(message, data = {})
        log_entry = {
          timestamp: Time.now,
          message: message,
          state: @state,
          data: data
        }
        @execution_log << log_entry

        # Also log to standard logging if available
        puts "[#{Time.now.strftime("%H:%M:%S")}] #{message}" if ENV["AIDP_DEBUG"] == "1"
      end

      def get_completion_message
        case @state
        when STATES[:completed]
          "Enhanced harness completed successfully. All steps finished."
        when STATES[:stopped]
          "Enhanced harness stopped by user."
        when STATES[:error]
          "Enhanced harness encountered an error and stopped."
        else
          "Enhanced harness finished in state: #{@state}"
        end
      end
    end
  end
end
