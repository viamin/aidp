# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles interactive question collection using CLI UI prompts
      class QuestionCollector < Base
        def initialize(ui_components = {})
          super()
          @prompt = ui_components[:prompt] || CLI::UI::Prompt
        end

        def collect_questions(questions)
          questions.map.with_index do |question, index|
            collect_single_question(question, index + 1)
          end
        end

        private

        def collect_single_question(question, number)
          @prompt.ask("Question #{number}: #{question[:text]}") do |handler|
            add_question_options(handler, question)
          end
        end

        def add_question_options(handler, question)
          return unless question[:options]

          question[:options].each { |option| handler.option(option) }
        end
      end
    end
  end
end
