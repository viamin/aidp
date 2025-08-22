# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"
require "tty-table"
require "io/console"
require "que"

module Aidp
  class CLI
    class JobsCommand
      def initialize
        @cursor = TTY::Cursor
        @screen_width = TTY::Screen.width
        @screen_height = TTY::Screen.height
        @running = true
        @view_mode = :list
        @selected_job_id = nil
      end

      def run
        # Initialize Que connection
        Que.connection = PG.connect(
          host: ENV["AIDP_DB_HOST"] || "localhost",
          port: ENV["AIDP_DB_PORT"] || 5432,
          dbname: ENV["AIDP_DB_NAME"] || "aidp",
          user: ENV["AIDP_DB_USER"] || ENV["USER"],
          password: ENV["AIDP_DB_PASSWORD"]
        )
        Que.migrate!

        # Start the UI loop
        while @running
          case @view_mode
          when :list
            render_job_list
          when :details
            render_job_details
          end

          handle_input
          sleep 1 unless @running
        end
      ensure
        # Clear screen and show cursor
        print @cursor.clear_screen
        print @cursor.show
      end

      private

      def render_job_list
        jobs = fetch_jobs

        # Clear screen and hide cursor
        print @cursor.hide
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)

        # Print header
        puts "Background Jobs"
        puts "-" * @screen_width
        puts

        if jobs.empty?
          puts "No jobs are currently running"
        else
          # Create table
          table = TTY::Table.new(
            header: ["ID", "Job", "Queue", "Status", "Runtime", "Error"],
            rows: jobs.map do |job|
              [
                job["job_id"],
                job["job_class"].split("::").last,
                job["queue"],
                job_status(job),
                format_runtime(job),
                truncate_error(job["last_error_message"])
              ]
            end
          )

          # Render table
          puts table.render(:unicode, padding: [0, 1], width: @screen_width)
        end

        puts
        puts "Commands: (d)etails, (r)etry, (q)uit"
      end

      def render_job_details
        return switch_to_list unless @selected_job_id

        job = fetch_job(@selected_job_id)
        return switch_to_list unless job

        # Clear screen and hide cursor
        print @cursor.hide
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)

        # Print header
        puts "Job Details - ID: #{@selected_job_id}"
        puts "-" * @screen_width
        puts

        # Print job details
        puts "Class:      #{job["job_class"]}"
        puts "Queue:      #{job["queue"]}"
        puts "Status:     #{job_status(job)}"
        puts "Runtime:    #{format_runtime(job)}"
        puts "Created:    #{job["created_at"]}"
        puts "Started:    #{job["run_at"]}"
        puts "Finished:   #{job["finished_at"]}"
        puts "Attempts:   #{job["error_count"]}"
        puts
        puts "Error:" if job["last_error_message"]
        puts job["last_error_message"] if job["last_error_message"]

        puts
        puts "Commands: (b)ack, (r)etry, (q)uit"
      end

      def handle_input
        if $stdin.ready?
          case $stdin.getch.downcase
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

        print "Enter job ID: "
        job_id = gets.chomp
        if job_exists?(job_id)
          @selected_job_id = job_id
          @view_mode = :details
        end
      end

      def handle_retry_command
        job_id = @view_mode == :details ? @selected_job_id : nil

        unless job_id
          print "Enter job ID: "
          job_id = gets.chomp
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
              WHERE job_id = $1
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
              job_id DESC
          SQL
        )
      end

      def fetch_job(job_id)
        Que.execute("SELECT * FROM que_jobs WHERE job_id = $1", [job_id]).first
      end

      def job_exists?(job_id)
        fetch_job(job_id) != nil
      end

      def job_status(job)
        if job["finished_at"]
          job["error_count"].to_i > 0 ? "failed" : "completed"
        else
          "running"
        end
      end

      def format_runtime(job)
        if job["finished_at"]
          duration = Time.parse(job["finished_at"]) - Time.parse(job["run_at"])
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          minutes > 0 ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        elsif job["run_at"]
          duration = Time.now - Time.parse(job["run_at"])
          minutes = (duration / 60).to_i
          seconds = (duration % 60).to_i
          minutes > 0 ? "#{minutes}m #{seconds}s" : "#{seconds}s"
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
    end
  end
end
