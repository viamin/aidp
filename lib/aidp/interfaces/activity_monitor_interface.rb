# frozen_string_literal: true

module Aidp
  module Interfaces
    # ActivityMonitorInterface defines the contract for activity monitoring implementations.
    # Activity monitoring tracks the state of long-running provider operations, detecting
    # stuck processes and enabling timeout/cancellation logic.
    #
    # States:
    # - :idle - No operation in progress
    # - :working - Active and producing output
    # - :stuck - No activity detected for stuck_timeout seconds
    # - :completed - Operation finished successfully
    # - :failed - Operation failed with an error
    #
    # @example Implementing the interface
    #   class MyActivityMonitor
    #     include Aidp::Interfaces::ActivityMonitorInterface
    #
    #     def start(step_name:, stuck_timeout:, on_state_change: nil)
    #       # Implementation
    #     end
    #     # ... other methods
    #   end
    #
    # @example Using an activity monitor
    #   monitor = ActivityMonitor.new
    #   monitor.start(step_name: "sending_prompt", stuck_timeout: 60)
    #   monitor.record_activity("Received response")
    #   monitor.complete
    #
    module ActivityMonitorInterface
      # Valid activity states
      STATES = [:idle, :working, :stuck, :completed, :failed].freeze

      # Start monitoring an operation.
      #
      # @param step_name [String] name of the operation being monitored
      # @param stuck_timeout [Integer] seconds before considering the operation stuck
      # @param on_state_change [Proc, nil] callback for state changes (state, message)
      # @return [void]
      def start(step_name:, stuck_timeout:, on_state_change: nil)
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      # Record activity, resetting the stuck timer.
      #
      # @param message [String, nil] optional message describing the activity
      # @return [void]
      def record_activity(message = nil)
        raise NotImplementedError, "#{self.class} must implement #record_activity"
      end

      # Mark the operation as completed successfully.
      #
      # @return [void]
      def complete
        raise NotImplementedError, "#{self.class} must implement #complete"
      end

      # Mark the operation as failed.
      #
      # @param error_message [String, nil] optional error description
      # @return [void]
      def fail(error_message = nil)
        raise NotImplementedError, "#{self.class} must implement #fail"
      end

      # Check if the operation appears to be stuck.
      #
      # @return [Boolean] true if no activity for stuck_timeout seconds
      def stuck?
        raise NotImplementedError, "#{self.class} must implement #stuck?"
      end

      # Get the current activity state.
      #
      # @return [Symbol] one of STATES
      def state
        raise NotImplementedError, "#{self.class} must implement #state"
      end

      # Get elapsed time since start.
      #
      # @return [Float] seconds since monitoring started, or 0 if not started
      def elapsed_time
        raise NotImplementedError, "#{self.class} must implement #elapsed_time"
      end

      # Get a summary of the monitoring session.
      #
      # @return [Hash] summary with keys :step_name, :state, :elapsed_time, :stuck_detected, :output_count
      def summary
        raise NotImplementedError, "#{self.class} must implement #summary"
      end
    end

    # NullActivityMonitor is a no-op implementation.
    # Useful for testing or when monitoring is not needed.
    #
    class NullActivityMonitor
      include ActivityMonitorInterface

      def start(step_name:, stuck_timeout:, on_state_change: nil)
        @state = :working
      end

      def record_activity(message = nil)
        # no-op
      end

      def complete
        @state = :completed
      end

      def fail(error_message = nil)
        @state = :failed
      end

      def stuck?
        false
      end

      def state
        @state || :idle
      end

      def elapsed_time
        0.0
      end

      def summary
        {step_name: nil, state: state, elapsed_time: 0.0, stuck_detected: false, output_count: 0}
      end
    end

    # ActivityMonitor is the standard implementation that tracks activity state.
    #
    # @example Basic usage
    #   monitor = ActivityMonitor.new
    #   monitor.start(step_name: "processing", stuck_timeout: 60)
    #   monitor.record_activity("Started processing")
    #   # ... do work ...
    #   monitor.complete
    #   puts monitor.summary
    #
    class ActivityMonitor
      include ActivityMonitorInterface

      attr_reader :state

      DEFAULT_STUCK_TIMEOUT = 30

      def initialize(logger: nil)
        @logger = logger
        @state = :idle
        @start_time = nil
        @last_activity_time = nil
        @stuck_timeout = DEFAULT_STUCK_TIMEOUT
        @step_name = nil
        @on_state_change = nil
        @output_count = 0
      end

      def start(step_name:, stuck_timeout: DEFAULT_STUCK_TIMEOUT, on_state_change: nil)
        @step_name = step_name
        @stuck_timeout = stuck_timeout
        @on_state_change = on_state_change
        @start_time = Time.now
        @last_activity_time = @start_time
        @output_count = 0
        update_state(:working)
        log_debug("started", step_name: step_name, stuck_timeout: stuck_timeout)
      end

      def record_activity(message = nil)
        @output_count += 1
        @last_activity_time = Time.now
        update_state(:working, message)
      end

      def complete
        update_state(:completed)
        log_debug("completed", elapsed_time: elapsed_time, output_count: @output_count)
      end

      def fail(error_message = nil)
        update_state(:failed, error_message)
        log_debug("failed", error_message: error_message, elapsed_time: elapsed_time)
      end

      def stuck?
        return false unless @state == :working
        return false if @last_activity_time.nil?

        seconds_since_activity = Time.now - @last_activity_time
        if seconds_since_activity > @stuck_timeout
          update_state(:stuck, "No activity for #{seconds_since_activity.round}s")
          true
        else
          false
        end
      end

      def elapsed_time
        return 0.0 unless @start_time
        Time.now - @start_time
      end

      def summary
        {
          step_name: @step_name,
          state: @state,
          start_time: @start_time&.iso8601,
          elapsed_time: elapsed_time.round(2),
          stuck_detected: @state == :stuck,
          output_count: @output_count
        }
      end

      private

      def update_state(new_state, message = nil)
        old_state = @state
        @state = new_state
        @on_state_change&.call(new_state, message) if old_state != new_state
      end

      def log_debug(message, **metadata)
        @logger&.log_debug("activity_monitor", message, step_name: @step_name, **metadata)
      end
    end
  end
end
