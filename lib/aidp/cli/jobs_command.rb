# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"
require "tty-table"
require "io/console"
require "que"
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
      end

      def run
        # Initialize Que connection
        setup_database_connection

        # Start the UI loop with timeout
        Timeout.timeout(60) do
          while @running
            case @view_mode
            when :list
              render_job_list
            when :details
              render_job_details
            end

            handle_input
            sleep_for_refresh unless @running
          end
        end
      rescue Timeout::Error
        @io.puts "Command timed out"
        @running = false
      ensure
        # Clear screen and show cursor
        @io.print @cursor.clear_screen
        @io.print @cursor.show
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
      rescue => e
        @io.puts "Error connecting to database: #{e.message}"
        raise
      end

      def render_job_list
        jobs = fetch_jobs

        # Clear screen and hide cursor
        @io.print(@cursor.hide)
        @io.print(@cursor.clear_screen)
        @io.print(@cursor.move_to(0, 0))

        # Print header
        @io.puts "Background Jobs"
        @io.puts "-" * @screen_width
        @io.puts

        if jobs.empty?
          @io.puts "No jobs are currently running"
        else
          # Create table
          table = TTY::Table.new(
            header: ["ID", "Job", "Queue", "Status", "Runtime", "Error"],
            rows: jobs.map do |job|
              [
                job["id"],
                job["job_class"]&.split("::")&.last || "Unknown",
                job["queue"] || "default",
                job_status(job),
                format_runtime(job),
                truncate_error(job["last_error_message"])
              ]
            end
          )

          # Render table
          @io.puts table.render(:unicode, padding: [0, 1], width: @screen_width)
        end

        @io.puts
        @io.puts "Commands: (d)etails, (r)etry, (q)uit"
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
        @io.puts "Class:      #{job["job_class"]}"
        @io.puts "Queue:      #{job["queue"]}"
        @io.puts "Status:     #{job_status(job)}"
        @io.puts "Runtime:    #{format_runtime(job)}"
        @io.puts "Created:    #{job["created_at"]}"
        @io.puts "Started:    #{job["run_at"]}"
        @io.puts "Finished:   #{job["finished_at"]}"
        @io.puts "Attempts:   #{job["error_count"]}"
        @io.puts
        @io.puts "Error:" if job["last_error_message"]
        @io.puts job["last_error_message"] if job["last_error_message"]

        @io.puts
        @io.puts "Commands: (b)ack, (r)etry, (q)uit"
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
          when "r"
            handle_retry_command
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

      def handle_retry_command
        job_id = (@view_mode == :details) ? @selected_job_id : nil

        unless job_id
          @io.print "Enter job ID: "
          job_id = @io.gets.chomp
        end

        if job_exists?(job_id)
          job = fetch_job(job_id)
          if job["error_count"].to_i > 0
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

        Timeout.timeout(1) do
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

        if job["finished_at"]
          (job["error_count"].to_i > 0) ? "failed" : "completed"
        else
          "running"
        end
      end

      def format_runtime(job)
        return "unknown" unless job

        if job["finished_at"] && job["run_at"]
          duration = Time.parse(job["finished_at"]) - Time.parse(job["run_at"])
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          (minutes > 0) ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        elsif job["run_at"]
          duration = Time.now - Time.parse(job["run_at"])
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          (minutes > 0) ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        else
          "pending"
        end
      rescue
        "error"
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
    end
  end
end
