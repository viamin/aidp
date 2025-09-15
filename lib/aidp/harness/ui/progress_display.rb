# frozen_string_literal: true

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
          @progress = ui_components[:progress] || CLI::UI::Progress
          @formatter = ui_components[:formatter] || ProgressFormatter.new
        end

        def show_progress(total_steps, &block)
          validate_total_steps(total_steps)

          @progress.progress do |bar|
            execute_progress_steps(bar, total_steps, &block)
          end
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
      end
    end
  end
end
