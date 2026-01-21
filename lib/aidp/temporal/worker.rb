# frozen_string_literal: true

require "temporalio/worker"
require_relative "connection"

module Aidp
  module Temporal
    # Temporal worker that runs workflows and activities
    # Manages the worker lifecycle and task queue configuration
    class Worker
      DEFAULT_TASK_QUEUE = "aidp-workflows"
      DEFAULT_MAX_CONCURRENT_ACTIVITIES = 10
      DEFAULT_MAX_CONCURRENT_WORKFLOWS = 10

      attr_reader :task_queue, :config, :connection

      def initialize(connection:, config: {})
        @connection = connection
        @config = normalize_config(config)
        @task_queue = @config[:task_queue]
        @worker = nil
        @running = false
        @shutdown_requested = false
      end

      # Register workflow classes
      def register_workflows(*workflow_classes)
        @workflow_classes ||= []
        @workflow_classes.concat(workflow_classes)
        self
      end

      # Register activity classes or instances
      def register_activities(*activity_classes)
        @activity_classes ||= []
        @activity_classes.concat(activity_classes)
        self
      end

      # Start the worker (blocking)
      def run
        return if @running

        Aidp.log_info("temporal_worker", "starting",
          task_queue: @task_queue,
          workflows: @workflow_classes&.map(&:name),
          activities: @activity_classes&.map { |a| a.is_a?(Class) ? a.name : a.class.name })

        @running = true
        @shutdown_requested = false

        begin
          @worker = create_worker
          @worker.run
        rescue => e
          Aidp.log_error("temporal_worker", "run_failed",
            error: e.message,
            error_class: e.class.name)
          raise
        ensure
          @running = false
          @worker = nil
        end
      end

      # Request graceful shutdown
      def shutdown
        return unless @running

        Aidp.log_info("temporal_worker", "shutdown_requested", task_queue: @task_queue)
        @shutdown_requested = true
        @worker&.shutdown
      end

      # Check if running
      def running?
        @running
      end

      # Check if shutdown was requested
      def shutdown_requested?
        @shutdown_requested
      end

      private

      def normalize_config(config)
        {
          task_queue: config[:task_queue] || config["task_queue"] || ENV["TEMPORAL_TASK_QUEUE"] || DEFAULT_TASK_QUEUE,
          max_concurrent_activities: config[:max_concurrent_activities] || config["max_concurrent_activities"] || DEFAULT_MAX_CONCURRENT_ACTIVITIES,
          max_concurrent_workflows: config[:max_concurrent_workflows] || config["max_concurrent_workflows"] || DEFAULT_MAX_CONCURRENT_WORKFLOWS
        }
      end

      def create_worker
        client = @connection.connect

        worker_options = {
          client: client,
          task_queue: @task_queue
        }

        # Add workflows if registered
        worker_options[:workflows] = @workflow_classes if @workflow_classes&.any?

        # Add activities if registered
        if @activity_classes&.any?
          worker_options[:activities] = @activity_classes
        end

        # Add tuning options
        worker_options[:max_concurrent_activity_task_polls] = @config[:max_concurrent_activities]
        worker_options[:max_concurrent_workflow_task_polls] = @config[:max_concurrent_workflows]

        Temporalio::Worker.new(**worker_options)
      end
    end
  end
end
