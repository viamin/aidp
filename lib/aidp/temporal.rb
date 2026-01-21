# frozen_string_literal: true

# Temporal integration for AIDP
# Provides durable workflow orchestration for issue-to-PR pipelines
#
# Components:
# - Connection: Manages Temporal client connections
# - Worker: Runs workflows and activities
# - WorkflowClient: Interface for starting/managing workflows
# - Configuration: Loads Temporal settings from aidp.yml
#
# Workflows:
# - IssueToPrWorkflow: Full issue analysis → implementation → PR pipeline
# - WorkLoopWorkflow: Fix-forward iteration pattern
# - SubIssueWorkflow: Child workflow for decomposed tasks
#
# Activities:
# - RunAgentActivity: Execute AI agent
# - RunTestsActivity: Run tests/linters
# - AnalyzeIssueActivity: Analyze GitHub issue
# - CreatePlanActivity: Generate implementation plan
# - CreatePromptActivity: Build PROMPT.md
# - DiagnoseFailureActivity: Analyze failures
# - PrepareNextIterationActivity: Set up next iteration
# - RecordCheckpointActivity: Save progress
# - CreatePrActivity: Create GitHub PR

module Aidp
  module Temporal
    class << self
      # Get the default configuration
      def configuration(project_dir = Dir.pwd)
        @configurations ||= {}
        @configurations[project_dir] ||= Configuration.new(project_dir)
      end

      # Check if Temporal is enabled
      def enabled?(project_dir = Dir.pwd)
        configuration(project_dir).enabled?
      end

      # Build a connection with project configuration
      def connection(project_dir = Dir.pwd)
        configuration(project_dir).build_connection
      end

      # Build a workflow client with project configuration
      def workflow_client(project_dir = Dir.pwd)
        configuration(project_dir).build_workflow_client
      end

      # Build a worker with project configuration
      def worker(project_dir = Dir.pwd)
        configuration(project_dir).build_worker
      end

      # Start a workflow
      def start_workflow(workflow_class, input, project_dir: Dir.pwd, **options)
        client = workflow_client(project_dir)
        client.start_workflow(workflow_class, input, options)
      end

      # Execute a workflow synchronously
      def execute_workflow(workflow_class, input, project_dir: Dir.pwd, **options)
        client = workflow_client(project_dir)
        client.execute_workflow(workflow_class, input, options)
      end

      # Get workflow status
      def workflow_status(workflow_id, project_dir: Dir.pwd)
        client = workflow_client(project_dir)
        handle = client.get_workflow(workflow_id)
        handle.describe
      end

      # Signal a workflow
      def signal_workflow(workflow_id, signal_name, *args, project_dir: Dir.pwd)
        client = workflow_client(project_dir)
        client.signal_workflow(workflow_id, signal_name, *args)
      end

      # Cancel a workflow
      def cancel_workflow(workflow_id, project_dir: Dir.pwd)
        client = workflow_client(project_dir)
        client.cancel_workflow(workflow_id)
      end

      # Reset configuration cache (useful for testing)
      def reset!
        @configurations = {}
      end
    end
  end
end

# Require components in dependency order
require_relative "temporal/configuration"
require_relative "temporal/connection"
require_relative "temporal/worker"
require_relative "temporal/workflow_client"

# Require workflows
require_relative "temporal/workflows/base_workflow"
require_relative "temporal/workflows/issue_to_pr_workflow"
require_relative "temporal/workflows/work_loop_workflow"
require_relative "temporal/workflows/sub_issue_workflow"

# Require activities
require_relative "temporal/activities/base_activity"
require_relative "temporal/activities/run_agent_activity"
require_relative "temporal/activities/run_tests_activity"
require_relative "temporal/activities/analyze_issue_activity"
require_relative "temporal/activities/create_plan_activity"
require_relative "temporal/activities/create_prompt_activity"
require_relative "temporal/activities/diagnose_failure_activity"
require_relative "temporal/activities/prepare_next_iteration_activity"
require_relative "temporal/activities/record_checkpoint_activity"
require_relative "temporal/activities/create_pr_activity"
require_relative "temporal/activities/run_work_loop_iteration_activity"
require_relative "temporal/activities/analyze_sub_task_activity"
