# frozen_string_literal: true

require "tty-prompt"

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

      def initialize(output: nil, prompt: TTY::Prompt.new)
        @activity_state = :idle
        @last_activity_time = Time.now
        @start_time = nil
        @step_name = nil
        @activity_callback = nil
        @stuck_timeout = DEFAULT_STUCK_TIMEOUT
        @output_count = 0
        @last_output_time = Time.now
        @job_context = nil
        @harness_context = nil
        @output = output
        @prompt = prompt
        @harness_metrics = {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          rate_limited_requests: 0,
          total_tokens_used: 0,
          total_cost: 0.0,
          average_response_time: 0.0,
          last_request_time: nil
        }
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

      # Harness integration methods

      # Set harness context for provider
      def set_harness_context(harness_runner)
        @harness_context = harness_runner
      end

      # Check if provider is operating in harness mode
      def harness_mode?
        !@harness_context.nil?
      end

      # Get harness metrics
      def harness_metrics
        @harness_metrics.dup
      end

      # Record harness request metrics
      def record_harness_request(success:, tokens_used: 0, cost: 0.0, response_time: 0.0, rate_limited: false)
        @harness_metrics[:total_requests] += 1
        @harness_metrics[:last_request_time] = Time.now

        if success
          @harness_metrics[:successful_requests] += 1
        else
          @harness_metrics[:failed_requests] += 1
        end

        if rate_limited
          @harness_metrics[:rate_limited_requests] += 1
        end

        @harness_metrics[:total_tokens_used] += tokens_used
        @harness_metrics[:total_cost] += cost

        # Update average response time
        total_time = @harness_metrics[:average_response_time] * (@harness_metrics[:total_requests] - 1) + response_time
        @harness_metrics[:average_response_time] = total_time / @harness_metrics[:total_requests]

        # Notify harness context if available
        @harness_context&.record_provider_metrics(name, @harness_metrics)
      end

      # Get provider health status for harness
      def harness_health_status
        {
          provider: name,
          activity_state: @activity_state,
          stuck: stuck?,
          success_rate: calculate_success_rate,
          average_response_time: @harness_metrics[:average_response_time],
          total_requests: @harness_metrics[:total_requests],
          rate_limit_ratio: calculate_rate_limit_ratio,
          last_activity: @last_activity_time,
          health_score: calculate_health_score
        }
      end

      # Check if provider is healthy for harness use
      def harness_healthy?
        return false if stuck?
        return false if @harness_metrics[:total_requests] > 0 && calculate_success_rate < 0.5
        return false if calculate_rate_limit_ratio > 0.3

        true
      end

      # Get provider configuration for harness
      def harness_config
        {
          name: name,
          supports_activity_monitoring: supports_activity_monitoring?,
          default_timeout: @stuck_timeout,
          available: available?,
          health_status: harness_health_status
        }
      end

      # Check if provider is available (override in subclasses)
      def available?
        true # Default to true, override in subclasses
      end

      # Enhanced send method that integrates with harness
      def send_with_harness(prompt:, session: nil, _options: {})
        start_time = Time.now
        success = false
        rate_limited = false
        tokens_used = 0
        cost = 0.0
        error_message = nil

        begin
          # Call the original send method
          result = send(prompt: prompt, session: session)
          success = true

          # Extract token usage and cost if available
          if result.is_a?(Hash) && result[:token_usage]
            tokens_used = result[:token_usage][:total] || 0
            cost = result[:token_usage][:cost] || 0.0
          end

          # Check for rate limiting in result
          if result.is_a?(Hash) && result[:rate_limited]
            rate_limited = true
          end

          result
        rescue => e
          error_message = e.message

          # Check if error is rate limiting
          if e.message.match?(/rate.?limit/i) || e.message.match?(/quota/i)
            rate_limited = true
          end

          raise e
        ensure
          response_time = Time.now - start_time
          record_harness_request(
            success: success,
            tokens_used: tokens_used,
            cost: cost,
            response_time: response_time,
            rate_limited: rate_limited
          )

          # Log to harness context if available
          if @harness_context && error_message
            @harness_context.record_provider_error(name, error_message, rate_limited)
          end
        end
      end

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

      # Calculate success rate for harness metrics
      def calculate_success_rate
        return 1.0 if @harness_metrics[:total_requests] == 0
        @harness_metrics[:successful_requests].to_f / @harness_metrics[:total_requests]
      end

      # Calculate rate limit ratio for harness metrics
      def calculate_rate_limit_ratio
        return 0.0 if @harness_metrics[:total_requests] == 0
        @harness_metrics[:rate_limited_requests].to_f / @harness_metrics[:total_requests]
      end

      # Calculate overall health score for harness
      def calculate_health_score
        return 100.0 if @harness_metrics[:total_requests] == 0

        success_rate = calculate_success_rate
        rate_limit_ratio = calculate_rate_limit_ratio
        response_time_score = [100 - (@harness_metrics[:average_response_time] * 10), 0].max

        # Weighted health score
        (success_rate * 50) + ((1 - rate_limit_ratio) * 30) + (response_time_score * 0.2)
      end

      private

      def display_message(message, type: :info)
        color = case type
        when :error then :red
        when :success then :green
        when :warning then :yellow
        when :info then :blue
        when :highlight then :cyan
        when :muted then :bright_black
        else :white
        end
        @prompt.say(message, color: color)
      end
    end
  end
end
