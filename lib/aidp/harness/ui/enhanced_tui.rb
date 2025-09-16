# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"
require "tty-reader"
require "tty-box"
require "tty-table"
require "tty-progressbar"
require "tty-spinner"
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

          @jobs = {}
          @jobs_visible = false
          @current_selection = nil
          @selection_mode = false
          @multiselect_items = []
          @multiselect_selected = []
          @multiselect_cursor = 0
          @main_content = []
          @current_progress = nil
          @display_active = false
          @display_thread = nil
          @input_buffer = ""
          @input_position = 0

          # Layout dimensions
          @job_area_height = 8
          @input_area_height = 3
          @main_area_height = @screen.height - @job_area_height - @input_area_height - 2

          setup_signal_handlers
          initialize_display
        end

        # Main display loop - shows jobs, main content, and input area
        def start_display_loop
          @display_active = true
          @display_thread = Thread.new do
            loop do
              break unless @display_active
              refresh_display
              sleep 0.1
            end
          end
        end

        def stop_display_loop
          @display_active = false
          @display_thread&.join
          restore_screen
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
          @reader.read_line(prompt)
        end

        def get_confirmation(message, default: true)
          default_text = default ? "Y/n" : "y/N"
          response = @reader.read_line("#{message} [#{default_text}]: ")

          case response.downcase
          when "y", "yes"
            true
          when "n", "no"
            false
          when ""
            default
          else
            get_confirmation(message, default: default)
          end
        end

        # Multiselect interface with arrow keys + space bar (like modern GUIs)
        def multiselect(title, items, selected: [])
          @multiselect_items = items
          @multiselect_selected = selected.dup
          @multiselect_cursor = 0

          # Show initial interface
          show_multiselect_interface(title)

          # Handle keyboard input with tty-reader
          @reader.on(:keypress) do |event|
            case event.key.name
            when :up
              @multiselect_cursor = [@multiselect_cursor - 1, 0].max
              show_multiselect_interface(title)
            when :down
              @multiselect_cursor = [@multiselect_cursor + 1, @multiselect_items.length - 1].min
              show_multiselect_interface(title)
            when :space
              item = @multiselect_items[@multiselect_cursor]
              if @multiselect_selected.include?(item)
                @multiselect_selected.delete(item)
              else
                @multiselect_selected << item
              end
              show_multiselect_interface(title)
            when :return
              @reader.stop
            when :ctrl_c
              @reader.stop
              raise Interrupt
            end
          end

          # Start reading input
          @reader.read_line

          @multiselect_selected
        end

        private

        def show_multiselect_interface(title)
          # Clear screen and show interface
          @cursor.clear_screen
          @cursor.move_to(1, 1)

          # Create a box for the multiselect
          box = TTY::Box.frame(
            width: @screen.width - 4,
            height: @multiselect_items.length + 6,
            title: {top_left: title, bottom_right: "Multiselect"},
            border: {
              type: :thick,
              top_left: "┌",
              top_right: "┐",
              bottom_left: "└",
              bottom_right: "┘",
              top: "─",
              bottom: "─",
              left: "│",
              right: "│"
            }
          )

          # Build content
          content = []
          content << @pastel.bold("Use ↑↓ to navigate, SPACE to select/deselect, ENTER to confirm")
          content << ""

          @multiselect_items.each_with_index do |item, index|
            # Selection indicator
            if @multiselect_selected.include?(item)
              indicator = @pastel.green("☑")
            else
              indicator = @pastel.dim("☐")
            end

            # Cursor indicator
            if index == @multiselect_cursor
              cursor = @pastel.yellow("▶")
              item_text = @pastel.bold.white(item)
            else
              cursor = " "
              item_text = item
            end

            content << "#{cursor} #{indicator} #{item_text}"
          end

          content << ""
          content << @pastel.dim("Selected: #{@multiselect_selected.length} items")

          # Display the box
          puts box.render(content.join("\n"))
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
          @main_content << { message: message, type: type, timestamp: Time.now }
          @main_content = @main_content.last(50) # Keep only last 50 messages
        end

        def show_progress(message, progress = 0)
          @current_progress = { message: message, progress: progress }

          if progress > 0
            progress_bar = TTY::ProgressBar.new(
              "⏳ #{message} [:bar] :percent",
              total: 100,
              width: 40
            )
            progress_bar.current = progress
            progress_bar.render
          else
            spinner = TTY::Spinner.new("⏳ #{message} :spinner", format: :dots)
            spinner.start
            @current_spinner = spinner
          end
        end

        def hide_progress
          @current_progress = nil
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
            width: @screen.width - 4,
            height: @jobs.length + 3,
            title: {top_left: "🔄 Background Jobs"},
            border: {type: :thick}
          )

          puts box.render(table.render(:unicode, padding: [0, 1]))
        end

        # Enhanced workflow display
        def show_workflow_status(workflow_data)
          ::CLI::UI::Frame.open("📋 Workflow Status") do
            ::CLI::UI.puts "{{bold:Type:}} #{workflow_data[:workflow_type]}"
            ::CLI::UI.puts "{{bold:Steps:}} #{workflow_data[:steps]&.length || 0} total"
            ::CLI::UI.puts "{{bold:Completed:}} #{workflow_data[:completed_steps] || 0}"
            ::CLI::UI.puts "{{bold:Current:}} #{workflow_data[:current_step] || 'None'}"

            if workflow_data[:progress_percentage]
              ::CLI::UI::Progress.progress do |bar|
                bar.percentage = workflow_data[:progress_percentage]
                bar.format = "{{bold:Progress:}} {{bar}} {{percent}}%"
              end
            end
          end
        end

        # Input area with border (like Claude Code)
        def show_input_area(prompt = "💬 You: ")
          ::CLI::UI::Frame.open("Input", color: :blue) do
            ::CLI::UI.puts "{{blue:#{prompt}}}"
            ::CLI::UI.puts "{{dim:Type your message and press Enter}}"
          end
        end

        # Enhanced step execution display
        def show_step_execution(step_name, status, details = {})
          case status
          when :starting
            ::CLI::UI::Frame.open("🚀 Executing Step: #{step_name}") do
              ::CLI::UI.puts "{{blue:Starting execution...}}"
              if details[:provider]
                ::CLI::UI.puts "{{dim:Provider: #{details[:provider]}}}"
              end
            end
          when :running
            ::CLI::UI::Frame.open("⏳ Running Step: #{step_name}") do
              ::CLI::UI.puts "{{yellow:Step is running...}}"
              if details[:message]
                ::CLI::UI.puts "{{dim:#{details[:message]}}}"
              end
            end
          when :completed
            ::CLI::UI::Frame.open("✅ Completed Step: #{step_name}") do
              ::CLI::UI.puts "{{green:Step completed successfully}}"
              if details[:duration]
                ::CLI::UI.puts "{{dim:Duration: #{details[:duration].round(2)}s}}"
              end
            end
          when :failed
            ::CLI::UI::Frame.open("❌ Failed Step: #{step_name}") do
              ::CLI::UI.puts "{{red:Step failed}}"
              if details[:error]
                ::CLI::UI.puts "{{red:Error: #{details[:error]}}}"
              end
            end
          end
        end

        private

        def initialize_display
          @cursor.hide
          @cursor.clear_screen
          @cursor.move_to(1, 1)
        end

        def restore_screen
          @cursor.show
          @cursor.clear_screen
          @cursor.move_to(1, 1)
        end

        def refresh_display
          @cursor.save
          @cursor.move_to(1, 1)

          # Clear screen
          print "\e[2J"

          # Draw jobs area
          draw_jobs_area if @jobs_visible

          # Draw main content area
          draw_main_area

          # Draw input area (if not in selection mode)
          draw_input_area unless @selection_mode

          @cursor.restore
        end

        def draw_jobs_area
          return unless @jobs_visible

          # Draw jobs header
          header = @pastel.bold.blue("🔄 Background Jobs")
          print @cursor.move_to(1, 1) + header

          # Draw jobs table
          y_pos = 2
          @jobs.each_with_index do |(job_id, job), index|
            break if y_pos > @job_area_height

            status_color = case job[:status]
                          when :running then @pastel.green
                          when :completed then @pastel.blue
                          when :failed then @pastel.red
                          when :pending then @pastel.yellow
                          else @pastel.white
                          end

            elapsed = Time.now - job[:started_at]
            elapsed_str = format_elapsed_time(elapsed)

            # Job name and status
            job_line = "#{status_color.call('●')} #{job[:name]} #{status_color.call(job[:status].to_s.capitalize)}"
            print @cursor.move_to(1, y_pos) + job_line

            # Progress bar
            if job[:status] == :running && job[:progress]
              progress_width = 30
              filled = (job[:progress] * progress_width / 100).to_i
              bar = "[" + "█" * filled + "░" * (progress_width - filled) + "]"
              print @cursor.move_to(1, y_pos + 1) + bar
            end

            # Elapsed time and message
            info_line = "  #{elapsed_str} | #{job[:provider]} | #{job[:message]}"
            print @cursor.move_to(1, y_pos + 2) + info_line

            y_pos += 3
          end

          # Draw separator
          separator = "─" * @screen.width
          print @cursor.move_to(1, @job_area_height + 1) + @pastel.dim(separator)
        end

        def draw_main_area
          start_y = @jobs_visible ? @job_area_height + 2 : 1
          end_y = @screen.height - @input_area_height - 1

          # Clear main area
          (start_y..end_y).each do |y|
            print @cursor.move_to(1, y) + " " * @screen.width
          end

          # Draw main content
          if @main_content
            content_y = start_y
            @main_content.last((end_y - start_y + 1)).each do |item|
              break if content_y > end_y

              timestamp = item[:timestamp].strftime("%H:%M:%S")
              line = "[#{timestamp}] #{item[:message]}"

              # Truncate if too long
              if line.length > @screen.width
                line = line[0...(@screen.width - 3)] + "..."
              end

              print @cursor.move_to(1, content_y) + line
              content_y += 1
            end
          end

          # Draw current progress
          if @current_progress
            progress_y = end_y - 1
            progress_line = @pastel.cyan("⏳ #{@current_progress[:message]}")
            print @cursor.move_to(1, progress_y) + progress_line

            # Progress bar
            if @current_progress[:progress] > 0
              progress_width = 40
              filled = (@current_progress[:progress] * progress_width / 100).to_i
              bar = "[" + "█" * filled + "░" * (progress_width - filled) + "] #{@current_progress[:progress]}%"
              print @cursor.move_to(1, progress_y + 1) + @pastel.cyan(bar)
            end
          end
        end

        def draw_input_area
          input_y = @screen.height - @input_area_height

          # Draw input border
          border = "┌" + "─" * (@screen.width - 2) + "┐"
          print @cursor.move_to(1, input_y) + @pastel.blue(border)

          # Draw input prompt and text
          prompt = "💬 You: "
          input_line = prompt + @input_buffer

          # Handle cursor position
          cursor_x = prompt.length + @input_position + 1
          cursor_y = input_y + 1

          print @cursor.move_to(1, input_y + 1) + input_line
          print @cursor.move_to(cursor_x, cursor_y)

          # Draw bottom border
          bottom_border = "└" + "─" * (@screen.width - 2) + "┘"
          print @cursor.move_to(1, input_y + 2) + @pastel.blue(bottom_border)
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

        def refresh_display
          # CLI::UI handles most of the display management
          # This method can be used for periodic updates if needed
        end

        def status_color(status)
          case status
          when :running then :green
          when :completed then :blue
          when :failed then :red
          when :pending then :yellow
          else :white
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
