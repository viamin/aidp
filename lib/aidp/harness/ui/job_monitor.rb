# frozen_string_literal: true

require "tty-prompt"
require "pastel"
require_relative "base"
require_relative "status_manager"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Real-time job monitoring and status tracking
      class JobMonitor < Base
        class JobMonitorError < StandardError; end

        class JobNotFoundError < JobMonitorError; end

        class MonitorError < JobMonitorError; end

        JOB_STATUSES = {
          pending: "Pending",
          running: "Running",
          completed: "Completed",
          failed: "Failed",
          cancelled: "Cancelled",
          retrying: "Retrying"
        }.freeze

        JOB_PRIORITIES = {
          low: "Low",
          normal: "Normal",
          high: "High",
          urgent: "Urgent"
        }.freeze

        def initialize(ui_components = {}, prompt: TTY::Prompt.new)
          super()
          @prompt = prompt
          @pastel = Pastel.new
          @status_manager = ui_components[:status_manager] || StatusManager.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || JobMonitorFormatter.new

          @jobs = {}
          @job_history = []
          @monitoring_active = false
          @monitor_thread = nil
          @monitor_mutex = Mutex.new
          @update_callbacks = []
        end

        def register_job(job_id, job_data)
          validate_job_id(job_id)
          validate_job_data(job_data)

          @monitor_mutex.synchronize do
            job = create_job_entry(job_id, job_data)
            @jobs[job_id] = job
            record_job_event(job_id, :registered, job_data)
            notify_callbacks(:job_registered, job)
          end
        rescue => e
          raise MonitorError, "Failed to register job: #{e.message}"
        end

        def update_job_status(job_id, status, additional_data = {})
          validate_job_id(job_id)
          validate_job_status(status)

          @monitor_mutex.synchronize do
            job = @jobs[job_id]
            raise JobNotFoundError, "Job not found: #{job_id}" unless job

            old_status = job[:status]
            job[:status] = status
            job[:last_updated] = Time.now
            job.merge!(additional_data)

            record_job_event(job_id, :status_changed, {from: old_status, to: status})
            notify_callbacks(:job_status_changed, job, old_status)
          end
        rescue JobNotFoundError => e
          raise e
        rescue => e
          raise MonitorError, "Failed to update job status: #{e.message}"
        end

        def job_status(job_id)
          validate_job_id(job_id)

          @monitor_mutex.synchronize do
            job = @jobs[job_id]
            raise JobNotFoundError, "Job not found: #{job_id}" unless job
            job.dup
          end
        end

        def has_job?(job_id)
          validate_job_id(job_id)
          @monitor_mutex.synchronize { @jobs.key?(job_id) }
        end

        def all_jobs
          @monitor_mutex.synchronize { @jobs.dup }
        end

        def jobs_by_status(status)
          validate_job_status(status)

          @monitor_mutex.synchronize do
            @jobs.select { |_, job| job[:status] == status }
          end
        rescue JobMonitorError => e
          raise MonitorError, "Failed to get jobs by status: #{e.message}"
        end

        def jobs_by_priority(priority)
          validate_job_priority(priority)

          @monitor_mutex.synchronize do
            @jobs.select { |_, job| job[:priority] == priority }
          end
        end

        def start_monitoring(interval_seconds = 1.0)
          return if @monitoring_active

          @monitoring_active = true
          @monitor_thread = Thread.new do
            monitoring_loop(interval_seconds)
          end

          @prompt.say(@formatter.format_monitoring_started(interval_seconds))
        rescue => e
          raise MonitorError, "Failed to start monitoring: #{e.message}"
        end

        def stop_monitoring
          return unless @monitoring_active

          @monitoring_active = false
          @monitor_thread&.join
          @monitor_thread = nil

          @prompt.say(@formatter.format_monitoring_stopped)
        rescue => e
          raise MonitorError, "Failed to stop monitoring: #{e.message}"
        end

        def monitoring_active?
          @monitoring_active
        end

        def add_update_callback(callback)
          validate_callback(callback)
          @update_callbacks << callback
        rescue JobMonitorError => e
          raise MonitorError, "Failed to add update callback: #{e.message}"
        end

        def remove_update_callback(callback)
          @update_callbacks.delete(callback)
        end

        def monitoring_summary
          @monitor_mutex.synchronize do
            {
              total_jobs: @jobs.size,
              jobs_by_status: @jobs.values.map { |job| job[:status] }.tally,
              jobs_by_priority: @jobs.values.map { |job| job[:priority] }.tally,
              monitoring_active: @monitoring_active,
              total_events: @job_history.size,
              last_update: @job_history.last&.dig(:timestamp)
            }
          end
        end

        def display_job_status(job_id)
          job = job_status(job_id)
          @frame_manager.section("Job Status: #{job_id}") do
            display_job_details(job)
          end
        end

        def display_all_jobs
          @frame_manager.section("All Jobs") do
            display_jobs_table(@jobs)
          end
        end

        def display_jobs_by_status(status)
          jobs = jobs_by_status(status)
          @frame_manager.section("Jobs with Status: #{status}") do
            display_jobs_table(jobs)
          end
        end

        private

        def validate_job_id(job_id)
          raise JobMonitorError, "Job ID cannot be empty" if job_id.to_s.strip.empty?
        end

        def validate_job_data(job_data)
          raise JobMonitorError, "Job data must be a hash" unless job_data.is_a?(Hash)
        end

        def validate_job_status(status)
          unless JOB_STATUSES.key?(status)
            raise JobMonitorError, "Invalid job status: #{status}. Must be one of: #{JOB_STATUSES.keys.join(", ")}"
          end
        end

        def validate_job_priority(priority)
          unless JOB_PRIORITIES.key?(priority)
            raise JobMonitorError, "Invalid job priority: #{priority}. Must be one of: #{JOB_PRIORITIES.keys.join(", ")}"
          end
        end

        def validate_callback(callback)
          unless callback.respond_to?(:call)
            raise JobMonitorError, "Callback must respond to :call"
          end
        end

        def create_job_entry(job_id, job_data)
          {
            id: job_id,
            status: job_data[:status] || :pending,
            priority: job_data[:priority] || :normal,
            created_at: Time.now,
            last_updated: Time.now,
            progress: job_data[:progress] || 0,
            total_steps: job_data[:total_steps] || 1,
            current_step: job_data[:current_step] || 0,
            error_message: job_data[:error_message],
            retry_count: job_data[:retry_count] || 0,
            max_retries: job_data[:max_retries] || 3,
            estimated_completion: job_data[:estimated_completion],
            metadata: job_data[:metadata] || {}
          }
        end

        def record_job_event(job_id, event_type, event_data)
          event = {
            job_id: job_id,
            event_type: event_type,
            timestamp: Time.now,
            data: event_data
          }

          @job_history << event
        end

        def notify_callbacks(event_type, job, additional_data = nil)
          @update_callbacks.each do |callback|
            callback.call(event_type, job, additional_data)
          rescue => e
            @prompt.say(@formatter.format_callback_error(callback, e.message))
          end
        end

        def monitoring_loop(interval_seconds)
          # ACCEPTABLE: Job monitoring loop for periodic status checks
          # Using sleep is fine here for periodic monitoring with @monitoring_active flag for cancellation
          # See: docs/CONCURRENCY_PATTERNS.md - Category E: Periodic/Interval-Based
          loop do
            break unless @monitoring_active

            begin
              perform_monitoring_cycle
              sleep(interval_seconds)
            rescue => e
              @prompt.say(@formatter.format_monitoring_error(e.message))
            end
          end
        end

        def perform_monitoring_cycle
          # Perform monitoring tasks like checking for stuck jobs, updating progress, etc.
          check_for_stuck_jobs
          update_job_progress
          cleanup_completed_jobs
        end

        def check_for_stuck_jobs
          stuck_threshold = 300 # 5 minutes
          current_time = Time.now

          @jobs.each do |job_id, job|
            if job[:status] == :running && (current_time - job[:last_updated]) > stuck_threshold
              update_job_status(job_id, :failed, {error_message: "Job appears to be stuck"})
            end
          end
        end

        def update_job_progress
          # Update progress for running jobs
          @jobs.each do |job_id, job|
            if job[:status] == :running && job[:current_step] < job[:total_steps]
              # Simulate progress update - in real implementation, this would come from the job
              new_progress = [(job[:current_step] + 1).to_f / job[:total_steps] * 100, 100].min
              update_job_status(job_id, :running, {progress: new_progress})
            end
          end
        end

        def cleanup_completed_jobs
          # Clean up old completed jobs
          cleanup_threshold = 3600 # 1 hour
          current_time = Time.now

          jobs_to_remove = @jobs.select do |job_id, job|
            (job[:status] == :completed || job[:status] == :failed) &&
              (current_time - job[:last_updated]) > cleanup_threshold
          end

          jobs_to_remove.each do |job_id, _|
            @jobs.delete(job_id)
            record_job_event(job_id, :cleaned_up, {reason: "Old completed job"})
          end
        end

        def display_job_details(job)
          details = []
          details << "Job ID: #{job[:id]}"
          details << "Status: #{@formatter.format_job_status(job[:status])}"
          details << "Priority: #{@formatter.format_job_priority(job[:priority])}"
          details << "Progress: #{@formatter.format_job_progress(job[:progress])}"
          details << "Created: #{job[:created_at]}"
          details << "Last Updated: #{job[:last_updated]}"

          if job[:error_message]
            details << "Error: #{@formatter.format_job_error(job[:error_message])}"
          end

          if job[:retry_count] > 0
            details << "Retries: #{job[:retry_count]}/#{job[:max_retries]}"
          end

          details.join("\n")
        end

        def display_jobs_table(jobs)
          if jobs.empty?
            return "No jobs found."
          end

          lines = []
          lines << "ID".ljust(20) + "Status".ljust(12) + "Priority".ljust(10) + "Progress".ljust(10) + "Created"
          lines << "-" * 70

          jobs.each do |job_id, job|
            status = @formatter.format_job_status_short(job[:status])
            priority = @formatter.format_job_priority_short(job[:priority])
            progress = @formatter.format_job_progress_short(job[:progress])
            created = job[:created_at].strftime("%H:%M:%S")

            lines << job_id.to_s.ljust(20) + status.to_s.ljust(12) + priority.to_s.ljust(10) + progress.to_s.ljust(10) + created.to_s
          end

          lines.join("\n")
        end
      end

      # Formats job monitor display
      class JobMonitorFormatter
        def initialize
          @pastel = Pastel.new
        end

        def format_job_status(status)
          case status
          when :pending
            @pastel.yellow("⏳ Pending")
          when :running
            @pastel.blue("🔄 Running")
          when :completed
            @pastel.green("✅ Completed")
          when :failed
            @pastel.red("❌ Failed")
          when :cancelled
            @pastel.red("🚫 Cancelled")
          when :retrying
            @pastel.yellow("🔄 Retrying")
          else
            @pastel.blue("❓ #{status.to_s.capitalize}")
          end
        end

        def format_job_status_short(status)
          case status
          when :pending
            @pastel.yellow("⏳")
          when :running
            @pastel.blue("🔄")
          when :completed
            @pastel.green("✅")
          when :failed
            @pastel.red("❌")
          when :cancelled
            @pastel.red("🚫")
          when :retrying
            @pastel.yellow("🔄")
          else
            @pastel.blue("❓")
          end
        end

        def format_job_priority(priority)
          case priority
          when :low
            @pastel.blue("🔽 Low")
          when :normal
            @pastel.blue("➡️ Normal")
          when :high
            @pastel.yellow("🔼 High")
          when :urgent
            @pastel.red("🚨 Urgent")
          else
            @pastel.blue("❓ #{priority.to_s.capitalize}")
          end
        end

        def format_job_priority_short(priority)
          case priority
          when :low
            @pastel.blue("🔽")
          when :normal
            @pastel.blue("➡️")
          when :high
            @pastel.yellow("🔼")
          when :urgent
            @pastel.red("🚨")
          else
            @pastel.blue("❓")
          end
        end

        def format_job_progress(progress)
          progress_int = progress.to_i
          if progress_int >= 100
            @pastel.green("100%")
          elsif progress_int >= 75
            @pastel.blue("#{progress_int}%")
          elsif progress_int >= 50
            @pastel.yellow("#{progress_int}%")
          else
            @pastel.blue("#{progress_int}%")
          end
        end

        def format_job_progress_short(progress)
          progress_int = progress.to_i
          if progress_int >= 100
            @pastel.green("100%")
          elsif progress_int >= 75
            @pastel.blue("#{progress_int}%")
          elsif progress_int >= 50
            @pastel.yellow("#{progress_int}%")
          else
            @pastel.blue("#{progress_int}%")
          end
        end

        def format_job_error(error_message)
          @pastel.red("❌ #{error_message}")
        end

        def format_monitoring_started(interval_seconds)
          @pastel.green("✅ Job monitoring started (interval: #{interval_seconds}s)")
        end

        def format_monitoring_stopped
          @pastel.red("❌ Job monitoring stopped")
        end

        def format_monitoring_error(error_message)
          @pastel.red("❌ Monitoring error: #{error_message}")
        end

        def format_callback_error(callback, error_message)
          @pastel.red("❌ Callback error: #{error_message}")
        end

        def format_monitoring_summary(summary)
          result = []
          result << @pastel.bold(@pastel.blue("📊 Job Monitoring Summary"))
          result << "Total jobs: #{@pastel.bold(summary[:total_jobs])}"
          result << "Monitoring: #{summary[:monitoring_active] ? "Active" : "Inactive"}"
          result << "Total events: #{@pastel.blue(summary[:total_events])}"

          if summary[:jobs_by_status].any?
            result << "Jobs by status:"
            summary[:jobs_by_status].each do |status, count|
              result << "  #{@pastel.blue("#{status}: #{count}")}"
            end
          end

          result.join("\n")
        end
      end
    end
  end
end
