# frozen_string_literal: true

require "tty-progressbar"
require "pastel"
require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles progress display using CLI UI progress bars
      class ProgressDisplay < Base
        class ProgressError < StandardError; end
        class InvalidProgressError < ProgressError; end
        class DisplayError < ProgressError; end

        def initialize(ui_components = {})
          super()
          @progress = ui_components[:progress] || TTY::ProgressBar
          @pastel = Pastel.new
          @formatter = ui_components[:formatter] || ProgressFormatter.new
          @display_history = []
          @auto_refresh_enabled = false
          @refresh_interval = 1.0
          @refresh_thread = nil
        end

        def show_progress(total_steps, &block)
          validate_total_steps(total_steps)

          progress_bar = @progress.new(
            "[:bar] :percent% :current/:total",
            total: total_steps,
            width: 30
          )

          execute_progress_steps(progress_bar, total_steps, &block)
        rescue => e
          raise DisplayError, "Failed to display progress: #{e.message}"
        end

        def update_progress(bar, message = nil)
          validate_progress_bar(bar)

          bar.tick
          bar.update_title(message) if message
        rescue => e
          raise DisplayError, "Failed to update progress: #{e.message}"
        end

        def show_step_progress(step_name, total_substeps, &block)
          validate_step_inputs(step_name, total_substeps)

          formatted_title = @formatter.format_step_title(step_name)
          @progress.progress do |bar|
            execute_substeps(bar, total_substeps, formatted_title, &block)
          end
        rescue => e
          raise DisplayError, "Failed to display step progress: #{e.message}"
        end

        def show_indeterminate_progress(message)
          validate_message(message)

          @progress.progress do |bar|
            bar.update_title(message)
            yield(bar) if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to display indeterminate progress: #{e.message}"
        end

        private

        def validate_total_steps(total_steps)
          raise InvalidProgressError, "Total steps must be positive" unless total_steps > 0
        end

        def validate_progress_bar(bar)
          raise InvalidProgressError, "Progress bar cannot be nil" if bar.nil?
        end

        def validate_step_inputs(step_name, total_substeps)
          raise InvalidProgressError, "Step name cannot be empty" if step_name.to_s.strip.empty?
          raise InvalidProgressError, "Total substeps must be positive" unless total_substeps > 0
        end

        def validate_message(message)
          raise InvalidProgressError, "Message cannot be empty" if message.to_s.strip.empty?
        end

        def execute_progress_steps(bar, total_steps, &block)
          total_steps.times do
            yield(bar) if block_given?
            bar.tick
          end
        end

        def execute_substeps(bar, total_substeps, title, &block)
          bar.update_title(title)
          total_substeps.times do |index|
            substep_title = @formatter.format_substep_title(title, index + 1, total_substeps)
            bar.update_title(substep_title)
            yield(bar, index) if block_given?
            bar.tick
          end
        end
      end

      # Formats progress display text
      class ProgressFormatter
        def format_step_title(step_name)
          "Step: #{step_name}"
        end

        def format_substep_title(step_title, current, total)
          "#{step_title} (#{current}/#{total})"
        end

        def format_percentage(current, total)
          percentage = (current.to_f / total * 100).round(1)
          "#{percentage}%"
        end

        def format_eta(remaining_steps, average_time_per_step)
          return "Unknown" unless average_time_per_step > 0

          eta_seconds = remaining_steps * average_time_per_step
          format_duration(eta_seconds)
        end

        # New methods expected by tests
        def display_progress(progress_data, display_type = :standard)
          validate_progress_data(progress_data)
          validate_display_type(display_type)

          case display_type
          when :standard
            display_standard_progress(progress_data)
          when :detailed
            display_detailed_progress(progress_data)
          when :minimal
            display_minimal_progress(progress_data)
          end

          record_display_history(progress_data, display_type)
        rescue InvalidProgressError => e
          raise e
        rescue => e
          raise DisplayError, "Failed to display progress: #{e.message}"
        end

        def start_auto_refresh(interval_seconds)
          return if @auto_refresh_enabled

          @auto_refresh_enabled = true
          @refresh_interval = interval_seconds
          @refresh_thread = Thread.new do
            loop do
              break unless @auto_refresh_enabled
              sleep(@refresh_interval)
              refresh_display if @auto_refresh_enabled
            end
          end
        end

        def stop_auto_refresh
          @auto_refresh_enabled = false
          @refresh_thread&.join
          @refresh_thread = nil
        end

        def auto_refresh_enabled?
          @auto_refresh_enabled
        end

        attr_reader :refresh_interval

        def display_multiple_progress(progress_items, display_type = :standard)
          return if progress_items.empty?

          progress_items.each do |item|
            display_progress(item, display_type)
          end
        rescue => e
          raise DisplayError, "Failed to display multiple progress: #{e.message}"
        end

        def get_display_history
          @display_history.dup
        end

        def clear_display_history
          @display_history.clear
        end

        private

        def format_duration(seconds)
          if seconds < 60
            "#{seconds.round}s"
          elsif seconds < 3600
            "#{(seconds / 60).round}m"
          else
            hours = (seconds / 3600).round
            minutes = ((seconds % 3600) / 60).round
            "#{hours}h #{minutes}m"
          end
        end

        def display_standard_progress(progress_data)
          progress_bar = create_progress_bar(progress_data[:progress])
          puts("#{progress_data[:id]}: #{progress_bar} #{progress_data[:progress]}%")

          if progress_data[:current_step] && progress_data[:total_steps]
            puts("Step: #{progress_data[:current_step]}/#{progress_data[:total_steps]}")
          end
        end

        def display_detailed_progress(progress_data)
          puts("Progress: #{progress_data[:progress]}%")
          puts("Created: #{progress_data[:created_at]}")
          puts("Last Updated: #{progress_data[:last_updated]}")

          if progress_data[:estimated_completion]
            puts("ETA: #{progress_data[:estimated_completion]}")
          end
        end

        def display_minimal_progress(progress_data)
          puts("#{progress_data[:progress]}%")
        end

        def create_progress_bar(progress)
          bar_length = 20
          filled_length = (progress * bar_length / 100).round
          bar = "█" * filled_length + "░" * (bar_length - filled_length)
          "[#{bar}]"
        end

        def validate_progress_data(progress_data)
          raise InvalidProgressError, "Progress data cannot be nil" if progress_data.nil?
          raise InvalidProgressError, "Progress data must be a hash" unless progress_data.is_a?(Hash)
          raise InvalidProgressError, "Progress must be between 0 and 100" if progress_data[:progress] < 0 || progress_data[:progress] > 100
        end

        def validate_display_type(display_type)
          valid_types = [:standard, :detailed, :minimal]
          unless valid_types.include?(display_type)
            raise InvalidProgressError, "Invalid display type: #{display_type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

        def record_display_history(progress_data, display_type)
          @display_history << {
            data: progress_data.dup,
            display_type: display_type,
            timestamp: Time.now
          }
        end
      end
    end
  end
end
