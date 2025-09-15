# frozen_string_literal: true

require_relative "state/persistence"
require_relative "state/ui_state"
require_relative "state/provider_state"
require_relative "state/workflow_state"
require_relative "state/metrics"

module Aidp
  module Harness
    # Refactored StateManager using focused components following Sandi Metz's rules
    class StateManagerNew
      def initialize(project_dir, mode)
        @project_dir = project_dir
        @mode = mode
        @persistence = State::Persistence.new(project_dir, mode)
        @ui_state = State::UIState.new(@persistence)
        @provider_state = State::ProviderState.new(@persistence)
        @workflow_state = State::WorkflowState.new(@persistence, project_dir, mode)
        @metrics = State::Metrics.new(@persistence, @workflow_state)
      end

      # Delegate to focused components
      def has_state?
        @persistence.has_state?
      end

      def load_state
        @persistence.load_state
      end

      def save_state(state_data)
        @persistence.save_state(state_data)
      end

      def clear_state
        @persistence.clear_state
      end

      def state_metadata
        @ui_state.state_metadata
      end

      def update_state(updates)
        current_state = load_state
        updated_state = current_state.merge(updates)
        updated_state[:last_updated] = Time.now
        save_state(updated_state)
      end

      # UI State delegation
      def user_input
        @ui_state.user_input
      end

      def add_user_input(key, value)
        @ui_state.add_user_input(key, value)
      end

      def execution_log
        @ui_state.execution_log
      end

      def add_execution_log(entry)
        @ui_state.add_execution_log(entry)
      end

      def current_step_from_state
        @ui_state.current_step
      end

      def set_current_step(step_name)
        @ui_state.set_current_step(step_name)
      end

      # Provider State delegation
      def provider_state
        @provider_state.provider_state
      end

      def update_provider_state(provider_name, provider_data)
        @provider_state.update_provider_state(provider_name, provider_data)
      end

      def rate_limit_info
        @provider_state.rate_limit_info
      end

      def update_rate_limit_info(provider_name, reset_time, error_count = 0)
        @provider_state.update_rate_limit_info(provider_name, reset_time, error_count)
      end

      def provider_rate_limited?(provider_name)
        @provider_state.provider_rate_limited?(provider_name)
      end

      def next_provider_reset_time
        @provider_state.next_provider_reset_time
      end

      def record_token_usage(provider_name, model_name, input_tokens, output_tokens, cost = nil)
        @provider_state.record_token_usage(provider_name, model_name, input_tokens, output_tokens, cost)
      end

      def get_token_usage_summary
        @provider_state.token_usage_summary
      end

      # Workflow State delegation
      def progress_tracker
        @workflow_state.progress_tracker
      end

      def completed_steps
        @workflow_state.completed_steps
      end

      def current_step
        @workflow_state.current_step
      end

      def step_completed?(step_name)
        @workflow_state.step_completed?(step_name)
      end

      def mark_step_completed(step_name)
        @workflow_state.mark_step_completed(step_name)
      end

      def mark_step_in_progress(step_name)
        @workflow_state.mark_step_in_progress(step_name)
      end

      def next_step
        @workflow_state.next_step
      end

      def total_steps
        @workflow_state.total_steps
      end

      def all_steps_completed?
        @workflow_state.all_steps_completed?
      end

      def progress_percentage
        @workflow_state.progress_percentage
      end

      def session_duration
        @workflow_state.session_duration
      end

      def reset_all
        @workflow_state.reset_all
      end

      def progress_summary
        summary = @workflow_state.progress_summary
        summary.merge(
          harness_metrics: harness_metrics,
          token_usage: get_token_usage_summary
        )
      end

      # Metrics delegation
      def record_provider_switch(from_provider, to_provider)
        @metrics.record_provider_switch(from_provider, to_provider)
      end

      def record_rate_limit_event(provider_name, reset_time)
        @metrics.record_rate_limit_event(provider_name, reset_time)
      end

      def record_user_feedback_request(step_name, questions_count)
        @metrics.record_user_feedback_request(step_name, questions_count)
      end

      def record_error_event(step_name, error_type, provider_name = nil)
        @metrics.record_error_event(step_name, error_type, provider_name)
      end

      def record_retry_attempt(step_name, provider_name, attempt_number)
        @metrics.record_retry_attempt(step_name, provider_name, attempt_number)
      end

      def harness_metrics
        @metrics.harness_metrics
      end

      def get_performance_metrics
        @metrics.performance_metrics
      end

      # Legacy methods for backward compatibility
      def cleanup_old_state(days_old = 7)
        return unless has_state?

        state = load_state
        saved_at = Time.parse(state[:saved_at]) if state[:saved_at]

        if saved_at && (Time.now - saved_at) > (days_old * 24 * 60 * 60)
          clear_state
          true
        else
          false
        end
      end

      def export_state
        {
          state_file: @persistence.instance_variable_get(:@state_file),
          has_state: has_state?,
          metadata: state_metadata,
          state: load_state
        }
      end
    end
  end
end
