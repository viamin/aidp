# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles interactive question collection using CLI UI prompts
      class QuestionCollector < Base
        class QuestionError < StandardError; end
        class ValidationError < QuestionError; end
        class CollectionError < QuestionError; end

        def initialize(ui_components = {})
          super()
          @prompt = ui_components[:prompt] || (defined?(CLI::UI) ? CLI::UI::Prompt : nil)
          @validator = ui_components[:validator] || QuestionValidator.new
        end

        def collect_questions(questions)
          validate_questions_input(questions)

          questions.map.with_index do |question, index|
            collect_single_question(question, index + 1)
          end
        rescue => e
          raise CollectionError, "Failed to collect questions: #{e.message}"
        end

        def collect_single_question(question, number)
          validate_question_format(question)

          question_text = format_question_text(question, number)
          response = prompt_for_response(question_text, question)

          validate_response(response, question)
          response
        rescue => e
          raise QuestionError, "Failed to collect question #{number}: #{e.message}"
        end

        private

        def validate_questions_input(questions)
          raise ValidationError, "Questions must be an array" unless questions.is_a?(Array)
          raise ValidationError, "Questions array cannot be empty" if questions.empty?
        end

        def validate_question_format(question)
          raise ValidationError, "Question must be a hash" unless question.is_a?(Hash)
          raise ValidationError, "Question must have :text key" unless question.key?(:text)
          raise ValidationError, "Question text cannot be empty" if question[:text].to_s.strip.empty?
        end

        def format_question_text(question, number)
          "Question #{number}: #{question[:text]}"
        end

        def prompt_for_response(question_text, question)
          @prompt.ask(question_text) do |handler|
            add_question_options(handler, question)
          end
        end

        def add_question_options(handler, question)
          return unless question[:options]

          question[:options].each { |option| handler.option(option) }
        end

        def validate_response(response, question)
          @validator.validate(response, question)
        end
      end

      # Validates question responses
      class QuestionValidator
        def validate(response, question)
          validate_required(response, question)
          validate_format(response, question)
          validate_options(response, question)
        end

        private

        def validate_required(response, question)
          return unless question[:required]
          raise ValidationError, "Response is required" if response.nil? || response.to_s.strip.empty?
        end

        def validate_format(response, question)
          return unless question[:format]
          return if response.to_s.match?(question[:format])
          raise ValidationError, "Response format is invalid"
        end

        def validate_options(response, question)
          return unless question[:options]
          return if question[:options].include?(response)
          raise ValidationError, "Response must be one of: #{question[:options].join(", ")}"
        end
      end
    end
  end
end
