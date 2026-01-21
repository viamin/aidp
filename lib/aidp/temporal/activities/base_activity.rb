# frozen_string_literal: true

require "temporalio/activity"

module Aidp
  module Temporal
    module Activities
      # Base class for AIDP Temporal activities
      # Provides common patterns and utilities for activity implementations
      class BaseActivity
        extend Temporalio::Activity::Definition

        # Activity context (set by Temporal)
        def activity_context
          Temporalio::Activity.context
        end

        # Send heartbeat to indicate activity is still running
        def heartbeat(*details)
          Temporalio::Activity.heartbeat(*details)
        end

        # Check if cancellation was requested
        def cancellation_requested?
          Temporalio::Activity.cancellation_requested?
        end

        # Raise if cancellation was requested
        def check_cancellation!
          raise Temporalio::Error::CanceledError, "Activity canceled" if cancellation_requested?
        end

        protected

        # Log within activity context
        def log_activity(action, **context)
          info = activity_context&.info
          Aidp.log_debug("temporal_activity", action,
            activity_type: self.class.name.split("::").last,
            task_token: info&.task_token&.slice(0, 8),
            **context)
        end

        # Wrap activity execution with standard error handling
        def with_activity_context
          log_activity("started")

          result = yield

          log_activity("completed", success: true)
          result
        rescue => e
          log_activity("failed", error: e.message, error_class: e.class.name)
          raise
        end

        # Load AIDP configuration for project
        def load_config(project_dir)
          Aidp::Config.load_harness_config(project_dir)
        end

        # Create a provider manager for the project
        def create_provider_manager(project_dir, config)
          require_relative "../../harness/provider_manager"
          Aidp::Harness::ProviderManager.new(project_dir, config)
        end

        # Build success result
        def success_result(data = {})
          {success: true}.merge(data)
        end

        # Build error result
        def error_result(message, data = {})
          {success: false, error: message}.merge(data)
        end
      end
    end
  end
end
