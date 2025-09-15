# frozen_string_literal: true

require_relative "user_interface_new"
require_relative "feedback_collector"
require_relative "file_selector"
require_relative "question_validator"
require_relative "progress_tracker"
require_relative "status_manager"

module Aidp
  module Harness
    module UI
      # Compatibility layer to maintain backward compatibility with existing UserInterface
      class CompatibilityLayer
        class CompatibilityError < StandardError; end

        def initialize(ui_components = {})
          @user_interface = UserInterfaceNew.new(ui_components)
          @feedback_collector = FeedbackCollector.new(ui_components)
          @file_selector = FileSelector.new(ui_components)
          @question_validator = QuestionValidator.new(ui_components)
          @progress_tracker = ProgressTracker.new(ui_components)
          @status_manager = StatusManager.new(ui_components)

          # Legacy state variables
          @input_history = []
          @control_interface_enabled = true
          @pause_requested = false
          @stop_requested = false
          @resume_requested = false
        end

        # Legacy method compatibility
        def collect_feedback(questions, context = nil)
          @feedback_collector.collect_feedback(questions, context)
        end

        def get_user_input(prompt)
          # Simple text input - can be enhanced with CLI UI
          print "#{prompt}: "
          input = gets.chomp
          @input_history << input
          input
        end

        def get_confirmation(message, default: true)
          default_text = default ? "Y/n" : "y/N"
          response = get_user_input("#{message} [#{default_text}]")

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

        def get_choice(message, options, default: nil)
          CLI::UI.puts(message)
          options.each_with_index do |option, index|
            CLI::UI.puts("#{index + 1}. #{option}")
          end

          response = get_user_input("Select an option")
          index = response.to_i - 1

          if index >= 0 && index < options.length
            options[index]
          elsif default
            default
          else
            get_choice(message, options, default: default)
          end
        end

        def show_progress(message)
          @status_manager.show_info_status(message)
        end

        def clear_progress
          # CLI UI handles this automatically
        end

        def input_history
          @input_history.dup
        end

        def clear_history
          @input_history.clear
        end

        def show_help
          display_help_menu
        end

        # Control interface compatibility
        def pause_requested?
          @pause_requested
        end

        def stop_requested?
          @stop_requested
        end

        def resume_requested?
          @resume_requested
        end

        def request_pause
          @pause_requested = true
        end

        def request_stop
          @stop_requested = true
        end

        def request_resume
          @resume_requested = true
        end

        def clear_control_requests
          @pause_requested = false
          @stop_requested = false
          @resume_requested = false
        end

        def enable_control_interface
          @control_interface_enabled = true
        end

        def disable_control_interface
          @control_interface_enabled = false
        end

        def control_interface_enabled?
          @control_interface_enabled
        end

        # File selection compatibility
        def find_files(search_term)
          @file_selector.find_files_by_pattern(search_term)
        end

        def get_file_selection(max_files = 1)
          @file_selector.select_files(nil, max_files)
        end

        def show_file_preview(file_path)
          if File.exist?(file_path)
            CLI::UI.puts("📄 File: #{file_path}")
            CLI::UI.puts("Size: #{File.size(file_path)} bytes")
            CLI::UI.puts("Modified: #{File.mtime(file_path)}")
          else
            CLI::UI.puts("❌ File not found: #{file_path}")
          end
        end

        # Question validation compatibility
        def validate_input_type(input, expected_type, options = {})
          question = {
            type: expected_type,
            required: options[:required] || false,
            format: options[:format],
            options: options[:options],
            range: options[:range],
            length: options[:length]
          }

          result = @question_validator.validate(input, question)
          result[:valid]
        end

        # Progress tracking compatibility
        def display_question_progress(current_index, total_questions)
          percentage = (current_index.to_f / total_questions * 100).round(1)
          @status_manager.show_info_status("Progress: #{current_index}/#{total_questions} (#{percentage}%)")
        end

        def generate_progress_bar(percentage, width = 20)
          filled = (percentage / 100.0 * width).round
          bar = "█" * filled + "░" * (width - filled)
          "[#{bar}] #{percentage}%"
        end

        # Status display compatibility
        def show_success(message)
          @status_manager.show_success_status(message)
        end

        def show_error(message)
          @status_manager.show_error_status(message)
        end

        def show_warning(message)
          @status_manager.show_warning_status(message)
        end

        def show_info(message)
          @status_manager.show_info_status(message)
        end

        # Legacy method stubs for full compatibility
        def display_feedback_context(context)
          @feedback_collector.display_feedback_context(context)
        end

        def display_question_presentation_header(questions, context)
          @feedback_collector.display_feedback_header(questions, context)
        end

        def display_question_overview(questions)
          @feedback_collector.display_question_summary(questions)
        end

        def display_question_completion_summary(responses, questions)
          @feedback_collector.display_completion_summary(responses, questions)
        end

        def get_question_response(question_data, question_number)
          @question_validator.validate(question_data, {})
          # Return mock response for compatibility
          "mock_response_#{question_number}"
        end

        def handle_input_error(error, question_data, retry_count = 0)
          @status_manager.show_error_status("Input error: #{error.message}")
        end

        def show_question_help(question_data)
          CLI::UI.puts("Help: #{question_data[:help_text] || "No help available"}")
        end

        def display_validation_error(validation_result, input_type)
          @question_validator.display_validation_errors(validation_result[:errors], {})
        end

        def display_validation_warnings(validation_result)
          validation_result[:warnings]&.each do |warning|
            @status_manager.show_warning_status(warning)
          end
        end

        # Control interface methods
        def start_control_interface
          @control_interface_enabled = true
        end

        def stop_control_interface
          @control_interface_enabled = false
        end

        def wait_for_control_input
          # Simplified control input handling
          input = get_user_input("Control command (pause/stop/resume/help)")
          handle_control_command(input)
        end

        def handle_control_command(command)
          case command.downcase
          when "pause", "p"
            request_pause
          when "stop", "s"
            request_stop
          when "resume", "r"
            request_resume
          when "help", "h"
            show_control_help
          else
            CLI::UI.puts("Unknown command: #{command}")
          end
        end

        def show_control_help
          CLI::UI.puts("Control Commands:")
          CLI::UI.puts("  pause/p - Pause the workflow")
          CLI::UI.puts("  stop/s - Stop the workflow")
          CLI::UI.puts("  resume/r - Resume the workflow")
          CLI::UI.puts("  help/h - Show this help")
        end

        def get_control_status
          {
            pause_requested: @pause_requested,
            stop_requested: @stop_requested,
            resume_requested: @resume_requested,
            control_enabled: @control_interface_enabled
          }
        end

        def display_control_status
          status = get_control_status
          CLI::UI.puts("Control Status:")
          CLI::UI.puts("  Pause: #{status[:pause_requested] ? "Requested" : "No"}")
          CLI::UI.puts("  Stop: #{status[:stop_requested] ? "Requested" : "No"}")
          CLI::UI.puts("  Resume: #{status[:resume_requested] ? "Requested" : "No"}")
          CLI::UI.puts("  Interface: #{status[:control_enabled] ? "Enabled" : "Disabled"}")
        end

        private

        def display_help_menu
          CLI::UI.puts("AIDP CLI Help:")
          CLI::UI.puts("  This is the new CLI UI interface")
          CLI::UI.puts("  All existing functionality is maintained")
          CLI::UI.puts("  Enhanced with better visual feedback")
        end
      end
    end
  end
end
