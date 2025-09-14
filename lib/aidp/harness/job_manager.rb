# frozen_string_literal: true

# require "que" # Removed - using async instead
require "json"

module Aidp
  module Harness
    # Enhanced job manager for harness workflows
    class JobManager
      def initialize(project_dir, harness_runner = nil)
        @project_dir = project_dir
        @harness_runner = harness_runner
        @harness_jobs = {}
        @job_metrics = {
          total_jobs: 0,
          successful_jobs: 0,
          failed_jobs: 0,
          running_jobs: 0,
          queued_jobs: 0,
          total_duration: 0.0,
          average_duration: 0.0
        }
      end

      # Create a harness-aware job
      def create_harness_job(job_class, args = {}, options = {})
        job_id = generate_job_id

        # Add harness context to job arguments
        harness_args = (args || {}).merge(
          harness_context: {
            project_dir: @project_dir,
            harness_runner_id: @harness_runner&.object_id,
            created_at: Time.now,
            job_type: options[:job_type] || :harness_step
          }
        )

        # Create the job
        return nil unless job_class
        job = job_class.enqueue(**harness_args)

        # Track harness job metadata
        @harness_jobs[job_id] = {
          id: job_id,
          que_job_id: job,
          job_class: job_class.name,
          args: harness_args,
          status: :queued,
          created_at: Time.now,
          harness_context: harness_args[:harness_context],
          metrics: {
            start_time: nil,
            end_time: nil,
            duration: nil,
            retry_count: 0,
            error_messages: []
          }
        }

        # Update job metrics
        update_job_metrics(:queued)

        # Notify harness runner if available
        @harness_runner&.record_job_created(job_id, job_class.name, harness_args)

        job_id
      end

      # Get harness job information
      def get_harness_job(job_id)
        @harness_jobs[job_id]
      end

      # Update job status
      def update_job_status(job_id, status, error: nil, result: nil)
        job = @harness_jobs[job_id]
        return unless job

        old_status = job[:status]
        job[:status] = status
        job[:updated_at] = Time.now

        case status
        when :running
          job[:metrics][:start_time] = Time.now
          update_job_metrics(:running)
        when :completed
          job[:metrics][:end_time] = Time.now
          job[:metrics][:duration] = calculate_duration(job[:metrics])
          job[:result] = result
          update_job_metrics(:completed)
        when :failed
          job[:metrics][:end_time] = Time.now
          job[:metrics][:duration] = calculate_duration(job[:metrics])
          job[:metrics][:error_messages] << error if error
          job[:metrics][:retry_count] += 1
          update_job_metrics(:failed)
        when :retrying
          job[:metrics][:retry_count] += 1
          update_job_metrics(:retrying)
        end

        # Notify harness runner if available
        @harness_runner&.record_job_status_change(job_id, old_status, status, error, result)

        # Log status change
        log_job_status_change(job_id, old_status, status, error)
      end

      # Get all harness jobs
      def get_harness_jobs
        @harness_jobs.values
      end

      # Get jobs by status
      def get_jobs_by_status(status)
        @harness_jobs.values.select { |job| job[:status] == status }
      end

      # Get running jobs
      def get_running_jobs
        get_jobs_by_status(:running)
      end

      # Get failed jobs
      def get_failed_jobs
        get_jobs_by_status(:failed)
      end

      # Get completed jobs
      def get_completed_jobs
        get_jobs_by_status(:completed)
      end

      # Retry a failed job
      def retry_job(job_id)
        job = @harness_jobs[job_id]
        return false unless job && job[:status] == :failed

        # Reset job status
        job[:status] = :queued
        job[:updated_at] = Time.now
        job[:metrics][:start_time] = nil
        job[:metrics][:end_time] = nil
        job[:metrics][:duration] = nil

        # Re-enqueue the job
        begin
          job_class = Object.const_get(job[:job_class])
          new_que_job_id = job_class.enqueue(**job[:args])
          job[:que_job_id] = new_que_job_id

          update_job_metrics(:queued)

          @harness_runner&.record_job_retry(job_id, job[:metrics][:retry_count])

          true
        rescue => e
          job[:status] = :failed
          job[:metrics][:error_messages] << "Retry failed: #{e.message}"
          false
        end
      end

      # Cancel a job
      def cancel_job(job_id)
        job = @harness_jobs[job_id]
        return false unless job

        # Only allow canceling queued or running jobs
        return false unless [:queued, :running].include?(job[:status])

        old_status = job[:status]
        job[:status] = :cancelled
        job[:updated_at] = Time.now
        job[:metrics][:end_time] = Time.now

        # Try to cancel the queued job
        begin
          if job[:que_job_id]
            Que.execute(
              "UPDATE que_jobs SET finished_at = NOW(), last_error_message = 'Job cancelled by harness' WHERE id = $1",
              [job[:que_job_id]]
            )
          end
        rescue => e
          # Log error but continue
          log_job_error(job_id, "Failed to cancel queued job: #{e.message}")
        end

        update_job_metrics(:cancelled)

        @harness_runner&.record_job_cancelled(job_id, old_status)

        true
      end

      # Get job metrics
      def get_job_metrics
        @job_metrics.dup
      end

      # Get harness job summary
      def get_harness_job_summary
        {
          total_jobs: @harness_jobs.size,
          by_status: {
            queued: get_jobs_by_status(:queued).size,
            running: get_jobs_by_status(:running).size,
            completed: get_jobs_by_status(:completed).size,
            failed: get_jobs_by_status(:failed).size,
            cancelled: get_jobs_by_status(:cancelled).size,
            retrying: get_jobs_by_status(:retrying).size
          },
          metrics: @job_metrics,
          recent_jobs: get_recent_jobs(10)
        }
      end

      # Clean up old completed jobs
      def cleanup_old_jobs(max_age_hours = 24)
        cutoff_time = Time.now - (max_age_hours * 3600)

        jobs_to_remove = @harness_jobs.select do |_job_id, job|
          [:completed, :cancelled].include?(job[:status]) &&
            job[:updated_at] < cutoff_time
        end

        jobs_to_remove.each do |job_id, _job|
          @harness_jobs.delete(job_id)
        end

        jobs_to_remove.size
      end

      # Get jobs for a specific step
      def get_jobs_for_step(step_name)
        @harness_jobs.values.select do |job|
          job[:args][:step_name] == step_name
        end
      end

      # Check if any jobs are running for a step
      def step_has_running_jobs?(step_name)
        get_jobs_for_step(step_name).any? { |job| job[:status] == :running }
      end

      # Wait for all jobs to complete
      def wait_for_jobs_completion(timeout_seconds = 300)
        start_time = Time.now

        while Time.now - start_time < timeout_seconds
          running_jobs = get_running_jobs
          return true if running_jobs.empty?

          if ENV["RACK_ENV"] == "test" || defined?(RSpec)
            sleep(1)
          else
            Async::Task.current.sleep(1)
          end
        end

        false # Timeout reached
      end

      # Get job output/logs
      def get_job_output(job_id)
        job = @harness_jobs[job_id]
        return "" unless job

        output = []

        # Add job metadata
        output << "Job ID: #{job_id}"
        output << "Class: #{job[:job_class]}"
        output << "Status: #{job[:status]}"
        output << "Created: #{job[:created_at]}"

        if job[:metrics][:start_time]
          output << "Started: #{job[:metrics][:start_time]}"
        end

        if job[:metrics][:end_time]
          output << "Finished: #{job[:metrics][:end_time]}"
        end

        if job[:metrics][:duration]
          output << "Duration: #{format_duration(job[:metrics][:duration])}"
        end

        if job[:metrics][:retry_count] > 0
          output << "Retries: #{job[:metrics][:retry_count]}"
        end

        # Add error messages
        if job[:metrics][:error_messages].any?
          output << "Errors:"
          job[:metrics][:error_messages].each do |error|
            output << "  - #{error}"
          end
        end

        # Add result if available
        if job[:result]
          output << "Result: #{job[:result]}"
        end

        output.join("\n")
      end

      # Log message for a specific job
      def log_job_message(job_id, message, level = "info", metadata = {})
        job = @harness_jobs[job_id]
        return unless job

        log_entry = {
          timestamp: Time.now,
          level: level,
          message: message,
          metadata: metadata
        }

        job[:logs] ||= []
        job[:logs] << log_entry

        # Keep only last 100 log entries
        if job[:logs].size > 100
          job[:logs] = job[:logs].last(100)
        end

        # Also log to harness runner if available
        @harness_runner&.log_job_message(job_id, message, level, metadata)
      end

      private

      def generate_job_id
        "harness_#{Time.now.to_i}_#{rand(1000..9999)}"
      end

      def update_job_metrics(status)
        case status
        when :queued
          @job_metrics[:queued_jobs] += 1
        when :running
          @job_metrics[:running_jobs] += 1
          @job_metrics[:queued_jobs] -= 1
        when :completed
          @job_metrics[:successful_jobs] += 1
          @job_metrics[:running_jobs] -= 1
        when :failed
          @job_metrics[:failed_jobs] += 1
          @job_metrics[:running_jobs] -= 1
        when :cancelled
          @job_metrics[:running_jobs] -= 1
        end

        @job_metrics[:total_jobs] = @harness_jobs.size
      end

      def calculate_duration(metrics)
        return nil unless metrics[:start_time] && metrics[:end_time]
        metrics[:end_time] - metrics[:start_time]
      end

      def get_recent_jobs(count = 10)
        @harness_jobs.values
          .sort_by { |job| job[:created_at] }
          .reverse
          .first(count)
          .map do |job|
            {
              id: job[:id],
              job_class: job[:job_class],
              status: job[:status],
              created_at: job[:created_at],
              duration: job[:metrics][:duration]
            }
          end
      end

      def log_job_status_change(job_id, old_status, new_status, error)
        message = "Job #{job_id} status changed from #{old_status} to #{new_status}"
        message += " - Error: #{error}" if error

        log_job_message(job_id, message, "info", {
          old_status: old_status,
          new_status: new_status,
          error: error
        })
      end

      def log_job_error(job_id, error_message)
        log_job_message(job_id, error_message, "error", {
          error: error_message
        })
      end

      def format_duration(seconds)
        return "0s" unless seconds

        if seconds < 60
          "#{seconds.round(1)}s"
        elsif seconds < 3600
          minutes = (seconds / 60).to_i
          secs = (seconds % 60).to_i
          "#{minutes}m #{secs}s"
        else
          hours = (seconds / 3600).to_i
          minutes = ((seconds % 3600) / 60).to_i
          "#{hours}h #{minutes}m"
        end
      end
    end
  end
end
