# frozen_string_literal: true

require "tty-prompt"
require "pastel"
require_relative "question_collector"
require_relative "progress_display"
require_relative "status_widget"
require_relative "frame_manager"
require_relative "spinner_group"
require_relative "error_handler"
require_relative "navigation/main_menu"
require_relative "navigation/menu_item"
require_relative "navigation/workflow_selector"
require_relative "navigation/menu_state"

module Aidp
  module Harness
    module UI
      # New UserInterface class using TTY components
      class UserInterfaceNew
        class UIError < StandardError; end
        class FeedbackError < UIError; end
        class FileSelectionError < UIError; end

        def initialize(ui_components = {})
          @prompt = TTY::Prompt.new
          @pastel = Pastel.new
          @question_collector = ui_components[:question_collector] || QuestionCollector.new
          @progress_display = ui_components[:progress_display] || ProgressDisplay.new
          @status_widget = ui_components[:status_widget] || StatusWidget.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @spinner_group = ui_components[:spinner_group] || SpinnerGroup.new
          @error_handler = ui_components[:error_handler] || ErrorHandler.new
          @workflow_selector = ui_components[:workflow_selector] || Navigation::WorkflowSelector.new
          @menu_state = ui_components[:menu_state] || Navigation::MenuState.new

          @input_history = []
          @control_interface_enabled = true
          @pause_requested = false
          @stop_requested = false
          @resume_requested = false
        end

        # Main feedback collection method
        def collect_feedback(questions, context = nil)
          validate_questions(questions)

          @frame_manager.workflow_frame("Feedback Collection") do
            display_feedback_context(context) if context
            collect_questions_with_progress(questions)
          end
        rescue => e
          @error_handler.handle_feedback_error(e, context)
          raise FeedbackError, "Failed to collect feedback: #{e.message}"
        end

        # File selection with CLI UI
        def select_files(search_term = nil, max_files = 1)
          validate_file_selection_params(search_term, max_files)

          @frame_manager.section("File Selection") do
            files = find_files(search_term)
            display_file_selection_menu(files, max_files)
          end
        rescue => e
          @error_handler.handle_file_selection_error(e, search_term)
          raise FileSelectionError, "Failed to select files: #{e.message}"
        end

        # Progress tracking
        def show_progress(message)
          @status_widget.show_loading_status(message)
        end

        def update_progress(bar, message = nil)
          @progress_display.update_progress(bar, message)
        end

        def show_step_progress(step_name, total_substeps, &block)
          @progress_display.show_step_progress(step_name, total_substeps, &block)
        end

        # Status updates
        def show_success(message)
          @status_widget.show_success_status(message)
        end

        def show_error(message)
          @status_widget.show_error_status(message)
        end

        def show_warning(message)
          @status_widget.show_warning_status(message)
        end

        # Workflow control
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

        # Workflow mode selection
        def select_workflow_mode
          @workflow_selector.select_workflow_mode
        end

        # Input history management
        def input_history
          @input_history.dup
        end

        def clear_history
          @input_history.clear
        end

        # Control interface
        def enable_control_interface
          @control_interface_enabled = true
        end

        def disable_control_interface
          @control_interface_enabled = false
        end

        def control_interface_enabled?
          @control_interface_enabled
        end

        private

        def validate_questions(questions)
          raise FeedbackError, "Questions must be an array" unless questions.is_a?(Array)
          raise FeedbackError, "Questions array cannot be empty" if questions.empty?
        end

        def validate_file_selection_params(search_term, max_files)
          raise FileSelectionError, "Max files must be positive" unless max_files > 0
        end

        def display_feedback_context(context)
          @frame_manager.subsection("Context") do
            display_context_info(context)
          end
        end

          def display_context_info(context)
            @prompt.say("Type: #{context[:type]}") if context[:type]
            @prompt.say("Urgency: #{format_urgency(context[:urgency])}") if context[:urgency]
            @prompt.say("Description: #{context[:description]}") if context[:description]

            if context[:agent_output]
              @prompt.say("\nAgent Output:")
              @prompt.say(context[:agent_output])
            end
          end

        def format_urgency(urgency)
          urgency_emojis = {
            "high" => "🔴",
            "medium" => "🟡",
            "low" => "🟢"
          }
          emoji = urgency_emojis[urgency] || "ℹ️"
          "#{emoji} #{urgency.capitalize}"
        end

        def collect_questions_with_progress(questions)
          @progress_display.show_progress(questions.length) do |bar|
            responses = {}

            questions.each_with_index do |question, index|
              response = collect_single_question(question, index + 1)
              responses["question_#{index + 1}"] = response
              @progress_display.update_progress(bar, "Question #{index + 1}/#{questions.length}")
            end

            display_completion_summary(responses, questions)
            responses
          end
        end

        def collect_single_question(question, number)
          @frame_manager.step_frame(question[:text], number, 1) do
            @question_collector.collect_single_question(question, number)
          end
        end

        def display_completion_summary(responses, questions)
            @frame_manager.subsection("Completion Summary") do
              @prompt.say("✅ Collected #{responses.size} responses")
              @prompt.say("📊 Total questions: #{questions.length}")
            end
        end

        def find_files(search_term)
          # Simplified file finding - can be enhanced later
          return [] unless search_term

          Dir.glob("**/*#{search_term}*").first(10)
        end

        def display_file_selection_menu(files, max_files)
          if files.empty?
            @prompt.say("No files found matching the search term.")
            return []
          end

          @prompt.say("Found #{files.length} files:")
          files.each_with_index do |file, index|
            @prompt.say("#{index + 1}. #{file}")
          end

          # For now, return first file - can be enhanced with interactive selection
          [files.first]
        end
      end
    end
  end
end
