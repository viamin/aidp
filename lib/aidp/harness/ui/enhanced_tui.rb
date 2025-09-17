# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"
require "tty-reader"
require "tty-box"
require "tty-table"
require "tty-progressbar"
require "tty-spinner"
require "tty-prompt"
require "pastel"

module Aidp
  module Harness
    module UI
      # Enhanced TUI system using TTY libraries, inspired by Claude Code and modern LLM agents
      class EnhancedTUI
        class TUIError < StandardError; end
        class InputError < TUIError; end
        class DisplayError < TUIError; end

        def initialize
          @cursor = TTY::Cursor
          @screen = TTY::Screen
          @reader = TTY::Reader.new
          @pastel = Pastel.new
          @prompt = TTY::Prompt.new

          @jobs = {}
          @jobs_visible = false
          @input_mode = false
          @input_prompt = ""
          @input_buffer = ""
          @input_position = 0
          @display_active = false
          @display_thread = nil

          setup_signal_handlers
        end

        # Smart display loop - only shows input overlay when needed
        def start_display_loop
          # Display loop is no longer needed since we use TTY::Prompt for input
          # Keep this method for compatibility but don't start the loop
          @display_active = true
        end

        def stop_display_loop
          @display_active = false
          @display_thread&.join
          restore_screen
        end

        def pause_display_loop
          @input_mode = false
        end

        def resume_display_loop
          @input_mode = true
        end

        # Job monitoring methods
        def add_job(job_id, job_data)
          @jobs[job_id] = {
            id: job_id,
            name: job_data[:name] || job_id,
            status: job_data[:status] || :pending,
            progress: job_data[:progress] || 0,
            started_at: Time.now,
            message: job_data[:message] || "",
            provider: job_data[:provider] || "unknown"
          }
          @jobs_visible = true
          add_message("🔄 Started job: #{@jobs[job_id][:name]}", :info)
        end

        def update_job(job_id, updates)
          return unless @jobs[job_id]

          old_status = @jobs[job_id][:status]
          @jobs[job_id].merge!(updates)
          @jobs[job_id][:updated_at] = Time.now

          # Show status change messages
          if old_status != @jobs[job_id][:status]
            case @jobs[job_id][:status]
            when :completed
              add_message("✅ Completed job: #{@jobs[job_id][:name]}", :success)
            when :failed
              add_message("❌ Failed job: #{@jobs[job_id][:name]}", :error)
            when :running
              add_message("🔄 Running job: #{@jobs[job_id][:name]}", :info)
            end
          end
        end

        def remove_job(job_id)
          job_name = @jobs[job_id]&.dig(:name)
          @jobs.delete(job_id)
          @jobs_visible = @jobs.any?
          add_message("🗑️ Removed job: #{job_name}", :info) if job_name
        end

        # Input methods using TTY
        def get_user_input(prompt = "💬 You: ")
          # Use TTY::Prompt for better input handling - no display loop needed
          @prompt.ask(prompt)
        rescue TTY::Reader::InputInterrupt
          # Clean exit without error trace
          puts "\n\n👋 Goodbye!"
          exit(0)
        end

        def get_confirmation(message, default: true)
          # Use TTY::Prompt for better input handling - no display loop needed
          @prompt.yes?(message)
        rescue TTY::Reader::InputInterrupt
          # Clean exit without error trace
          puts "\n\n👋 Goodbye!"
          exit(0)
        end

        # Single-select interface using TTY::Prompt (much better!)
        def single_select(title, items, default: 0)
          @prompt.select(title, items, default: default, cycle: true)
        rescue TTY::Reader::InputInterrupt
          # Clean exit without error trace
          puts "\n\n👋 Goodbye!"
          exit(0)
        end

        # Multiselect interface using TTY::Prompt (much better!)
        def multiselect(title, items, selected: [])
          @prompt.multi_select(title, items, default: selected)
        rescue TTY::Reader::InputInterrupt
          # Clean exit without error trace
          puts "\n\n👋 Goodbye!"
          exit(0)
        end

        # Display methods using TTY
        def show_message(message, type = :info)
          case type
          when :info
            puts @pastel.blue("ℹ") + " #{message}"
          when :success
            puts @pastel.green("✓") + " #{message}"
          when :warning
            puts @pastel.yellow("⚠") + " #{message}"
          when :error
            puts @pastel.red("✗") + " #{message}"
          else
            puts message
          end

          # Add to main content for history
          add_message(message, type)
        end

        def add_message(message, type = :info)
          # Just add to a simple message log - no recursion
          # This method is used by job monitoring, not for display
        end

        def show_progress(message, progress = 0)
          if progress > 0
            progress_bar = TTY::ProgressBar.new(
              "⏳ #{message} [:bar] :percent",
              total: 100,
              width: 40
            )
            progress_bar.current = progress
            progress_bar.render
          else
            # Use the unified spinner helper for indeterminate progress
            @current_spinner = TTY::Spinner.new("⏳ #{message} :spinner", format: :pulse)
            @current_spinner.start
          end
        end

        def hide_progress
          @current_spinner&.stop
          @current_spinner = nil
        end

        # Job display methods
        def show_jobs_dashboard
          return unless @jobs_visible && @jobs.any?

          # Create jobs table
          table = TTY::Table.new(header: ["Status", "Job", "Provider", "Elapsed", "Message"])

          @jobs.each do |job_id, job|
            status_icon = case job[:status]
            when :running then @pastel.green("●")
            when :completed then @pastel.blue("●")
            when :failed then @pastel.red("●")
            when :pending then @pastel.yellow("●")
            else @pastel.white("●")
            end

            elapsed = format_elapsed_time(Time.now - job[:started_at])
            status_text = "#{status_icon} #{job[:status].to_s.capitalize}"

            table << [
              status_text,
              job[:name],
              job[:provider],
              elapsed,
              job[:message]
            ]
          end

          # Display in a box
          box = TTY::Box.frame(
            width: 80,  # Fixed width instead of @screen.width
            height: @jobs.length + 3,
            title: {top_left: "🔄 Background Jobs"},
            border: {type: :thick}
          )

          puts box.render(table.render(:unicode, padding: [0, 1]))
        end

        # Enhanced workflow display
        def show_workflow_status(workflow_data)
          content = []
          content << "#{@pastel.bold("Type:")} #{workflow_data[:workflow_type]}"
          content << "#{@pastel.bold("Steps:")} #{workflow_data[:steps]&.length || 0} total"
          content << "#{@pastel.bold("Completed:")} #{workflow_data[:completed_steps] || 0}"
          content << "#{@pastel.bold("Current:")} #{workflow_data[:current_step] || "None"}"

          if workflow_data[:progress_percentage]
            progress_bar = TTY::ProgressBar.new(
              "#{@pastel.bold("Progress:")} [:bar] :percent%",
              total: 100,
              width: 30
            )
            progress_bar.current = workflow_data[:progress_percentage]
            content << progress_bar.render
          end

          box = TTY::Box.frame(
            content.join("\n"),
            title: {top_left: "📋 Workflow Status"},
            border: :thick,
            padding: [1, 2]
          )
          puts box
        end

        # Enhanced step execution display
        def show_step_execution(step_name, status, details = {})
          case status
          when :starting
            content = []
            content << @pastel.blue("Starting execution...")
            if details[:provider]
              content << @pastel.dim("Provider: #{details[:provider]}")
            end

            box = TTY::Box.frame(
              content.join("\n"),
              title: {top_left: "🚀 Executing Step: #{step_name}"},
              border: :thick,
              padding: [1, 2],
              style: {border: {fg: :blue}}
            )
            puts box

          when :running
            content = []
            content << @pastel.yellow("Step is running...")
            if details[:message]
              content << @pastel.dim(details[:message])
            end

            box = TTY::Box.frame(
              content.join("\n"),
              title: {top_left: "⏳ Running Step: #{step_name}"},
              border: :thick,
              padding: [1, 2],
              style: {border: {fg: :yellow}}
            )
            puts box

          when :completed
            content = []
            content << @pastel.green("Step completed successfully")
            if details[:duration]
              content << @pastel.dim("Duration: #{details[:duration].round(2)}s")
            end

            box = TTY::Box.frame(
              content.join("\n"),
              title: {top_left: "✅ Completed Step: #{step_name}"},
              border: :thick,
              padding: [1, 2],
              style: {border: {fg: :green}}
            )
            puts box

          when :failed
            content = []
            content << @pastel.red("Step failed")
            if details[:error]
              content << @pastel.red("Error: #{details[:error]}")
            end

            box = TTY::Box.frame(
              content.join("\n"),
              title: {top_left: "❌ Failed Step: #{step_name}"},
              border: :thick,
              padding: [1, 2],
              style: {border: {fg: :red}}
            )
            puts box
          end
        end

        private

        def initialize_display
          @cursor.hide
        end

        def restore_screen
          @cursor.show
          @cursor.clear_screen
          @cursor.move_to(1, 1)
        end

        def refresh_display
          return unless @input_mode

          @cursor.save
          @cursor.move_to(1, @screen.height)

          # Clear the bottom line
          print " " * @screen.width

          # Draw input overlay at the bottom
          draw_input_overlay

          @cursor.restore
        end

        def draw_input_overlay
          # Get terminal width and ensure we don't exceed it
          width = @screen.width
          max_width = width - 4  # Leave some margin

          # Create the input line
          input_line = @input_prompt + @input_buffer

          # Truncate if too long
          if input_line.length > max_width
            input_line = input_line[0...max_width] + "..."
          end

          # Draw the input overlay at the bottom
          @cursor.move_to(1, @screen.height)
          print @pastel.blue("┌") + "─" * (width - 2) + @pastel.blue("┐")

          @cursor.move_to(1, @screen.height + 1)
          print @pastel.blue("│") + input_line + " " * (width - input_line.length - 2) + @pastel.blue("│")

          @cursor.move_to(1, @screen.height + 2)
          print @pastel.blue("└") + "─" * (width - 2) + @pastel.blue("┘")
        end

        def setup_signal_handlers
          Signal.trap("INT") do
            stop_display_loop
            exit(1)
          end

          Signal.trap("TERM") do
            stop_display_loop
            exit(0)
          end
        end

        def format_elapsed_time(seconds)
          if seconds < 60
            "#{seconds.to_i}s"
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
end
