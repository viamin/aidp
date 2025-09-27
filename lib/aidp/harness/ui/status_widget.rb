# frozen_string_literal: true

require "tty-spinner"
require "pastel"
require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles status display using CLI UI spinners
      class StatusWidget < Base
        class StatusError < StandardError; end
        class InvalidStatusError < StatusError; end
        class DisplayError < StatusError; end

        def initialize(ui_components = {})
          super()
          @spinner = ui_components[:spinner] || TTY::Spinner
          @pastel = Pastel.new
          @formatter = ui_components[:formatter] || StatusFormatter.new
          @output = ui_components[:output]
          @status_history = []
          @current_spinner = nil
          @spinner_active = false
        end

        def show_status(message, &block)
          validate_message(message)

          formatted_message = @formatter.format_status_message(message)
          @spinner.spin(formatted_message) do |spinner|
            yield(spinner) if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to show status: #{e.message}"
        end

        def update_status(spinner, message)
          validate_spinner_and_message(spinner, message)

          formatted_message = @formatter.format_status_message(message)
          spinner.update_title(formatted_message)
        rescue => e
          raise DisplayError, "Failed to update status: #{e.message}"
        end

        def show_loading_status(operation_name, &block)
          validate_operation_name(operation_name)

          message = @formatter.format_loading_message(operation_name)
          show_status(message, &block)
        rescue => e
          raise DisplayError, "Failed to show loading status: #{e.message}"
        end

        def show_success_status(message)
          validate_message(message)

          formatted_message = @formatter.format_success_message(message)
          display_message(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show success status: #{e.message}"
        end

        def show_error_status(message)
          validate_message(message)

          formatted_message = @formatter.format_error_message(message)
          display_message(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show error status: #{e.message}"
        end

        def show_warning_status(message)
          validate_message(message)

          formatted_message = @formatter.format_warning_message(message)
          display_message(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show warning status: #{e.message}"
        end

        # Methods expected by tests
        def display_status(status_type, message, error_data = nil)
          validate_status_type(status_type)
          validate_message(message)

          case status_type
          when :loading
            display_loading_status(message)
          when :success
            display_success_status(message)
          when :error
            display_error_status(message, error_data)
          when :warning
            display_warning_status(message)
          end

          record_status_history(status_type, message, error_data)
        rescue InvalidStatusError => e
          raise e
        rescue => e
          raise DisplayError, "Failed to display status: #{e.message}"
        end

        def start_spinner(message)
          validate_message(message)
          stop_spinner if @spinner_active

          @spinner_active = true
          @current_spinner = @spinner.new("⏳ #{message} :spinner", format: :pulse)
          @current_spinner.start
        end

        def stop_spinner
          return unless @spinner_active

          @current_spinner&.stop
          @spinner_active = false
          @current_spinner = nil
        end

        def update_spinner_message(message)
          validate_message(message)
          raise DisplayError, "No active spinner to update" unless @spinner_active

          @current_spinner&.stop
          @current_spinner = @spinner.new("⏳ #{message} :spinner", format: :pulse)
          @current_spinner.start
        end

        def display_status_with_duration(status_type, message, duration)
          validate_status_type(status_type)
          validate_message(message)

          formatted_duration = format_duration(duration)
          message_with_duration = "#{message} (#{formatted_duration})"
          display_status(status_type, message_with_duration)
        end

        def display_multiple_status(status_items)
          return if status_items.empty?

          status_items.each do |item|
            display_status(item[:type], item[:message], item[:error_data])
          end
        end

        def get_status_history
          @status_history.dup
        end

        def clear_status_history
          @status_history.clear
        end

        def format_duration(seconds)
          return "0s" if seconds <= 0

          if seconds < 60
            "#{seconds.round(1)}s"
          elsif seconds < 3600
            minutes = (seconds / 60).floor
            remaining_seconds = (seconds % 60).floor
            "#{minutes}m #{remaining_seconds}s"
          else
            hours = (seconds / 3600).floor
            minutes = ((seconds % 3600) / 60).floor
            remaining_seconds = (seconds % 60).floor
            "#{hours}h #{minutes}m #{remaining_seconds}s"
          end
        end

        def spinner_active?
          @spinner_active
        end

        def current_spinner_message
          return nil unless @spinner_active
          @current_spinner&.message&.to_s&.gsub(/⏳\s+|\s+:spinner/, "")
        end

        private

        def display_message(message)
          if @output
            @output.say(message)
          else
            puts message
          end
        end

        def validate_message(message)
          raise InvalidStatusError, "Message cannot be empty" if message.to_s.strip.empty?
        end

        def validate_spinner_and_message(spinner, message)
          raise InvalidStatusError, "Spinner cannot be nil" if spinner.nil?
          validate_message(message)
        end

        def validate_operation_name(operation_name)
          raise InvalidStatusError, "Operation name cannot be empty" if operation_name.to_s.strip.empty?
        end

        def validate_status_type(status_type)
          valid_types = [:loading, :success, :error, :warning]
          unless valid_types.include?(status_type)
            raise InvalidStatusError, "Invalid status type: #{status_type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

        def record_status_history(status_type, message, error_data)
          @status_history << {
            type: status_type,
            message: message,
            error_data: error_data,
            timestamp: Time.now
          }
        end

        def display_loading_status(message)
          display_message("⏳ #{message}")
        end

        def display_success_status(message)
          display_message("✅ #{message}")
        end

        def display_error_status(message, error_data)
          display_message("❌ #{message}")
          if error_data && error_data[:message]
            display_message("  #{error_data[:message]}")
          end
        end

        def display_warning_status(message)
          display_message("⚠️ #{message}")
        end
      end

      # Formats status display messages
      class StatusFormatter
        def initialize
          @pastel = Pastel.new
        end

        def format_status_message(message)
          "⏳ #{message}"
        end

        def format_loading_message(operation_name)
          "Loading #{operation_name}..."
        end

        def format_success_message(message)
          "#{@pastel.green("✓")} #{message}"
        end

        def format_error_message(message)
          "#{@pastel.red("✗")} #{message}"
        end

        def format_warning_message(message)
          "#{@pastel.yellow("⚠")} #{message}"
        end

        def format_info_message(message)
          "#{@pastel.blue("ℹ")} #{message}"
        end

        def format_step_message(step_name, status)
          case status
          when :starting
            "Starting #{step_name}..."
          when :in_progress
            "Processing #{step_name}..."
          when :completed
            "Completed #{step_name}"
          when :failed
            "Failed #{step_name}"
          else
            "#{step_name}: #{status}"
          end
        end
      end
    end
  end
end
