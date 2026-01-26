# frozen_string_literal: true

require "timeout"
require "json"

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
        error: "error",
        needs_clarification: "needs_clarification"
      }.freeze

      # Public accessors for testing and integration
      attr_reader :clarification_questions, :last_error
      attr_accessor :current_provider, :current_step, :user_input, :execution_log, :provider_manager
      attr_accessor :state, :mode, :project_dir, :configuration, :condition_detector
      attr_accessor :state_manager, :user_interface, :error_handler, :status_display
      attr_writer :completion_checker, :workflow_type, :non_interactive

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
        @last_error = nil
        @prompt = options[:prompt] || TTY::Prompt.new

        # Store workflow configuration
        @selected_steps = options[:selected_steps]
        @workflow_type = options[:workflow_type]
        @non_interactive = options[:non_interactive] || (@workflow_type == :watch_mode)

        # Initialize components
        @configuration = Configuration.new(project_dir)
        @state_manager = StateManager.new(project_dir, @mode)
        @provider_manager = create_provider_manager(options)

        # Use ZFC-enabled condition detector
        # ZfcConditionDetector will create its own ProviderFactory if needed
        # Falls back to legacy pattern matching when ZFC is disabled
        @condition_detector = ZfcConditionDetector.new(@configuration)

        @user_interface = SimpleUserInterface.new
        @error_handler = ErrorHandler.new(@provider_manager, @configuration)
        @status_display = StatusDisplay.new
        @completion_checker = CompletionChecker.new(@project_dir, @workflow_type)
        @failure_reason = nil
        @failure_metadata = nil
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
              if confirmation_prompt_allowed?
                if @user_interface.get_confirmation("Continue anyway? This may indicate issues that should be addressed.", default: false)
                  @state = STATES[:completed]
                  log_execution("Harness completed with user override")
                else
                  mark_completion_failure(completion_status)
                  @state = STATES[:error]
                  log_execution("Harness stopped due to unmet completion criteria")
                end
              else
                display_message("⚠️  Non-interactive mode: cannot override failed completion criteria. Stopping run.", type: :warning)
                mark_completion_failure(completion_status)
                @state = STATES[:error]
                log_execution("Harness stopped due to unmet completion criteria in non-interactive mode")
              end
            end
          end
        rescue Aidp::Errors::ConfigurationError
          # Configuration errors should crash immediately (crash-early principle)
          # Re-raise without catching
          raise
        rescue => e
          @state = STATES[:error]
          @last_error = e
          log_execution("Harness error: #{e.message}", {error: e.class.name, backtrace: e.backtrace&.first(5)})
          handle_error(e)
        ensure
          # Save state before exiting - protect against exceptions during cleanup
          begin
            save_state
          rescue => e
            # Don't let state save failures kill the whole run or prevent cleanup
            Aidp.logger.error("harness", "Failed to save state during cleanup: #{e.message}", error: e.class.name)
            @last_error ||= e # Only set if no previous error
          end

          begin
            cleanup
          rescue => e
            # Don't let cleanup failures propagate
            Aidp.logger.error("harness", "Failed during cleanup: #{e.message}", error: e.class.name)
          end
        end

        result = {status: @state, message: get_completion_message}
        result[:reason] = @failure_reason if @failure_reason
        result[:failure_metadata] = @failure_metadata if @failure_metadata
        result[:clarification_questions] = @clarification_questions if @clarification_questions
        if @last_error
          result[:error] = @last_error.message
          result[:error_class] = @last_error.class.name
          result[:backtrace] = @last_error.backtrace&.first(10)
        end
        result
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
            default_provider: @configuration.default_provider,
            fallback_providers: @configuration.fallback_providers,
            max_retries: @configuration.harness_config[:max_retries]
          },
          provider_manager: @provider_manager.status,
          error_stats: @error_handler.error_stats
        }
      end

      private

      def create_provider_manager(_options)
        require_relative "agent_harness_provider_manager"
        AgentHarnessProviderManager.new(@configuration, prompt: @prompt)
      end

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
        # Extract questions from result
        questions = @condition_detector.extract_questions(result)

        # Check if we're in watch mode (non-interactive)
        if @options[:workflow_type] == :watch_mode
          # Store questions for later retrieval and set state to needs_clarification
          @clarification_questions = questions
          @state = STATES[:needs_clarification]
          log_execution("Clarification needed in watch mode", {question_count: questions.size})
          # Don't continue - exit the loop so we can return this status
          return
        end

        # Interactive mode: collect feedback from user
        @state = STATES[:waiting_for_user]
        log_execution("Waiting for user feedback")

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

      def handle_rate_limit(result)
        @state = STATES[:waiting_for_rate_limit]
        log_execution("Rate limit detected, switching provider")

        rate_limit_info = nil
        if @condition_detector.respond_to?(:extract_rate_limit_info)
          rate_limit_info = @condition_detector.extract_rate_limit_info(result, @current_provider)
        end
        reset_time = rate_limit_info && rate_limit_info[:reset_time]

        # Mark current provider as rate limited
        @provider_manager.mark_rate_limited(@current_provider, reset_time)

        # Provider manager might already have switched upstream (e.g., during CLI execution)
        manager_current = @provider_manager.current_provider
        if manager_current && manager_current != @current_provider
          @current_provider = manager_current
          @state = STATES[:running]
          log_execution("Provider already switched upstream", new_provider: manager_current)
          return
        end

        # Switch to next provider explicitly when still on the rate-limited provider
        next_provider = @provider_manager.switch_provider("rate_limit", previous_provider: @current_provider)
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

      def confirmation_prompt_allowed?
        !@non_interactive
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
        # Save harness-specific state (execution_log removed to prevent unbounded growth)
        @state_manager.save_state({
          state: @state,
          current_step: @current_step,
          current_provider: @current_provider,
          user_input: @user_input,
          last_saved: Time.now
        })
      end

      def handle_error(error)
        @error_handler.handle_error(error, self)
      end

      def cleanup
        @status_display.cleanup
        log_execution("Harness cleanup completed")
      end

      def log_execution(message, data = {})
        # Keep in-memory log for runtime diagnostics (not persisted)
        log_entry = {
          timestamp: Time.now,
          message: message,
          state: @state,
          data: data
        }
        @execution_log << log_entry

        # Log to persistent logger instead of state file
        Aidp.logger.info("harness_execution", message,
          state: @state,
          step: @current_step,
          **data.slice(:error, :error_class, :criteria, :all_complete, :summary).compact)

        # Also log to standard output in debug mode
        puts "[#{Time.now.strftime("%H:%M:%S")}] #{message}" if Aidp.debug_env_level >= 1
      end

      def get_completion_message
        case @state
        when STATES[:completed]
          "Harness completed successfully. All steps finished."
        when STATES[:stopped]
          "Harness stopped by user."
        when STATES[:error]
          if @last_error
            "Harness encountered an error and stopped: #{@last_error.class.name}: #{@last_error.message}"
          else
            "Harness encountered an error and stopped."
          end
        else
          "Harness finished in state: #{@state}"
        end
      end

      def mark_completion_failure(completion_status)
        @failure_reason = :completion_criteria
        @failure_metadata = completion_status
      end

      private
    end
  end
end
