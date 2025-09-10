# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

  describe "numbered question presentation system" do
    describe "#display_question_presentation_header" do
      it "displays question presentation header" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        expect { ui.display_question_presentation_header(questions, nil) }.to output(/Agent needs your feedback/).to_stdout
        expect { ui.display_question_presentation_header(questions, nil) }.to output(/Questions to answer/).to_stdout
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

        expect { ui.display_question_presentation_header(questions, context) }.to output(/Context Summary/).to_stdout
        expect { ui.display_question_presentation_header(questions, context) }.to output(/Type: user_registration/).to_stdout
        expect { ui.display_question_presentation_header(questions, context) }.to output(/Urgency: 🔴 High/).to_stdout
      end
    end

    describe "#display_question_overview" do
      it "displays question overview statistics" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false},
          {question: "Do you want to continue?", type: "confirmation", required: true}
        ]

        expect { ui.display_question_overview(questions) }.to output(/Overview:/).to_stdout
        expect { ui.display_question_overview(questions) }.to output(/Total questions: 3/).to_stdout
        expect { ui.display_question_overview(questions) }.to output(/Required: 2/).to_stdout
        expect { ui.display_question_overview(questions) }.to output(/Optional: 1/).to_stdout
        expect { ui.display_question_overview(questions) }.to output(/Question types: text, number, confirmation/).to_stdout
      end

      it "displays estimated completion time" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        expect { ui.display_question_overview(questions) }.to output(/Estimated time:/).to_stdout
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
        expect(time).to eq("1.1 minutes")
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

        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Question 1 of 3/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/📝 What is your name/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Question Details:/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Instructions:/).to_stdout
      end

      it "displays question metadata" do
        question_data = {
          question: "What is your name?",
          type: "text",
          expected_input: "text",
          required: true
        }

        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Type: Text/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Status: 🔴 Required/).to_stdout
      end

      it "displays optional question status" do
        question_data = {
          question: "What is your age?",
          type: "number",
          expected_input: "integer",
          required: false
        }

        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Status: 🟢 Optional/).to_stdout
      end

      it "displays choice question options" do
        question_data = {
          question: "Choose an option:",
          type: "choice",
          options: ["Option A", "Option B", "Option C"],
          default: "Option A",
          required: true
        }

        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Options: 3 available/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Default: Option A/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/Available Options:/).to_stdout
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/1. Option A \(default\)/).to_stdout
      end
    end

    describe "#display_question_instructions" do
      it "displays text question instructions" do
        expect { ui.display_question_instructions("text", nil, nil, true) }.to output(/Enter your text response/).to_stdout
        expect { ui.display_question_instructions("text", nil, nil, true) }.to output(/Use @ for file selection/).to_stdout
      end

      it "displays choice question instructions" do
        options = ["Option A", "Option B"]
        expect { ui.display_question_instructions("choice", options, nil, true) }.to output(/Select from the numbered options/).to_stdout
        expect { ui.display_question_instructions("choice", options, nil, true) }.to output(/Enter the number of your choice/).to_stdout
      end

      it "displays confirmation question instructions" do
        expect { ui.display_question_instructions("confirmation", nil, nil, true) }.to output(/Enter 'y' or 'yes' for Yes/).to_stdout
        expect { ui.display_question_instructions("confirmation", nil, nil, true) }.to output(/Enter 'n' or 'no' for No/).to_stdout
      end

      it "displays file question instructions" do
        expect { ui.display_question_instructions("file", nil, nil, true) }.to output(/Enter file path directly/).to_stdout
        expect { ui.display_question_instructions("file", nil, nil, true) }.to output(/Use @ to browse and select files/).to_stdout
      end

      it "displays number question instructions" do
        expect { ui.display_question_instructions("number", nil, nil, true) }.to output(/Enter a valid number/).to_stdout
        expect { ui.display_question_instructions("number", nil, nil, true) }.to output(/Use decimal point for decimals/).to_stdout
      end

      it "displays email question instructions" do
        expect { ui.display_question_instructions("email", nil, nil, true) }.to output(/Enter a valid email address/).to_stdout
        expect { ui.display_question_instructions("email", nil, nil, true) }.to output(/Format: user@domain.com/).to_stdout
      end

      it "displays URL question instructions" do
        expect { ui.display_question_instructions("url", nil, nil, true) }.to output(/Enter a valid URL/).to_stdout
        expect { ui.display_question_instructions("url", nil, nil, true) }.to output(/Format: https:\/\/example.com/).to_stdout
      end

      it "displays default value instructions" do
        expect { ui.display_question_instructions("text", nil, "Default Value", true) }.to output(/Quick Answer:/).to_stdout
        expect { ui.display_question_instructions("text", nil, "Default Value", true) }.to output(/Press Enter to use default: Default Value/).to_stdout
      end

      it "displays required field instructions" do
        expect { ui.display_question_instructions("text", nil, nil, true) }.to output(/Required Field:/).to_stdout
        expect { ui.display_question_instructions("text", nil, nil, true) }.to output(/This question must be answered/).to_stdout
        expect { ui.display_question_instructions("text", nil, nil, true) }.to output(/Cannot be left blank/).to_stdout
      end

      it "displays optional field instructions" do
        expect { ui.display_question_instructions("text", nil, nil, false) }.to output(/Optional Field:/).to_stdout
        expect { ui.display_question_instructions("text", nil, nil, false) }.to output(/This question can be skipped/).to_stdout
        expect { ui.display_question_instructions("text", nil, nil, false) }.to output(/Press Enter to leave blank/).to_stdout
      end
    end

    describe "#display_question_progress" do
      it "displays progress bar and percentage" do
        expect { ui.display_question_progress(2, 5) }.to output(/Progress:/).to_stdout
        expect { ui.display_question_progress(2, 5) }.to output(/40.0%/).to_stdout
        expect { ui.display_question_progress(2, 5) }.to output(/\(2\/5\)/).to_stdout
      end

      it "displays estimated time remaining" do
        expect { ui.display_question_progress(2, 5) }.to output(/Estimated time remaining:/).to_stdout
      end

      it "does not display time remaining for last question" do
        expect { ui.display_question_progress(5, 5) }.not_to output(/Estimated time remaining:/).to_stdout
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

        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Question Completion Summary/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Statistics:/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Total questions: 2/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Answered: 1/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Skipped: 1/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Completion rate: 50.0%/).to_stdout
      end

      it "displays response summary" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        responses = {
          "question_1" => "John Doe"
        }

        expect { ui.display_question_completion_summary(responses, questions) }.to output(/Response Summary:/).to_stdout
        expect { ui.display_question_completion_summary(responses, questions) }.to output(/1. John Doe/).to_stdout
      end

      it "displays skipped responses" do
        questions = [
          {question: "What is your age?", type: "number", required: false}
        ]

        responses = {
          "question_1" => nil
        }

        expect { ui.display_question_completion_summary(responses, questions) }.to output(/1. \[Skipped\]/).to_stdout
      end

      it "truncates long responses" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        long_response = "A" * 60
        responses = {
          "question_1" => long_response
        }

        expect { ui.display_question_completion_summary(responses, questions) }.to output(/1. AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.../).to_stdout
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

        # Mock Readline to return test inputs
        allow(Readline).to receive(:readline).and_return("John Doe", "25")

        responses = ui.collect_feedback(questions, context)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
        expect(responses["question_2"]).to eq(25)
      end
    end
  end
end
