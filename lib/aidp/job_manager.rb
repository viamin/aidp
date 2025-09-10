# frozen_string_literal: true

module Aidp
  class JobManager
    def initialize(project_dir, harness_runner = nil)
      @project_dir = project_dir
      @harness_runner = harness_runner
      @jobs ||= {}
      @harness_job_manager = nil
    end

    def create_job(job_class, args = {})
      # Check if this is a harness job
      if harness_job?(job_class)
        return create_harness_job(job_class, args)
      end

      # Create a regular job
      job_id = rand(1000..9999)

      # Store job metadata
      @jobs[job_id] = {
        id: job_id,
        job_class: job_class,
        args: args,
        status: "queued",
        created_at: Time.now,
        harness_context: nil
      }

      job_id
    end

    def get_job(job_id)
      # Check harness jobs first
      if @harness_job_manager
        harness_job = @harness_job_manager.get_harness_job(job_id)
        return harness_job if harness_job
      end

      # Check regular jobs
      @jobs ||= {}
      @jobs[job_id]
    end

    def update_job_status(job_id, status, error: nil)
      # Check if this is a harness job
      if @harness_job_manager && @harness_job_manager.get_harness_job(job_id)
        @harness_job_manager.update_job_status(job_id, status, error: error)
        return
      end

      # Update regular job
      @jobs ||= {}
      return unless @jobs[job_id]

      @jobs[job_id][:status] = status
      @jobs[job_id][:error] = error if error
      @jobs[job_id][:updated_at] = Time.now
    end

    # Harness integration methods

    def set_harness_runner(harness_runner)
      @harness_runner = harness_runner
      @harness_job_manager = Aidp::Harness::JobManager.new(@project_dir, harness_runner)
    end

    attr_reader :harness_job_manager

    def get_all_jobs
      jobs = []

      # Add regular jobs
      jobs.concat(@jobs.values) if @jobs

      # Add harness jobs
      if @harness_job_manager
        jobs.concat(@harness_job_manager.get_harness_jobs)
      end

      jobs
    end

    def get_jobs_by_status(status)
      get_all_jobs.select { |job| job[:status] == status }
    end

    def get_running_jobs
      get_jobs_by_status(:running)
    end

    def get_failed_jobs
      get_jobs_by_status(:failed)
    end

    def get_completed_jobs
      get_jobs_by_status(:completed)
    end

    def retry_job(job_id)
      # Check if this is a harness job
      if @harness_job_manager && @harness_job_manager.get_harness_job(job_id)
        return @harness_job_manager.retry_job(job_id)
      end

      # Retry regular job (placeholder implementation)
      job = @jobs[job_id]
      return false unless job && job[:status] == "failed"

      job[:status] = "queued"
      job[:updated_at] = Time.now
      job[:error] = nil
      true
    end

    def cancel_job(job_id)
      # Check if this is a harness job
      if @harness_job_manager && @harness_job_manager.get_harness_job(job_id)
        return @harness_job_manager.cancel_job(job_id)
      end

      # Cancel regular job (placeholder implementation)
      job = @jobs[job_id]
      return false unless job

      job[:status] = "cancelled"
      job[:updated_at] = Time.now
      true
    end

    def get_job_summary
      all_jobs = get_all_jobs

      {
        total_jobs: all_jobs.size,
        by_status: {
          queued: get_jobs_by_status(:queued).size,
          running: get_jobs_by_status(:running).size,
          completed: get_jobs_by_status(:completed).size,
          failed: get_jobs_by_status(:failed).size,
          cancelled: get_jobs_by_status(:cancelled).size
        },
        harness_jobs: @harness_job_manager ? @harness_job_manager.get_harness_job_summary : nil
      }
    end

    def log_message(job_id, _execution_id, message, level, metadata = {})
      # Log to harness job manager if available
      if @harness_job_manager
        @harness_job_manager.log_job_message(job_id, message, level, metadata)
      end

      # Also log to regular job if it exists
      job = @jobs[job_id] if @jobs
      if job
        job[:logs] ||= []
        job[:logs] << {
          timestamp: Time.now,
          level: level,
          message: message,
          metadata: metadata
        }
      end
    end

    private

    def harness_job?(job_class)
      # Check if the job class is a harness job
      job_class.name.include?("Harness") ||
        job_class.ancestors.include?(Aidp::Jobs::HarnessJob)
    rescue
      false
    end

    def create_harness_job(job_class, args)
      return nil unless @harness_job_manager

      @harness_job_manager.create_harness_job(job_class, args)
    end
  end
end
