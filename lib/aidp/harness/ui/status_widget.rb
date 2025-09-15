# frozen_string_literal: true

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
          @spinner = ui_components[:spinner] || (defined?(CLI::UI) ? CLI::UI::Spinner : nil)
          @formatter = ui_components[:formatter] || StatusFormatter.new
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
          CLI::UI.puts(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show success status: #{e.message}"
        end

        def show_error_status(message)
          validate_message(message)

          formatted_message = @formatter.format_error_message(message)
          CLI::UI.puts(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show error status: #{e.message}"
        end

        def show_warning_status(message)
          validate_message(message)

          formatted_message = @formatter.format_warning_message(message)
          CLI::UI.puts(formatted_message)
        rescue => e
          raise DisplayError, "Failed to show warning status: #{e.message}"
        end

        private

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
      end

      # Formats status display messages
      class StatusFormatter
        def format_status_message(message)
          "⏳ #{message}"
        end

        def format_loading_message(operation_name)
          "Loading #{operation_name}..."
        end

        def format_success_message(message)
          CLI::UI.fmt("{{green:✓}} #{message}")
        end

        def format_error_message(message)
          CLI::UI.fmt("{{red:✗}} #{message}")
        end

        def format_warning_message(message)
          CLI::UI.fmt("{{yellow:⚠}} #{message}")
        end

        def format_info_message(message)
          CLI::UI.fmt("{{blue:ℹ}} #{message}")
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
