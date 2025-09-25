# frozen_string_literal: true

require "tty-prompt"
require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles interactive question collection using CLI UI prompts
      class QuestionCollector < Base
        class QuestionError < StandardError; end
        class ValidationError < QuestionError; end
        class CollectionError < QuestionError; end

        def initialize(ui_components = {}, prompt: nil)
          super()
          @prompt = prompt || ui_components[:prompt] || TTY::Prompt.new
          @validator = ui_components[:validator] || QuestionValidator.new
        end

        def collect_questions(questions)
          validate_questions_input(questions)

          # Validate all questions first
          errors = get_validation_errors(questions)
          raise ValidationError, errors.join("\n") unless errors.empty?

          responses = {}
          questions.each_with_index do |question, index|
            question_key = question[:key] || "question_#{index + 1}"
            responses[question_key] = collect_single_question(question, index + 1)
          end
          responses
        rescue ValidationError => e
          raise e
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

        def validate_questions(questions)
          return true if questions.empty?

          questions.all? do |question|
            validate_question_format(question)
            true
          rescue ValidationError
            false
          end
        end

        def get_validation_errors(questions)
          errors = []

          questions.each_with_index do |question, index|
            validate_question_format(question)
          rescue ValidationError => e
            errors << "Question #{index + 1}: #{e.message}"
          end

          errors
        end

        def validate_question_format(question)
          raise ValidationError, "Question must be a hash" unless question.is_a?(Hash)
          raise ValidationError, "Question must have :text key" unless question.key?(:text)
          raise ValidationError, "Question text cannot be empty" if question[:text].to_s.strip.empty?
          unless question.key?(:type) && question.key?(:required)
            raise ValidationError, "Question missing required fields"
          end
        end

        def validate_questions_input(questions)
          raise ValidationError, "Questions must be an array" unless questions.is_a?(Array)
          # Allow empty array - return empty hash
        end

        private

        def validate_response(response, question)
          @validator.validate(response, question)
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
