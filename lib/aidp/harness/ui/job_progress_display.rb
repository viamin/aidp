# frozen_string_literal: true

require_relative "base"
require_relative "job_monitor"

module Aidp
  module Harness
    module UI
      # Job progress display using CLI UI components
      class JobProgressDisplay < Base
        class ProgressDisplayError < StandardError; end
        class InvalidProgressError < ProgressDisplayError; end
        class DisplayError < ProgressDisplayError; end

        def initialize(ui_components = {})
          super()
          @job_monitor = ui_components[:job_monitor] || JobMonitor.new
          @formatter = ui_components[:formatter] || JobProgressDisplayFormatter.new

          @active_displays = {}
          @display_history = []
          @auto_refresh_interval = 0.5
          @refresh_thread = nil
          @display_active = false
        end

        def display_job_progress(job_id, display_type = :standard)
          validate_job_id(job_id)
          validate_display_type(display_type)

          job = @job_monitor.get_job_status(job_id)
          progress_data = extract_progress_data(job)

          case display_type
          when :standard
            display_standard_progress(job_id, progress_data)
          when :detailed
            display_detailed_progress(job_id, progress_data)
          when :minimal
            display_minimal_progress(job_id, progress_data)
          when :spinner
            display_spinner_progress(job_id, progress_data)
          end

          record_display_event(job_id, display_type, progress_data)
        rescue StandardError => e
          raise DisplayError, "Failed to display job progress: #{e.message}"
        end

        def start_auto_refresh(interval_seconds = nil)
          return if @display_active

          @auto_refresh_interval = interval_seconds if interval_seconds
          @display_active = true

          @refresh_thread = Thread.new do
            auto_refresh_loop
          end

          CLI::UI.puts(@formatter.format_auto_refresh_started(@auto_refresh_interval))
        rescue StandardError => e
          raise DisplayError, "Failed to start auto refresh: #{e.message}"
        end

        def stop_auto_refresh
          return unless @display_active

          @display_active = false
          @refresh_thread&.join
          @refresh_thread = nil

          CLI::UI.puts(@formatter.format_auto_refresh_stopped)
        end

        def display_multiple_jobs(job_ids, display_type = :standard)
          validate_job_ids(job_ids)

          @frame_manager.section("Multiple Job Progress") do
            job_ids.each do |job_id|
              display_job_progress(job_id, display_type)
              CLI::UI.puts("") # Add spacing between jobs
            end
          end
        end

        def display_job_summary(job_id)
          validate_job_id(job_id)

          job = @job_monitor.get_job_status(job_id)
          summary_data = extract_summary_data(job)

          @frame_manager.section("Job Summary: #{job_id}") do
            display_summary_details(summary_data)
          end
        end

        def get_display_history
          @display_history.dup
        end

        def clear_display_history
          @display_history.clear
        end

        private

        def validate_job_id(job_id)
          raise ProgressDisplayError, "Job ID cannot be empty" if job_id.to_s.strip.empty?
        end

        def validate_display_type(display_type)
          valid_types = [:standard, :detailed, :minimal, :spinner]
          unless valid_types.include?(display_type)
            raise ProgressDisplayError, "Invalid display type: #{display_type}. Must be one of: #{valid_types.join(', ')}"
          end
        end

        def validate_job_ids(job_ids)
          raise ProgressDisplayError, "Job IDs must be an array" unless job_ids.is_a?(Array)
          raise ProgressDisplayError, "Job IDs cannot be empty" if job_ids.empty?
        end

        def extract_progress_data(job)
          {
            id: job[:id],
            status: job[:status],
            progress: job[:progress] || 0,
            current_step: job[:current_step] || 0,
            total_steps: job[:total_steps] || 1,
            created_at: job[:created_at],
            last_updated: job[:last_updated],
            estimated_completion: job[:estimated_completion],
            error_message: job[:error_message]
          }
        end

        def extract_summary_data(job)
          {
            id: job[:id],
            status: job[:status],
            priority: job[:priority],
            progress: job[:progress] || 0,
            created_at: job[:created_at],
            last_updated: job[:last_updated],
            duration: calculate_duration(job[:created_at], job[:last_updated]),
            retry_count: job[:retry_count] || 0,
            max_retries: job[:max_retries] || 3,
            error_message: job[:error_message]
          }
        end

        def calculate_duration(start_time, end_time)
          return 0 unless start_time && end_time
          end_time - start_time
        end

        def display_standard_progress(job_id, progress_data)
          progress_bar = create_progress_bar(progress_data[:progress])
          status_icon = get_status_icon(progress_data[:status])

          CLI::UI.puts("#{status_icon} #{job_id}: #{progress_bar} #{progress_data[:progress].to_i}%")

          if progress_data[:current_step] > 0
            CLI::UI.puts("  Step: #{progress_data[:current_step]}/#{progress_data[:total_steps]}")
          end

          if progress_data[:error_message]
            CLI::UI.puts("  #{@formatter.format_error(progress_data[:error_message])}")
          end
        end

        def display_detailed_progress(job_id, progress_data)
          CLI::UI.puts("Job: #{job_id}")
          CLI::UI.puts("Status: #{@formatter.format_status(progress_data[:status])}")
          CLI::UI.puts("Progress: #{create_progress_bar(progress_data[:progress])} #{progress_data[:progress].to_i}%")

          if progress_data[:current_step] > 0
            CLI::UI.puts("Current Step: #{progress_data[:current_step]}/#{progress_data[:total_steps]}")
          end

          CLI::UI.puts("Created: #{progress_data[:created_at]}")
          CLI::UI.puts("Last Updated: #{progress_data[:last_updated]}")

          if progress_data[:estimated_completion]
            CLI::UI.puts("ETA: #{progress_data[:estimated_completion]}")
          end

          if progress_data[:error_message]
            CLI::UI.puts("Error: #{@formatter.format_error(progress_data[:error_message])}")
          end
        end

        def display_minimal_progress(job_id, progress_data)
          status_icon = get_status_icon(progress_data[:status])
          progress = progress_data[:progress].to_i

          CLI::UI.puts("#{status_icon} #{job_id}: #{progress}%")
        end

        def display_spinner_progress(job_id, progress_data)
          status_icon = get_status_icon(progress_data[:status])
          progress = progress_data[:progress].to_i

          # Use CLI::UI::Spinner for running jobs
          if progress_data[:status] == :running
            CLI::UI::Spinner.spin("Processing #{job_id}") do |spinner|
              spinner.update_title("#{status_icon} #{job_id}: #{progress}%")
              sleep(0.1) # Simulate work
            end
          else
            CLI::UI.puts("#{status_icon} #{job_id}: #{progress}%")
          end
        end

        def create_progress_bar(progress, width = 20)
          progress_int = progress.to_i
          filled = (progress_int * width / 100).to_i
          empty = width - filled

          bar = "█" * filled + "░" * empty
          CLI::UI.fmt("[{{blue:#{bar}}}]")
        end

        def get_status_icon(status)
          case status
          when :pending
            "⏳"
          when :running
            "🔄"
          when :completed
            "✅"
          when :failed
            "❌"
          when :cancelled
            "🚫"
          when :retrying
            "🔄"
          else
            "❓"
          end
        end

        def display_summary_details(summary_data)
          CLI::UI.puts("Job ID: #{summary_data[:id]}")
          CLI::UI.puts("Status: #{@formatter.format_status(summary_data[:status])}")
          CLI::UI.puts("Priority: #{@formatter.format_priority(summary_data[:priority])}")
          CLI::UI.puts("Progress: #{summary_data[:progress].to_i}%")
          CLI::UI.puts("Duration: #{@formatter.format_duration(summary_data[:duration])}")
          CLI::UI.puts("Created: #{summary_data[:created_at]}")
          CLI::UI.puts("Last Updated: #{summary_data[:last_updated]}")

          if summary_data[:retry_count] > 0
            CLI::UI.puts("Retries: #{summary_data[:retry_count]}/#{summary_data[:max_retries]}")
          end

          if summary_data[:error_message]
            CLI::UI.puts("Error: #{@formatter.format_error(summary_data[:error_message])}")
          end
        end

        def auto_refresh_loop
          loop do
            break unless @display_active

            begin
              refresh_active_displays
              sleep(@auto_refresh_interval)
            rescue StandardError => e
              CLI::UI.puts(@formatter.format_refresh_error(e.message))
            end
          end
        end

        def refresh_active_displays
          @active_displays.each do |job_id, display_type|
            begin
              display_job_progress(job_id, display_type)
            rescue StandardError => e
              CLI::UI.puts(@formatter.format_display_error(job_id, e.message))
            end
          end
        end

        def record_display_event(job_id, display_type, progress_data)
          @display_history << {
            job_id: job_id,
            display_type: display_type,
            timestamp: Time.now,
            progress: progress_data[:progress],
            status: progress_data[:status]
          }
        end
      end

      # Formats job progress display
      class JobProgressDisplayFormatter
        def format_status(status)
          case status
          when :pending
            CLI::UI.fmt("{{yellow:⏳ Pending}}")
          when :running
            CLI::UI.fmt("{{blue:🔄 Running}}")
          when :completed
            CLI::UI.fmt("{{green:✅ Completed}}")
          when :failed
            CLI::UI.fmt("{{red:❌ Failed}}")
          when :cancelled
            CLI::UI.fmt("{{red:🚫 Cancelled}}")
          when :retrying
            CLI::UI.fmt("{{yellow:🔄 Retrying}}")
          else
            CLI::UI.fmt("{{dim:❓ #{status.to_s.capitalize}}}")
          end
        end

        def format_priority(priority)
          case priority
          when :low
            CLI::UI.fmt("{{dim:🔽 Low}}")
          when :normal
            CLI::UI.fmt("{{blue:➡️ Normal}}")
          when :high
            CLI::UI.fmt("{{yellow:🔼 High}}")
          when :urgent
            CLI::UI.fmt("{{red:🚨 Urgent}}")
          else
            CLI::UI.fmt("{{dim:❓ #{priority.to_s.capitalize}}}")
          end
        end

        def format_duration(duration_seconds)
          if duration_seconds < 60
            "#{duration_seconds.round(1)}s"
          elsif duration_seconds < 3600
            "#{(duration_seconds / 60).round(1)}m"
          else
            "#{(duration_seconds / 3600).round(1)}h"
          end
        end

        def format_error(error_message)
          CLI::UI.fmt("{{red:❌ #{error_message}}}")
        end

        def format_auto_refresh_started(interval_seconds)
          CLI::UI.fmt("{{green:✅ Auto refresh started (interval: #{interval_seconds}s)}}")
        end

        def format_auto_refresh_stopped
          CLI::UI.fmt("{{red:❌ Auto refresh stopped}}")
        end

        def format_refresh_error(error_message)
          CLI::UI.fmt("{{red:❌ Refresh error: #{error_message}}}")
        end

        def format_display_error(job_id, error_message)
          CLI::UI.fmt("{{red:❌ Display error for #{job_id}: #{error_message}}}")
        end

        def format_progress_bar(progress, width = 20)
          progress_int = progress.to_i
          filled = (progress_int * width / 100).to_i
          empty = width - filled

          bar = "█" * filled + "░" * empty
          CLI::UI.fmt("[{{blue:#{bar}}}]")
        end
      end
    end
  end
end
