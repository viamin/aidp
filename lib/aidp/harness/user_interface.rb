# frozen_string_literal: true

require "tty-prompt"
require "tty-cursor"

module Aidp
  module Harness
    # Handles user interaction and feedback collection
    class UserInterface
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new)
        @input_history = []
        @file_selection_enabled = false
        @prompt = prompt
        @cursor = TTY::Cursor
        @control_mutex = Mutex.new
        @pause_requested = false
        @stop_requested = false
        @resume_requested = false
        @control_interface_enabled = false
        @control_thread = nil
      end

      private

      # Helper method to handle input consistently with TTY::Prompt
      # Fixed to avoid keystroke loss issues with TTY::Prompt's required validation
      def input_with_prompt(message, required: false, default: nil)
        loop do
          # Always use simple ask without built-in validation to avoid echo issues
          input = if default
            @prompt.ask("#{message} (default: #{default}): ")
          else
            @prompt.ask("#{message}: ")
          end

          # Handle empty input
          if input.nil? || input.strip.empty?
            if default
              return default
            elsif required
              display_message("❌ This field is required. Please provide a response.", type: :error)
              next
            else
              return nil
            end
          end

          return input.strip
        end
      end

      public

      def setup_control_interface
        @control_interface_enabled = true
        @pause_requested = false
        @stop_requested = false
        @resume_requested = false
        @control_thread = nil
        @control_mutex = Mutex.new
      end

      # Collect user feedback for a list of questions
      def collect_feedback(questions, context = nil)
        responses = {}

        # Display context if provided
        if context
          display_feedback_context(context)
        end

        # Display question presentation header
        display_question_presentation_header(questions, context)

        # Process questions with advanced presentation
        questions.each_with_index do |question_data, index|
          question_number = question_data[:number] || (index + 1)

          # Display question with advanced formatting
          display_numbered_question(question_data, question_number, index + 1, questions.length)

          # Get user response based on question type
          response = question_response(question_data, question_number)

          # Validate response if required
          if question_data[:required] != false && (response.nil? || response.to_s.strip.empty?)
            display_message("❌ This question is required. Please provide a response.", type: :error)
            redo
          end

          responses["question_#{question_number}"] = response

          # Show progress indicator
          display_question_progress(index + 1, questions.length)
        end

        # Display completion summary
        display_question_completion_summary(responses, questions)
        responses
      end

      # Display feedback context
      def display_feedback_context(context)
        display_message("\n📋 Context:", type: :highlight)
        display_message("-" * 30, type: :muted)

        if context[:type]
          display_message("Type: #{context[:type]}", type: :info)
        end

        if context[:urgency]
          urgency_emojis = {
            "high" => "🔴",
            "medium" => "🟡",
            "low" => "🟢"
          }
          urgency_emoji = urgency_emojis[context[:urgency]] || "ℹ️"
          display_message("Urgency: #{urgency_emoji} #{context[:urgency].capitalize}", type: :info)
        end

        if context[:description]
          display_message("Description: #{context[:description]}", type: :info)
        end

        if context[:agent_output]
          display_message("\nAgent Output:", type: :info)
          display_message(context[:agent_output], type: :info)
        end
      end

      # Display question presentation header
      def display_question_presentation_header(questions, context)
        display_message("\n🤖 Agent needs your feedback:", type: :highlight)
        display_message("=" * 60, type: :muted)

        # Display question overview
        display_question_overview(questions)

        # Display context summary if available
        if context
          display_context_summary(context)
        end

        display_message("\n📝 Questions to answer:", type: :info)
        display_message("-" * 40, type: :muted)
      end

      # Display question overview
      def display_question_overview(questions)
        total_questions = questions.length
        required_questions = questions.count { |q| q[:required] != false }
        optional_questions = total_questions - required_questions

        question_types = questions.map { |q| q[:type] || "text" }.uniq

        display_message("📊 Overview:", type: :info)
        display_message("  Total questions: #{total_questions}", type: :info)
        display_message("  Required: #{required_questions}", type: :info)
        display_message("  Optional: #{optional_questions}", type: :info)
        display_message("  Question types: #{question_types.join(", ")}", type: :info)

        # Estimate completion time
        estimated_time = estimate_completion_time(questions)
        display_message("  Estimated time: #{estimated_time}", type: :info)
      end

      # Display context summary
      def display_context_summary(context)
        display_message("\n📋 Context Summary:", type: :info)

        if context[:type]
          display_message("  Type: #{context[:type]}", type: :info)
        end

        if context[:urgency]
          urgency_emojis = {
            "high" => "🔴",
            "medium" => "🟡",
            "low" => "🟢"
          }
          urgency_emoji = urgency_emojis[context[:urgency]] || "ℹ️"
          display_message("  Urgency: #{urgency_emoji} #{context[:urgency].capitalize}", type: :info)
        end

        if context[:description]
          display_message("  Description: #{context[:description]}", type: :info)
        end
      end

      # Estimate completion time for questions
      def estimate_completion_time(questions)
        total_time = 0

        questions.each do |question|
          question_type = question[:type] || "text"

          total_time += case question_type
          when "text"
            30 # 30 seconds for text input
          when "choice"
            15 # 15 seconds for choice selection
          when "confirmation"
            10 # 10 seconds for yes/no
          when "file"
            45 # 45 seconds for file selection
          when "number"
            20 # 20 seconds for number input
          when "email"
            25 # 25 seconds for email input
          when "url"
            30 # 30 seconds for URL input
          else
            30 # Default 30 seconds
          end
        end

        if total_time < 60
          "#{total_time} seconds"
        else
          minutes = (total_time / 60.0).round(1)
          "#{minutes} minutes"
        end
      end

      # Display numbered question with advanced formatting
      def display_numbered_question(question_data, question_number, _current_index, total_questions)
        question_text = question_data[:question]
        question_type = question_data[:type] || "text"
        expected_input = question_data[:expected_input] || "text"
        options = question_data[:options]
        default_value = question_data[:default]
        required = question_data[:required] != false

        # Display question header
        display_message("\n" + "=" * 60, type: :muted)
        display_message("📝 Question #{question_number} of #{total_questions}", type: :highlight)
        display_message("=" * 60, type: :muted)

        # Display question text with formatting
        display_question_text(question_text, question_type)

        # Display question metadata
        display_question_metadata(question_type, expected_input, options, default_value, required)

        # Display question instructions
        display_question_instructions(question_type, options, default_value, required)

        display_message("\n" + "-" * 60, type: :muted)
      end

      # Display question text with formatting
      def display_question_text(question_text, question_type)
        # Get question type emoji
        type_emojis = {
          "text" => "📝",
          "choice" => "🔘",
          "confirmation" => "✅",
          "file" => "📁",
          "number" => "🔢",
          "email" => "📧",
          "url" => "🔗"
        }
        type_emoji = type_emojis[question_type] || "❓"

        display_message("#{type_emoji} #{question_text}", type: :info)
      end

      # Display question metadata
      def display_question_metadata(question_type, expected_input, options, default_value, required)
        display_message("\n📋 Question Details:", type: :info)

        # Question type
        display_message("  Type: #{question_type.capitalize}", type: :info)

        # Expected input
        if expected_input != "text"
          display_message("  Expected input: #{expected_input}", type: :info)
        end

        # Options
        if options && !options.empty?
          display_message("  Options: #{options.length} available", type: :info)
        end

        # Default value
        if default_value
          display_message("  Default: #{default_value}", type: :info)
        end

        # Required status
        status = required ? "Required" : "Optional"
        status_emoji = required ? "🔴" : "🟢"
        display_message("  Status: #{status_emoji} #{status}", type: :info)
      end

      # Display question instructions
      def display_question_instructions(question_type, options, default_value, required)
        display_message("\n💡 Instructions:", type: :info)

        case question_type
        when "text"
          display_message("  • Enter your text response", type: :info)
          display_message("  • Use @ for file selection if needed", type: :info)
          display_message("  • Press Enter when done", type: :info)
        when "choice"
          display_message("  • Select from the numbered options below", type: :info)
          display_message("  • Enter the number of your choice", type: :info)
          display_message("  • Press Enter to confirm", type: :info)
        when "confirmation"
          display_message("  • Enter 'y' or 'yes' for Yes", type: :info)
          display_message("  • Enter 'n' or 'no' for No", type: :info)
          display_message("  • Press Enter for default", type: :info)
        when "file"
          display_message("  • Enter file path directly", type: :info)
          display_message("  • Use @ to browse and select files", type: :info)
          display_message("  • File must exist and be readable", type: :info)
        when "number"
          display_message("  • Enter a valid number", type: :info)
          display_message("  • Use decimal point for decimals", type: :info)
          display_message("  • Press Enter when done", type: :info)
        when "email"
          display_message("  • Enter a valid email address", type: :info)
          display_message("  • Format: user@domain.com", type: :info)
          display_message("  • Press Enter when done", type: :info)
        when "url"
          display_message("  • Enter a valid URL", type: :info)
          display_message("  • Format: https://example.com", type: :info)
          display_message("  • Press Enter when done", type: :info)
        end

        # Additional instructions based on options
        if options && !options.empty?
          display_message("\n📋 Available Options:", type: :info)
          options.each_with_index do |option, index|
            marker = (default_value && option == default_value) ? " (default)" : ""
            display_message("  #{index + 1}. #{option}#{marker}", type: :info)
          end
        end

        # Default value instructions
        if default_value
          display_message("\n⚡ Quick Answer:", type: :info)
          display_message("  • Press Enter to use default: #{default_value}", type: :info)
        end

        # Required field instructions
        if required
          display_message("\n⚠️  Required Field:", type: :info)
          display_message("  • This question must be answered", type: :info)
          display_message("  • Cannot be left blank", type: :info)
        else
          display_message("\n✅ Optional Field:", type: :info)
          display_message("  • This question can be skipped", type: :info)
          display_message("  • Press Enter to leave blank", type: :info)
        end
      end

      # Display question progress
      def display_question_progress(current_index, total_questions)
        progress_percentage = (current_index.to_f / total_questions * 100).round(1)
        progress_bar = generate_progress_bar(progress_percentage)

        display_message("\n📊 Progress: #{progress_bar} #{progress_percentage}% (#{current_index}/#{total_questions})", type: :info)

        # Show estimated time remaining
        if current_index < total_questions
          remaining_questions = total_questions - current_index
          estimated_remaining = estimate_remaining_time(remaining_questions)
          display_message("⏱️  Estimated time remaining: #{estimated_remaining}", type: :info)
        end
      end

      # Generate progress bar
      def generate_progress_bar(percentage, width = 20)
        filled = (percentage / 100.0 * width).round
        empty = width - filled

        "[" + "█" * filled + "░" * empty + "]"
      end

      # Estimate remaining time
      def estimate_remaining_time(remaining_questions)
        # Assume average 25 seconds per question
        total_seconds = remaining_questions * 25

        if total_seconds < 60
          "#{total_seconds} seconds"
        else
          minutes = (total_seconds / 60.0).round(1)
          "#{minutes} minutes"
        end
      end

      # Display question completion summary
      def display_question_completion_summary(responses, questions)
        display_message("\n" + "=" * 60, type: :muted)
        display_message("✅ Question Completion Summary", type: :success)
        display_message("=" * 60, type: :muted)

        # Show completion statistics
        total_questions = questions.length
        answered_questions = responses.values.count { |v| !v.nil? && !v.to_s.strip.empty? }
        skipped_questions = total_questions - answered_questions

        display_message("📊 Statistics:", type: :info)
        display_message("  Total questions: #{total_questions}", type: :info)
        display_message("  Answered: #{answered_questions}", type: :info)
        display_message("  Skipped: #{skipped_questions}", type: :info)
        display_message("  Completion rate: #{(answered_questions.to_f / total_questions * 100).round(1)}%", type: :info)

        # Show response summary
        display_message("\n📝 Response Summary:", type: :info)
        responses.each do |key, value|
          question_number = key.gsub("question_", "")
          if value.nil? || value.to_s.strip.empty?
            display_message("  #{question_number}. [Skipped]", type: :muted)
          else
            display_value = (value.to_s.length > 50) ? "#{value.to_s[0..47]}..." : value.to_s
            display_message("  #{question_number}. #{display_value}", type: :info)
          end
        end

        display_message("\n🚀 Continuing execution...", type: :success)
      end

      # Display question information (legacy method for compatibility)
      def display_question_info(question_type, expected_input, options, default_value, required)
        info_parts = []

        # Question type
        type_emojis = {
          "text" => "📝",
          "choice" => "🔘",
          "confirmation" => "✅",
          "file" => "📁",
          "number" => "🔢",
          "email" => "📧",
          "url" => "🔗"
        }
        type_emoji = type_emojis[question_type] || "❓"
        info_parts << "#{type_emoji} #{question_type.capitalize}"

        # Expected input type
        if expected_input != "text"
          info_parts << "Expected: #{expected_input}"
        end

        # Options
        if options && !options.empty?
          info_parts << "Options: #{options.join(", ")}"
        end

        # Default value
        if default_value
          info_parts << "Default: #{default_value}"
        end

        # Required status
        info_parts << if required
          "Required: Yes"
        else
          "Required: No"
        end

        display_message("   #{info_parts.join(" | ")}", type: :info)
      end

      # Get response for a specific question with enhanced validation
      def question_response(question_data, _question_number)
        question_type = question_data[:type] || "text"
        expected_input = question_data[:expected_input] || "text"
        options = question_data[:options]
        default_value = question_data[:default]
        required = question_data[:required] != false
        validation_options = question_data[:validation_options] || {}

        case question_type
        when "text"
          text_response(expected_input, default_value, required, validation_options)
        when "choice"
          choice_response(options, default_value, required)
        when "confirmation"
          confirmation_response(default_value, required)
        when "file"
          file_response(expected_input, default_value, required, validation_options)
        when "number"
          number_response(expected_input, default_value, required, validation_options)
        when "email"
          email_response(default_value, required, validation_options)
        when "url"
          url_response(default_value, required, validation_options)
        else
          text_response(expected_input, default_value, required, validation_options)
        end
      end

      # Comprehensive error recovery system
      def handle_input_error(error, question_data, retry_count = 0)
        max_retries = 3

        display_message("\n🚨 Input Error:", type: :error)
        display_message("  #{error.message}", type: :error)

        if retry_count < max_retries
          display_message("\n🔄 Retry Options:", type: :info)
          display_message("  1. Try again", type: :info)
          display_message("  2. Skip this question", type: :info)
          display_message("  3. Get help", type: :info)
          display_message("  4. Cancel all questions", type: :info)

          choice = @prompt.select("Choose an option:", {
            "Try again" => "1",
            "Skip this question" => "2",
            "Get help" => "3",
            "Cancel all questions" => "4"
          })

          case choice
          when "1"
            display_message("🔄 Retrying...", type: :info)
            :retry
          when "2"
            display_message("⏭️  Skipping question...", type: :warning)
            :skip
          when "3"
            show_question_help(question_data)
            :retry
          when "4"
            display_message("❌ Cancelling all questions...", type: :error)
            :cancel
          else
            display_message("❌ Invalid choice. Retrying...", type: :error)
            :retry
          end
        else
          display_message("\n❌ Maximum retries exceeded. Skipping question...", type: :error)
          :skip
        end
      end

      # Show help for specific question
      def show_question_help(question_data)
        question_type = question_data[:type] || "text"

        display_message("\n📖 Help for #{question_type.capitalize} Question:", type: :info)
        display_message("=" * 50, type: :muted)

        case question_type
        when "text"
          display_message("• Enter any text response", type: :info)
          display_message("• Use @ for file selection if needed", type: :info)
          display_message("• Press Enter when done", type: :info)
        when "choice"
          display_message("• Select from the numbered options", type: :info)
          display_message("• Enter the number of your choice", type: :info)
          display_message("• Or type the option text directly", type: :info)
        when "confirmation"
          display_message("• Enter 'y' or 'yes' for Yes", type: :info)
          display_message("• Enter 'n' or 'no' for No", type: :info)
          display_message("• Press Enter for default", type: :info)
        when "file"
          display_message("• Enter file path directly", type: :info)
          display_message("• Use @ to browse and select files", type: :info)
          display_message("• File must exist and be readable", type: :info)
        when "number"
          display_message("• Enter a valid number", type: :info)
          display_message("• Use decimal point for decimals", type: :info)
          display_message("• Check range requirements", type: :info)
        when "email"
          display_message("• Enter a valid email address", type: :info)
          display_message("• Format: user@domain.com", type: :info)
          display_message("• Check for typos", type: :info)
        when "url"
          display_message("• Enter a valid URL", type: :info)
          display_message("• Format: https://example.com", type: :info)
          display_message("• Include protocol (http:// or https://)", type: :info)
        end

        display_message("\nPress Enter to continue...", type: :info)
        @prompt.keypress("Press any key to continue...")
      end

      # Enhanced error handling and validation display
      def display_validation_error(validation_result, _input_type)
        display_message("\n❌ Validation Error:", type: :error)
        display_message("  #{validation_result[:error_message]}", type: :error)

        if validation_result[:suggestions].any?
          display_message("\n💡 Suggestions:", type: :info)
          validation_result[:suggestions].each do |suggestion|
            display_message("  • #{suggestion}", type: :info)
          end
        end

        if validation_result[:warnings].any?
          display_message("\n⚠️  Warnings:", type: :warning)
          validation_result[:warnings].each do |warning|
            display_message("  • #{warning}", type: :warning)
          end
        end

        display_message("\n🔄 Please try again...", type: :info)
      end

      # Display validation warnings
      def display_validation_warnings(validation_result)
        if validation_result[:warnings].any?
          display_message("\n⚠️  Warnings:", type: :warning)
          validation_result[:warnings].each do |warning|
            display_message("  • #{warning}", type: :warning)
          end
          display_message("\nPress Enter to continue or type 'fix' to correct...", type: :info)

          input = @prompt.ask("")
          return input&.strip&.downcase == "fix"
        end
        false
      end

      # Get text response with enhanced validation
      def text_response(expected_input, default_value, required, options = {})
        prompt = "Your response"
        prompt += " (default: #{default_value})" if default_value
        prompt_text = prompt + (required ? "" : " (optional)")

        loop do
          input = input_with_prompt(prompt_text, required: required, default: default_value)

          # get_input_with_prompt already handles required validation and returns non-empty input
          # Only validate the type/format if we got input
          if input.nil?
            # This should only happen for non-required fields
            return nil
          end

          # Enhanced validation
          validation_result = validate_input_type(input.strip, expected_input, options)

          unless validation_result[:valid]
            display_validation_error(validation_result, expected_input)
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          return input.strip
        end
      end

      # Get choice response with enhanced validation
      def choice_response(options, default_value, required)
        return nil if options.nil? || options.empty?

        display_message("\n   Available options:", type: :info)
        options.each_with_index do |option, index|
          marker = (default_value && option == default_value) ? " (default)" : ""
          display_message("     #{index + 1}. #{option}#{marker}", type: :info)
        end

        loop do
          prompt = "Your choice (1-#{options.size})"
          prompt += " (default: #{default_value})" if default_value
          prompt += required ? ": " : " (optional): "

          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              display_message("❌ Please make a selection.", type: :error)
              next
            else
              return nil
            end
          end

          # Enhanced validation for choice
          validation_result = validate_input_type(input.strip, "choice", {choices: options})

          unless validation_result[:valid]
            display_validation_error(validation_result, "choice")
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          # Parse the choice
          choice = input.strip
          if choice.match?(/\A\d+\z/)
            return options[choice.to_i - 1]
          else
            return choice
          end
        end
      end

      # Get confirmation response with enhanced validation
      def confirmation_response(default_value, required)
        default = default_value.nil? || default_value
        default_text = default ? "Y/n" : "y/N"
        prompt = "Your response [#{default_text}]"
        prompt += required ? ": " : " (optional): "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            return default
          end

          # Enhanced validation for boolean
          validation_result = validate_input_type(input.strip, "boolean")

          unless validation_result[:valid]
            display_validation_error(validation_result, "boolean")
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          response = input.strip.downcase
          case response
          when "y", "yes", "true", "1"
            return true
          when "n", "no", "false", "0"
            return false
          end
        end
      end

      # Get file response with enhanced validation
      def file_response(_expected_input, default_value, required, options = {})
        prompt = "File path"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              display_message("❌ Please provide a file path.", type: :error)
              next
            else
              return nil
            end
          end

          # Handle file selection with @ character
          if input.strip.start_with?("@")
            file_path = handle_file_selection(input.strip)
            return file_path if file_path
          else
            # Enhanced validation for file path
            validation_result = validate_input_type(input.strip, "file", options)

            unless validation_result[:valid]
              display_validation_error(validation_result, "file")
              next
            end

            # Check for warnings
            if display_validation_warnings(validation_result)
              next
            end

            return input.strip
          end
        end
      end

      # Get number response with enhanced validation
      def number_response(expected_input, default_value, required, options = {})
        prompt = "Number"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              display_message("❌ Please provide a number.", type: :error)
              next
            else
              return nil
            end
          end

          # Enhanced validation for numbers
          validation_result = validate_input_type(input.strip, expected_input, options)

          unless validation_result[:valid]
            display_validation_error(validation_result, expected_input)
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          # Parse the number
          begin
            if expected_input == "integer"
              return Integer(input.strip)
            else
              return Float(input.strip)
            end
          rescue ArgumentError
            display_message("❌ Please enter a valid #{expected_input}.", type: :error)
            next
          end
        end
      end

      # Get email response with enhanced validation
      def email_response(default_value, required, options = {})
        prompt = "Email address"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              display_message("❌ Please provide an email address.", type: :error)
              next
            else
              return nil
            end
          end

          # Enhanced validation for email
          validation_result = validate_input_type(input.strip, "email", options)

          unless validation_result[:valid]
            display_validation_error(validation_result, "email")
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          return input.strip
        end
      end

      # Get URL response with enhanced validation
      def url_response(default_value, required, options = {})
        prompt = "URL"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              display_message("❌ Please provide a URL.", type: :error)
              next
            else
              return nil
            end
          end

          # Enhanced validation for URL
          validation_result = validate_input_type(input.strip, "url", options)

          unless validation_result[:valid]
            display_validation_error(validation_result, "url")
            next
          end

          # Check for warnings
          if display_validation_warnings(validation_result)
            next
          end

          return input.strip
        end
      end

      # Comprehensive input validation system
      def validate_input_type(input, expected_type, options = {})
        case expected_type
        when "email"
          validate_email(input, options)
        when "url"
          validate_url(input, options)
        when "number", "integer"
          validate_number(input, options)
        when "float", "decimal"
          validate_float(input, options)
        when "boolean"
          validate_boolean(input, options)
        when "file", "path"
          validate_file_path(input, options)
        when "text"
          validate_text(input, options)
        when "choice"
          validate_choice(input, options)
        else
          validate_generic(input, options)
        end
      end

      # Validate email input
      def validate_email(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        # Basic email regex
        email_regex = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "Email address cannot be empty"
          else
            result[:valid] = true
          end
          return result
        end

        if !email_regex.match?(input.strip)
          result[:error_message] = "Invalid email format"
          result[:suggestions] = [
            "Use format: user@domain.com",
            "Check for typos in domain name",
            "Ensure @ symbol is present"
          ]
          return result
        end

        # Additional validations
        email = input.strip.downcase
        local_part, domain = email.split("@")

        # Check local part length
        if local_part.length > 64
          result[:warnings] << "Local part is very long (#{local_part.length} characters)"
        end

        # Check domain length
        if domain.length > 253
          result[:warnings] << "Domain is very long (#{domain.length} characters)"
        end

        # Check for common typos
        common_domains = %w[gmail.com yahoo.com hotmail.com outlook.com]
        if common_domains.any? { |d| domain.include?(d) && domain != d }
          result[:suggestions] << "Did you mean #{domain.gsub(/[^a-z.]/, "")}?"
        end

        result[:valid] = true
        result
      end

      # Validate URL input
      def validate_url(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "URL cannot be empty"
          else
            result[:valid] = true
          end
          return result
        end

        url = input.strip

        # Basic URL regex
        url_regex = /\Ahttps?:\/\/.+/i

        if !url_regex.match?(url)
          result[:error_message] = "Invalid URL format"
          result[:suggestions] = [
            "Use format: https://example.com",
            "Include http:// or https:// protocol",
            "Check for typos in domain name"
          ]
          return result
        end

        # Additional validations
        begin
          uri = URI.parse(url)

          # Check for valid hostname
          if uri.host.nil? || uri.host.empty?
            result[:error_message] = "Invalid hostname in URL"
            return result
          end

          # Check for common typos
          if uri.host.include?("www.") && !uri.host.start_with?("www.")
            result[:suggestions] << "Consider using www.#{uri.host}"
          end

          # Check for HTTP vs HTTPS
          if uri.scheme == "http" && !uri.host.include?("localhost")
            result[:warnings] << "Consider using HTTPS for security"
          end
        rescue URI::InvalidURIError
          result[:error_message] = "Invalid URL format"
          result[:suggestions] = [
            "Check for special characters",
            "Ensure proper URL encoding",
            "Verify domain name spelling"
          ]
          return result
        end

        result[:valid] = true
        result
      end

      # Validate number input
      def validate_number(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          result[:error_message] = "Number cannot be empty"
          return result
        end

        number_str = input.strip

        # Check for valid integer format
        if !number_str.match?(/\A-?\d+\z/)
          result[:error_message] = "Invalid number format"
          result[:suggestions] = [
            "Enter a whole number (e.g., 25, -10, 0)",
            "Remove any decimal points or letters",
            "Check for typos"
          ]
          return result
        end

        number = number_str.to_i

        # Range validation
        if options[:min] && number < options[:min]
          result[:error_message] = "Number must be at least #{options[:min]}"
          return result
        end

        if options[:max] && number > options[:max]
          result[:error_message] = "Number must be at most #{options[:max]}"
          return result
        end

        # Warning for very large numbers
        if number.abs > 1_000_000
          result[:warnings] << "Very large number (#{number})"
        end

        result[:valid] = true
        result
      end

      # Validate float input
      def validate_float(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          result[:error_message] = "Number cannot be empty"
          return result
        end

        number_str = input.strip

        # Check for valid float format
        if !number_str.match?(/\A-?\d+(?:\.\d+)?\z/)
          result[:error_message] = "Invalid number format"
          result[:suggestions] = [
            "Enter a number (e.g., 25, 3.14, -10.5)",
            "Use decimal point for decimals",
            "Remove any letters or special characters"
          ]
          return result
        end

        number = number_str.to_f

        # Range validation
        if options[:min] && number < options[:min]
          result[:error_message] = "Number must be at least #{options[:min]}"
          return result
        end

        if options[:max] && number > options[:max]
          result[:error_message] = "Number must be at most #{options[:max]}"
          return result
        end

        # Precision validation
        if options[:precision] && number_str.include?(".")
          decimal_places = number_str.split(".")[1]&.length || 0
          if decimal_places > options[:precision]
            result[:warnings] << "Number has more decimal places than expected (#{decimal_places} > #{options[:precision]})"
          end
        end

        result[:valid] = true
        result
      end

      # Validate boolean input
      def validate_boolean(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "Please enter a yes/no response"
          else
            result[:valid] = true
          end
          return result
        end

        response = input.strip.downcase
        valid_responses = %w[y yes n no true false 1 0]

        if !valid_responses.include?(response)
          result[:error_message] = "Invalid response"
          result[:suggestions] = [
            "Enter 'y' or 'yes' for Yes",
            "Enter 'n' or 'no' for No",
            "Enter 'true' or 'false'",
            "Enter '1' for Yes or '0' for No"
          ]
          return result
        end

        result[:valid] = true
        result
      end

      # Validate file path input
      def validate_file_path(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          result[:error_message] = "File path cannot be empty"
          return result
        end

        file_path = input.strip

        # Check if file exists
        if !File.exist?(file_path)
          result[:error_message] = "File does not exist: #{file_path}"
          result[:suggestions] = [
            "Check the file path for typos",
            "Use @ to browse and select files",
            "Ensure the file exists in the specified location"
          ]
          return result
        end

        # Check if it's actually a file (not a directory)
        if !File.file?(file_path)
          result[:error_message] = "Path is not a file: #{file_path}"
          result[:suggestions] = [
            "Select a file, not a directory",
            "Use @ to browse files"
          ]
          return result
        end

        # Check file permissions
        if !File.readable?(file_path)
          result[:error_message] = "File is not readable: #{file_path}"
          result[:suggestions] = [
            "Check file permissions",
            "Ensure you have read access to the file"
          ]
          return result
        end

        # File size warning
        file_size = File.size(file_path)
        if file_size > 10 * 1024 * 1024 # 10MB
          result[:warnings] << "Large file size (#{format_file_size(file_size)})"
        end

        # File extension validation
        if options[:allowed_extensions]
          ext = File.extname(file_path).downcase
          if !options[:allowed_extensions].include?(ext)
            result[:warnings] << "Unexpected file extension: #{ext}"
            result[:suggestions] << "Expected extensions: #{options[:allowed_extensions].join(", ")}"
          end
        end

        result[:valid] = true
        result
      end

      # Validate text input
      def validate_text(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "Text input is required"
          else
            result[:valid] = true
          end
          return result
        end

        text = input.strip

        # Length validation
        if options[:min_length] && text.length < options[:min_length]
          result[:error_message] = "Text must be at least #{options[:min_length]} characters"
          return result
        end

        if options[:max_length] && text.length > options[:max_length]
          result[:error_message] = "Text must be at most #{options[:max_length]} characters"
          return result
        end

        # Pattern validation
        if options[:pattern] && !text.match?(options[:pattern])
          result[:error_message] = "Text does not match required pattern"
          result[:suggestions] = [
            "Check the format requirements",
            "Ensure all required characters are present"
          ]
          return result
        end

        # Content validation
        if options[:forbidden_words]&.any? { |word| text.downcase.include?(word.downcase) }
          result[:warnings] << "Text contains potentially inappropriate content"
        end

        result[:valid] = true
        result
      end

      # Validate choice input
      def validate_choice(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          result[:error_message] = "Please make a selection"
          return result
        end

        choice = input.strip

        # Check if it's a number selection
        if choice.match?(/\A\d+\z/)
          choice_num = choice.to_i
          if options[:choices] && (choice_num < 1 || choice_num > options[:choices].length)
            result[:error_message] = "Invalid selection number"
            result[:suggestions] = [
              "Enter a number between 1 and #{options[:choices].length}",
              "Available options: #{options[:choices].join(", ")}"
            ]
            return result
          end
        elsif options[:choices] && !options[:choices].include?(choice)
          # Check if it's a direct choice
          result[:error_message] = "Invalid choice"
          result[:suggestions] = [
            "Available options: #{options[:choices].join(", ")}",
            "Or enter the number of your choice"
          ]
          return result
        end

        result[:valid] = true
        result
      end

      # Validate generic input
      def validate_generic(input, options = {})
        result = {valid: false, error_message: nil, suggestions: [], warnings: []}

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "Input is required"
          else
            result[:valid] = true
          end
          return result
        end

        result[:valid] = true
        result
      end

      # Get user input with support for file selection
      def user_input(prompt)
        loop do
          input = @prompt.ask(prompt)

          # Handle empty input
          if input.nil? || input.strip.empty?
            display_message("Please provide a response.", type: :error)
            next
          end

          # Handle file selection with @ character
          if input.strip.start_with?("@")
            file_path = handle_file_selection(input.strip)
            return file_path if file_path
          else
            # Add to history and return
            @input_history << input.strip
            return input.strip
          end
        end
      end

      # Handle file selection interface
      def handle_file_selection(input)
        # Remove @ character and any following text
        search_term = input[1..].strip

        # Parse search options
        search_options = parse_file_search_options(search_term)

        # Get available files with advanced search
        available_files = find_files_advanced(search_options)

        if available_files.empty?
          display_message("No files found matching '#{search_options[:term]}'. Please try again.", type: :warning)
          display_message("💡 Try: @ (all files), @.rb (Ruby files), @config (files with 'config'), @lib/ (files in lib directory)", type: :info)
          return nil
        end

        # Display file selection menu with advanced features
        display_advanced_file_menu(available_files, search_options)

        # Get user selection with advanced options
        selection = advanced_file_selection(available_files.size, search_options)

        if selection && selection >= 0 && selection < available_files.size
          selected_file = available_files[selection]
          display_message("✅ Selected: #{selected_file}", type: :success)

          # Show file preview if requested
          if search_options[:preview]
            show_file_preview(selected_file)
          end

          selected_file
        elsif selection == -1
          # User wants to refine search
          handle_file_selection("@#{search_term}")
        else
          display_message("❌ Invalid selection. Please try again.", type: :error)
          nil
        end
      end

      # Parse file search options from search term
      def parse_file_search_options(search_term)
        options = {
          term: search_term,
          extensions: [],
          directories: [],
          patterns: [],
          preview: false,
          case_sensitive: false,
          max_results: 50
        }

        # Parse extension filters (e.g., .rb, .js, .py)
        if search_term.match?(/\.\w+$/)
          options[:extensions] = [search_term]
          options[:term] = ""
        end

        # Parse directory filters (e.g., lib/, spec/, app/)
        if search_term.match?(/^[^\/]+\/$/)
          options[:directories] = [search_term.chomp("/")]
          options[:term] = ""
        end

        # Parse pattern filters (e.g., config, test, spec)
        if search_term.match?(/^[a-zA-Z_][a-zA-Z0-9_]*$/)
          options[:patterns] = [search_term]
        end

        # Parse special options
        if search_term.include?("preview")
          options[:preview] = true
          options[:term] = options[:term].gsub("preview", "").strip
        end

        if search_term.include?("case")
          options[:case_sensitive] = true
          options[:term] = options[:term].gsub("case", "").strip
        end

        # Clean up multiple spaces
        options[:term] = options[:term].gsub(/\s+/, " ").strip

        options
      end

      # Find files with advanced search options
      def find_files_advanced(search_options)
        files = []

        # Determine search paths
        search_paths = determine_search_paths(search_options)

        search_paths.each do |path|
          next unless Dir.exist?(path)

          # Use appropriate glob pattern
          glob_pattern = build_glob_pattern(path, search_options)

          Dir.glob(glob_pattern).each do |file|
            next unless File.file?(file)

            # Apply filters
            if matches_filters?(file, search_options)
              files << file
            end
          end
        end

        # Sort and limit results
        files = sort_files(files, search_options)
        files.first(search_options[:max_results])
      end

      # Determine search paths based on options
      def determine_search_paths(search_options)
        if search_options[:directories].any?
          search_options[:directories]
        else
          [
            ".",
            "lib",
            "spec",
            "app",
            "src",
            "docs",
            "templates",
            "config",
            "test",
            "tests"
          ]
        end
      end

      # Build glob pattern for file search
      def build_glob_pattern(base_path, search_options)
        if search_options[:extensions].any?
          # Search for specific extensions
          extensions = search_options[:extensions].join(",")
          File.join(base_path, "**", "*{#{extensions}}")
        else
          # Search for all files
          File.join(base_path, "**", "*")
        end
      end

      # Check if file matches search filters
      def matches_filters?(file, search_options)
        filename = File.basename(file)
        filepath = file

        # Apply case sensitivity
        if search_options[:case_sensitive]
          filename_to_check = filename
          term_to_check = search_options[:term]
        else
          filename_to_check = filename.downcase
          term_to_check = search_options[:term]&.downcase
        end

        # Check term match
        if search_options[:term] && search_options[:term].empty?
          true
        elsif search_options[:patterns]&.any?
          # Check if any pattern matches
          search_options[:patterns].any? do |pattern|
            pattern_to_check = search_options[:case_sensitive] ? pattern : pattern.downcase
            filename_to_check.include?(pattern_to_check) || filepath.include?(pattern_to_check)
          end
        else
          # Simple term matching
          filename_to_check.include?(term_to_check) || filepath.include?(term_to_check)
        end
      end

      # Sort files by relevance and type
      def sort_files(files, search_options)
        files.sort_by do |file|
          filename = File.basename(file)
          ext = File.extname(file)

          # Priority scoring
          score = 0

          # Exact filename match gets highest priority
          if filename.downcase == search_options[:term].downcase
            score += 1000
          end

          # Filename starts with search term
          if filename.downcase.start_with?(search_options[:term].downcase)
            score += 500
          end

          # Filename contains search term
          if filename.downcase.include?(search_options[:term].downcase)
            score += 100
          end

          # File type priority
          case ext
          when ".rb"
            score += 50
          when ".js", ".ts"
            score += 40
          when ".py"
            score += 40
          when ".md"
            score += 30
          when ".yml", ".yaml"
            score += 30
          when ".json"
            score += 20
          end

          # Directory priority
          if file.include?("lib/")
            score += 25
          elsif file.include?("spec/") || file.include?("test/")
            score += 20
          elsif file.include?("config/")
            score += 15
          end

          # Shorter paths get slight priority
          score += (100 - file.length)

          [-score, file] # Negative for descending order
        end
      end

      # Find files matching search term (legacy method for compatibility)
      def find_files(search_term)
        search_options = parse_file_search_options(search_term)
        find_files_advanced(search_options)
      end

      # Display advanced file selection menu
      def display_advanced_file_menu(files, search_options)
        display_message("\n📁 Available files:", type: :info)
        display_message("Search: #{search_options[:term]} | Extensions: #{search_options[:extensions].join(", ")} | Directories: #{search_options[:directories].join(", ")}", type: :info)
        display_message("-" * 80, type: :muted)

        files.each_with_index do |file, index|
          file_info = get_file_info(file)
          display_message("  #{index + 1}. #{file_info[:display_name]}", type: :info)
          display_message("     📄 #{file_info[:size]} | 📅 #{file_info[:modified]} | 🏷️  #{file_info[:type]}", type: :muted)
        end

        display_message("\nOptions:", type: :info)
        display_message("  0. Cancel", type: :info)
        display_message("  -1. Refine search", type: :info)
        display_message("  p. Preview selected file", type: :info)
        display_message("  h. Show help", type: :info)
      end

      # Get file information for display
      def file_info(file)
        {
          display_name: file,
          size: format_file_size(File.size(file)),
          modified: File.mtime(file).strftime("%Y-%m-%d %H:%M"),
          type: file_type(file)
        }
      end

      # Format file size for display
      def format_file_size(size)
        if size < 1024
          "#{size} B"
        elsif size < 1024 * 1024
          "#{(size / 1024.0).round(1)} KB"
        else
          "#{(size / (1024.0 * 1024.0)).round(1)} MB"
        end
      end

      # Get file type for display
      def file_type(file)
        ext = File.extname(file)
        case ext
        when ".rb"
          "Ruby"
        when ".js"
          "JavaScript"
        when ".ts"
          "TypeScript"
        when ".py"
          "Python"
        when ".md"
          "Markdown"
        when ".yml", ".yaml"
          "YAML"
        when ".json"
          "JSON"
        when ".xml"
          "XML"
        when ".html", ".htm"
          "HTML"
        when ".css"
          "CSS"
        when ".scss", ".sass"
          "Sass"
        when ".sql"
          "SQL"
        when ".sh"
          "Shell"
        when ".txt"
          "Text"
        else
          ext.empty? ? "File" : ext[1..].upcase
        end
      end

      # Display file selection menu (legacy method for compatibility)
      def display_file_menu(files)
        display_advanced_file_menu(files, {term: "", extensions: [], directories: []})
      end

      # Get advanced file selection from user
      def advanced_file_selection(max_files, _search_options)
        loop do
          input = @prompt.ask("Select file (0-#{max_files}, -1=refine, p=preview, h=help): ")

          if input.nil? || input.strip.empty?
            display_message("Please enter a selection.", type: :error)
            next
          end

          input = input.strip.downcase

          # Handle special commands
          case input
          when "h", "help"
            show_file_selection_help
            next
          when "p", "preview"
            display_message("💡 Select a file number first, then use 'p' to preview it.", type: :info)
            next
          end

          begin
            selection = input.to_i
            if selection == 0
              return nil # Cancel
            elsif selection == -1
              return -1 # Refine search
            elsif selection.between?(1, max_files)
              return selection - 1 # Convert to 0-based index
            else
              display_message("Please enter a number between 0 and #{max_files}, or use -1, p, h.", type: :error)
            end
          rescue ArgumentError
            display_message("Please enter a valid number or command (0-#{max_files}, -1, p, h).", type: :error)
          end
        end
      end

      # Show file selection help
      def show_file_selection_help
        display_message("\n📖 File Selection Help:", type: :info)
        display_message("=" * 40, type: :muted)

        display_message("\n🔍 Search Examples:", type: :info)
        display_message("  @                    - Show all files", type: :info)
        display_message("  @.rb                 - Show Ruby files only", type: :info)
        display_message("  @config              - Show files with 'config' in name", type: :info)
        display_message("  @lib/                - Show files in lib directory", type: :info)
        display_message("  @spec preview        - Show spec files with preview option", type: :info)
        display_message("  @.js case            - Show JavaScript files (case sensitive)", type: :info)

        display_message("\n⌨️  Selection Commands:", type: :info)
        display_message("  1-50                 - Select file by number", type: :info)
        display_message("  0                    - Cancel selection", type: :info)
        display_message("  -1                   - Refine search", type: :info)
        display_message("  p                    - Preview selected file", type: :info)
        display_message("  h                    - Show this help", type: :info)

        display_message("\n💡 Tips:", type: :info)
        display_message("  • Files are sorted by relevance and type", type: :info)
        display_message("  • Use extension filters for specific file types", type: :info)
        display_message("  • Use directory filters to limit search scope", type: :info)
        display_message("  • Preview option shows file content before selection", type: :info)
      end

      # Show file preview
      def show_file_preview(file_path)
        display_message("\n📄 File Preview: #{file_path}", type: :highlight)
        display_message("=" * 60, type: :muted)

        begin
          content = File.read(file_path)
          lines = content.lines

          display_message("📊 File Info:", type: :info)
          display_message("  Size: #{format_file_size(File.size(file_path))}", type: :info)
          display_message("  Lines: #{lines.count}", type: :info)
          display_message("  Modified: #{File.mtime(file_path).strftime("%Y-%m-%d %H:%M:%S")}", type: :info)
          display_message("  Type: #{file_type(file_path)}", type: :info)

          display_message("\n📝 Content Preview (first 20 lines):", type: :info)
          display_message("-" * 40, type: :muted)

          lines.first(20).each_with_index do |line, index|
            display_message("#{(index + 1).to_s.rjust(3)}: #{line.chomp}", type: :info)
          end

          if lines.count > 20
            display_message("... (#{lines.count - 20} more lines)", type: :muted)
          end
        rescue => e
          display_message("❌ Error reading file: #{e.message}", type: :error)
        end

        display_message("\nPress Enter to continue...", type: :info)
        @prompt.keypress("Press any key to continue...")
      end

      # Get file selection from user (legacy method for compatibility)
      def file_selection(max_files)
        advanced_file_selection(max_files, {term: "", extensions: [], directories: []})
      end

      # Get confirmation from user
      def confirmation(message, default: true)
        default_text = default ? "Y/n" : "y/N"
        prompt = "#{message} [#{default_text}]: "

        loop do
          input = @prompt.ask(prompt)

          if input.nil? || input.strip.empty?
            return default
          end

          response = input.strip.downcase
          case response
          when "y", "yes"
            return true
          when "n", "no"
            return false
          else
            display_message("Please enter 'y' or 'n'.", type: :error)
          end
        end
      end

      # Get choice from multiple options
      def choice(message, options, default: nil)
        display_message("\n#{message}", type: :info)
        options.each_with_index do |option, index|
          marker = (default && index == default) ? " (default)" : ""
          display_message("  #{index + 1}. #{option}#{marker}", type: :info)
        end

        loop do
          input = @prompt.ask("Your choice (1-#{options.size}): ")

          if input.nil? || input.strip.empty?
            return default if default
            display_message("Please make a selection.", type: :error)
            next
          end

          begin
            choice = input.strip.to_i
            if choice.between?(1, options.size)
              return choice - 1 # Convert to 0-based index
            else
              display_message("Please enter a number between 1 and #{options.size}.", type: :error)
            end
          rescue ArgumentError
            display_message("Please enter a valid number.", type: :error)
          end
        end
      end

      # Display progress message
      def show_progress(message)
        print_to_stderr(@cursor.clear_line, @cursor.column(1), message)
      end

      # Clear progress message
      def clear_progress
        print_to_stderr(@cursor.clear_line, @cursor.column(1))
      end

      # Helper method to print to stderr with flush
      def print_to_stderr(*parts)
        parts.each { |part| $stderr.print part }
        $stderr.flush
      end

      # Get input history
      def input_history
        @input_history.dup
      end

      # Clear input history
      def clear_history
        @input_history.clear
      end

      # Display interactive help
      def show_help
        display_message("\n📖 Interactive Prompt Help:", type: :info)
        display_message("=" * 40, type: :info)

        display_message("\n🔤 Input Types:", type: :info)
        display_message("  • Text: Free-form text input", type: :info)
        display_message("  • Choice: Select from predefined options", type: :info)
        display_message("  • Confirmation: Yes/No questions", type: :info)
        display_message("  • File: File path with @ browsing", type: :info)
        display_message("  • Number: Integer or decimal numbers", type: :info)
        display_message("  • Email: Email address format", type: :info)
        display_message("  • URL: Web URL format", type: :info)

        display_message("\n⌨️  Special Commands:", type: :info)
        display_message("  • @: Browse and select files", type: :info)
        display_message("  • Enter: Use default value (if available)", type: :info)
        display_message("  • Ctrl+C: Cancel operation", type: :info)

        display_message("\n📁 File Selection:", type: :info)
        display_message("  • Type @ to browse files", type: :info)
        display_message("  • Type @search to filter files", type: :info)
        display_message("  • Select by number or type 0 to cancel", type: :info)

        display_message("\n✅ Validation:", type: :info)
        display_message("  • Required fields must be filled", type: :info)
        display_message("  • Input format is validated automatically", type: :info)
        display_message("  • Invalid input shows error and retries", type: :info)

        display_message("\n💡 Tips:", type: :info)
        display_message("  • Use Tab for auto-completion", type: :info)
        display_message("  • Arrow keys for history navigation", type: :info)
        display_message("  • Default values are shown in prompts", type: :info)
      end

      # Display question summary
      def display_question_summary(questions)
        display_message("\n📋 Question Summary:", type: :info)
        display_message("-" * 30, type: :info)

        questions.each_with_index do |question_data, index|
          question_number = question_data[:number] || (index + 1)
          question_text = question_data[:question]
          question_type = question_data[:type] || "text"
          required = question_data[:required] != false

          status = required ? "Required" : "Optional"
          type_emojis = {
            "text" => "📝",
            "choice" => "🔘",
            "confirmation" => "✅",
            "file" => "📁",
            "number" => "🔢",
            "email" => "📧",
            "url" => "🔗"
          }
          type_emoji = type_emojis[question_type] || "❓"

          display_message("  #{question_number}. #{type_emoji} #{question_text} (#{status})", type: :info)
        end
      end

      # Get user preferences for feedback collection
      def user_preferences
        display_message("\n⚙️  User Preferences:", type: :info)
        display_message("-" * 25, type: :muted)

        preferences = {}

        # Auto-confirm defaults
        preferences[:auto_confirm_defaults] = confirmation(
          "Auto-confirm default values without prompting?",
          default: false
        )

        # Show help automatically
        preferences[:show_help_automatically] = confirmation(
          "Show help automatically for new question types?",
          default: false
        )

        # Verbose mode
        preferences[:verbose_mode] = confirmation(
          "Enable verbose mode with detailed information?",
          default: true
        )

        # File browsing enabled
        preferences[:file_browsing_enabled] = confirmation(
          "Enable file browsing with @ character?",
          default: true
        )

        preferences
      end

      # Apply user preferences
      def apply_preferences(preferences)
        @auto_confirm_defaults = preferences[:auto_confirm_defaults] || false
        @show_help_automatically = preferences[:show_help_automatically] || false
        @verbose_mode = preferences[:verbose_mode] != false
        @file_selection_enabled = preferences[:file_browsing_enabled] != false
      end

      # Check if help should be shown
      def should_show_help?(question_type, seen_types)
        return false unless @show_help_automatically

        !seen_types.include?(question_type)
      end

      # Mark question type as seen
      def mark_question_type_seen(question_type, seen_types)
        seen_types << question_type
      end

      # Get feedback with preferences
      def collect_feedback_with_preferences(questions, context = nil, preferences = {})
        # Apply preferences
        apply_preferences(preferences)

        # Track seen question types
        seen_types = Set.new

        # Show help if needed
        if should_show_help?(questions.first&.dig(:type), seen_types)
          show_help
          display_message("\nPress Enter to continue...", type: :info)
          @prompt.keypress("Press any key to continue...")
        end

        # Display question summary if verbose
        if @verbose_mode
          display_question_summary(questions)
          display_message("\nPress Enter to start answering questions...", type: :info)
          @prompt.keypress("Press any key to continue...")
        end

        # Collect feedback
        responses = collect_feedback(questions, context)

        # Mark question types as seen
        questions.each do |question_data|
          mark_question_type_seen(question_data[:type] || "text", seen_types)
        end

        responses
      end

      # Get quick feedback for simple questions
      def quick_feedback(question, options = {})
        question_type = options[:type] || "text"
        default_value = options[:default]
        required = options[:required] != false

        display_message("\n❓ #{question}", type: :info)

        case question_type
        when "text"
          text_response("text", default_value, required)
        when "confirmation"
          confirmation_response(default_value, required)
        when "choice"
          choice_response(options[:options], default_value, required)
        else
          text_response("text", default_value, required)
        end
      end

      # Batch collect feedback for multiple simple questions
      def collect_batch_feedback(questions)
        responses = {}

        display_message("\n📝 Quick Feedback Collection:", type: :info)
        display_message("=" * 35, type: :muted)

        questions.each_with_index do |question_data, index|
          question_number = index + 1
          question_text = question_data[:question]
          question_type = question_data[:type] || "text"
          default_value = question_data[:default]
          required = question_data[:required] != false

          display_message("\n#{question_number}. #{question_text}", type: :info)

          response = quick_feedback(question_text, {
            type: question_type,
            default: default_value,
            required: required,
            options: question_data[:options]
          })

          responses["question_#{question_number}"] = response
        end

        display_message("\n✅ Batch feedback collected.", type: :success)
        responses
      end

      # ============================================================================
      # PAUSE/RESUME/STOP CONTROL INTERFACE
      # ============================================================================

      # Start the control interface
      def start_control_interface
        return unless @control_interface_enabled

        @control_mutex.synchronize do
          return if @control_thread&.alive?

          # Start control interface using Async (skip in test mode)
          unless ENV["RACK_ENV"] == "test" || defined?(RSpec)
            require "async"
            Async do |task|
              task.async { control_interface_loop }
            end
          end
        end

        display_message("\n🎮 Control Interface Started", type: :success)
        display_message("   Press 'p' + Enter to pause", type: :info)
        display_message("   Press 'r' + Enter to resume", type: :info)
        display_message("   Press 's' + Enter to stop", type: :info)
        display_message("   Press 'h' + Enter for help", type: :info)
        display_message("   Press 'q' + Enter to quit control interface", type: :info)
        display_message("=" * 50, type: :muted)
      end

      # Stop the control interface
      def stop_control_interface
        @control_mutex.synchronize do
          if @control_thread&.alive?
            @control_thread.kill
            @control_thread = nil
          end
        end

        display_message("\n🛑 Control Interface Stopped", type: :info)
      end

      # Check if pause is requested
      def pause_requested?
        @control_mutex.synchronize { !!@pause_requested }
      end

      # Check if stop is requested
      def stop_requested?
        @control_mutex.synchronize { !!@stop_requested }
      end

      # Check if resume is requested
      def resume_requested?
        @control_mutex.synchronize { !!@resume_requested }
      end

      # Request pause
      def request_pause
        @control_mutex.synchronize do
          @pause_requested = true
          @resume_requested = false
        end
        display_message("\n⏸️  Pause requested...", type: :warning)
      end

      # Request stop
      def request_stop
        @control_mutex.synchronize do
          @stop_requested = true
          @pause_requested = false
          @resume_requested = false
        end
        display_message("\n🛑 Stop requested...", type: :error)
      end

      # Request resume
      def request_resume
        @control_mutex.synchronize do
          @resume_requested = true
          @pause_requested = false
        end
        display_message("\n▶️  Resume requested...", type: :success)
      end

      # Clear all control requests
      def clear_control_requests
        @control_mutex.synchronize do
          @pause_requested = false
          @stop_requested = false
          @resume_requested = false
        end
      end

      # Wait for user control input
      def wait_for_control_input
        return unless @control_interface_enabled

        loop do
          if pause_requested?
            handle_pause_state
          elsif stop_requested?
            handle_stop_state
            break
          elsif resume_requested?
            handle_resume_state
            break
          elsif ENV["RACK_ENV"] == "test" || defined?(RSpec)
            sleep(0.1)
          else
            Async::Task.current.sleep(0.1)
          end
        end
      end

      # Handle pause state
      def handle_pause_state
        display_message("\n⏸️  HARNESS PAUSED", type: :warning)
        display_message("=" * 50, type: :muted)
        display_message("🎮 Control Options:", type: :info)
        display_message("   'r' + Enter: Resume execution", type: :info)
        display_message("   's' + Enter: Stop execution", type: :info)
        display_message("   'h' + Enter: Show help", type: :info)
        display_message("   'q' + Enter: Quit control interface", type: :info)
        display_message("=" * 50, type: :muted)

        loop do
          input = @prompt.ask("Paused>")

          case input&.strip&.downcase
          when "r", "resume"
            request_resume
            break
          when "s", "stop"
            request_stop
            break
          when "h", "help"
            show_control_help
          when "q", "quit"
            stop_control_interface
            break
          else
            display_message("❌ Invalid command. Type 'h' for help.", type: :error)
          end
        end
      end

      # Handle stop state
      def handle_stop_state
        display_message("\n🛑 HARNESS STOPPED", type: :error)
        display_message("=" * 50, type: :muted)
        display_message("Execution has been stopped by user request.", type: :info)
        display_message("You can restart the harness from where it left off.", type: :info)
        display_message("=" * 50, type: :muted)
      end

      # Handle resume state
      def handle_resume_state
        display_message("\n▶️  HARNESS RESUMED", type: :success)
        display_message("=" * 50, type: :muted)
        display_message("Execution has been resumed.", type: :info)
        display_message("=" * 50, type: :muted)
      end

      # Show control help
      def show_control_help
        display_message("\n📖 Control Interface Help", type: :info)
        display_message("=" * 50, type: :muted)
        display_message("🎮 Available Commands:", type: :info)
        display_message("   'p' or 'pause'    - Pause the harness execution", type: :info)
        display_message("   'r' or 'resume'   - Resume the harness execution", type: :info)
        display_message("   's' or 'stop'     - Stop the harness execution", type: :info)
        display_message("   'h' or 'help'     - Show this help message", type: :info)
        display_message("   'q' or 'quit'     - Quit the control interface", type: :info)
        display_message("", type: :info)
        display_message("📋 Control States:", type: :info)
        display_message("   Running  - Harness is executing normally", type: :info)
        display_message("   Paused   - Harness is paused, waiting for resume", type: :info)
        display_message("   Stopped  - Harness has been stopped by user", type: :info)
        display_message("   Resumed  - Harness has been resumed from pause", type: :info)
        display_message("", type: :info)
        display_message("💡 Tips:", type: :info)
        display_message("   • You can pause/resume/stop at any time during execution", type: :info)
        display_message("   • The harness will save its state when paused/stopped", type: :info)
        display_message("   • You can restart from where you left off", type: :info)
        display_message("   • Use 'h' for help at any time", type: :info)
        display_message("=" * 50, type: :muted)
      end

      # Control interface main loop
      def control_interface_loop
        loop do
          input = @prompt.ask("Control> ")

          case input&.strip&.downcase
          when "p", "pause"
            request_pause
          when "r", "resume"
            request_resume
          when "s", "stop"
            request_stop
          when "h", "help"
            show_control_help
          when "q", "quit"
            stop_control_interface
            break
          when ""
            # Empty input, continue
            next
          else
            display_message("❌ Invalid command. Type 'h' for help.", type: :error)
          end
        rescue Interrupt
          display_message("\n🛑 Control interface interrupted. Stopping...", type: :error)
          request_stop
          break
        rescue => e
          display_message("❌ Control interface error: #{e.message}", type: :error)
          display_message("   Type 'h' for help or 'q' to quit.", type: :info)
        end
      end

      # Check for control input during execution
      def check_control_input
        return unless @control_interface_enabled

        if pause_requested?
          handle_pause_state
        elsif stop_requested?
          handle_stop_state
          return :stop
        elsif resume_requested?
          handle_resume_state
          return :resume
        end

        nil
      end

      # Enable control interface
      def enable_control_interface
        @control_interface_enabled = true
        display_message("🎮 Control interface enabled", type: :success)
      end

      # Disable control interface
      def disable_control_interface
        @control_interface_enabled = false
        stop_control_interface
        display_message("🎮 Control interface disabled", type: :info)
      end

      # Get control status
      def control_status
        @control_mutex.synchronize do
          {
            enabled: !!@control_interface_enabled,
            pause_requested: !!@pause_requested,
            stop_requested: !!@stop_requested,
            resume_requested: !!@resume_requested,
            control_thread_alive: !!@control_thread&.alive?
          }
        end
      end

      # Display control status
      def display_control_status
        status = control_status

        display_message("\n🎮 Control Interface Status", type: :info)
        display_message("=" * 40, type: :muted)
        display_message("Enabled: #{status[:enabled] ? "✅ Yes" : "❌ No"}", type: :info)
        display_message("Pause Requested: #{status[:pause_requested] ? "⏸️  Yes" : "▶️  No"}", type: :info)
        display_message("Stop Requested: #{status[:stop_requested] ? "🛑 Yes" : "▶️  No"}", type: :info)
        display_message("Resume Requested: #{status[:resume_requested] ? "▶️  Yes" : "⏸️  No"}", type: :info)
        display_message("Control Thread: #{status[:control_thread_alive] ? "🟢 Active" : "🔴 Inactive"}", type: :info)
        display_message("=" * 40, type: :muted)
      end

      # Interactive control menu
      def show_control_menu
        display_message("\n🎮 Harness Control Menu", type: :info)
        display_message("=" * 50, type: :muted)
        display_message("1. Start Control Interface", type: :info)
        display_message("2. Stop Control Interface", type: :info)
        display_message("3. Pause Harness", type: :info)
        display_message("4. Resume Harness", type: :info)
        display_message("5. Stop Harness", type: :info)
        display_message("6. Show Control Status", type: :info)
        display_message("7. Show Help", type: :info)
        display_message("8. Exit Menu", type: :info)
        display_message("=" * 50, type: :muted)

        loop do
          choice = @prompt.ask("Select option (1-8): ")

          case choice&.strip
          when "1"
            start_control_interface
          when "2"
            stop_control_interface
          when "3"
            request_pause
          when "4"
            request_resume
          when "5"
            request_stop
          when "6"
            display_control_status
          when "7"
            show_control_help
          when "8"
            display_message("👋 Exiting control menu...", type: :info)
            break
          else
            display_message("❌ Invalid option. Please select 1-8.", type: :error)
          end
        end
      end

      # Quick control commands
      def quick_pause
        request_pause
        display_message("⏸️  Quick pause requested. Use 'r' to resume.", type: :warning)
      end

      def quick_resume
        request_resume
        display_message("▶️  Quick resume requested.", type: :success)
      end

      def quick_stop
        request_stop
        display_message("🛑 Quick stop requested.", type: :error)
      end

      # Control interface with timeout
      def control_interface_with_timeout(timeout_seconds = 30)
        return unless @control_interface_enabled

        start_time = Time.now

        loop do
          if pause_requested?
            handle_pause_state
          elsif stop_requested?
            handle_stop_state
            break
          elsif resume_requested?
            handle_resume_state
            break
          elsif Time.now - start_time > timeout_seconds
            display_message("\n⏰ Control interface timeout reached. Continuing execution...", type: :warning)
            break
          elsif ENV["RACK_ENV"] == "test" || defined?(RSpec)
            sleep(0.1)
          else
            Async::Task.current.sleep(0.1)
          end
        end
      end

      # Emergency stop
      def emergency_stop
        display_message("\n🚨 EMERGENCY STOP INITIATED", type: :error)
        display_message("=" * 50, type: :muted)
        display_message("All execution will be halted immediately.", type: :error)
        display_message("This action cannot be undone.", type: :error)
        display_message("=" * 50, type: :muted)

        @control_mutex.synchronize do
          @stop_requested = true
          @pause_requested = false
          @resume_requested = false
        end

        stop_control_interface
        display_message("🛑 Emergency stop completed.", type: :error)
      end
    end
  end
end
