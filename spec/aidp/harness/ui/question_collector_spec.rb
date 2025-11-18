# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/harness/ui/question_collector"

RSpec.describe Aidp::Harness::UI::QuestionCollector do
  let(:mock_prompt) { double("TTY::Prompt", ask: "test response") }
  let(:question_collector) { described_class.new(prompt: mock_prompt) }
  let(:sample_questions) { build_sample_questions }

  describe "#collect_questions" do
    context "when valid questions are provided" do
      it "returns a hash of responses" do
        result = question_collector.collect_questions(sample_questions)

        expect(result).to be_a(Hash)
      end

      it "includes responses for all questions" do
        result = question_collector.collect_questions(sample_questions)

        expect(result.keys).to match_array(["question_1", "question_2"])
      end

      it "validates required questions" do
        required_questions = build_required_questions

        result = question_collector.collect_questions(required_questions)

        expect(result["question_1"]).to eq("test response")
      end
    end

    context "when no questions are provided" do
      it "returns an empty hash" do
        result = question_collector.collect_questions([])

        expect(result).to eq({})
      end
    end

    context "when questions have validation errors" do
      it "raises ValidationError for invalid question format" do
        invalid_questions = [{invalid: "question"}]

        expect {
          question_collector.collect_questions(invalid_questions)
        }.to raise_error(Aidp::Harness::UI::QuestionCollector::ValidationError)
      end
    end
  end

  describe "#validate_questions" do
    context "with valid questions" do
      it "returns true for properly formatted questions" do
        result = question_collector.validate_questions(sample_questions)

        expect(result).to be true
      end
    end

    context "with invalid questions" do
      it "returns false for questions missing required fields" do
        invalid_questions = [{text: "Question without type"}]

        result = question_collector.validate_questions(invalid_questions)

        expect(result).to be false
      end
    end
  end

  describe "#get_validation_errors" do
    context "when questions are valid" do
      it "returns an empty array" do
        errors = question_collector.get_validation_errors(sample_questions)

        expect(errors).to be_empty
      end
    end

    context "when questions have validation issues" do
      it "returns array of error messages" do
        invalid_questions = [{text: "Question without type"}]

        errors = question_collector.get_validation_errors(invalid_questions)

        expect(errors).to include(/missing required fields/i)
      end
    end
  end

  private

  def build_sample_questions
    [
      {
        text: "What is your name?",
        type: "text",
        required: true,
        number: 1
      },
      {
        text: "What is your age?",
        type: "number",
        required: false,
        number: 2
      }
    ]
  end

  def build_required_questions
    [
      {
        text: "Required question?",
        type: "text",
        required: true,
        number: 1
      }
    ]
  end
end
