# frozen_string_literal: true

require_relative "ui/enhanced_tui"
require_relative "ui/enhanced_workflow_selector"
require_relative "ui/job_monitor"
require_relative "ui/workflow_controller"
require_relative "ui/progress_display"
require_relative "ui/status_widget"

module Aidp
  module Harness
    # Enhanced harness runner with modern TTY-based TUI
    class EnhancedRunner
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
        @user_input = {} if @user_input.nil?  # Ensure it's never nil
        @execution_log = []

        # Store workflow configuration
        @selected_steps = options[:selected_steps] || []
        @workflow_type = options[:workflow_type] || :default

        # Initialize enhanced TUI components
        @tui = UI::EnhancedTUI.new
        @workflow_selector = UI::EnhancedWorkflowSelector.new(@tui)
        @job_monitor = UI::JobMonitor.new
        @workflow_controller = UI::WorkflowController.new
        @progress_display = UI::ProgressDisplay.new
        @status_widget = UI::StatusWidget.new

        # Initialize other components
        @configuration = Configuration.new(project_dir)
        @state_manager = StateManager.new(project_dir, @mode)
        @condition_detector = ConditionDetector.new
        @provider_manager = ProviderManager.new(@configuration)
        @error_handler = ErrorHandler.new(@provider_manager, @configuration)
        @completion_checker = CompletionChecker.new(@project_dir, @workflow_type)
      end

      # Main execution method with enhanced TUI
      def run
        @state = STATES[:running]
        @start_time = Time.now

        @tui.show_message("🚀 Starting #{@mode.to_s.capitalize} Mode", :info)

        begin
          # Start TUI display loop
          @tui.start_display_loop

          # Load existing state if resuming
          # Temporarily disabled to test
          # load_state if @state_manager.has_state?

          # Get the appropriate runner for the mode
          runner = get_mode_runner

          # Register main workflow job
          register_workflow_job

          # Show initial workflow status
          show_workflow_status(runner)

          # Show mode-specific feedback
          show_mode_specific_feedback

          # Main execution loop
          loop do
            break if should_stop?

            # Check for pause conditions
            if should_pause?
              handle_pause_condition
              next
            end

            # Get next step to execute with spinner
            next_step = show_step_spinner("Finding next step to execute...") do
              get_next_step(runner)
            end
            break unless next_step

            # Execute the step with enhanced TUI integration
            execute_step_with_enhanced_tui(runner, next_step)

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
              @tui.show_message("🎉 Harness completed successfully - all criteria met", :success)
            else
              @tui.show_message("⚠️ Steps completed but completion criteria not met", :warning)
              handle_completion_criteria_not_met(completion_status)
            end
          end
        rescue => e
          @state = STATES[:error]
          # Single error message - don't duplicate
          @tui.show_message("❌ Error: #{e.message}", :error)
        ensure
          # Save state before exiting
          save_state
          @tui.stop_display_loop
          cleanup
        end

        {status: @state, message: get_completion_message}
      end

      # Enhanced step execution with TUI integration
      def execute_step_with_enhanced_tui(runner, step_name)
        @current_step = step_name
        @tui.show_message("🔄 Executing step: #{step_name}", :info)

        # Register step as a job
        step_job_id = "step_#{step_name}"
        step_job_data = {
          name: step_name,
          status: :running,
          progress: 0,
          provider: @current_provider || "unknown",
          message: "Starting execution..."
        }
        @tui.add_job(step_job_id, step_job_data)

        # Show step execution display
        @tui.show_step_execution(step_name, :starting, {provider: @current_provider})

        # Mark step as in progress
        runner.mark_step_in_progress(step_name)

        # Get current provider
        @current_provider = @provider_manager.current_provider

        # Execute the step with error handling and spinner
        start_time = Time.now

        # Show spinner while executing the step
        spinner_message = "Executing #{step_name}..."
        result = show_step_spinner(spinner_message) do
          @error_handler.execute_with_retry do
            step_options = @options.merge(user_input: @user_input)
            runner.run_step(step_name, step_options)
          end
        end
        duration = Time.now - start_time

        # Update step job status
        if result && result[:status] == "completed"
          @tui.update_job(step_job_id, {
            status: :completed,
            progress: 100,
            message: "Completed successfully"
          })
          @tui.show_step_execution(step_name, :completed, {duration: duration})
          runner.mark_step_completed(step_name)
        else
          @tui.update_job(step_job_id, {
            status: :failed,
            message: result&.dig(:error) || "Step execution failed"
          })
          @tui.show_step_execution(step_name, :failed, {
            error: result&.dig(:error) || "Unknown error"
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

        # Remove job after a delay to show completion
        Thread.new do
          sleep 2
          @tui.remove_job(step_job_id)
        end

        result
      end

      # Enhanced user feedback handling
      def handle_user_feedback_request_with_tui(result)
        @state = STATES[:waiting_for_user]
        @workflow_controller.pause_workflow("Waiting for user feedback")
        @tui.show_message("⏸️ Waiting for user feedback", :warning)

        # Extract questions from result
        questions = @condition_detector.extract_questions(result)

        # Show input area
        @tui.show_input_area("Please provide feedback:")

        # Collect user input using enhanced TUI
        user_responses = {}
        questions.each_with_index do |question_data, index|
          question_number = question_data[:number] || (index + 1)
          prompt = "Question #{question_number}: #{question_data[:question]}"

          response = @tui.get_user_input(prompt)
          user_responses["question_#{question_number}"] = response
        end

        # Store user input
        @user_input.merge!(user_responses)
        user_responses.each do |key, value|
          @state_manager.add_user_input(key, value)
        end

        @state = STATES[:running]
        @workflow_controller.resume_workflow("User feedback collected")
        @tui.show_message("✅ User feedback collected", :success)
      end

      # Enhanced workflow status display
      def show_workflow_status(runner)
        workflow_data = {
          workflow_type: @workflow_type,
          steps: @selected_steps || runner.all_steps,
          completed_steps: runner.progress.completed_steps.size,
          current_step: runner.progress.current_step,
          progress_percentage: calculate_progress_percentage(runner)
        }

        @tui.show_workflow_status(workflow_data)
      end

      # Job monitoring integration
      def register_workflow_job
        job_data = {
          name: "Main Workflow",
          status: :running,
          progress: 0,
          provider: @current_provider || "unknown",
          message: "Starting workflow execution..."
        }

        @tui.add_job("main_workflow", job_data)
      end

      def complete_workflow_job
        @tui.update_job("main_workflow", {
          status: :completed,
          progress: 100,
          message: "Workflow completed"
        })
      end

      # Control methods
      def pause
        return unless @state == STATES[:running]

        @state = STATES[:paused]
        @workflow_controller.pause_workflow("User requested pause")
        @tui.show_message("⏸️ Harness paused by user", :warning)
      end

      def resume
        return unless @state == STATES[:paused]

        @state = STATES[:running]
        @workflow_controller.resume_workflow("User requested resume")
        @tui.show_message("▶️ Harness resumed by user", :success)
      end

      def stop
        @state = STATES[:stopped]
        @workflow_controller.stop_workflow("User requested stop")
        @tui.show_message("⏹️ Harness stopped by user", :warning)
      end

      # Status methods
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
          jobs_count: @tui.instance_variable_get(:@jobs).size
        }
      end

      private

      def show_step_spinner(message)
        spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        spinner_index = 0

        # Start spinner in a separate thread
        spinner_thread = Thread.new do
          loop do
            print "\r#{spinner_chars[spinner_index]} #{message}"
            $stdout.flush
            spinner_index = (spinner_index + 1) % spinner_chars.length
            sleep 0.1
          end
        end

        # Execute the block
        result = yield

        # Stop spinner and show completion
        spinner_thread.kill
        print "\r✅ #{message} completed\n"
        $stdout.flush

        result
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
          sleep(1)
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

      def calculate_progress_percentage(runner)
        total_steps = runner.all_steps.size
        completed_steps = runner.progress.completed_steps.size
        return 0 if total_steps == 0
        (completed_steps.to_f / total_steps * 100).round(2)
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
          state = @state_manager.load_state
          # Ensure state is not nil before accessing it
          if state&.is_a?(Hash)
            @user_input.merge!(state[:user_input] || {})
          end
        end
      end

      def save_state
        @state_manager.save_state({
          state: @state,
          current_step: @current_step,
          current_provider: @current_provider,
          user_input: @user_input,
          last_updated: Time.now
        })
      end

      def show_mode_specific_feedback
        case @mode
        when :analyze
          @tui.show_message("🔬 Starting codebase analysis...", :info)
          @tui.show_message("Press 'j' to view background jobs, 'h' for help", :info)
        when :execute
          @tui.show_message("🏗️ Starting development workflow...", :info)
          @tui.show_message("Press 'j' to view background jobs, 'h' for help", :info)
        end
      end

      def handle_error(error)
        # Single comprehensive error report
        @tui.show_message("❌ Harness error: #{error.message}", :error)
        @tui.show_message("Error type: #{error.class.name}", :error)

        # Log error details for debugging
        @execution_log << {
          timestamp: Time.now,
          level: :error,
          message: error.message,
          backtrace: error.backtrace&.first(5)
        }

        # Show backtrace in debug mode only
        if ENV["DEBUG"]
          @tui.show_message("Backtrace: #{error.backtrace&.first(3)&.join("\n")}", :error)
        end
      end

      def handle_completion_criteria_not_met(completion_status)
        @tui.show_message("Completion criteria not met: #{completion_status[:summary]}", :warning)

        if @tui.get_confirmation("Continue anyway? This may indicate issues that should be addressed.", default: false)
          @state = STATES[:completed]
          @workflow_controller.complete_workflow("Completed with user override")
          @tui.show_message("✅ Harness completed with user override", :success)
        else
          @state = STATES[:error]
          @workflow_controller.stop_workflow("Completion criteria not met")
          @tui.show_message("❌ Harness stopped due to unmet completion criteria", :error)
        end
      end

      def handle_rate_limit(result)
        @state = STATES[:waiting_for_rate_limit]
        @tui.show_message("⏳ Rate limit detected, switching provider", :warning)

        @provider_manager.mark_rate_limited(@current_provider)
        next_provider = @provider_manager.switch_provider
        @current_provider = next_provider

        if next_provider
          @state = STATES[:running]
          @tui.show_message("🔄 Switched to provider: #{next_provider}", :info)
        else
          wait_for_rate_limit_reset
        end
      end

      def wait_for_rate_limit_reset
        reset_time = @provider_manager.next_reset_time
        if reset_time
          @tui.show_message("⏰ Waiting for rate limit reset at #{reset_time}", :warning)
          sleep_until_reset(reset_time)
          @state = STATES[:running]
        else
          @state = STATES[:error]
          raise "All providers rate limited with no reset time available"
        end
      end

      def sleep_until_reset(reset_time)
        while Time.now < reset_time && @state == STATES[:waiting_for_rate_limit]
          remaining = reset_time - Time.now
          @tui.show_message("⏳ Rate limit reset in #{remaining.to_i} seconds", :info)
          sleep(1)
        end
      end

      def cleanup
        # Cleanup any remaining jobs
        @tui.instance_variable_get(:@jobs).keys.each do |job_id|
          @tui.remove_job(job_id)
        end
      end

      def get_completion_message
        case @state
        when STATES[:completed]
          "Harness completed successfully"
        when STATES[:stopped]
          "Harness stopped by user"
        when STATES[:error]
          "Harness encountered an error"
        else
          "Harness finished"
        end
      end
    end
  end
end
