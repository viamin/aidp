# frozen_string_literal: true

require_relative "connection"

module Aidp
  module Temporal
    # Client interface for starting and managing Temporal workflows
    # Wraps Temporal client operations with AIDP-specific conventions
    class WorkflowClient
      DEFAULT_WORKFLOW_TIMEOUT = 86400 # 24 hours in seconds
      DEFAULT_TASK_QUEUE = "aidp-workflows"

      attr_reader :connection

      def initialize(connection:)
        @connection = connection
      end

      # Start a workflow execution
      # Returns workflow handle for status tracking
      def start_workflow(workflow_class, input, options = {})
        client = @connection.connect
        workflow_id = options[:workflow_id] || generate_workflow_id(workflow_class)
        task_queue = options[:task_queue] || DEFAULT_TASK_QUEUE

        Aidp.log_info("workflow_client", "starting_workflow",
          workflow: workflow_class.name,
          workflow_id: workflow_id,
          task_queue: task_queue)

        handle = client.start_workflow(
          workflow_class,
          input,
          id: workflow_id,
          task_queue: task_queue,
          execution_timeout: options[:execution_timeout] || DEFAULT_WORKFLOW_TIMEOUT,
          **extract_temporal_options(options)
        )

        Aidp.log_debug("workflow_client", "workflow_started",
          workflow_id: workflow_id,
          run_id: handle.result_run_id)

        handle
      end

      # Execute a workflow synchronously (start and wait for result)
      def execute_workflow(workflow_class, input, options = {})
        handle = start_workflow(workflow_class, input, options)
        handle.result
      end

      # Get a workflow handle by ID
      def get_workflow(workflow_id, run_id: nil)
        client = @connection.connect
        client.workflow_handle(workflow_id, run_id: run_id)
      end

      # Query workflow state
      def query_workflow(workflow_id, query_name, *args)
        handle = get_workflow(workflow_id)
        handle.query(query_name, *args)
      end

      # Signal a running workflow
      def signal_workflow(workflow_id, signal_name, *args)
        handle = get_workflow(workflow_id)

        Aidp.log_debug("workflow_client", "signaling_workflow",
          workflow_id: workflow_id,
          signal: signal_name)

        handle.signal(signal_name, *args)
      end

      # Cancel a running workflow
      def cancel_workflow(workflow_id)
        handle = get_workflow(workflow_id)

        Aidp.log_info("workflow_client", "canceling_workflow",
          workflow_id: workflow_id)

        handle.cancel
      end

      # Terminate a workflow
      def terminate_workflow(workflow_id, reason: nil)
        handle = get_workflow(workflow_id)

        Aidp.log_info("workflow_client", "terminating_workflow",
          workflow_id: workflow_id,
          reason: reason)

        handle.terminate(reason: reason)
      end

      # Get workflow result (waits for completion)
      def get_workflow_result(workflow_id, timeout: nil)
        handle = get_workflow(workflow_id)

        if timeout
          # Use timeout for waiting
          Timeout.timeout(timeout) do
            handle.result
          end
        else
          handle.result
        end
      end

      # Check if workflow is running
      def workflow_running?(workflow_id)
        handle = get_workflow(workflow_id)
        desc = handle.describe
        desc.status == :running
      rescue Temporalio::Error::WorkflowNotFoundError
        false
      end

      # List workflows with optional filters
      def list_workflows(query: nil, page_size: 100)
        client = @connection.connect

        options = { page_size: page_size }
        options[:query] = query if query

        client.list_workflows(**options)
      end

      private

      def generate_workflow_id(workflow_class)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        random = SecureRandom.hex(4)
        workflow_name = workflow_class.name.split("::").last.gsub(/Workflow$/, "").downcase
        "#{workflow_name}_#{timestamp}_#{random}"
      end

      def extract_temporal_options(options)
        temporal_opts = {}

        # Timeout options
        temporal_opts[:run_timeout] = options[:run_timeout] if options[:run_timeout]
        temporal_opts[:task_timeout] = options[:task_timeout] if options[:task_timeout]

        # Retry policy
        if options[:retry_policy]
          temporal_opts[:retry_policy] = build_retry_policy(options[:retry_policy])
        end

        # Memo and search attributes
        temporal_opts[:memo] = options[:memo] if options[:memo]
        temporal_opts[:search_attributes] = options[:search_attributes] if options[:search_attributes]

        temporal_opts
      end

      def build_retry_policy(policy_config)
        Temporalio::RetryPolicy.new(
          initial_interval: policy_config[:initial_interval] || 1,
          backoff_coefficient: policy_config[:backoff_coefficient] || 2.0,
          maximum_interval: policy_config[:maximum_interval] || 60,
          maximum_attempts: policy_config[:maximum_attempts] || 3
        )
      end
    end
  end
end
