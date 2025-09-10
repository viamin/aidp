# frozen_string_literal: true

require_relative "base_job"

module Aidp
  module Jobs
    # Base job class for harness workflows
    class HarnessJob < BaseJob
      # Default settings for harness jobs
      self.retry_interval = 60.0 # 1 minute between retries
      self.maximum_retry_count = 2 # Fewer retries for harness jobs

      def run(harness_context:, **args)
        @harness_context = harness_context
        @job_start_time = Time.now

        # Extract harness information
        @project_dir = harness_context[:project_dir]
        @harness_runner_id = harness_context[:harness_runner_id]
        @job_type = harness_context[:job_type] || :harness_step

        # Log job start
        log_info("Starting harness job: #{self.class.name}")
        log_info("Project: #{@project_dir}")
        log_info("Job type: #{@job_type}")

        # Execute the job
        result = execute_harness_job(**args)

        # Log completion
        duration = Time.now - @job_start_time
        log_info("Harness job completed in #{format_duration(duration)}")

        result
      rescue => error
        # Log error with harness context
        log_error("Harness job failed: #{error.message}")
        log_error("Project: #{@project_dir}")
        log_error("Job type: #{@job_type}")

        # Re-raise to trigger retry mechanism
        raise
      end

      protected

      # Override in subclasses to implement job logic
      def execute_harness_job(**args)
        raise NotImplementedError, "#{self.class} must implement #execute_harness_job"
      end

      # Get harness context
      def harness_context
        @harness_context
      end

      # Get project directory
      def project_dir
        @project_dir
      end

      # Get job type
      def job_type
        @job_type
      end

      # Log with harness context
      def log_harness_info(message, metadata = {})
        log_info("[HARNESS] #{message}")

        # Add harness metadata
        harness_metadata = {
          project_dir: @project_dir,
          job_type: @job_type,
          harness_runner_id: @harness_runner_id,
          job_id: que_attrs[:job_id],
          attempt: que_attrs[:error_count] + 1
        }.merge(metadata)

        # Store in job logs if available
        store_harness_log("info", message, harness_metadata)
      end

      def log_harness_error(message, metadata = {})
        log_error("[HARNESS] #{message}")

        # Add harness metadata
        harness_metadata = {
          project_dir: @project_dir,
          job_type: @job_type,
          harness_runner_id: @harness_runner_id,
          job_id: que_attrs[:job_id],
          attempt: que_attrs[:error_count] + 1
        }.merge(metadata)

        # Store in job logs if available
        store_harness_log("error", message, harness_metadata)
      end

      def log_harness_warning(message, metadata = {})
        log_warning("[HARNESS] #{message}")

        # Add harness metadata
        harness_metadata = {
          project_dir: @project_dir,
          job_type: @job_type,
          harness_runner_id: @harness_runner_id,
          job_id: que_attrs[:job_id],
          attempt: que_attrs[:error_count] + 1
        }.merge(metadata)

        # Store in job logs if available
        store_harness_log("warning", message, harness_metadata)
      end

      # Store harness-specific log entry
      def store_harness_log(level, message, metadata)
        # Try to store in database if available
        begin
          require_relative "../database_connection"

          Aidp::DatabaseConnection.connection.exec_params(
            <<~SQL,
              INSERT INTO harness_job_logs (
                job_id, level, message, metadata, created_at
              )
              VALUES ($1, $2, $3, $4, $5)
            SQL
            [
              que_attrs[:job_id],
              level,
              message,
              metadata.to_json,
              Time.now
            ]
          )
        rescue => e
          # Database not available or table doesn't exist - continue
          log_info("Could not store harness log: #{e.message}") if ENV["AIDP_DEBUG"]
        end
      end

      # Get job progress (override in subclasses)
      def get_job_progress
        {
          job_id: que_attrs[:job_id],
          job_class: self.class.name,
          status: :running,
          start_time: @job_start_time,
          current_time: Time.now,
          duration: Time.now - @job_start_time,
          attempt: que_attrs[:error_count] + 1,
          harness_context: {
            project_dir: @project_dir,
            job_type: @job_type
          }
        }
      end

      # Update job progress (override in subclasses)
      def update_job_progress(progress_data)
        log_harness_info("Job progress update", progress_data)

        # Store progress in database if available
        begin
          require_relative "../database_connection"

          Aidp::DatabaseConnection.connection.exec_params(
            <<~SQL,
              INSERT INTO harness_job_progress (
                job_id, progress_data, updated_at
              )
              VALUES ($1, $2, $3)
              ON CONFLICT (job_id)
              DO UPDATE SET
                progress_data = EXCLUDED.progress_data,
                updated_at = EXCLUDED.updated_at
            SQL
            [
              que_attrs[:job_id],
              progress_data.to_json,
              Time.now
            ]
          )
        rescue => e
          # Database not available or table doesn't exist - continue
          log_info("Could not store job progress: #{e.message}") if ENV["AIDP_DEBUG"]
        end
      end

      # Check if job should continue (override in subclasses)
      def should_continue?
        # Check if harness is still running
        return true unless @harness_runner_id

        # In a real implementation, this would check with the harness runner
        # For now, we'll assume the job should continue
        true
      end

      # Handle job cancellation
      def handle_cancellation
        log_harness_warning("Job cancellation requested")

        # Override in subclasses to handle cleanup
        cleanup_on_cancellation
      end

      # Cleanup on cancellation (override in subclasses)
      def cleanup_on_cancellation
        log_harness_info("Performing cleanup on cancellation")
        # Default implementation - override in subclasses
      end

      # Format duration for logging
      def format_duration(seconds)
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

      # Get job result summary
      def get_job_result_summary
        {
          job_id: que_attrs[:job_id],
          job_class: self.class.name,
          status: :completed,
          start_time: @job_start_time,
          end_time: Time.now,
          duration: Time.now - @job_start_time,
          attempt: que_attrs[:error_count] + 1,
          harness_context: {
            project_dir: @project_dir,
            job_type: @job_type
          }
        }
      end

      private

      def log_warning(message)
        Que.logger.warn "[#{self.class.name}] #{message}"
      end
    end
  end
end
