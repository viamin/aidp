# frozen_string_literal: true

require "securerandom"
require "yaml"
require "fileutils"
require_relative "../rescue_logging"

module Aidp
  module Jobs
    # Manages background execution of work loops
    # Runs harness in daemon process and tracks job metadata
    class BackgroundRunner
      include Aidp::MessageDisplay
      include Aidp::RescueLogging

      attr_reader :project_dir, :jobs_dir

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @jobs_dir = File.join(project_dir, ".aidp", "jobs")
        ensure_jobs_directory
      end

      # Start a background job
      # Returns job_id
      def start(mode, options = {})
        job_id = generate_job_id
        log_file = File.join(@jobs_dir, job_id, "output.log")
        pid_file = File.join(@jobs_dir, job_id, "job.pid")

        # Create job directory
        FileUtils.mkdir_p(File.dirname(log_file))

        # Fork and daemonize
        pid = fork do
          # Detach from parent process
          Process.daemon(true)

          # Redirect stdout/stderr to log file
          $stdout.reopen(log_file, "a")
          $stderr.reopen(log_file, "a")
          $stdout.sync = true
          $stderr.sync = true

          # Write PID file
          File.write(pid_file, Process.pid)

          begin
            # Run the harness
            puts "[#{Time.now}] Starting #{mode} mode in background"
            puts "[#{Time.now}] Job ID: #{job_id}"
            puts "[#{Time.now}] PID: #{Process.pid}"

            runner = Aidp::Harness::Runner.new(@project_dir, mode, options.merge(job_id: job_id))
            result = runner.run

            puts "[#{Time.now}] Job completed with status: #{result[:status]}"
            mark_job_completed(job_id, result)
          rescue => e
            log_rescue(e, component: "background_runner", action: "execute_job", fallback: "mark_failed", job_id: job_id, mode: mode)
            puts "[#{Time.now}] Job failed with error: #{e.message}"
            puts e.backtrace.join("\n")
            mark_job_failed(job_id, e)
          ensure
            # Clean up PID file
            File.delete(pid_file) if File.exist?(pid_file)
          end
        end

        # Wait for child to fork
        Process.detach(pid)
        sleep 0.1 # Give daemon time to write PID file

        # Save job metadata in parent process
        save_job_metadata(job_id, pid, mode, options)

        job_id
      end

      # List all jobs
      def list_jobs
        return [] unless Dir.exist?(@jobs_dir)

        Dir.glob(File.join(@jobs_dir, "*")).select { |d| File.directory?(d) }.map do |job_dir|
          job_id = File.basename(job_dir)
          load_job_metadata(job_id)
        end.compact.sort_by { |job| job[:started_at] || Time.now }.reverse
      end

      # Get job status
      def job_status(job_id)
        metadata = load_job_metadata(job_id)
        return nil unless metadata

        # Check if process is still running
        pid = metadata[:pid]
        running = pid && process_running?(pid)

        # Get checkpoint data
        checkpoint = get_job_checkpoint(job_id)

        {
          job_id: job_id,
          mode: metadata[:mode],
          status: determine_job_status(metadata, running, checkpoint),
          pid: pid,
          running: running,
          started_at: metadata[:started_at],
          completed_at: metadata[:completed_at],
          checkpoint: checkpoint,
          log_file: File.join(@jobs_dir, job_id, "output.log")
        }
      end

      # Stop a running job
      def stop_job(job_id)
        metadata = load_job_metadata(job_id)
        return {success: false, message: "Job not found"} unless metadata

        pid = metadata[:pid]
        unless pid && process_running?(pid)
          return {success: false, message: "Job is not running"}
        end

        begin
          # Send TERM signal
          Process.kill("TERM", pid)

          # Wait for process to terminate (max 10 seconds)
          10.times do
            sleep 0.5
            break unless process_running?(pid)
          end

          # Force kill if still running
          if process_running?(pid)
            Process.kill("KILL", pid)
          end

          mark_job_stopped(job_id)
          {success: true, message: "Job stopped successfully"}
        rescue Errno::ESRCH => e
          log_rescue(e, component: "background_runner", action: "stop_job", fallback: "mark_stopped", job_id: job_id, pid: pid, level: :info)
          # Process already dead
          mark_job_stopped(job_id)
          {success: true, message: "Job was already stopped"}
        rescue => e
          log_rescue(e, component: "background_runner", action: "stop_job", fallback: "error_result", job_id: job_id, pid: pid)
          {success: false, message: "Failed to stop job: #{e.message}"}
        end
      end

      # Get job logs
      def job_logs(job_id, options = {})
        log_file = File.join(@jobs_dir, job_id, "output.log")
        return nil unless File.exist?(log_file)

        if options[:tail]
          lines = options[:lines] || 50
          `tail -n #{lines} #{log_file}`
        else
          File.read(log_file)
        end
      end

      # Follow job logs in real-time
      def follow_job_logs(job_id)
        log_file = File.join(@jobs_dir, job_id, "output.log")
        return unless File.exist?(log_file)

        # Use tail -f to follow logs
        exec("tail", "-f", log_file)
      end

      private

      def ensure_jobs_directory
        FileUtils.mkdir_p(@jobs_dir) unless Dir.exist?(@jobs_dir)
      end

      def generate_job_id
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        random = SecureRandom.hex(4)
        "#{timestamp}_#{random}"
      end

      def save_job_metadata(job_id, pid, mode, options)
        metadata_file = File.join(@jobs_dir, job_id, "metadata.yml")

        metadata = {
          job_id: job_id,
          pid: pid,
          mode: mode,
          started_at: Time.now,
          status: "running",
          options: options.except(:prompt) # Don't save prompt object
        }

        File.write(metadata_file, metadata.to_yaml)
      end

      def load_job_metadata(job_id)
        metadata_file = File.join(@jobs_dir, job_id, "metadata.yml")
        return nil unless File.exist?(metadata_file)

        YAML.load_file(metadata_file)
      rescue
        nil
      end

      def update_job_metadata(job_id, updates)
        metadata = load_job_metadata(job_id)
        return unless metadata

        metadata.merge!(updates)
        metadata_file = File.join(@jobs_dir, job_id, "metadata.yml")
        File.write(metadata_file, metadata.to_yaml)
      end

      def mark_job_completed(job_id, result)
        update_job_metadata(job_id, {
          status: "completed",
          completed_at: Time.now,
          result: result
        })
      end

      def mark_job_failed(job_id, error)
        update_job_metadata(job_id, {
          status: "failed",
          completed_at: Time.now,
          error: {
            message: error.message,
            class: error.class.name,
            backtrace: error.backtrace&.first(10)
          }
        })
      end

      def mark_job_stopped(job_id)
        update_job_metadata(job_id, {
          status: "stopped",
          completed_at: Time.now
        })
      end

      def process_running?(pid)
        return false unless pid

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM => e
        log_rescue(e, component: "background_runner", action: "check_process_running", fallback: false, pid: pid, level: :debug)
        false
      end

      def get_job_checkpoint(job_id)
        # Try to load checkpoint from project directory
        checkpoint = Aidp::Execute::Checkpoint.new(@project_dir)
        checkpoint.latest_checkpoint
      rescue => e
        log_rescue(e, component: "background_runner", action: "get_job_checkpoint", fallback: nil, job_id: job_id)
        nil
      end

      def determine_job_status(metadata, running, checkpoint)
        return metadata[:status] if metadata[:status] && !%w[running].include?(metadata[:status])

        if running
          # Check if job appears stuck based on checkpoint
          if checkpoint && checkpoint[:timestamp]
            last_update = Time.parse(checkpoint[:timestamp])
            age = Time.now - last_update

            return "stuck" if age > 600 # No update in 10 minutes
            return "running"
          end
          "running"
        else
          metadata[:status] || "completed"
        end
      end
    end
  end
end
