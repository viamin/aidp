# frozen_string_literal: true

module Aidp
  # Adapter for orchestration execution
  # Routes to Temporal-based or legacy orchestration based on configuration
  #
  # When Temporal is enabled:
  # - Workflows execute through Temporal for durability and observability
  # - Activities wrap existing AIDP functionality
  # - State is persisted in Temporal's history
  #
  # When Temporal is disabled (legacy mode):
  # - Falls back to existing AsyncWorkLoopRunner and BackgroundRunner
  # - State is tracked in file-based storage
  #
  # Migration strategy:
  # 1. Enable Temporal in aidp.yml
  # 2. Start Temporal worker: `aidp temporal worker`
  # 3. Use `aidp temporal start` for new workflows
  # 4. Existing jobs continue until complete
  class OrchestrationAdapter
    include Aidp::MessageDisplay

    def initialize(project_dir: Dir.pwd)
      @project_dir = project_dir
    end

    # Check if Temporal orchestration is enabled
    def temporal_enabled?
      return @temporal_enabled if defined?(@temporal_enabled)

      begin
        require_relative "temporal"
        @temporal_enabled = Aidp::Temporal.enabled?(@project_dir)
      rescue LoadError
        @temporal_enabled = false
      end

      @temporal_enabled
    end

    # Start an issue-to-PR workflow
    # Routes to Temporal or legacy based on configuration
    def start_issue_workflow(issue_number, options = {})
      if temporal_enabled?
        start_temporal_issue_workflow(issue_number, options)
      else
        start_legacy_issue_workflow(issue_number, options)
      end
    end

    # Start a work loop
    # Routes to Temporal or legacy based on configuration
    def start_work_loop(step_name, step_spec, context = {}, options = {})
      if temporal_enabled?
        start_temporal_work_loop(step_name, step_spec, context, options)
      else
        start_legacy_work_loop(step_name, step_spec, context, options)
      end
    end

    # Get workflow status
    def workflow_status(workflow_id)
      if temporal_enabled?
        temporal_workflow_status(workflow_id)
      else
        legacy_job_status(workflow_id)
      end
    end

    # Cancel a workflow
    def cancel_workflow(workflow_id)
      if temporal_enabled?
        cancel_temporal_workflow(workflow_id)
      else
        cancel_legacy_job(workflow_id)
      end
    end

    # List active workflows
    def list_workflows
      if temporal_enabled?
        list_temporal_workflows
      else
        list_legacy_jobs
      end
    end

    private

    # Temporal-based implementations
    def start_temporal_issue_workflow(issue_number, options)
      Aidp.log_info("orchestration_adapter", "starting_temporal_issue_workflow",
        issue_number: issue_number)

      input = {
        project_dir: @project_dir,
        issue_number: issue_number.to_i,
        max_iterations: options[:max_iterations] || 50,
        options: options
      }

      handle = Aidp::Temporal.start_workflow(
        Aidp::Temporal::Workflows::IssueToPrWorkflow,
        input,
        project_dir: @project_dir,
        **extract_temporal_options(options)
      )

      {
        type: :temporal,
        workflow_id: handle.id,
        issue_number: issue_number,
        status: "started"
      }
    end

    def start_temporal_work_loop(step_name, step_spec, context, options)
      Aidp.log_info("orchestration_adapter", "starting_temporal_work_loop",
        step_name: step_name)

      input = {
        project_dir: @project_dir,
        step_name: step_name,
        step_spec: step_spec,
        context: context,
        max_iterations: options[:max_iterations] || 50
      }

      handle = Aidp::Temporal.start_workflow(
        Aidp::Temporal::Workflows::WorkLoopWorkflow,
        input,
        project_dir: @project_dir,
        **extract_temporal_options(options)
      )

      {
        type: :temporal,
        workflow_id: handle.id,
        step_name: step_name,
        status: "started"
      }
    end

    def temporal_workflow_status(workflow_id)
      desc = Aidp::Temporal.workflow_status(workflow_id, project_dir: @project_dir)

      {
        type: :temporal,
        workflow_id: workflow_id,
        status: desc.status.to_s,
        workflow_type: desc.workflow_type,
        start_time: desc.start_time,
        close_time: desc.close_time
      }
    rescue Temporalio::Error::WorkflowNotFoundError
      {type: :temporal, workflow_id: workflow_id, status: "not_found"}
    end

    def cancel_temporal_workflow(workflow_id)
      Aidp::Temporal.cancel_workflow(workflow_id, project_dir: @project_dir)
      {type: :temporal, workflow_id: workflow_id, status: "canceled"}
    end

    def list_temporal_workflows
      client = Aidp::Temporal.workflow_client(@project_dir)
      workflows = client.list_workflows

      workflows.map do |wf|
        {
          type: :temporal,
          workflow_id: wf.id,
          workflow_type: wf.workflow_type,
          status: wf.status.to_s,
          start_time: wf.start_time
        }
      end
    rescue => e
      Aidp.log_error("orchestration_adapter", "list_temporal_failed", error: e.message)
      []
    end

    def extract_temporal_options(options)
      temporal_opts = {}
      temporal_opts[:workflow_id] = options[:workflow_id] if options[:workflow_id]
      temporal_opts[:task_queue] = options[:task_queue] if options[:task_queue]
      temporal_opts
    end

    # Legacy implementations
    def start_legacy_issue_workflow(issue_number, options)
      Aidp.log_info("orchestration_adapter", "starting_legacy_issue_workflow",
        issue_number: issue_number)

      require_relative "jobs/background_runner"

      runner = Aidp::Jobs::BackgroundRunner.new(@project_dir)
      job_id = runner.start(:execute, options.merge(issue_number: issue_number))

      {
        type: :legacy,
        job_id: job_id,
        issue_number: issue_number,
        status: "started"
      }
    end

    def start_legacy_work_loop(step_name, step_spec, context, options)
      Aidp.log_info("orchestration_adapter", "starting_legacy_work_loop",
        step_name: step_name)

      require_relative "jobs/background_runner"

      runner = Aidp::Jobs::BackgroundRunner.new(@project_dir)
      job_id = runner.start(:execute, options.merge(
        step_name: step_name,
        step_spec: step_spec,
        context: context
      ))

      {
        type: :legacy,
        job_id: job_id,
        step_name: step_name,
        status: "started"
      }
    end

    def legacy_job_status(job_id)
      require_relative "jobs/background_runner"

      runner = Aidp::Jobs::BackgroundRunner.new(@project_dir)
      status = runner.job_status(job_id)

      return {type: :legacy, job_id: job_id, status: "not_found"} unless status

      {
        type: :legacy,
        job_id: job_id,
        status: status[:status],
        running: status[:running],
        started_at: status[:started_at],
        completed_at: status[:completed_at]
      }
    end

    def cancel_legacy_job(job_id)
      require_relative "jobs/background_runner"

      runner = Aidp::Jobs::BackgroundRunner.new(@project_dir)
      result = runner.stop_job(job_id)

      {
        type: :legacy,
        job_id: job_id,
        status: result[:success] ? "canceled" : "failed",
        message: result[:message]
      }
    end

    def list_legacy_jobs
      require_relative "jobs/background_runner"

      runner = Aidp::Jobs::BackgroundRunner.new(@project_dir)
      runner.list_jobs.map do |job|
        {
          type: :legacy,
          job_id: job[:job_id],
          status: job[:status],
          started_at: job[:started_at]
        }
      end
    end
  end
end
