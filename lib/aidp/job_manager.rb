# frozen_string_literal: true

module Aidp
  class JobManager
    def initialize(project_dir)
      @project_dir = project_dir
    end

    def create_job(job_class, args = {})
      # Create a new job and return job ID
      # This is a placeholder implementation
      job_id = rand(1000..9999)

      # Store job metadata for testing
      @jobs ||= {}
      @jobs[job_id] = {
        id: job_id,
        job_class: job_class,
        args: args,
        status: "queued",
        created_at: Time.now
      }

      job_id
    end

    def get_job(job_id)
      @jobs ||= {}
      @jobs[job_id]
    end

    def update_job_status(job_id, status, error: nil)
      @jobs ||= {}
      return unless @jobs[job_id]

      @jobs[job_id][:status] = status
      @jobs[job_id][:error] = error if error
      @jobs[job_id][:updated_at] = Time.now
    end
  end
end
