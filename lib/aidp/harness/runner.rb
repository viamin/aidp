# frozen_string_literal: true

require "timeout"
require "json"
require_relative "config_manager"
require_relative "state_manager"
require_relative "condition_detector"
require_relative "provider_manager"
require_relative "simple_user_interface"
require_relative "error_handler"
require_relative "status_display"
require_relative "completion_checker"
require_relative "../concurrency"

module Aidp
  module Harness
    # Main harness runner that orchestrates the execution loop
    class Runner
      include Aidp::MessageDisplay

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

      # Public accessors for testing and integration
      attr_reader :current_provider, :current_step, :user_input, :execution_log, :provider_manager

      def initialize(project_dir, mode = :analyze, options = {})
        @project_dir = project_dir
        @mode = mode.to_sym
        @options = options
        @state = STATES[:idle]
        @start_time = nil
        @current_step = nil
        @current_provider = nil
        @user_input = options[:user_input] || {} # Include user input from workflow selection
        @execution_log = []
        @prompt = options[:prompt] || TTY::Prompt.new

        # Store workflow configuration
        @selected_steps = options[:selected_steps]
        @workflow_type = options[:workflow_type]

        # Initialize components
        @config_manager = ConfigManager.new(project_dir)
        @state_manager = StateManager.new(project_dir, @mode)
        @provider_manager = ProviderManager.new(@config_manager, prompt: @prompt)

        # Use ZFC-enabled condition detector
        # ZfcConditionDetector will create its own ProviderFactory if needed
        # Falls back to legacy pattern matching when ZFC is disabled
        require_relative "zfc_condition_detector"
        @condition_detector = ZfcConditionDetector.new(@config_manager)

        @user_interface = SimpleUserInterface.new
        @error_handler = ErrorHandler.new(@provider_manager, @config_manager)
        @status_display = StatusDisplay.new
        @completion_checker = CompletionChecker.new(@project_dir, @workflow_type)
      end

      # Main execution method - runs the harness loop
      def run
        @state = STATES[:running]
        @start_time = Time.now

        log_execution("Harness started", {mode: @mode, project_dir: @project_dir})

        begin
          # Load existing state if resuming
          load_state if @state_manager.has_state?

          # Get the appropriate runner for the mode
          runner = get_mode_runner

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

            # Execute the step
            execute_step(runner, next_step)

            # Update state
            update_state
          end

          # Mark as completed if we finished all steps AND all completion criteria are met
          if all_steps_completed?(runner)
            completion_status = @completion_checker.completion_status
            if completion_status[:all_complete]
              @state = STATES[:completed]
              log_execution("Harness completed successfully - all criteria met", completion_status)
            else
              log_execution("Steps completed but completion criteria not met", completion_status)
              display_message("\n⚠️  All steps completed but some completion criteria not met:", type: :warning)
              display_message(completion_status[:summary], type: :info)

              # Ask user if they want to continue anyway
              if @user_interface.get_confirmation("Continue anyway? This may indicate issues that should be addressed.", default: false)
                @state = STATES[:completed]
                log_execution("Harness completed with user override")
              else
                @state = STATES[:error]
                log_execution("Harness stopped due to unmet completion criteria")
              end
            end
          end
        rescue => e
          @state = STATES[:error]
          log_execution("Harness error: #{e.message}", {error: e.class.name})
          handle_error(e)
        ensure
          # Save state before exiting
          save_state
          cleanup
        end

        {status: @state, message: get_completion_message}
      end

      # Pause the harness execution
      def pause
        return unless @state == STATES[:running]

        @state = STATES[:paused]
        log_execution("Harness paused by user")
        @status_display.show_paused_status
      end

      # Resume the harness execution
      def resume
        return unless @state == STATES[:paused]

        @state = STATES[:running]
        log_execution("Harness resumed by user")
        @status_display.show_resumed_status
      end

      # Stop the harness execution
      def stop
        @state = STATES[:stopped]
        log_execution("Harness stopped by user")
        @status_display.show_stopped_status
      end

      # Get current harness status
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
          progress: @state_manager.progress_summary
        }
      end

      # Get detailed status including all components
      def detailed_status
        {
          harness: status,
          configuration: {
            default_provider: @config_manager.default_provider,
            fallback_providers: @config_manager.fallback_providers,
            max_retries: @config_manager.harness_config[:max_retries]
          },
          provider_manager: @provider_manager.status,
          error_stats: @error_handler.error_stats
        }
      end

      private

      def get_mode_runner
        case @mode
        when :analyze
          Aidp::Analyze::Runner.new(@project_dir, self, prompt: @prompt)
        when :execute
          Aidp::Execute::Runner.new(@project_dir, self, prompt: @prompt)
        else
          raise ArgumentError, "Unsupported mode: #{@mode}"
        end
      end

      def get_next_step(runner)
        # Use the mode runner's next_step method
        runner.next_step
      end

      def execute_step(runner, step_name)
        @current_step = step_name
        log_execution("Executing step: #{step_name}")

        # Mark step as in progress using the runner's method
        runner.mark_step_in_progress(step_name)

        # Update status display
        @status_display.update_current_step(step_name)

        # Get current provider
        @current_provider = @provider_manager.current_provider
        @status_display.update_current_provider(@current_provider)

        # Execute the step with error handling
        result = @error_handler.execute_with_retry do
          # Merge harness options with user input
          step_options = @options.merge(user_input: @user_input)
          runner.run_step(step_name, step_options)
        end

        # Check for conditions that require user interaction
        if @condition_detector.needs_user_feedback?(result)
          handle_user_feedback_request(result)
        end

        # Check for rate limiting
        if @condition_detector.is_rate_limited?(result)
          handle_rate_limit(result)
        end

        # Mark step as completed if successful using the runner's method
        if result && result[:status] == "completed"
          runner.mark_step_completed(step_name)
        end

        log_execution("Step completed: #{step_name}", {result: result})
        result
      end

      def handle_user_feedback_request(result)
        @state = STATES[:waiting_for_user]
        log_execution("Waiting for user feedback")

        # Extract questions from result
        questions = @condition_detector.extract_questions(result)

        # Collect user input
        user_responses = @user_interface.collect_feedback(questions)

        # Store user input in both local state and state manager
        @user_input.merge!(user_responses)
        user_responses.each do |key, value|
          @state_manager.add_user_input(key, value)
        end

        @state = STATES[:running]
        log_execution("User feedback collected", {responses: user_responses.keys})
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
          # All providers rate limited, wait for reset
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
          raise "All providers rate limited with no reset time available"
        end
      end

      def sleep_until_reset(reset_time)
        while Time.now < reset_time && @state == STATES[:waiting_for_rate_limit]
          remaining = reset_time - Time.now
          @status_display.update_rate_limit_countdown(remaining)
          sleep(1)
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
        # Use the mode runner's all_steps_completed? method
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
        # Save harness-specific state
        @state_manager.save_state({
          state: @state,
          current_step: @current_step,
          current_provider: @current_provider,
          user_input: @user_input,
          execution_log: @execution_log,
          last_saved: Time.now
        })

        # Also save execution log entries to state manager
        @execution_log.each do |entry|
          @state_manager.add_execution_log(entry)
        end
      end

      def handle_error(error)
        @error_handler.handle_error(error, self)
      end

      def cleanup
        @status_display.cleanup
        log_execution("Harness cleanup completed")
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
          "Harness completed successfully. All steps finished."
        when STATES[:stopped]
          "Harness stopped by user."
        when STATES[:error]
          "Harness encountered an error and stopped."
        else
          "Harness finished in state: #{@state}"
        end
      end

      private
    end
  end
end
