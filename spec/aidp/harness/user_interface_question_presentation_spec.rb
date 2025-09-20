# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::Harness::UserInterface do
  let(:mock_prompt) { instance_double(TTY::Prompt) }
  let(:ui) do
    # Create a new instance and directly inject the mock prompt
    ui_instance = described_class.new
    # Replace the @prompt instance variable with our mock
    ui_instance.instance_variable_set(:@prompt, mock_prompt)

    # Set default stub behaviors to prevent hanging
    allow(mock_prompt).to receive(:ask).and_return("")
    allow(mock_prompt).to receive(:select).and_return("")
    allow(mock_prompt).to receive(:keypress).and_return("")

    ui_instance
  end

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  describe "numbered question presentation system" do
    describe "#display_question_presentation_header" do
      it "displays question presentation header" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        output = capture_stdout do
          ui.display_question_presentation_header(questions, nil)
        end
        expect(output).to match(/Agent needs your feedback/)
        output = capture_stdout do
          ui.display_question_presentation_header(questions, nil)
        end
        expect(output).to match(/Questions to answer/)
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

        output = capture_stdout do
          ui.display_question_presentation_header(questions, context)
        end
        expect(output).to match(/Context Summary/)
        output = capture_stdout do
          ui.display_question_presentation_header(questions, context)
        end
        expect(output).to match(/Type: user_registration/)
        output = capture_stdout do
          ui.display_question_presentation_header(questions, context)
        end
        expect(output).to match(/Urgency: 🔴 High/)
      end
    end

    describe "#display_question_overview" do
      it "displays question overview statistics" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false},
          {question: "Do you want to continue?", type: "confirmation", required: true}
        ]

        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Overview:/)
        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Total questions: 3/)
        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Required: 2/)
        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Optional: 1/)
        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Question types: text, number, confirmation/)
      end

      it "displays estimated completion time" do
        questions = [
          {question: "What is your name?", type: "text", required: true},
          {question: "What is your age?", type: "number", required: false}
        ]

        output = capture_stdout do
          ui.display_question_overview(questions)
        end
        expect(output).to match(/Estimated time:/)
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

        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Question 1 of 3/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/📝 What is your name/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Question Details:/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Instructions:/)
      end

      it "displays question metadata" do
        question_data = {
          question: "What is your name?",
          type: "text",
          expected_input: "text",
          required: true
        }

        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Type: Text/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Status: 🔴 Required/)
      end

      it "displays optional question status" do
        question_data = {
          question: "What is your age?",
          type: "number",
          expected_input: "integer",
          required: false
        }

        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Status: 🟢 Optional/)
      end

      it "displays choice question options" do
        question_data = {
          question: "Choose an option:",
          type: "choice",
          options: ["Option A", "Option B", "Option C"],
          default: "Option A",
          required: true
        }

        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Options: 3 available/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Default: Option A/)
        output = capture_stdout do
          ui.display_numbered_question(question_data, 1, 1, 3)
        end
        expect(output).to match(/Available Options:/)
        expect { ui.display_numbered_question(question_data, 1, 1, 3) }.to output(/1. Option A \(default\)/).to_stdout
      end
    end

    describe "#display_question_instructions" do
      it "displays text question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, true)
        end
        expect(output).to match(/Enter your text response/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, true)
        end
        expect(output).to match(/Use @ for file selection/)
      end

      it "displays choice question instructions" do
        options = ["Option A", "Option B"]
        output = capture_stdout do
          ui.display_question_instructions("choice", options, nil, true)
        end
        expect(output).to match(/Select from the numbered options/)
        output = capture_stdout do
          ui.display_question_instructions("choice", options, nil, true)
        end
        expect(output).to match(/Enter the number of your choice/)
      end

      it "displays confirmation question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("confirmation", nil, nil, true)
        end
        expect(output).to match(/Enter 'y' or 'yes' for Yes/)
        output = capture_stdout do
          ui.display_question_instructions("confirmation", nil, nil, true)
        end
        expect(output).to match(/Enter 'n' or 'no' for No/)
      end

      it "displays file question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("file", nil, nil, true)
        end
        expect(output).to match(/Enter file path directly/)
        output = capture_stdout do
          ui.display_question_instructions("file", nil, nil, true)
        end
        expect(output).to match(/Use @ to browse and select files/)
      end

      it "displays number question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("number", nil, nil, true)
        end
        expect(output).to match(/Enter a valid number/)
        output = capture_stdout do
          ui.display_question_instructions("number", nil, nil, true)
        end
        expect(output).to match(/Use decimal point for decimals/)
      end

      it "displays email question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("email", nil, nil, true)
        end
        expect(output).to match(/Enter a valid email address/)
        output = capture_stdout do
          ui.display_question_instructions("email", nil, nil, true)
        end
        expect(output).to match(/Format: user@domain.com/)
      end

      it "displays URL question instructions" do
        output = capture_stdout do
          ui.display_question_instructions("url", nil, nil, true)
        end
        expect(output).to match(/Enter a valid URL/)
        output = capture_stdout do
          ui.display_question_instructions("url", nil, nil, true)
        end
        expect(output).to match(/Format: https:\/\/example.com/)
      end

      it "displays default value instructions" do
        output = capture_stdout do
          ui.display_question_instructions("text", nil, "Default Value", true)
        end
        expect(output).to match(/Quick Answer:/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, "Default Value", true)
        end
        expect(output).to match(/Press Enter to use default: Default Value/)
      end

      it "displays required field instructions" do
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, true)
        end
        expect(output).to match(/Required Field:/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, true)
        end
        expect(output).to match(/This question must be answered/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, true)
        end
        expect(output).to match(/Cannot be left blank/)
      end

      it "displays optional field instructions" do
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, false)
        end
        expect(output).to match(/Optional Field:/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, false)
        end
        expect(output).to match(/This question can be skipped/)
        output = capture_stdout do
          ui.display_question_instructions("text", nil, nil, false)
        end
        expect(output).to match(/Press Enter to leave blank/)
      end
    end

    describe "#display_question_progress" do
      it "displays progress bar and percentage" do
        output = capture_stdout do
          ui.display_question_progress(2, 5)
        end
        expect(output).to match(/Progress:/)
        output = capture_stdout do
          ui.display_question_progress(2, 5)
        end
        expect(output).to match(/40.0%/)
        expect { ui.display_question_progress(2, 5) }.to output(/\(2\/5\)/).to_stdout
      end

      it "displays estimated time remaining" do
        output = capture_stdout do
          ui.display_question_progress(2, 5)
        end
        expect(output).to match(/Estimated time remaining:/)
      end

      it "does not display time remaining for last question" do
        output = capture_stdout do
          ui.display_question_progress(5, 5)
        end
        expect(output).not_to match(/Estimated time remaining:/)
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

        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Question Completion Summary/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Statistics:/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Total questions: 2/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Answered: 1/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Skipped: 1/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Completion rate: 50.0%/)
      end

      it "displays response summary" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        responses = {
          "question_1" => "John Doe"
        }

        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/Response Summary:/)
        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/1. John Doe/)
      end

      it "displays skipped responses" do
        questions = [
          {question: "What is your age?", type: "number", required: false}
        ]

        responses = {
          "question_1" => nil
        }

        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/1. \[Skipped\]/)
      end

      it "truncates long responses" do
        questions = [
          {question: "What is your name?", type: "text", required: true}
        ]

        long_response = "A" * 60
        responses = {
          "question_1" => long_response
        }

        output = capture_stdout do
          ui.display_question_completion_summary(responses, questions)
        end
        expect(output).to match(/1. AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.../)
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
        allow(mock_prompt).to receive(:keypress).and_return("")

        responses = ui.collect_feedback(questions, context)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
        expect(responses["question_2"]).to eq(25)
      end
    end
  end
end
