# frozen_string_literal: true

require "async"
require "async/job/processor/generic"
require "securerandom"
require_relative "../storage/file_manager"

module Aidp
  module Jobs
    # Simple harness job using async-job gem only
    class HarnessJob
      # Default settings for harness jobs
      RETRY_INTERVAL = 60.0 # 1 minute between retries
      MAXIMUM_RETRY_COUNT = 2 # Fewer retries for harness jobs

      attr_reader :id, :status, :harness_context, :project_dir, :job_type, :start_time, :end_time, :result, :error

      def initialize(harness_context:, **args)
        @id = SecureRandom.uuid
        @status = :pending
        @harness_context = harness_context
        @project_dir = harness_context[:project_dir]
        @harness_runner_id = harness_context[:harness_runner_id]
        @job_type = harness_context[:job_type] || :harness_step
        @start_time = nil
        @end_time = nil
        @result = nil
        @error = nil
        @retry_count = 0
        @file_manager = Aidp::Storage::FileManager.new(File.join(@project_dir, ".aidp"))
      end

      # Execute the job using async-job
      def perform
        @status = :running
        @start_time = Time.now

        log_harness_info("Starting harness job: #{self.class.name}")
        log_harness_info("Project: #{@project_dir}")
        log_harness_info("Job type: #{@job_type}")

        begin
          # Execute the job
          @result = execute_harness_job
          @status = :completed
          @end_time = Time.now

          duration = @end_time - @start_time
          log_harness_info("Harness job completed in #{format_duration(duration)}")

          @result
        rescue => error
          @error = error
          @status = :failed
          @end_time = Time.now

          log_harness_error("Harness job failed: #{error.message}")

          # Simple retry logic
          if @retry_count < MAXIMUM_RETRY_COUNT
            @retry_count += 1
            @status = :retrying
            log_harness_info("Retrying job (attempt #{@retry_count}/#{MAXIMUM_RETRY_COUNT})")

            # Schedule retry using async-job
            Async do |task|
              task.sleep(RETRY_INTERVAL)
              perform
            end
          else
            @status = :failed
            log_harness_error("Job failed after #{MAXIMUM_RETRY_COUNT} retries")
            raise error
          end
        end
      end

      # Enqueue the job using async-job
      def enqueue
        # Create a simple delegate for async-job
        delegate = HarnessJobDelegate.new(self)
        @processor = Async::Job::Processor::Generic.new(delegate)
        @processor.start
        self
      end

      # Stop the job processor
      def stop
        @processor&.stop
      end

      # Log with harness context
      def log_harness_info(message, metadata = {})
        log_info("[HARNESS] #{message}")

        # Add harness metadata
        harness_metadata = {
          project_dir: @project_dir,
          job_type: @job_type,
          harness_runner_id: @harness_runner_id,
          job_id: @id,
          attempt: @retry_count + 1
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
          job_id: @id,
          attempt: @retry_count + 1
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
          job_id: @id,
          attempt: @retry_count + 1
        }.merge(metadata)

        # Store in job logs if available
        store_harness_log("warning", message, harness_metadata)
      end

      # Get job progress information
      def get_job_progress
        {
          job_id: @id,
          status: :running,
          start_time: @job_start_time,
          current_time: Time.now,
          duration: Time.now - @job_start_time,
          attempt: @retry_count + 1,
          harness_context: {
            project_dir: @project_dir,
            job_type: @job_type
          }
        }
      end

      # Update job progress (override in subclasses)
      def update_job_progress(progress_data)
        log_harness_info("Job progress update", progress_data)

        # Store progress in JSON file storage
        begin
          storage = Aidp::Analyze::JsonFileStorage.new
          progress_entry = {
            job_id: @id,
            progress_data: progress_data,
            updated_at: Time.now.iso8601
          }

          # Store in harness progress directory
          storage.store_data("harness_progress/#{@id}", progress_entry)
        rescue => e
          # Storage not available - continue
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
          job_id: @id,
          job_class: self.class.name,
          status: :completed,
          start_time: @job_start_time,
          end_time: Time.now,
          duration: Time.now - @job_start_time,
          attempt: @retry_count + 1,
          harness_context: {
            project_dir: @project_dir,
            job_type: @job_type
          }
        }
      end

      protected

      # Override in subclasses to implement job logic
      def execute_harness_job(**args)
        raise NotImplementedError, "#{self.class} must implement #execute_harness_job"
      end

      # Store harness-specific log entry
      def store_harness_log(level, message, metadata)
        # Use file-based storage for harness logs

        log_entry = {
          job_id: @id,
          level: level,
          message: message,
          metadata: metadata,
          created_at: Time.now.iso8601
        }

        # Store in harness logs directory
        @file_manager.store_json("harness_logs/#{@id}", log_entry)
      rescue => e
        # Storage not available - continue
        puts "Could not store harness log: #{e.message}" if ENV["AIDP_DEBUG"]
      end

      private

      def log_warning(message)
        puts "⚠️  [#{self.class.name}] #{message}"
      end
    end

    # Simple delegate for async-job integration
    class HarnessJobDelegate
      def initialize(harness_job)
        @harness_job = harness_job
        @running = false
      end

      def start
        @running = true
        puts "Harness job delegate started"
      end

      def stop
        @running = false
        puts "Harness job delegate stopped"
      end

      def call(job)
        return unless @running
        puts "Executing harness job: #{@harness_job.id}"
        @harness_job.perform
      end
    end
  end
end
