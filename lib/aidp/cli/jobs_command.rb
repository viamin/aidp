# frozen_string_literal: true

require "tty-prompt"
require "tty-box"
require "pastel"
require "io/console"
require "json"
require_relative "terminal_io"
require_relative "../storage/file_manager"
require_relative "../jobs/background_runner"

module Aidp
  class CLI
    class JobsCommand
      include Aidp::MessageDisplay

      def initialize(input: nil, output: nil, prompt: TTY::Prompt.new, file_manager: nil, background_runner: nil)
        @io = TerminalIO.new(input: input, output: output)
        @prompt = prompt
        @pastel = Pastel.new
        @running = true
        @view_mode = :list
        @selected_job_id = nil
        @jobs_displayed = false # Track if we've displayed jobs in interactive mode
        @file_manager = file_manager || Aidp::Storage::FileManager.new(File.join(Dir.pwd, ".aidp"))
        @background_runner = background_runner || Aidp::Jobs::BackgroundRunner.new(Dir.pwd)
        @screen_width = 80 # Default screen width
      end

      private

      public

      def run(subcommand = nil, args = [])
        case subcommand
        when "list", nil
          list_jobs
        when "status"
          job_id = args.shift
          if job_id
            show_job_status(job_id, follow: args.include?("--follow"))
          else
            display_message("Usage: aidp jobs status <job_id> [--follow]", type: :error)
          end
        when "stop"
          job_id = args.shift
          if job_id
            stop_job(job_id)
          else
            display_message("Usage: aidp jobs stop <job_id>", type: :error)
          end
        when "logs"
          job_id = args.shift
          if job_id
            show_job_logs(job_id, tail: args.include?("--tail"), follow: args.include?("--follow"))
          else
            display_message("Usage: aidp jobs logs <job_id> [--tail] [--follow]", type: :error)
          end
        else
          display_message("Unknown jobs subcommand: #{subcommand}", type: :error)
          display_message("Available: list, status, stop, logs", type: :info)
        end
      end

      def list_jobs
        jobs = @background_runner.list_jobs

        if jobs.empty?
          display_message("Background Jobs", type: :info)
          display_message("-" * @screen_width, type: :muted)
          display_message("")
          display_message("No background jobs found", type: :info)
          display_message("")
          display_message("Start a background job with:", type: :info)
          display_message("  aidp execute --background", type: :info)
          display_message("  aidp analyze --background", type: :info)
          return
        end

        render_background_jobs(jobs)
      end

      def show_job_status(job_id, follow: false)
        if follow
          follow_job_status(job_id)
        else
          status = @background_runner.job_status(job_id)
          unless status
            display_message("Job not found: #{job_id}", type: :error)
            return
          end

          render_job_status(status)
        end
      end

      def stop_job(job_id)
        result = @background_runner.stop_job(job_id)

        if result[:success]
          display_message("✓ #{result[:message]}", type: :success)
        else
          display_message("✗ #{result[:message]}", type: :error)
        end
      end

      def show_job_logs(job_id, tail: false, follow: false)
        if follow
          display_message("Following logs for job #{job_id} (Ctrl+C to exit)...", type: :info)
          @background_runner.follow_job_logs(job_id)
        else
          logs = @background_runner.job_logs(job_id, tail: tail, lines: 50)
          unless logs
            display_message("No logs found for job: #{job_id}", type: :error)
            return
          end

          display_message("Logs for job #{job_id}:", type: :info)
          display_message("-" * @screen_width, type: :muted)
          puts logs
        end
      end

      private

      def render_background_jobs(jobs)
        require "tty-table"

        display_message("Background Jobs", type: :info)
        display_message("=" * @screen_width, type: :muted)
        display_message("")

        headers = ["Job ID", "Mode", "Status", "Started", "Duration"]
        rows = jobs.map do |job|
          [
            job[:job_id][0..15] + "...",
            job[:mode].to_s.capitalize,
            format_job_status(job[:status]),
            format_time(job[:started_at]),
            format_duration_from_start(job[:started_at], job[:completed_at])
          ]
        end

        table = TTY::Table.new(headers, rows)
        puts table.render(:basic)

        display_message("")
        display_message("Commands:", type: :info)
        display_message("  aidp jobs status <job_id>        - Show detailed status", type: :info)
        display_message("  aidp jobs logs <job_id> --tail   - Show recent logs", type: :info)
        display_message("  aidp jobs stop <job_id>          - Stop a running job", type: :info)
      end

      def render_job_status(status)
        display_message("Job Status: #{status[:job_id]}", type: :info)
        display_message("=" * @screen_width, type: :muted)
        display_message("")
        display_message("Mode:       #{status[:mode]}", type: :info)
        display_message("Status:     #{format_job_status(status[:status])}", type: :info)
        display_message("PID:        #{status[:pid] || "N/A"}", type: :info)
        display_message("Running:    #{status[:running] ? "Yes" : "No"}", type: :info)
        display_message("Started:    #{format_time(status[:started_at])}", type: :info)

        if status[:completed_at]
          display_message("Completed:  #{format_time(status[:completed_at])}", type: :info)
          display_message("Duration:   #{format_duration_from_start(status[:started_at], status[:completed_at])}", type: :info)
        end

        if status[:checkpoint]
          display_message("", type: :info)
          display_message("Latest Checkpoint:", type: :info)
          cp = status[:checkpoint]
          display_message("  Step:       #{cp[:step_name]}", type: :info)
          display_message("  Iteration:  #{cp[:iteration]}", type: :info)
          display_message("  Updated:    #{format_checkpoint_age(cp[:timestamp])}", type: :info)

          if cp[:metrics]
            display_message("  Metrics:", type: :info)
            display_message("    LOC:      #{cp[:metrics][:lines_of_code]}", type: :info)
            display_message("    Coverage: #{cp[:metrics][:test_coverage]}%", type: :info)
            display_message("    Quality:  #{cp[:metrics][:code_quality]}%", type: :info)
          end
        end

        display_message("", type: :info)
        display_message("Log file: #{status[:log_file]}", type: :muted)
      end

      def follow_job_status(job_id)
        display_message("Following job status for #{job_id} (Ctrl+C to exit)...", type: :info)
        display_message("")

        begin
          loop do
            # Clear screen
            print "\e[2J\e[H"

            status = @background_runner.job_status(job_id)
            unless status
              display_message("Job not found: #{job_id}", type: :error)
              break
            end

            render_job_status(status)

            # Exit if job is done
            break unless status[:running]

            # Periodic status polling - acceptable for UI updates
            # Alternative: event-driven updates via IPC/file watching
            sleep 2
          end
        rescue Interrupt
          display_message("\nStopped following job status", type: :info)
        end
      end

      def format_job_status(status)
        case status.to_s
        when "running"
          @pastel.green("● Running")
        when "completed"
          @pastel.cyan("✓ Completed")
        when "failed"
          @pastel.red("✗ Failed")
        when "stopped"
          @pastel.yellow("⏹ Stopped")
        when "stuck"
          @pastel.magenta("⚠ Stuck")
        else
          @pastel.dim(status.to_s)
        end
      end

      def format_time(time)
        return "N/A" unless time

        begin
          time = Time.parse(time.to_s) if time.is_a?(String)
          time.strftime("%Y-%m-%d %H:%M:%S")
        rescue
          time.to_s
        end
      end

      def format_duration_from_start(started_at, completed_at)
        return "N/A" unless started_at

        start_time = started_at.is_a?(String) ? Time.parse(started_at) : started_at
        end_time = if completed_at
          completed_at.is_a?(String) ? Time.parse(completed_at) : completed_at
        else
          Time.now
        end

        duration = end_time - start_time
        format_duration(duration)
      end

      def format_duration(seconds)
        return "0s" if seconds.nil? || seconds <= 0

        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        secs = (seconds % 60).to_i

        parts = []
        parts << "#{hours}h" if hours > 0
        parts << "#{minutes}m" if minutes > 0
        parts << "#{secs}s" if secs > 0 || parts.empty?

        parts.join(" ")
      end

      def format_checkpoint_age(timestamp)
        return "N/A" unless timestamp

        time = Time.parse(timestamp.to_s)
        age = Time.now - time

        if age < 60
          "#{age.to_i}s ago"
        elsif age < 3600
          "#{(age / 60).to_i}m ago"
        else
          "#{(age / 3600).to_i}h ago"
        end
      end

      # Fetch harness jobs from file-based storage
      def fetch_harness_jobs
        jobs = []

        # Get all harness log files
        harness_logs_dir = File.join(Dir.pwd, ".aidp", "harness_logs")
        return jobs unless Dir.exist?(harness_logs_dir)

        Dir.glob(File.join(harness_logs_dir, "*.json")).each do |log_file|
          log_data = JSON.parse(File.read(log_file))
          job_id = File.basename(log_file, ".json")

          # Get job metadata from the log
          job_info = {
            id: job_id,
            status: determine_job_status(log_data),
            created_at: log_data["created_at"],
            message: log_data["message"],
            level: log_data["level"],
            metadata: log_data["metadata"] || {}
          }

          jobs << job_info
        rescue JSON::ParserError => e
          display_message("Warning: Could not parse harness log #{log_file}: #{e.message}", type: :warning) if ENV["AIDP_DEBUG"]
        end

        # Sort by creation time (newest first)
        jobs.sort_by { |job| job[:created_at] }.reverse
      end

      # Determine job status from log data
      def determine_job_status(log_data)
        case log_data["level"]
        when "error"
          "failed"
        when "info"
          if log_data["message"].include?("completed")
            "completed"
          elsif log_data["message"].include?("retrying")
            "retrying"
          else
            "running"
          end
        else
          "unknown"
        end
      end

      # Render harness jobs in a simple table
      def render_harness_jobs(jobs)
        display_message("Harness Jobs", type: :info)
        display_message("-" * @screen_width, type: :muted)
        display_message("")

        # Create job content for TTY::Box
        job_content = []
        jobs.each do |job|
          status_icon = case job[:status]
          when "completed" then "✅"
          when "running" then "🔄"
          when "failed" then "❌"
          when "pending" then "⏳"
          else "❓"
          end

          job_info = []
          job_info << "#{status_icon} #{job[:id][0..7]}"
          job_info << "Status: #{@pastel.bold(job[:status])}"
          job_info << "Created: #{format_time(job[:created_at])}"
          job_info << "Message: #{truncate_message(job[:message])}"
          job_content << job_info.join("\n")
        end

        # Create main box with all jobs
        box = TTY::Box.frame(
          job_content.join("\n\n"),
          title: {top_left: "Background Jobs"},
          border: :thick,
          padding: [1, 2]
        )
        display_message(box)

        display_message("")
        display_message("Total: #{jobs.length} harness job(s)", type: :info)
        display_message("")
        display_message("Note: Harness jobs are stored as JSON files in .aidp/harness_logs/", type: :muted)
      end

      # Truncate message for table display
      def truncate_message(message)
        return "N/A" unless message

        max_length = @screen_width - 50 # Account for other columns
        if message.length > max_length
          "#{message[0..max_length - 4]}..."
        else
          message
        end
      end
    end
  end
end
