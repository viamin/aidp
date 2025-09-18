# frozen_string_literal: true

module Aidp
  module Harness
    module State
      # Manages metrics, analytics, and performance calculations
      class Metrics
        def initialize(persistence, workflow_state)
          @persistence = persistence
          @workflow_state = workflow_state
        end

        def record_provider_switch(from_provider, to_provider)
          current_state = load_state
          provider_switches = (current_state[:provider_switches] || 0) + 1

          update_state(
            provider_switches: provider_switches,
            last_provider_switch: create_switch_record(from_provider, to_provider)
          )
        end

        def record_rate_limit_event(provider_name, reset_time)
          current_state = load_state
          rate_limit_events = (current_state[:rate_limit_events] || 0) + 1

          update_state(
            rate_limit_events: rate_limit_events,
            last_rate_limit: create_rate_limit_record(provider_name, reset_time)
          )
        end

        def record_user_feedback_request(step_name, questions_count)
          current_state = load_state
          user_feedback_requests = (current_state[:user_feedback_requests] || 0) + 1

          update_state(
            user_feedback_requests: user_feedback_requests,
            last_user_feedback: create_feedback_record(step_name, questions_count)
          )
        end

        def record_error_event(step_name, error_type, provider_name = nil)
          current_state = load_state
          error_events = (current_state[:error_events] || 0) + 1

          update_state(
            error_events: error_events,
            last_error: create_error_record(step_name, error_type, provider_name)
          )
        end

        def record_retry_attempt(step_name, provider_name, attempt_number)
          current_state = load_state
          retry_attempts = (current_state[:retry_attempts] || 0) + 1

          update_state(
            retry_attempts: retry_attempts,
            last_retry: create_retry_record(step_name, provider_name, attempt_number)
          )
        end

        def harness_metrics
          state = load_state
          {
            provider_switches: state[:provider_switches] || 0,
            rate_limit_events: state[:rate_limit_events] || 0,
            user_feedback_requests: state[:user_feedback_requests] || 0,
            error_events: state[:error_events] || 0,
            retry_attempts: state[:retry_attempts] || 0,
            current_provider: state[:current_provider],
            harness_state: state[:state],
            last_activity: state[:last_updated]
          }
        end

        def performance_metrics
          {
            efficiency: calculate_efficiency_metrics,
            reliability: calculate_reliability_metrics,
            performance: calculate_performance_metrics
          }
        end

        private

        def load_state
          @persistence.load_state
        end

        def update_state(updates)
          current_state = load_state
          updated_state = current_state.merge(updates)
          updated_state[:last_updated] = Time.now
          @persistence.save_state(updated_state)
        end

        def create_switch_record(from_provider, to_provider)
          {
            from: from_provider,
            to: to_provider,
            timestamp: Time.now
          }
        end

        def create_rate_limit_record(provider_name, reset_time)
          {
            provider: provider_name,
            reset_time: reset_time,
            timestamp: Time.now
          }
        end

        def create_feedback_record(step_name, questions_count)
          {
            step: step_name,
            questions_count: questions_count,
            timestamp: Time.now
          }
        end

        def create_error_record(step_name, error_type, provider_name)
          {
            step: step_name,
            error_type: error_type,
            provider: provider_name,
            timestamp: Time.now
          }
        end

        def create_retry_record(step_name, provider_name, attempt_number)
          {
            step: step_name,
            provider: provider_name,
            attempt: attempt_number,
            timestamp: Time.now
          }
        end

        def calculate_efficiency_metrics
          {
            provider_switches_per_step: calculate_switches_per_step,
            average_retries_per_step: calculate_retries_per_step,
            user_feedback_ratio: calculate_feedback_ratio
          }
        end

        def calculate_reliability_metrics
          {
            error_rate: calculate_error_rate,
            rate_limit_frequency: calculate_rate_limit_frequency,
            success_rate: calculate_success_rate
          }
        end

        def calculate_performance_metrics
          {
            session_duration: @workflow_state.session_duration,
            steps_per_hour: calculate_steps_per_hour,
            average_step_duration: calculate_average_step_duration
          }
        end

        def calculate_switches_per_step
          provider_switches = load_state[:provider_switches] || 0
          completed_steps_count = @workflow_state.completed_steps.size
          return 0 if completed_steps_count == 0
          (provider_switches.to_f / completed_steps_count).round(2)
        end

        def calculate_retries_per_step
          retry_attempts = load_state[:retry_attempts] || 0
          completed_steps_count = @workflow_state.completed_steps.size
          return 0 if completed_steps_count == 0
          (retry_attempts.to_f / completed_steps_count).round(2)
        end

        def calculate_feedback_ratio
          user_feedback_requests = load_state[:user_feedback_requests] || 0
          completed_steps_count = @workflow_state.completed_steps.size
          return 0 if completed_steps_count == 0
          (user_feedback_requests.to_f / completed_steps_count).round(2)
        end

        def calculate_error_rate
          error_events = load_state[:error_events] || 0
          total_events = error_events + @workflow_state.completed_steps.size
          return 0 if total_events == 0
          (error_events.to_f / total_events * 100).round(2)
        end

        def calculate_rate_limit_frequency
          rate_limit_events = load_state[:rate_limit_events] || 0
          session_duration_hours = @workflow_state.session_duration / 3600.0
          return 0 if session_duration_hours == 0
          (rate_limit_events / session_duration_hours).round(2)
        end

        def calculate_success_rate
          error_events = load_state[:error_events] || 0
          total_attempts = @workflow_state.completed_steps.size + error_events
          return 100 if total_attempts == 0
          ((@workflow_state.completed_steps.size.to_f / total_attempts) * 100).round(2)
        end

        def calculate_steps_per_hour
          session_duration_hours = @workflow_state.session_duration / 3600.0
          return 0 if session_duration_hours == 0
          (@workflow_state.completed_steps.size / session_duration_hours).round(2)
        end

        def calculate_average_step_duration
          return 0 if @workflow_state.completed_steps.size == 0
          (@workflow_state.session_duration / @workflow_state.completed_steps.size).round(2)
        end
      end
    end
  end
end
