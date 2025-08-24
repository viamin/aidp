# frozen_string_literal: true

module Aidp
  module Providers
    class Base
      # Activity indicator states
      ACTIVITY_STATES = {
        idle: "⏳",
        working: "🔄",
        stuck: "⚠️",
        completed: "✅",
        failed: "❌"
      }.freeze

      # Default timeout for stuck detection (2 minutes)
      DEFAULT_STUCK_TIMEOUT = 120

      attr_reader :activity_state, :last_activity_time, :start_time, :step_name

      def initialize
        @activity_state = :idle
        @last_activity_time = Time.now
        @start_time = nil
        @step_name = nil
        @activity_callback = nil
        @stuck_timeout = DEFAULT_STUCK_TIMEOUT
        @output_count = 0
        @last_output_time = Time.now
        @job_context = nil
      end

      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      def send(prompt:, session: nil)
        raise NotImplementedError, "#{self.class} must implement #send"
      end

      # Set job context for background execution
      def set_job_context(job_id:, execution_id:, job_manager:)
        @job_context = {
          job_id: job_id,
          execution_id: execution_id,
          job_manager: job_manager
        }
      end

      # Set up activity monitoring for a step
      def setup_activity_monitoring(step_name, activity_callback = nil, stuck_timeout = nil)
        @step_name = step_name
        @activity_callback = activity_callback
        @stuck_timeout = stuck_timeout || DEFAULT_STUCK_TIMEOUT
        @start_time = Time.now
        @last_activity_time = @start_time
        @output_count = 0
        @last_output_time = @start_time
        update_activity_state(:working)
      end

      # Update activity state and notify callback
      def update_activity_state(state, message = nil)
        @activity_state = state
        @last_activity_time = Time.now if state == :working

        # Log state change to job if in background mode
        if @job_context
          level = case state
          when :completed then "info"
          when :failed then "error"
          else "debug"
          end

          log_to_job(message || "Provider state changed to #{state}", level)
        end

        @activity_callback&.call(state, message, self)
      end

      # Check if provider appears to be stuck
      def stuck?
        return false unless @activity_state == :working

        time_since_activity = Time.now - @last_activity_time
        time_since_activity > @stuck_timeout
      end

      # Get current execution time
      def execution_time
        return 0 unless @start_time
        Time.now - @start_time
      end

      # Get time since last activity
      def time_since_last_activity
        Time.now - @last_activity_time
      end

      # Record activity (called when provider produces output)
      def record_activity(message = nil)
        @output_count += 1
        @last_output_time = Time.now
        update_activity_state(:working, message)
      end

      # Mark as completed
      def mark_completed
        update_activity_state(:completed)
      end

      # Mark as failed
      def mark_failed(error_message = nil)
        update_activity_state(:failed, error_message)
      end

      # Get activity summary for metrics
      def activity_summary
        {
          provider: name,
          step_name: @step_name,
          start_time: @start_time&.iso8601,
          end_time: Time.now.iso8601,
          duration: execution_time,
          final_state: @activity_state,
          stuck_detected: stuck?,
          output_count: @output_count
        }
      end

      # Check if provider supports activity monitoring
      def supports_activity_monitoring?
        true # Default to true, override in subclasses if needed
      end

      # Get stuck timeout for this provider
      attr_reader :stuck_timeout

      protected

      # Log message to job if in background mode
      def log_to_job(message, level = "info", metadata = {})
        return unless @job_context && @job_context[:job_manager]

        metadata = metadata.merge(
          provider: name,
          step_name: @step_name,
          activity_state: @activity_state,
          execution_time: execution_time,
          output_count: @output_count
        )

        @job_context[:job_manager].log_message(
          @job_context[:job_id],
          @job_context[:execution_id],
          message,
          level,
          metadata
        )
      end
    end
  end
end
