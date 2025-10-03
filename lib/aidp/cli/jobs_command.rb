# frozen_string_literal: true

require "tty-prompt"
require "tty-box"
require "pastel"
require "io/console"
require "json"
require_relative "terminal_io"
require_relative "../storage/file_manager"

module Aidp
  class CLI
    class JobsCommand
      include Aidp::MessageDisplay

      def initialize(input: nil, output: nil, prompt: TTY::Prompt.new)
        @io = TerminalIO.new(input: input, output: output)
        @prompt = prompt
        @pastel = Pastel.new
        @running = true
        @view_mode = :list
        @selected_job_id = nil
        @jobs_displayed = false # Track if we've displayed jobs in interactive mode
        @file_manager = Aidp::Storage::FileManager.new(File.join(Dir.pwd, ".aidp"))
        @screen_width = 80 # Default screen width
      end

      private

      public

      def run
        # Simple harness jobs display
        jobs = fetch_harness_jobs

        if jobs.empty?
          display_message("Harness Jobs", type: :info)
          display_message("-" * @screen_width, type: :muted)
          display_message("")
          display_message("No harness jobs found", type: :info)
          display_message("")
          display_message("Harness jobs are background tasks that run during harness mode.", type: :info)
          display_message("They are stored as JSON files in the .aidp/harness_logs/ directory.", type: :info)
        else
          render_harness_jobs(jobs)
        end
      end

      private

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

      # Format timestamp for display
      def format_time(timestamp)
        return "unknown" unless timestamp

        begin
          time = Time.parse(timestamp)
          time.strftime("%Y-%m-%d %H:%M:%S")
        rescue
          timestamp
        end
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
