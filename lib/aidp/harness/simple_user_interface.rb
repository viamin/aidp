# frozen_string_literal: true

require "tty-prompt"

module Aidp
  module Harness
    # Simple, focused user interface for collecting feedback
    # Replaces the bloated UserInterface with minimal, clean code
    class SimpleUserInterface
      def initialize(prompt: TTY::Prompt.new)
        @prompt = prompt
      end

      # Main method - collect responses for questions
      def collect_feedback(questions, context = nil)
        show_context(context) if context

        responses = {}
        questions.each_with_index do |question_data, index|
          key = "question_#{question_data[:number] || index + 1}"
          responses[key] = ask_question(question_data)
        end

        responses
      end

      private

      def show_context(context)
        puts "\n🤖 Agent needs feedback"
        puts "Context: #{context[:description]}" if context[:description]
        puts ""
      end

      def ask_question(question_data)
        question = question_data[:question]
        type = question_data[:type] || "text"
        default = question_data[:default]
        required = question_data[:required] != false
        options = question_data[:options]

        puts "\n#{question}"

        case type
        when "text"
          ask_text(question, default, required)
        when "choice"
          @prompt.select("Choose:", options, default: default)
        when "confirmation"
          @prompt.yes?("#{question}?", default: default)
        when "file"
          ask_file(question, default, required)
        when "number"
          ask_number(question, default, required)
        when "email"
          ask_email(question, default, required)
        when "url"
          ask_url(question, default, required)
        else
          ask_text(question, default, required)
        end
      end

      def ask_text(question, default, required)
        options = {}
        options[:default] = default if default
        options[:required] = required

        @prompt.ask("Response:", **options)
      end

      def ask_file(question, default, required)
        input = @prompt.ask("File path:", default: default, required: required)

        # Handle @ file selection
        if input&.start_with?("@")
          search_term = input[1..].strip
          files = find_files(search_term)

          return nil if files.empty?

          @prompt.select("Select file:", files, per_page: 15)
        else
          input
        end
      end

      def ask_number(question, default, required)
        @prompt.ask("Number:", default: default, required: required) do |q|
          q.convert :int
          q.validate(/^\d+$/, "Please enter a valid number")
        end
      end

      def ask_email(question, default, required)
        @prompt.ask("Email:", default: default, required: required) do |q|
          q.validate(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i, "Please enter a valid email")
        end
      end

      def ask_url(question, default, required)
        @prompt.ask("URL:", default: default, required: required) do |q|
          q.validate(/\Ahttps?:\/\/.+/i, "Please enter a valid URL (http:// or https://)")
        end
      end

      def find_files(search_term)
        if search_term.empty?
          # Show common files
          Dir.glob("**/*").select { |f| File.file?(f) }.first(20)
        elsif search_term.start_with?(".")
          # Extension search (e.g., .rb)
          Dir.glob("**/*#{search_term}").select { |f| File.file?(f) }
        elsif search_term.end_with?("/")
          # Directory search (e.g., lib/)
          dir = search_term.chomp("/")
          Dir.glob("#{dir}/**/*").select { |f| File.file?(f) }
        else
          # Name search
          Dir.glob("**/*#{search_term}*").select { |f| File.file?(f) }
        end
      end
    end
  end
end
