# frozen_string_literal: true

require "temporalio/workflow"

module Aidp
  module Temporal
    module Workflows
      # Base class for AIDP Temporal workflows
      # Provides common patterns and utilities for workflow implementations
      class BaseWorkflow < Temporalio::Workflow::Definition
        # Default activity options applied to all activities
        DEFAULT_ACTIVITY_OPTIONS = {
          start_to_close_timeout: 600,    # 10 minutes
          heartbeat_timeout: 60,          # 1 minute
          retry_policy: {
            initial_interval: 1,
            backoff_coefficient: 2.0,
            maximum_interval: 60,
            maximum_attempts: 3
          }
        }.freeze

        class << self
          # Define workflow name from class name
          def workflow_name
            name.split("::").last.gsub(/Workflow$/, "").gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, "")
          end

          # Helper to define activity with default options
          def activity_options(overrides = {})
            DEFAULT_ACTIVITY_OPTIONS.merge(overrides)
          end
        end

        protected

        # Log within workflow context
        def log_workflow(action, **context)
          workflow_info = Temporalio::Workflow.info
          Aidp.log_debug("temporal_workflow", action,
            workflow_id: workflow_info.workflow_id,
            run_id: workflow_info.run_id,
            **context)
        end

        # Sleep that respects cancellation
        def workflow_sleep(duration)
          Temporalio::Workflow.sleep(duration)
        end

        # Get current workflow info
        def workflow_info
          Temporalio::Workflow.info
        end

        # Check if cancellation was requested
        def cancellation_requested?
          Temporalio::Workflow.cancellation_pending?
        end

        # Build retry policy from config
        def build_retry_policy(config)
          Temporalio::RetryPolicy.new(
            initial_interval: config[:initial_interval] || 1,
            backoff_coefficient: config[:backoff_coefficient] || 2.0,
            maximum_interval: config[:maximum_interval] || 60,
            maximum_attempts: config[:maximum_attempts] || 3
          )
        end
      end
    end
  end
end
