# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::Harness::UserInterface do
  let(:test_prompt) { TestPrompt.new }
  let(:ui) do
    # Use proper dependency injection via constructor
    described_class.new(prompt: test_prompt)
  end

  describe "numbered question presentation system" do
    describe "#display_question_presentation_header" do
      it "displays question presentation header" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        ui.display_question_presentation_header(questions, nil)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Agent needs your feedback/) }).to be true
        ui.display_question_presentation_header(questions, nil)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Questions to answer/) }).to be true
      end

      it "displays context summary when provided" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        context = {
          type: "user_registration",
          urgency: "high",
          description: "Please provide your information"
        }

        ui.display_question_presentation_header(questions, context)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Context Summary/) }).to be true
        ui.display_question_presentation_header(questions, context)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Type: user_registration/) }).to be true
        ui.display_question_presentation_header(questions, context)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Urgency: 🔴 High/) }).to be true
      end
    end

    describe "#display_question_overview" do
      it "displays question overview statistics" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false},
          {question: "Do you want to continue?", type: "confirmation", required: true}
        ]

        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Overview:/) }).to be true
        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Total questions: 3/) }).to be true
        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Required: 2/) }).to be true
        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Optional: 1/) }).to be true
        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Question types: text, number, confirmation/) }).to be true
      end

      it "displays estimated completion time" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        ui.display_question_overview(questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Estimated time:/) }).to be true
      end
    end

    describe "#estimate_completion_time" do
      it "estimates time for text questions" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("30 seconds")
      end

      it "estimates time for choice questions" do
        questions = [
          {question: "Choose an option:", type: "choice", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("15 seconds")
      end

      it "estimates time for confirmation questions" do
        questions = [
          {question: "Do you want to continue?", type: "confirmation", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("10 seconds")
      end

      it "estimates time for file questions" do
        questions = [
          {question: "Select a file:", type: "file", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("45 seconds")
      end

      it "estimates time for number questions" do
        questions = [
          {question: "What is your age?", type: "number", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("20 seconds")
      end

      it "estimates time for email questions" do
        questions = [
          {question: "What is your email?", type: "email", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("25 seconds")
      end

      it "estimates time for URL questions" do
        questions = [
          {question: "What is your website?", type: "url", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("30 seconds")
      end

      it "estimates time for multiple questions" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: true},
          {question: "Do you want to continue?", type: "confirmation", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("1.0 minutes")
      end

      it "handles unknown question types" do
        questions = [
          {question: "Unknown question", type: "unknown", required: true}
        ]

        time = ui.estimate_completion_time(questions)
        expect(time).to eq("30 seconds")
      end
    end

    describe "#display_numbered_question" do
      it "displays numbered question with formatting" do
        question_data = {
          question: "What is your name?",
          type: "text",
          expected_input: "text",
          required: true
        }

        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Question 1 of 3/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/📝 What is your name/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Question Details:/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Instructions:/) }).to be true
      end

      it "displays question metadata" do
        question_data = {
          question: "What is your name?",
          type: "text",
          expected_input: "text",
          required: true
        }

        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Type: Text/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Status: 🔴 Required/) }).to be true
      end

      it "displays optional question status" do
        question_data = {
          question: "What is your age?",
          type: "number",
          expected_input: "integer",
          required: false
        }

        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Status: 🟢 Optional/) }).to be true
      end

      it "displays choice question options" do
        question_data = {
          question: "Choose an option:",
          type: "choice",
          options: ["Option A", "Option B", "Option C"],
          default: "Option A",
          required: true
        }

        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Options: 3 available/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Default: Option A/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Available Options:/) }).to be true
        ui.display_numbered_question(question_data, 1, 1, 3)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/1\. Option A \(default\)/) }).to be true
      end
    end

    describe "#display_question_instructions" do
      it "displays text question instructions" do
        ui.display_question_instructions("text", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter your text response/) }).to be true
        ui.display_question_instructions("text", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Use @ for file selection/) }).to be true
      end

      it "displays choice question instructions" do
        options = ["Option A", "Option B"]
        ui.display_question_instructions("choice", options, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Select from the numbered options/) }).to be true
        ui.display_question_instructions("choice", options, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter the number of your choice/) }).to be true
      end

      it "displays confirmation question instructions" do
        ui.display_question_instructions("confirmation", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter 'y' or 'yes' for Yes/) }).to be true
        ui.display_question_instructions("confirmation", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter 'n' or 'no' for No/) }).to be true
      end

      it "displays file question instructions" do
        ui.display_question_instructions("file", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter file path directly/) }).to be true
        ui.display_question_instructions("file", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Use @ to browse and select files/) }).to be true
      end

      it "displays number question instructions" do
        ui.display_question_instructions("number", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter a valid number/) }).to be true
        ui.display_question_instructions("number", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Use decimal point for decimals/) }).to be true
      end

      it "displays email question instructions" do
        ui.display_question_instructions("email", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter a valid email address/) }).to be true
        ui.display_question_instructions("email", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Format: user@domain.com/) }).to be true
      end

      it "displays URL question instructions" do
        ui.display_question_instructions("url", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Enter a valid URL/) }).to be true
        ui.display_question_instructions("url", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Format: https:\/\/example.com/) }).to be true
      end

      it "displays default value instructions" do
        ui.display_question_instructions("text", nil, "Default Value", true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Quick Answer:/) }).to be true
        ui.display_question_instructions("text", nil, "Default Value", true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Press Enter to use default: Default Value/) }).to be true
      end

      it "displays required field instructions" do
        ui.display_question_instructions("text", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Required Field:/) }).to be true
        ui.display_question_instructions("text", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/This question must be answered/) }).to be true
        ui.display_question_instructions("text", nil, nil, true)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Cannot be left blank/) }).to be true
      end

      it "displays optional field instructions" do
        ui.display_question_instructions("text", nil, nil, false)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Optional Field:/) }).to be true
        ui.display_question_instructions("text", nil, nil, false)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/This question can be skipped/) }).to be true
        ui.display_question_instructions("text", nil, nil, false)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Press Enter to leave blank/) }).to be true
      end
    end

    describe "#display_question_progress" do
      it "displays progress bar and percentage" do
        ui.display_question_progress(2, 5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Progress:/) }).to be true
        ui.display_question_progress(2, 5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/40.0%/) }).to be true
        ui.display_question_progress(2, 5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/\(2\/5\)/) }).to be true
      end

      it "displays estimated time remaining" do
        ui.display_question_progress(2, 5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Estimated time remaining:/) }).to be true
      end

      it "does not display time remaining for last question" do
        ui.display_question_progress(5, 5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Estimated time remaining:/) }).to be false
      end
    end

    describe "#generate_progress_bar" do
      it "generates progress bar for 0%" do
        bar = ui.generate_progress_bar(0)
        expect(bar).to eq("[░░░░░░░░░░░░░░░░░░░░]")
      end

      it "generates progress bar for 50%" do
        bar = ui.generate_progress_bar(50)
        expect(bar).to eq("[██████████░░░░░░░░░░]")
      end

      it "generates progress bar for 100%" do
        bar = ui.generate_progress_bar(100)
        expect(bar).to eq("[████████████████████]")
      end

      it "generates progress bar for custom width" do
        bar = ui.generate_progress_bar(50, 10)
        expect(bar).to eq("[█████░░░░░]")
      end
    end

    describe "#estimate_remaining_time" do
      it "estimates remaining time in seconds" do
        time = ui.estimate_remaining_time(2)
        expect(time).to eq("50 seconds")
      end

      it "estimates remaining time in minutes" do
        time = ui.estimate_remaining_time(5)
        expect(time).to eq("2.1 minutes")
      end
    end

    describe "#display_question_completion_summary" do
      it "displays completion summary" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        responses = {
          "question_1" => "John Doe",
          "question_2" => nil
        }

        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Question Completion Summary/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Statistics:/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Total questions: 2/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Answered: 1/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Skipped: 1/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Completion rate: 50.0%/) }).to be true
      end

      it "displays response summary" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        responses = {
          "question_1" => "John Doe"
        }

        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Response Summary:/) }).to be true
        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/1. John Doe/) }).to be true
      end

      it "displays skipped responses" do
        questions = [
          {question: "What is your age?", type: "number", required: false}
        ]

        responses = {
          "question_1" => nil
        }

        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/1. \[Skipped\]/) }).to be true
      end

      it "truncates long responses" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        long_response = "A" * 60
        responses = {
          "question_1" => long_response
        }

        ui.display_question_completion_summary(responses, questions)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/1. AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.../) }).to be true
      end
    end

    describe "integration with collect_feedback" do
      it "integrates with collect_feedback method" do
        questions = [
          {
            number: 1,
            question: "What is your name?",
            type: "text",
            required: true
          },
          {
            number: 2,
            question: "What is your age?",
            type: "number",
            required: false
          }
        ]

        context = {
          type: "user_registration",
          urgency: "high",
          description: "Please provide your information"
        }

        # Mock the response methods to avoid validation loops
        allow(ui).to receive(:get_text_response).and_return("John Doe")
        allow(ui).to receive(:get_number_response).and_return(25)
        # TestPrompt handles keypress automatically

        responses = ui.collect_feedback(questions, context)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
        expect(responses["question_2"]).to eq(25)
      end
    end
  end
end
