# frozen_string_literal: true

require "readline"

module Aidp
  module Harness
    # Handles user interaction and feedback collection
    class UserInterface
      def initialize
        @input_history = []
        @file_selection_enabled = false
      end

      # Collect user feedback for a list of questions
      def collect_feedback(questions)
        responses = {}

        puts "\n🤖 Agent needs your feedback:"
        puts "=" * 50

        questions.each_with_index do |question_data, index|
          question_number = question_data[:number] || (index + 1)
          question_text = question_data[:question]

          puts "\n#{question_number}. #{question_text}"

          response = get_user_input("Your response: ")
          responses["question_#{question_number}"] = response
        end

        puts "\n✅ Feedback collected. Continuing execution..."
        responses
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

        # Get available files in current directory and subdirectories
        available_files = find_files(search_term)

        if available_files.empty?
          puts "No files found matching '#{search_term}'. Please try again."
          return nil
        end

        # Display file selection menu
        display_file_menu(available_files)

        # Get user selection
        selection = get_file_selection(available_files.size)

        if selection && selection >= 0 && selection < available_files.size
          selected_file = available_files[selection]
          puts "Selected: #{selected_file}"
          return selected_file
        else
          puts "Invalid selection. Please try again."
          return nil
        end
      end

      # Find files matching search term
      def find_files(search_term)
        files = []

        # Search in current directory and common subdirectories
        search_paths = [
          ".",
          "lib",
          "spec",
          "app",
          "src",
          "docs",
          "templates"
        ]

        search_paths.each do |path|
          next unless Dir.exist?(path)

          Dir.glob(File.join(path, "**", "*")).each do |file|
            next unless File.file?(file)

            # Simple filename matching
            if search_term.empty? || File.basename(file).downcase.include?(search_term.downcase)
              files << file
            end
          end
        end

        # Limit to reasonable number of results
        files.first(20)
      end

      # Display file selection menu
      def display_file_menu(files)
        puts "\n📁 Available files:"
        files.each_with_index do |file, index|
          puts "  #{index + 1}. #{file}"
        end
        puts "  0. Cancel"
      end

      # Get file selection from user
      def get_file_selection(max_files)
        loop do
          input = Readline.readline("Select file (0-#{max_files}): ", true)

          if input.nil? || input.strip.empty?
            puts "Please enter a number."
            next
          end

          begin
            selection = input.strip.to_i
            if selection == 0
              return nil # Cancel
            elsif selection >= 1 && selection <= max_files
              return selection - 1 # Convert to 0-based index
            else
              puts "Please enter a number between 0 and #{max_files}."
            end
          rescue ArgumentError
            puts "Please enter a valid number."
          end
        end
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
    end
  end
end
