# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"
require "tty-table"
require "io/console"
require "que"
require "json"
require_relative "terminal_io"

module Aidp
  class CLI
    class JobsCommand
      def initialize(input: $stdin, output: $stdout)
        @io = TerminalIO.new(input, output)
        @cursor = TTY::Cursor
        @screen_width = TTY::Screen.width
        @screen_height = TTY::Screen.height
        @running = true
        @view_mode = :list
        @selected_job_id = nil
        @jobs_displayed = false  # Track if we've displayed jobs in interactive mode
      end

      def run
        # Initialize Que connection
        setup_database_connection

        # Start the UI loop with timeout
        Timeout.timeout(60) do
          while @running
            case @view_mode
            when :list
              result = render_job_list
              if result == :exit
                # Exit immediately when no jobs are found
                break
              end
              handle_input
              sleep_for_refresh unless @running
            when :details
              render_job_details
              handle_input
              sleep_for_refresh unless @running
            when :output
              render_job_output
              handle_input
              sleep_for_refresh unless @running
            end
          end
        end
      rescue Timeout::Error
        @io.puts "Command timed out"
        @running = false
      ensure
        # Only clear screen and show cursor if we were in interactive mode
        # (i.e., if we had jobs to display and were in a real terminal)
        if @view_mode == :list && @jobs_displayed
          @io.print @cursor.clear_screen
          @io.print @cursor.show
        end
      end

      private

      def setup_database_connection
        # Skip database setup in test mode if we're mocking
        return if ENV["RACK_ENV"] == "test" && ENV["MOCK_DATABASE"] == "true"

        dbname = (ENV["RACK_ENV"] == "test") ? "aidp_test" : (ENV["AIDP_DB_NAME"] || "aidp")

        # Use Sequel for connection pooling with timeout
        Timeout.timeout(10) do
          Que.connection = Sequel.connect(
            adapter: "postgres",
            host: ENV["AIDP_DB_HOST"] || "localhost",
            port: ENV["AIDP_DB_PORT"] || 5432,
            database: dbname,
            user: ENV["AIDP_DB_USER"] || ENV["USER"],
            password: ENV["AIDP_DB_PASSWORD"],
            max_connections: 10,
            pool_timeout: 30
          )

          Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
        end
      rescue Timeout::Error
        @io.puts "Database connection timed out"
        raise
      end

      def render_job_list
        jobs = fetch_jobs

        if jobs.empty?
          # Don't clear screen when no jobs - just show the message
          @io.puts "Background Jobs"
          @io.puts "-" * @screen_width
          @io.puts
          @io.puts "No jobs are currently running"
          return :exit
        else
          # Clear screen and hide cursor only when we have jobs to display
          @io.print(@cursor.hide)
          @io.print(@cursor.clear_screen)
          @io.print(@cursor.move_to(0, 0))
          @jobs_displayed = true  # Mark that we've displayed jobs

          # Print header
          @io.puts "Background Jobs"
          @io.puts "-" * @screen_width
          @io.puts

          # Create table
          table = TTY::Table.new(
            header: ["ID", "Job", "Queue", "Status", "Runtime", "Error"],
            rows: jobs.map do |job|
              [
                job[:id].to_s,
                job[:job_class]&.split("::")&.last || "Unknown",
                job[:queue] || "default",
                job_status(job),
                format_runtime(job),
                truncate_error(job[:last_error_message])
              ]
            end
          )

          # Render table
          @io.puts table.render(:unicode, padding: [0, 1], width: @screen_width)
        end

        @io.puts
        @io.puts "Commands: (d)etails, (o)utput, (r)etry, (k)ill, (q)uit"
        :continue
      end

      def render_job_details
        return switch_to_list unless @selected_job_id

        job = fetch_job(@selected_job_id)
        return switch_to_list unless job

        # Clear screen and hide cursor
        @io.print(@cursor.hide)
        @io.print(@cursor.clear_screen)
        @io.print(@cursor.move_to(0, 0))

        # Print header
        @io.puts "Job Details - ID: #{@selected_job_id}"
        @io.puts "-" * @screen_width
        @io.puts

        # Print job details
        @io.puts "Class:      #{job[:job_class]}"
        @io.puts "Queue:      #{job[:queue]}"
        @io.puts "Status:     #{job_status(job)}"
        @io.puts "Runtime:    #{format_runtime(job)}"
        @io.puts "Started:    #{job[:run_at]}"
        @io.puts "Finished:   #{job[:finished_at]}"
        @io.puts "Attempts:   #{job[:error_count]}"
        @io.puts
        @io.puts "Error:" if job[:last_error_message]
        @io.puts job[:last_error_message] if job[:last_error_message]

        @io.puts
        @io.puts "Commands: (b)ack, (o)utput, (r)etry, (k)ill, (q)uit"
      end

      def render_job_output
        return switch_to_list unless @selected_job_id

        job = fetch_job(@selected_job_id)
        return switch_to_list unless job

        # Clear screen and hide cursor
        @io.print(@cursor.hide)
        @io.print(@cursor.clear_screen)
        @io.print(@cursor.move_to(0, 0))

        # Print header
        @io.puts "Job Output - ID: #{@selected_job_id}"
        @io.puts "-" * @screen_width
        @io.puts

        # Get job output
        output = get_job_output(@selected_job_id)

        if output.empty?
          @io.puts "No output available for this job."
          @io.puts
          @io.puts "This could mean:"
          @io.puts "- The job hasn't started yet"
          @io.puts "- The job is still running but hasn't produced output"
          @io.puts "- The job completed without output"
        else
          @io.puts "Recent Output:"
          @io.puts "-" * 20
          @io.puts output
        end

        @io.puts
        @io.puts "Commands: (b)ack, (r)efresh, (q)uit"
      end

      def handle_input
        if @io.ready?
          char = @io.getch
          return if char.nil? || char.empty?

          case char.downcase
          when "q"
            @running = false
          when "d"
            handle_details_command
          when "o"
            handle_output_command
          when "r"
            handle_retry_command
          when "k"
            handle_kill_command
          when "b"
            switch_to_list
          end
        end
      end

      def handle_details_command
        return unless @view_mode == :list

        @io.print "Enter job ID: "
        job_id = @io.gets.chomp
        if job_exists?(job_id)
          @selected_job_id = job_id
          @view_mode = :details
        end
      end

      def handle_output_command
        job_id = (@view_mode == :details) ? @selected_job_id : nil

        unless job_id
          @io.print "Enter job ID: "
          job_id = @io.gets.chomp
        end

        if job_exists?(job_id)
          @selected_job_id = job_id
          @view_mode = :output
        end
      end

      def handle_retry_command
        job_id = (@view_mode == :details) ? @selected_job_id : nil

        unless job_id
          @io.print "Enter job ID: "
          job_id = @io.gets.chomp
        end

        if job_exists?(job_id)
          job = fetch_job(job_id)
          if job[:error_count].to_i > 0
            Que.execute(
              <<~SQL,
                UPDATE que_jobs
                SET error_count = 0,
                    last_error_message = NULL,
                    finished_at = NULL,
                    expired_at = NULL
                WHERE id = $1
              SQL
              [job_id]
            )
            @io.puts "Job #{job_id} has been queued for retry"
          else
            @io.puts "Job #{job_id} has no errors to retry"
          end
          sleep 2
        end
      end

      def handle_kill_command
        job_id = (@view_mode == :details) ? @selected_job_id : nil

        unless job_id
          @io.print "Enter job ID: "
          job_id = @io.gets.chomp
        end

        if job_exists?(job_id)
          job = fetch_job(job_id)

          # Only allow killing running jobs
          if job_status(job) == "running"
            @io.print "Are you sure you want to kill job #{job_id}? (y/N): "
            confirmation = @io.gets.chomp.downcase

            if confirmation == "y" || confirmation == "yes"
              kill_job(job_id)
              @io.puts "Job #{job_id} has been killed"
              sleep 2
            else
              @io.puts "Job kill cancelled"
              sleep 1
            end
          else
            @io.puts "Only running jobs can be killed. Job #{job_id} is #{job_status(job)}"
            sleep 2
          end
        end
      end

      def switch_to_list
        @view_mode = :list
        @selected_job_id = nil
      end

      def fetch_jobs
        # For testing, return empty array if no database connection
        return [] if ENV["RACK_ENV"] == "test" && !Que.connection
        return [] if ENV["RACK_ENV"] == "test" && ENV["MOCK_DATABASE"] == "true"

        Timeout.timeout(10) do
          Que.execute(
            <<~SQL
              SELECT *
              FROM que_jobs
              ORDER BY
                CASE
                  WHEN finished_at IS NULL AND error_count = 0 THEN 1  -- Running
                  WHEN error_count > 0 THEN 2                          -- Failed
                  ELSE 3                                              -- Completed
                END,
                id DESC
            SQL
          )
        end
      rescue Timeout::Error
        @io.puts "Database query timed out"
        []
      rescue Sequel::DatabaseError => e
        @io.puts "Error fetching jobs: #{e.message}"
        []
      end

      def fetch_job(job_id)
        Timeout.timeout(5) do
          Que.execute("SELECT * FROM que_jobs WHERE id = $1", [job_id]).first
        end
      rescue Timeout::Error
        @io.puts "Database query timed out"
        nil
      rescue Sequel::DatabaseError => e
        @io.puts "Error fetching job #{job_id}: #{e.message}"
        nil
      end

      def job_exists?(job_id)
        fetch_job(job_id) != nil
      end

      def sleep_for_refresh
        sleep 1
      end

      def job_status(job)
        return "unknown" unless job

        if job[:finished_at]
          (job[:error_count].to_i > 0) ? "failed" : "completed"
        else
          "running"
        end
      end

      def format_runtime(job)
        return "unknown" unless job

        if job[:finished_at] && job[:run_at]
          finished_at = job[:finished_at].is_a?(Time) ? job[:finished_at] : Time.parse(job[:finished_at])
          run_at = job[:run_at].is_a?(Time) ? job[:run_at] : Time.parse(job[:run_at])
          duration = finished_at - run_at
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          (minutes > 0) ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        elsif job[:run_at]
          run_at = job[:run_at].is_a?(Time) ? job[:run_at] : Time.parse(job[:run_at])
          duration = Time.now - run_at
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          (minutes > 0) ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        else
          "pending"
        end
      end

      def truncate_error(error)
        return nil unless error

        max_length = @screen_width - 60 # Account for other columns
        if error.length > max_length
          "#{error[0..max_length - 4]}..."
        else
          error
        end
      end

      def get_job_output(job_id)
        # Try to get output from various sources
        output = []

        # 1. Check if there's a result stored in analysis_results table
        begin
          result = Que.execute(
            "SELECT data FROM analysis_results WHERE step_name = $1",
            ["job_#{job_id}"]
          ).first

          if result && result["data"]
            data = JSON.parse(result["data"])
            output << "Result: #{data["output"]}" if data["output"]
          end
        rescue Sequel::DatabaseError => e
          # Database error - table might not exist
          @io.puts "Warning: Could not fetch job result: #{e.message}" if ENV["AIDP_DEBUG"]
        rescue JSON::ParserError => e
          # JSON parse error
          @io.puts "Warning: Could not parse job result data: #{e.message}" if ENV["AIDP_DEBUG"]
        end

        # 2. Check for any recent log entries
        begin
          logs = Que.execute(
            "SELECT message FROM que_jobs WHERE id = $1 AND last_error_message IS NOT NULL",
            [job_id]
          ).first

          if logs && logs["last_error_message"]
            output << "Error: #{logs["last_error_message"]}"
          end
        rescue Sequel::DatabaseError => e
          # Database error fetching logs - continue with diagnostic
          @io.puts "Warning: Could not fetch job logs: #{e.message}" if ENV["AIDP_DEBUG"]
        end

        # 3. Check if job appears to be hung
        job = fetch_job(job_id)
        if job && job_status(job) == "running"
          run_at = job[:run_at].is_a?(Time) ? job[:run_at] : Time.parse(job[:run_at])
          duration = Time.now - run_at

          if duration > 300 # 5 minutes
            output << "⚠️  WARNING: Job has been running for #{format_duration(duration)}"
            output << "   This job may be hung or stuck."
          end
        end

        output.join("\n")
      end

      def kill_job(job_id)
        # Mark the job as finished with an error to stop it
        Que.execute(
          <<~SQL,
            UPDATE que_jobs
            SET finished_at = NOW(),
                last_error_message = 'Job killed by user',
                error_count = error_count + 1
            WHERE id = $1
          SQL
          [job_id]
        )
      end

      def format_duration(seconds)
        minutes = (seconds / 60).to_i
        hours = (minutes / 60).to_i
        minutes %= 60

        if hours > 0
          "#{hours}h #{minutes}m"
        else
          "#{minutes}m"
        end
      end
    end
  end
end
