# frozen_string_literal: true

require "readline"

module Aidp
  module Harness
    # Handles user interaction and feedback collection
    class UserInterface
      include Aidp::OutputHelper
      def initialize
        @input_history = []
        @file_selection_enabled = false
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
          response = get_question_response(question_data, question_number)

          # Validate response if required
          if question_data[:required] != false && (response.nil? || response.to_s.strip.empty?)
            puts "❌ This question is required. Please provide a response."
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
        puts "\n📋 Context:"
        puts "-" * 30

        if context[:type]
          puts "Type: #{context[:type]}"
        end

        if context[:urgency]
          urgency_emojis = {
            "high" => "🔴",
            "medium" => "🟡",
            "low" => "🟢"
          }
          urgency_emoji = urgency_emojis[context[:urgency]] || "ℹ️"
          puts "Urgency: #{urgency_emoji} #{context[:urgency].capitalize}"
        end

        if context[:description]
          puts "Description: #{context[:description]}"
        end

        if context[:agent_output]
          puts "\nAgent Output:"
          puts context[:agent_output]
        end
      end

      # Display question presentation header
      def display_question_presentation_header(questions, context)
        puts "\n🤖 Agent needs your feedback:"
        puts "=" * 60

        # Display question overview
        display_question_overview(questions)

        # Display context summary if available
        if context
          display_context_summary(context)
        end

        puts "\n📝 Questions to answer:"
        puts "-" * 40
      end

      # Display question overview
      def display_question_overview(questions)
        total_questions = questions.length
        required_questions = questions.count { |q| q[:required] != false }
        optional_questions = total_questions - required_questions

        question_types = questions.map { |q| q[:type] || "text" }.uniq

        puts "📊 Overview:"
        puts "  Total questions: #{total_questions}"
        puts "  Required: #{required_questions}"
        puts "  Optional: #{optional_questions}"
        puts "  Question types: #{question_types.join(", ")}"

        # Estimate completion time
        estimated_time = estimate_completion_time(questions)
        puts "  Estimated time: #{estimated_time}"
      end

      # Display context summary
      def display_context_summary(context)
        puts "\n📋 Context Summary:"

        if context[:type]
          puts "  Type: #{context[:type]}"
        end

        if context[:urgency]
          urgency_emojis = {
            "high" => "🔴",
            "medium" => "🟡",
            "low" => "🟢"
          }
          urgency_emoji = urgency_emojis[context[:urgency]] || "ℹ️"
          puts "  Urgency: #{urgency_emoji} #{context[:urgency].capitalize}"
        end

        if context[:description]
          puts "  Description: #{context[:description]}"
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
        puts "\n" + "=" * 60
        puts "📝 Question #{question_number} of #{total_questions}"
        puts "=" * 60

        # Display question text with formatting
        display_question_text(question_text, question_type)

        # Display question metadata
        display_question_metadata(question_type, expected_input, options, default_value, required)

        # Display question instructions
        display_question_instructions(question_type, options, default_value, required)

        puts "\n" + "-" * 60
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

        puts "#{type_emoji} #{question_text}"
      end

      # Display question metadata
      def display_question_metadata(question_type, expected_input, options, default_value, required)
        puts "\n📋 Question Details:"

        # Question type
        puts "  Type: #{question_type.capitalize}"

        # Expected input
        if expected_input != "text"
          puts "  Expected input: #{expected_input}"
        end

        # Options
        if options && !options.empty?
          puts "  Options: #{options.length} available"
        end

        # Default value
        if default_value
          puts "  Default: #{default_value}"
        end

        # Required status
        status = required ? "Required" : "Optional"
        status_emoji = required ? "🔴" : "🟢"
        puts "  Status: #{status_emoji} #{status}"
      end

      # Display question instructions
      def display_question_instructions(question_type, options, default_value, required)
        puts "\n💡 Instructions:"

        case question_type
        when "text"
          puts "  • Enter your text response"
          puts "  • Use @ for file selection if needed"
          puts "  • Press Enter when done"
        when "choice"
          puts "  • Select from the numbered options below"
          puts "  • Enter the number of your choice"
          puts "  • Press Enter to confirm"
        when "confirmation"
          puts "  • Enter 'y' or 'yes' for Yes"
          puts "  • Enter 'n' or 'no' for No"
          puts "  • Press Enter for default"
        when "file"
          puts "  • Enter file path directly"
          puts "  • Use @ to browse and select files"
          puts "  • File must exist and be readable"
        when "number"
          puts "  • Enter a valid number"
          puts "  • Use decimal point for decimals"
          puts "  • Press Enter when done"
        when "email"
          puts "  • Enter a valid email address"
          puts "  • Format: user@domain.com"
          puts "  • Press Enter when done"
        when "url"
          puts "  • Enter a valid URL"
          puts "  • Format: https://example.com"
          puts "  • Press Enter when done"
        end

        # Additional instructions based on options
        if options && !options.empty?
          puts "\n📋 Available Options:"
          options.each_with_index do |option, index|
            marker = (default_value && option == default_value) ? " (default)" : ""
            puts "  #{index + 1}. #{option}#{marker}"
          end
        end

        # Default value instructions
        if default_value
          puts "\n⚡ Quick Answer:"
          puts "  • Press Enter to use default: #{default_value}"
        end

        # Required field instructions
        if required
          puts "\n⚠️  Required Field:"
          puts "  • This question must be answered"
          puts "  • Cannot be left blank"
        else
          puts "\n✅ Optional Field:"
          puts "  • This question can be skipped"
          puts "  • Press Enter to leave blank"
        end
      end

      # Display question progress
      def display_question_progress(current_index, total_questions)
        progress_percentage = (current_index.to_f / total_questions * 100).round(1)
        progress_bar = generate_progress_bar(progress_percentage)

        puts "\n📊 Progress: #{progress_bar} #{progress_percentage}% (#{current_index}/#{total_questions})"

        # Show estimated time remaining
        if current_index < total_questions
          remaining_questions = total_questions - current_index
          estimated_remaining = estimate_remaining_time(remaining_questions)
          puts "⏱️  Estimated time remaining: #{estimated_remaining}"
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
        puts "\n" + "=" * 60
        puts "✅ Question Completion Summary"
        puts "=" * 60

        # Show completion statistics
        total_questions = questions.length
        answered_questions = responses.values.count { |v| !v.nil? && !v.to_s.strip.empty? }
        skipped_questions = total_questions - answered_questions

        puts "📊 Statistics:"
        puts "  Total questions: #{total_questions}"
        puts "  Answered: #{answered_questions}"
        puts "  Skipped: #{skipped_questions}"
        puts "  Completion rate: #{(answered_questions.to_f / total_questions * 100).round(1)}%"

        # Show response summary
        puts "\n📝 Response Summary:"
        responses.each do |key, value|
          question_number = key.gsub("question_", "")
          if value.nil? || value.to_s.strip.empty?
            puts "  #{question_number}. [Skipped]"
          else
            display_value = (value.to_s.length > 50) ? "#{value.to_s[0..47]}..." : value.to_s
            puts "  #{question_number}. #{display_value}"
          end
        end

        puts "\n🚀 Continuing execution..."
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

        puts "   #{info_parts.join(" | ")}"
      end

      # Get response for a specific question with enhanced validation
      def get_question_response(question_data, _question_number)
        question_type = question_data[:type] || "text"
        expected_input = question_data[:expected_input] || "text"
        options = question_data[:options]
        default_value = question_data[:default]
        required = question_data[:required] != false
        validation_options = question_data[:validation_options] || {}

        case question_type
        when "text"
          get_text_response(expected_input, default_value, required, validation_options)
        when "choice"
          get_choice_response(options, default_value, required)
        when "confirmation"
          get_confirmation_response(default_value, required)
        when "file"
          get_file_response(expected_input, default_value, required, validation_options)
        when "number"
          get_number_response(expected_input, default_value, required, validation_options)
        when "email"
          get_email_response(default_value, required, validation_options)
        when "url"
          get_url_response(default_value, required, validation_options)
        else
          get_text_response(expected_input, default_value, required, validation_options)
        end
      end

      # Comprehensive error recovery system
      def handle_input_error(error, question_data, retry_count = 0)
        max_retries = 3

        puts "\n🚨 Input Error:"
        puts "  #{error.message}"

        if retry_count < max_retries
          puts "\n🔄 Retry Options:"
          puts "  1. Try again"
          puts "  2. Skip this question"
          puts "  3. Get help"
          puts "  4. Cancel all questions"

          choice = Readline.readline("Your choice (1-4): ", true)

          case choice&.strip
          when "1"
            puts "🔄 Retrying..."
            :retry
          when "2"
            puts "⏭️  Skipping question..."
            :skip
          when "3"
            show_question_help(question_data)
            :retry
          when "4"
            puts "❌ Cancelling all questions..."
            :cancel
          else
            puts "❌ Invalid choice. Retrying..."
            :retry
          end
        else
          puts "\n❌ Maximum retries exceeded. Skipping question..."
          :skip
        end
      end

      # Show help for specific question
      def show_question_help(question_data)
        question_type = question_data[:type] || "text"

        puts "\n📖 Help for #{question_type.capitalize} Question:"
        puts "=" * 50

        case question_type
        when "text"
          puts "• Enter any text response"
          puts "• Use @ for file selection if needed"
          puts "• Press Enter when done"
        when "choice"
          puts "• Select from the numbered options"
          puts "• Enter the number of your choice"
          puts "• Or type the option text directly"
        when "confirmation"
          puts "• Enter 'y' or 'yes' for Yes"
          puts "• Enter 'n' or 'no' for No"
          puts "• Press Enter for default"
        when "file"
          puts "• Enter file path directly"
          puts "• Use @ to browse and select files"
          puts "• File must exist and be readable"
        when "number"
          puts "• Enter a valid number"
          puts "• Use decimal point for decimals"
          puts "• Check range requirements"
        when "email"
          puts "• Enter a valid email address"
          puts "• Format: user@domain.com"
          puts "• Check for typos"
        when "url"
          puts "• Enter a valid URL"
          puts "• Format: https://example.com"
          puts "• Include protocol (http:// or https://)"
        end

        puts "\nPress Enter to continue..."
        Readline.readline
      end

      # Enhanced error handling and validation display
      def display_validation_error(validation_result, _input_type)
        puts "\n❌ Validation Error:"
        puts "  #{validation_result[:error_message]}"

        if validation_result[:suggestions].any?
          puts "\n💡 Suggestions:"
          validation_result[:suggestions].each do |suggestion|
            puts "  • #{suggestion}"
          end
        end

        if validation_result[:warnings].any?
          puts "\n⚠️  Warnings:"
          validation_result[:warnings].each do |warning|
            puts "  • #{warning}"
          end
        end

        puts "\n🔄 Please try again..."
      end

      # Display validation warnings
      def display_validation_warnings(validation_result)
        if validation_result[:warnings].any?
          puts "\n⚠️  Warnings:"
          validation_result[:warnings].each do |warning|
            puts "  • #{warning}"
          end
          puts "\nPress Enter to continue or type 'fix' to correct..."

          input = Readline.readline("", true)
          return input&.strip&.downcase == "fix"
        end
        false
      end

      # Get text response with enhanced validation
      def get_text_response(expected_input, default_value, required, options = {})
        prompt = "Your response"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

          # Handle empty input
          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ This field is required. Please provide a response."
              next
            else
              return nil
            end
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
      def get_choice_response(options, default_value, required)
        return nil if options.nil? || options.empty?

        puts "\n   Available options:"
        options.each_with_index do |option, index|
          marker = (default_value && option == default_value) ? " (default)" : ""
          puts "     #{index + 1}. #{option}#{marker}"
        end

        loop do
          prompt = "Your choice (1-#{options.size})"
          prompt += " (default: #{default_value})" if default_value
          prompt += required ? ": " : " (optional): "

          input = Readline.readline(prompt, true)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ Please make a selection."
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
      def get_confirmation_response(default_value, required)
        default = default_value.nil? || default_value
        default_text = default ? "Y/n" : "y/N"
        prompt = "Your response [#{default_text}]"
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

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
      def get_file_response(_expected_input, default_value, required, options = {})
        prompt = "File path"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ Please provide a file path."
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
      def get_number_response(expected_input, default_value, required, options = {})
        prompt = "Number"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ Please provide a number."
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
            puts "❌ Please enter a valid #{expected_input}."
            next
          end
        end
      end

      # Get email response with enhanced validation
      def get_email_response(default_value, required, options = {})
        prompt = "Email address"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ Please provide an email address."
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
      def get_url_response(default_value, required, options = {})
        prompt = "URL"
        prompt += " (default: #{default_value})" if default_value
        prompt += required ? ": " : " (optional): "

        loop do
          input = Readline.readline(prompt, true)

          if input.nil? || input.strip.empty?
            if default_value
              return default_value
            elsif required
              puts "❌ Please provide a URL."
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
        email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

        if input.nil? || input.strip.empty?
          if options[:required]
            result[:error_message] = "Email address cannot be empty"
            return result
          else
            result[:valid] = true
            return result
          end
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
            return result
          else
            result[:valid] = true
            return result
          end
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
        if !number_str.match?(/\A-?\d+\.?\d*\z/)
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
            return result
          else
            result[:valid] = true
            return result
          end
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
            return result
          else
            result[:valid] = true
            return result
          end
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
        if options[:forbidden_words] && options[:forbidden_words].any? { |word| text.downcase.include?(word.downcase) }
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
            return result
          else
            result[:valid] = true
            return result
          end
        end

        result[:valid] = true
        result
      end

      # Get user input with support for file selection
      def get_user_input(prompt)
        loop do
          input = Readline.readline(prompt, true)

          # Handle empty input
          if input.nil? || input.strip.empty?
            puts "Please provide a response."
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
        search_term = input[1..-1].strip

        # Parse search options
        search_options = parse_file_search_options(search_term)

        # Get available files with advanced search
        available_files = find_files_advanced(search_options)

        if available_files.empty?
          puts "No files found matching '#{search_options[:term]}'. Please try again."
          puts "💡 Try: @ (all files), @.rb (Ruby files), @config (files with 'config'), @lib/ (files in lib directory)"
          return nil
        end

        # Display file selection menu with advanced features
        display_advanced_file_menu(available_files, search_options)

        # Get user selection with advanced options
        selection = get_advanced_file_selection(available_files.size, search_options)

        if selection && selection >= 0 && selection < available_files.size
          selected_file = available_files[selection]
          puts "✅ Selected: #{selected_file}"

          # Show file preview if requested
          if search_options[:preview]
            show_file_preview(selected_file)
          end

          selected_file
        elsif selection == -1
          # User wants to refine search
          handle_file_selection("@#{search_term}")
        else
          puts "❌ Invalid selection. Please try again."
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
        if search_options[:term]&.empty?
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
        puts "\n📁 Available files:"
        puts "Search: #{search_options[:term]} | Extensions: #{search_options[:extensions].join(", ")} | Directories: #{search_options[:directories].join(", ")}"
        puts "-" * 80

        files.each_with_index do |file, index|
          file_info = get_file_info(file)
          puts "  #{index + 1}. #{file_info[:display_name]}"
          puts "     📄 #{file_info[:size]} | 📅 #{file_info[:modified]} | 🏷️  #{file_info[:type]}"
        end

        puts "\nOptions:"
        puts "  0. Cancel"
        puts "  -1. Refine search"
        puts "  p. Preview selected file"
        puts "  h. Show help"
      end

      # Get file information for display
      def get_file_info(file)
        {
          display_name: file,
          size: format_file_size(File.size(file)),
          modified: File.mtime(file).strftime("%Y-%m-%d %H:%M"),
          type: get_file_type(file)
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
      def get_file_type(file)
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
          ext.empty? ? "File" : ext[1..-1].upcase
        end
      end

      # Display file selection menu (legacy method for compatibility)
      def display_file_menu(files)
        display_advanced_file_menu(files, {term: "", extensions: [], directories: []})
      end

      # Get advanced file selection from user
      def get_advanced_file_selection(max_files, _search_options)
        loop do
          input = Readline.readline("Select file (0-#{max_files}, -1=refine, p=preview, h=help): ", true)

          if input.nil? || input.strip.empty?
            puts "Please enter a selection."
            next
          end

          input = input.strip.downcase

          # Handle special commands
          case input
          when "h", "help"
            show_file_selection_help
            next
          when "p", "preview"
            puts "💡 Select a file number first, then use 'p' to preview it."
            next
          end

          begin
            selection = input.to_i
            if selection == 0
              return nil # Cancel
            elsif selection == -1
              return -1 # Refine search
            elsif selection >= 1 && selection <= max_files
              return selection - 1 # Convert to 0-based index
            else
              puts "Please enter a number between 0 and #{max_files}, or use -1, p, h."
            end
          rescue ArgumentError
            puts "Please enter a valid number or command (0-#{max_files}, -1, p, h)."
          end
        end
      end

      # Show file selection help
      def show_file_selection_help
        puts "\n📖 File Selection Help:"
        puts "=" * 40

        puts "\n🔍 Search Examples:"
        puts "  @                    - Show all files"
        puts "  @.rb                 - Show Ruby files only"
        puts "  @config              - Show files with 'config' in name"
        puts "  @lib/                - Show files in lib directory"
        puts "  @spec preview        - Show spec files with preview option"
        puts "  @.js case            - Show JavaScript files (case sensitive)"

        puts "\n⌨️  Selection Commands:"
        puts "  1-50                 - Select file by number"
        puts "  0                    - Cancel selection"
        puts "  -1                   - Refine search"
        puts "  p                    - Preview selected file"
        puts "  h                    - Show this help"

        puts "\n💡 Tips:"
        puts "  • Files are sorted by relevance and type"
        puts "  • Use extension filters for specific file types"
        puts "  • Use directory filters to limit search scope"
        puts "  • Preview option shows file content before selection"
      end

      # Show file preview
      def show_file_preview(file_path)
        puts "\n📄 File Preview: #{file_path}"
        puts "=" * 60

        begin
          content = File.read(file_path)
          lines = content.lines

          puts "📊 File Info:"
          puts "  Size: #{format_file_size(File.size(file_path))}"
          puts "  Lines: #{lines.count}"
          puts "  Modified: #{File.mtime(file_path).strftime("%Y-%m-%d %H:%M:%S")}"
          puts "  Type: #{get_file_type(file_path)}"

          puts "\n📝 Content Preview (first 20 lines):"
          puts "-" * 40

          lines.first(20).each_with_index do |line, index|
            puts "#{(index + 1).to_s.rjust(3)}: #{line.chomp}"
          end

          if lines.count > 20
            puts "... (#{lines.count - 20} more lines)"
          end
        rescue => e
          puts "❌ Error reading file: #{e.message}"
        end

        puts "\nPress Enter to continue..."
        Readline.readline
      end

      # Get file selection from user (legacy method for compatibility)
      def get_file_selection(max_files)
        get_advanced_file_selection(max_files, {term: "", extensions: [], directories: []})
      end

      # Get confirmation from user
      def get_confirmation(message, default: true)
        default_text = default ? "Y/n" : "y/N"
        prompt = "#{message} [#{default_text}]: "

        loop do
          input = Readline.readline(prompt, true)

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
            puts "Please enter 'y' or 'n'."
          end
        end
      end

      # Get choice from multiple options
      def get_choice(message, options, default: nil)
        puts "\n#{message}"
        options.each_with_index do |option, index|
          marker = (default && index == default) ? " (default)" : ""
          puts "  #{index + 1}. #{option}#{marker}"
        end

        loop do
          input = Readline.readline("Your choice (1-#{options.size}): ", true)

          if input.nil? || input.strip.empty?
            return default if default
            puts "Please make a selection."
            next
          end

          begin
            choice = input.strip.to_i
            if choice >= 1 && choice <= options.size
              return choice - 1 # Convert to 0-based index
            else
              puts "Please enter a number between 1 and #{options.size}."
            end
          rescue ArgumentError
            puts "Please enter a valid number."
          end
        end
      end

      # Display progress message
      def show_progress(message)
        print "\r#{message}".ljust(80)
        $stdout.flush
      end

      # Clear progress message
      def clear_progress
        print "\r" + " " * 80 + "\r"
        $stdout.flush
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
        puts "\n📖 Interactive Prompt Help:"
        puts "=" * 40

        puts "\n🔤 Input Types:"
        puts "  • Text: Free-form text input"
        puts "  • Choice: Select from predefined options"
        puts "  • Confirmation: Yes/No questions"
        puts "  • File: File path with @ browsing"
        puts "  • Number: Integer or decimal numbers"
        puts "  • Email: Email address format"
        puts "  • URL: Web URL format"

        puts "\n⌨️  Special Commands:"
        puts "  • @: Browse and select files"
        puts "  • Enter: Use default value (if available)"
        puts "  • Ctrl+C: Cancel operation"

        puts "\n📁 File Selection:"
        puts "  • Type @ to browse files"
        puts "  • Type @search to filter files"
        puts "  • Select by number or type 0 to cancel"

        puts "\n✅ Validation:"
        puts "  • Required fields must be filled"
        puts "  • Input format is validated automatically"
        puts "  • Invalid input shows error and retries"

        puts "\n💡 Tips:"
        puts "  • Use Tab for auto-completion"
        puts "  • Arrow keys for history navigation"
        puts "  • Default values are shown in prompts"
      end

      # Display question summary
      def display_question_summary(questions)
        puts "\n📋 Question Summary:"
        puts "-" * 30

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

          puts "  #{question_number}. #{type_emoji} #{question_text} (#{status})"
        end
      end

      # Get user preferences for feedback collection
      def get_user_preferences
        puts "\n⚙️  User Preferences:"
        puts "-" * 25

        preferences = {}

        # Auto-confirm defaults
        preferences[:auto_confirm_defaults] = get_confirmation(
          "Auto-confirm default values without prompting?",
          default: false
        )

        # Show help automatically
        preferences[:show_help_automatically] = get_confirmation(
          "Show help automatically for new question types?",
          default: false
        )

        # Verbose mode
        preferences[:verbose_mode] = get_confirmation(
          "Enable verbose mode with detailed information?",
          default: true
        )

        # File browsing enabled
        preferences[:file_browsing_enabled] = get_confirmation(
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
          puts "\nPress Enter to continue..."
          Readline.readline
        end

        # Display question summary if verbose
        if @verbose_mode
          display_question_summary(questions)
          puts "\nPress Enter to start answering questions..."
          Readline.readline
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
      def get_quick_feedback(question, options = {})
        question_type = options[:type] || "text"
        default_value = options[:default]
        required = options[:required] != false

        puts "\n❓ #{question}"

        case question_type
        when "text"
          get_text_response("text", default_value, required)
        when "confirmation"
          get_confirmation_response(default_value, required)
        when "choice"
          get_choice_response(options[:options], default_value, required)
        else
          get_text_response("text", default_value, required)
        end
      end

      # Batch collect feedback for multiple simple questions
      def collect_batch_feedback(questions)
        responses = {}

        puts "\n📝 Quick Feedback Collection:"
        puts "=" * 35

        questions.each_with_index do |question_data, index|
          question_number = index + 1
          question_text = question_data[:question]
          question_type = question_data[:type] || "text"
          default_value = question_data[:default]
          required = question_data[:required] != false

          puts "\n#{question_number}. #{question_text}"

          response = get_quick_feedback(question_text, {
            type: question_type,
            default: default_value,
            required: required,
            options: question_data[:options]
          })

          responses["question_#{question_number}"] = response
        end

        puts "\n✅ Batch feedback collected."
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
          unless ENV['RACK_ENV'] == 'test' || defined?(RSpec)
            require "async"
            Async do |task|
              task.async { control_interface_loop }
            end
          end
        end

        puts "\n🎮 Control Interface Started"
        puts "   Press 'p' + Enter to pause"
        puts "   Press 'r' + Enter to resume"
        puts "   Press 's' + Enter to stop"
        puts "   Press 'h' + Enter for help"
        puts "   Press 'q' + Enter to quit control interface"
        puts "=" * 50
      end

      # Stop the control interface
      def stop_control_interface
        @control_mutex.synchronize do
          if @control_thread&.alive?
            @control_thread.kill
            @control_thread = nil
          end
        end

        puts "\n🛑 Control Interface Stopped"
      end

      # Check if pause is requested
      def pause_requested?
        @control_mutex.synchronize { @pause_requested }
      end

      # Check if stop is requested
      def stop_requested?
        @control_mutex.synchronize { @stop_requested }
      end

      # Check if resume is requested
      def resume_requested?
        @control_mutex.synchronize { @resume_requested }
      end

      # Request pause
      def request_pause
        @control_mutex.synchronize do
          @pause_requested = true
          @resume_requested = false
        end
        puts "\n⏸️  Pause requested..."
      end

      # Request stop
      def request_stop
        @control_mutex.synchronize do
          @stop_requested = true
          @pause_requested = false
          @resume_requested = false
        end
        puts "\n🛑 Stop requested..."
      end

      # Request resume
      def request_resume
        @control_mutex.synchronize do
          @resume_requested = true
          @pause_requested = false
        end
        puts "\n▶️  Resume requested..."
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
          else
            Async::Task.current.sleep(0.1) # Small delay to prevent busy waiting
          end
        end
      end

      # Handle pause state
      def handle_pause_state
        puts "\n⏸️  HARNESS PAUSED"
        puts "=" * 50
        puts "🎮 Control Options:"
        puts "   'r' + Enter: Resume execution"
        puts "   's' + Enter: Stop execution"
        puts "   'h' + Enter: Show help"
        puts "   'q' + Enter: Quit control interface"
        puts "=" * 50

        loop do
          input = Readline.readline("Paused> ", true)

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
            puts "❌ Invalid command. Type 'h' for help."
          end
        end
      end

      # Handle stop state
      def handle_stop_state
        puts "\n🛑 HARNESS STOPPED"
        puts "=" * 50
        puts "Execution has been stopped by user request."
        puts "You can restart the harness from where it left off."
        puts "=" * 50
      end

      # Handle resume state
      def handle_resume_state
        puts "\n▶️  HARNESS RESUMED"
        puts "=" * 50
        puts "Execution has been resumed."
        puts "=" * 50
      end

      # Show control help
      def show_control_help
        puts "\n📖 Control Interface Help"
        puts "=" * 50
        puts "🎮 Available Commands:"
        puts "   'p' or 'pause'    - Pause the harness execution"
        puts "   'r' or 'resume'   - Resume the harness execution"
        puts "   's' or 'stop'     - Stop the harness execution"
        puts "   'h' or 'help'     - Show this help message"
        puts "   'q' or 'quit'     - Quit the control interface"
        puts ""
        puts "📋 Control States:"
        puts "   Running  - Harness is executing normally"
        puts "   Paused   - Harness is paused, waiting for resume"
        puts "   Stopped  - Harness has been stopped by user"
        puts "   Resumed  - Harness has been resumed from pause"
        puts ""
        puts "💡 Tips:"
        puts "   • You can pause/resume/stop at any time during execution"
        puts "   • The harness will save its state when paused/stopped"
        puts "   • You can restart from where you left off"
        puts "   • Use 'h' for help at any time"
        puts "=" * 50
      end

      # Control interface main loop
      def control_interface_loop
        loop do
          input = Readline.readline("Control> ", true)

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
            puts "❌ Invalid command. Type 'h' for help."
          end
        rescue Interrupt
          puts "\n🛑 Control interface interrupted. Stopping..."
          request_stop
          break
        rescue => e
          puts "❌ Control interface error: #{e.message}"
          puts "   Type 'h' for help or 'q' to quit."
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
        puts "🎮 Control interface enabled"
      end

      # Disable control interface
      def disable_control_interface
        @control_interface_enabled = false
        stop_control_interface
        puts "🎮 Control interface disabled"
      end

      # Get control status
      def get_control_status
        @control_mutex.synchronize do
          {
            enabled: @control_interface_enabled,
            pause_requested: @pause_requested,
            stop_requested: @stop_requested,
            resume_requested: @resume_requested,
            control_thread_alive: @control_thread&.alive? || false
          }
        end
      end

      # Display control status
      def display_control_status
        status = get_control_status

        puts "\n🎮 Control Interface Status"
        puts "=" * 40
        puts "Enabled: #{status[:enabled] ? "✅ Yes" : "❌ No"}"
        puts "Pause Requested: #{status[:pause_requested] ? "⏸️  Yes" : "▶️  No"}"
        puts "Stop Requested: #{status[:stop_requested] ? "🛑 Yes" : "▶️  No"}"
        puts "Resume Requested: #{status[:resume_requested] ? "▶️  Yes" : "⏸️  No"}"
        puts "Control Thread: #{status[:control_thread_alive] ? "🟢 Active" : "🔴 Inactive"}"
        puts "=" * 40
      end

      # Interactive control menu
      def show_control_menu
        puts "\n🎮 Harness Control Menu"
        puts "=" * 50
        puts "1. Start Control Interface"
        puts "2. Stop Control Interface"
        puts "3. Pause Harness"
        puts "4. Resume Harness"
        puts "5. Stop Harness"
        puts "6. Show Control Status"
        puts "7. Show Help"
        puts "8. Exit Menu"
        puts "=" * 50

        loop do
          choice = Readline.readline("Select option (1-8): ", true)

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
            puts "👋 Exiting control menu..."
            break
          else
            puts "❌ Invalid option. Please select 1-8."
          end
        end
      end

      # Quick control commands
      def quick_pause
        request_pause
        puts "⏸️  Quick pause requested. Use 'r' to resume."
      end

      def quick_resume
        request_resume
        puts "▶️  Quick resume requested."
      end

      def quick_stop
        request_stop
        puts "🛑 Quick stop requested."
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
            puts "\n⏰ Control interface timeout reached. Continuing execution..."
            break
          else
            Async::Task.current.sleep(0.1)
          end
        end
      end

      # Emergency stop
      def emergency_stop
        puts "\n🚨 EMERGENCY STOP INITIATED"
        puts "=" * 50
        puts "All execution will be halted immediately."
        puts "This action cannot be undone."
        puts "=" * 50

        @control_mutex.synchronize do
          @stop_requested = true
          @pause_requested = false
          @resume_requested = false
        end

        stop_control_interface
        puts "🛑 Emergency stop completed."
      end
    end
  end
end
