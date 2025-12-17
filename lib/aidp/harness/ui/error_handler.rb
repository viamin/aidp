# frozen_string_literal: true

require "tty-prompt"
require "pastel"

module Aidp
  module Harness
    module UI
      # Centralized error handling for UI components
      class ErrorHandler
        class UIError < StandardError; end

        class ComponentError < UIError; end

        class ValidationError < UIError; end

        class DisplayError < UIError; end

        class InteractionError < UIError; end

        # Expose for testability
        attr_reader :logger

        def initialize(ui_components = {})
          @logger = ui_components[:logger] || default_logger
          @formatter = ui_components[:formatter] || ErrorFormatter.new
          @prompt = ui_components[:prompt] || TTY::Prompt.new
        end

        def handle_error(error, context = {})
          log_error(error, context)
          display_error(error, context)
        end

        def handle_validation_error(error, field_name = nil)
          message = @formatter.format_validation_error(error, field_name)
          display_user_friendly_error(message)
        end

        def handle_display_error(error, component_name = nil)
          message = @formatter.format_display_error(error, component_name)
          display_user_friendly_error(message)
        end

        def handle_interaction_error(error, interaction_type = nil)
          message = @formatter.format_interaction_error(error, interaction_type)
          display_user_friendly_error(message)
        end

        def handle_component_error(error, component_name = nil)
          message = @formatter.format_component_error(error, component_name)
          display_user_friendly_error(message)
        end

        private

        def log_error(error, context)
          @logger.error("UI Error: #{error.class.name}: #{error.message}")
          @logger.error("Context: #{context}") unless context.empty?
          @logger.error("Backtrace: #{error.backtrace.join("\n")}") if error.backtrace
        end

        def display_error(error, context)
          case error
          when ValidationError
            handle_validation_error(error, context[:field_name])
          when DisplayError
            handle_display_error(error, context[:component_name])
          when InteractionError
            handle_interaction_error(error, context[:interaction_type])
          when ComponentError
            handle_component_error(error, context[:component_name])
          else
            display_generic_error(error)
          end
        end

        def display_user_friendly_error(message)
          @prompt.say("Error: #{message}", color: :red)
        end

        def display_generic_error(error)
          message = @formatter.format_generic_error(error)
          display_user_friendly_error(message)
        end

        def default_logger
          require "logger"
          Logger.new($stderr)
        end
      end

      # Formats error messages for display
      class ErrorFormatter
        def format_validation_error(error, field_name = nil)
          base_message = "Validation failed"
          field_suffix = field_name ? " for #{field_name}" : ""
          "#{base_message}#{field_suffix}: #{error.message}"
        end

        def format_display_error(error, component_name = nil)
          base_message = "Display error"
          component_suffix = component_name ? " in #{component_name}" : ""
          "#{base_message}#{component_suffix}: #{error.message}"
        end

        def format_interaction_error(error, interaction_type = nil)
          base_message = "Interaction error"
          type_suffix = interaction_type ? " during #{interaction_type}" : ""
          "#{base_message}#{type_suffix}: #{error.message}"
        end

        def format_component_error(error, component_name = nil)
          base_message = "Component error"
          component_suffix = component_name ? " in #{component_name}" : ""
          "#{base_message}#{component_suffix}: #{error.message}"
        end

        def format_generic_error(error)
          "An unexpected error occurred: #{error.message}"
        end

        def format_recovery_suggestion(error_type)
          case error_type
          when :validation
            "Please check your input and try again."
          when :display
            "The display may not render correctly. Please try again."
          when :interaction
            "Please try the interaction again."
          when :component
            "The component may not function properly. Please restart the application."
          else
            "Please try again or restart the application if the problem persists."
          end
        end
      end
    end
  end
end
