# frozen_string_literal: true

require "tty-progressbar"
require "tty-prompt"
require "pastel"
require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles progress display using CLI UI progress bars
      class ProgressDisplay < Base
        include Aidp::MessageDisplay

        class ProgressError < StandardError; end

        class InvalidProgressError < ProgressError; end

        class DisplayError < ProgressError; end

        attr_reader :refresh_interval

        def initialize(ui_components = {})
          super()
          @progress = ui_components[:progress] || TTY::ProgressBar
          @pastel = Pastel.new
          @formatter = ui_components[:formatter] || ProgressFormatter.new
          @display_history = []
          @auto_refresh_enabled = false
          @refresh_interval = 1.0
          @refresh_thread = nil
          @output = ui_components[:output]
          @prompt = ui_components[:prompt] || TTY::Prompt.new
          @spinner_class = begin
            ui_components[:spinner] || TTY::Spinner
          rescue
            nil
          end
          @spinner = nil
        end

        # Simple spinner management used by component specs
        def start_spinner(message = "Loading...")
          return unless @spinner_class
          @spinner = @spinner_class.new("#{message} :spinner", format: :dots, output: @output)
          @spinner.start
        end

        def stop_spinner
          @spinner&.stop
          @spinner = nil
        end

        def show_progress(total_steps, &block)
          validate_total_steps(total_steps)

          progress_bar = @progress.new(
            "[:bar] :percent% :current/:total",
            total: total_steps,
            width: 30,
            output: @output
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

        def display_multiple_progress(progress_items, display_type = :standard)
          raise ArgumentError, "Progress items must be an array" unless progress_items.is_a?(Array)

          if progress_items.empty?
            display_message(@pastel.dim("No progress items to display."), type: :muted)
            return
          end

          progress_items.each do |item|
            display_progress(item, display_type)
          end
        end

        def get_display_history
          @display_history.dup
        end

        def clear_display_history
          @display_history = []
        end

        def start_auto_refresh(interval)
          return if @auto_refresh_enabled

          @refresh_interval = interval
          @auto_refresh_enabled = true
          @refresh_thread = Thread.new do
            while @auto_refresh_enabled
              yield if block_given?
              sleep @refresh_interval
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
            yield(bar) if block
            bar.tick
          end
        end

        def execute_substeps(bar, total_substeps, title, &block)
          bar.update_title(title)
          total_substeps.times do |index|
            substep_title = @formatter.format_substep_title(title, index + 1, total_substeps)
            bar.update_title(substep_title)
            yield(bar, index) if block
            bar.tick
          end
        end

        def display_standard_progress(progress_data)
          progress = progress_data[:progress] || 0
          message = progress_data[:message] || "Processing..."
          step_info = (progress_data[:current_step] && progress_data[:total_steps]) ?
            " (Step: #{progress_data[:current_step]}/#{progress_data[:total_steps]})" :
            " (Step: #{progress_data[:current_step]})"
          task_id = progress_data[:id] ? "[#{progress_data[:id]}] " : ""

          display_message("#{task_id}#{progress}% #{message}#{step_info}", type: :info)
        end

        def display_detailed_progress(progress_data)
          progress = progress_data[:progress] || 0
          message = progress_data[:message] || "Processing..."
          current_step = progress_data[:current_step] || "N/A"
          total_steps = progress_data[:total_steps] || "N/A"
          started_at = progress_data[:started_at] ? progress_data[:started_at].strftime("%H:%M:%S") : "N/A"
          eta = progress_data[:eta] || "N/A"

          display_message("Progress: #{progress}% - #{message} (Step: #{current_step}/#{total_steps}, Started: #{started_at}, ETA: #{eta})", type: :info)
        end

        def display_minimal_progress(progress_data)
          progress = progress_data[:progress] || 0
          message = progress_data[:message] || "Processing..."
          display_message("Progress: #{progress}% - #{message}", type: :info)
        end

        def create_progress_bar(progress)
          TTY::ProgressBar.new(
            "#{@pastel.green("[:bar]")} :percent",
            total: 100,
            width: 30,
            current: progress,
            output: @output
          )
        end

        def validate_progress_data(progress_data)
          raise ArgumentError, "Progress data must be a hash" unless progress_data.is_a?(Hash)
          progress = progress_data[:progress]
          if progress && (!progress.is_a?(Numeric) || progress < 0 || progress > 100)
            raise InvalidProgressError, "Progress must be a number between 0 and 100"
          end
        end

        def validate_display_type(display_type)
          valid_types = [:standard, :detailed, :minimal]
          unless valid_types.include?(display_type)
            raise InvalidProgressError, "Invalid display type: #{display_type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

        def record_display_history(progress_data, display_type)
          @display_history << {
            progress_data: progress_data.dup,
            display_type: display_type,
            timestamp: Time.now
          }
        end

        private

        # Use mixin display_message; fallback to stdout if no prompt
        def display_message(message, type: :info)
          if @prompt
            super
          elsif @output
            @output.puts(message)
          else
            puts(message)
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
      end
    end
  end
end
