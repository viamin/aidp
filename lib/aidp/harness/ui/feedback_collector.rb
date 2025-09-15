# frozen_string_literal: true

require_relative "base"
require_relative "question_collector"
require_relative "progress_display"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Specialized feedback collection using CLI UI components
      class FeedbackCollector < Base
        class FeedbackError < StandardError; end
        class ValidationError < FeedbackError; end
        class CollectionError < FeedbackError; end

        def initialize(ui_components = {})
          super()
          @question_collector = ui_components[:question_collector] || QuestionCollector.new
          @progress_display = ui_components[:progress_display] || ProgressDisplay.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || FeedbackFormatter.new
        end

        def collect_feedback(questions, context = nil)
          validate_questions(questions)

          @frame_manager.workflow_frame("Feedback Collection") do
            display_feedback_header(questions, context)
            collect_questions_with_context(questions, context)
          end
        rescue => e
          raise CollectionError, "Failed to collect feedback: #{e.message}"
        end

        def collect_quick_feedback(question, options = {})
          validate_single_question(question)

          @frame_manager.section("Quick Feedback") do
            display_quick_feedback_header(question)
            response = @question_collector.collect_single_question(question, 1)
            display_quick_feedback_result(response)
            response
          end
        rescue => e
          raise CollectionError, "Failed to collect quick feedback: #{e.message}"
        end

        def collect_batch_feedback(questions)
          validate_questions(questions)

          @frame_manager.workflow_frame("Batch Feedback Collection") do
            display_batch_header(questions)
            collect_questions_batch(questions)
          end
        rescue => e
          raise CollectionError, "Failed to collect batch feedback: #{e.message}"
        end

        private

        def validate_questions(questions)
          raise ValidationError, "Questions must be an array" unless questions.is_a?(Array)
          raise ValidationError, "Questions array cannot be empty" if questions.empty?
        end

        def validate_single_question(question)
          raise ValidationError, "Question must be a hash" unless question.is_a?(Hash)
          raise ValidationError, "Question must have :text" unless question.key?(:text)
        end

        def display_feedback_header(questions, context)
          @frame_manager.subsection("Collection Overview") do
            display_question_summary(questions)
            display_context_info(context) if context
            display_estimated_time(questions)
          end
        end

        def display_question_summary(questions)
          CLI::UI.puts("📋 Total Questions: #{questions.length}")
          CLI::UI.puts("📊 Question Types: #{get_question_types(questions).join(", ")}")
        end

        def display_context_info(context)
          CLI::UI.puts("\n📝 Context:")
          CLI::UI.puts("Type: #{context[:type]}") if context[:type]
          CLI::UI.puts("Urgency: #{format_urgency(context[:urgency])}") if context[:urgency]
          CLI::UI.puts("Description: #{context[:description]}") if context[:description]
        end

        def display_estimated_time(questions)
          estimated_minutes = estimate_completion_time(questions)
          CLI::UI.puts("⏱️ Estimated Time: #{estimated_minutes} minutes")
        end

        def collect_questions_with_context(questions, context)
          @progress_display.show_progress(questions.length) do |bar|
            responses = {}

            questions.each_with_index do |question, index|
              response = collect_question_with_progress(question, index + 1, questions.length, bar)
              responses["question_#{index + 1}"] = response
            end

            display_completion_summary(responses, questions)
            responses
          end
        end

        def collect_question_with_progress(question, number, total, bar)
          @frame_manager.step_frame(question[:text], number, total) do
            display_question_context(question, number, total)
            response = @question_collector.collect_single_question(question, number)
            @progress_display.update_progress(bar, "Completed #{number}/#{total}")
            response
          end
        end

        def display_question_context(question, number, total)
          CLI::UI.puts("Question #{number} of #{total}")
          CLI::UI.puts("Type: #{question[:type] || "text"}")
          CLI::UI.puts("Required: #{question[:required] ? "Yes" : "No"}")
        end

        def collect_questions_batch(questions)
          @spinner_group.run_concurrent_operations(
            questions.map.with_index do |question, index|
              {
                title: "Question #{index + 1}",
                block: ->(spinner) { collect_batch_question(question, index + 1, spinner) }
              }
            end
          )
        end

        def collect_batch_question(question, number, spinner)
          spinner.update_title("Collecting question #{number}")
          @question_collector.collect_single_question(question, number)
        end

        def display_quick_feedback_header(question)
          CLI::UI.puts("⚡ Quick Feedback Request")
          CLI::UI.puts("Question: #{question[:text]}")
        end

        def display_quick_feedback_result(response)
          CLI::UI.puts("✅ Response collected: #{response}")
        end

        def display_batch_header(questions)
          CLI::UI.puts("📦 Batch Feedback Collection")
          CLI::UI.puts("Processing #{questions.length} questions concurrently")
        end

        def display_completion_summary(responses, questions)
          @frame_manager.subsection("Collection Complete") do
            CLI::UI.puts("✅ Successfully collected #{responses.size} responses")
            CLI::UI.puts("📊 Completion rate: 100%")
            CLI::UI.puts("⏱️ Total time: #{calculate_total_time} seconds")
          end
        end

        def get_question_types(questions)
          questions.map { |q| q[:type] || "text" }.uniq
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

        def estimate_completion_time(questions)
          # Simple estimation: 30 seconds per question
          (questions.length * 0.5).ceil
        end

        def calculate_total_time
          # Placeholder - would track actual time
          "N/A"
        end
      end

      # Formats feedback collection display
      class FeedbackFormatter
        def format_feedback_title
          CLI::UI.fmt("{{bold:{{blue:💬 Feedback Collection}}}}")
        end

        def format_question_header(question_number, total_questions)
          CLI::UI.fmt("{{bold:{{green:Question #{question_number}/#{total_questions}}}}}")
        end

        def format_question_type(type)
          CLI::UI.fmt("{{dim:Type: #{type}}}")
        end

        def format_required_indicator(required)
          if required
            CLI::UI.fmt("{{red:* Required}}")
          else
            CLI::UI.fmt("{{dim:Optional}}")
          end
        end

        def format_completion_summary(responses_count, total_questions)
          CLI::UI.fmt("{{green:✅ Collected #{responses_count}/#{total_questions} responses}}")
        end

        def format_estimated_time(minutes)
          CLI::UI.fmt("{{dim:⏱️ Estimated: #{minutes} minutes}}")
        end
      end
    end
  end
end
