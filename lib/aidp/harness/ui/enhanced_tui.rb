# frozen_string_literal: true

require "io/console"

module Aidp
  module Harness
    module UI
      # Enhanced TUI system using CLI::UI, inspired by Claude Code and modern LLM agents
      class EnhancedTUI
        class TUIError < StandardError; end
        class InputError < TUIError; end
        class DisplayError < TUIError; end

        def initialize
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
              sleep 0.5
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
          show_message("🔄 Started job: #{@jobs[job_id][:name]}", :info)
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
              show_message("✅ Completed job: #{@jobs[job_id][:name]}", :success)
            when :failed
              show_message("❌ Failed job: #{@jobs[job_id][:name]}", :error)
            when :running
              show_message("🔄 Running job: #{@jobs[job_id][:name]}", :info)
            end
          end
        end

        def remove_job(job_id)
          job_name = @jobs[job_id]&.dig(:name)
          @jobs.delete(job_id)
          @jobs_visible = @jobs.any?
          show_message("🗑️ Removed job: #{job_name}", :info) if job_name
        end

        # Input methods using CLI::UI
        def get_user_input(prompt = "💬 You: ")
          ::CLI::UI::Prompt.ask(prompt)
        end

        def get_confirmation(message, default: true)
          ::CLI::UI::Prompt.confirm(message, default: default)
        end

        # Multiselect interface using CLI::UI
        def multiselect(title, items, selected: [])
          ::CLI::UI::Frame.open(title) do
            ::CLI::UI.puts "Use ↑↓ to navigate, SPACE to select/deselect, ENTER to confirm"
            ::CLI::UI.puts

            # Convert items to CLI::UI options format
            options = items.map.with_index do |item, index|
              {
                key: index.to_s,
                name: item,
                value: item
              }
            end

            # Use CLI::UI's multiselect
            ::CLI::UI::Prompt.ask("Select items (comma-separated numbers):") do |handler|
              options.each_with_index do |option, index|
                handler.option(option[:name]) { option[:value] }
              end
            end

            # For now, return all items if user doesn't specify
            # TODO: Implement proper multiselect with CLI::UI
            selected.any? ? selected : [items.first]
          end
        end

        # Display methods using CLI::UI
        def show_message(message, type = :info)
          case type
          when :info
            ::CLI::UI.puts "{{blue:ℹ}} #{message}"
          when :success
            ::CLI::UI.puts "{{green:✓}} #{message}"
          when :warning
            ::CLI::UI.puts "{{yellow:⚠}} #{message}"
          when :error
            ::CLI::UI.puts "{{red:✗}} #{message}"
          else
            ::CLI::UI.puts message
          end

          # Add to main content for history
          @main_content << { message: message, type: type, timestamp: Time.now }
          @main_content = @main_content.last(50) # Keep only last 50 messages
        end

        def show_progress(message, progress = 0)
          @current_progress = { message: message, progress: progress }

          if progress > 0
            ::CLI::UI::Progress.progress do |bar|
              bar.percentage = progress
              bar.format = "{{blue:⏳}} #{message} {{bar}} {{percent}}%"
            end
          else
            ::CLI::UI::Spinner.spin(message) do |spinner|
              # This will be updated by the display loop
            end
          end
        end

        def hide_progress
          @current_progress = nil
        end

        # Job display methods
        def show_jobs_dashboard
          return unless @jobs_visible && @jobs.any?

          ::CLI::UI::Frame.open("🔄 Background Jobs") do
            @jobs.each do |job_id, job|
              status_icon = case job[:status]
                           when :running then "{{green:●}}"
                           when :completed then "{{blue:●}}"
                           when :failed then "{{red:●}}"
                           when :pending then "{{yellow:●}}"
                           else "{{white:●}}"
                           end

              elapsed = format_elapsed_time(Time.now - job[:started_at])

              ::CLI::UI.puts "#{status_icon} {{bold:#{job[:name]}}} {{#{status_color(job[:status])}:#{job[:status].to_s.capitalize}}}"
              ::CLI::UI.puts "  {{dim:#{elapsed} | #{job[:provider]} | #{job[:message]}}}"

              # Show progress bar for running jobs
              if job[:status] == :running && job[:progress] && job[:progress] > 0
                ::CLI::UI::Progress.progress do |bar|
                  bar.percentage = job[:progress]
                  bar.format = "  {{bar}} {{percent}}%"
                end
              end

              ::CLI::UI.puts
            end
          end
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
          ::CLI::UI::StdoutRouter.enable
        end

        def restore_screen
          # CLI::UI handles cleanup automatically
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
