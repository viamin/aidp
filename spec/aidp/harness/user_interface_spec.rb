# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

  describe "interactive prompt system" do
    describe "#collect_feedback" do
      it "collects feedback for text questions" do
        questions = [
          {
            number: 1,
            question: "What is your name?",
            type: "text",
            expected_input: "text",
            required: true
          }
        ]

        # Mock Readline to return test input
        allow(Readline).to receive(:readline).and_return("John Doe")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
      end

      it "collects feedback for choice questions" do
        questions = [
          {
            number: 1,
            question: "Choose an option:",
            type: "choice",
            options: ["Option A", "Option B", "Option C"],
            required: true
          }
        ]

        # Mock Readline to return choice selection
        allow(Readline).to receive(:readline).and_return("2")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("Option B")
      end

      it "collects feedback for confirmation questions" do
        questions = [
          {
            number: 1,
            question: "Do you want to continue?",
            type: "confirmation",
            required: true
          }
        ]

        # Mock Readline to return confirmation
        allow(Readline).to receive(:readline).and_return("y")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to be true
      end

      it "collects feedback for email questions" do
        questions = [
          {
            number: 1,
            question: "What is your email?",
            type: "email",
            required: true
          }
        ]

        # Mock Readline to return email
        allow(Readline).to receive(:readline).and_return("test@example.com")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("test@example.com")
      end

      it "collects feedback for number questions" do
        questions = [
          {
            number: 1,
            question: "What is your age?",
            type: "number",
            expected_input: "integer",
            required: true
          }
        ]

        # Mock Readline to return number
        allow(Readline).to receive(:readline).and_return("25")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq(25)
      end

      it "collects feedback for URL questions" do
        questions = [
          {
            number: 1,
            question: "What is your website?",
            type: "url",
            required: true
          }
        ]

        # Mock Readline to return URL
        allow(Readline).to receive(:readline).and_return("https://example.com")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("https://example.com")
      end

      it "handles optional questions" do
        questions = [
          {
            number: 1,
            question: "Optional comment:",
            type: "text",
            required: false
          }
        ]

        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to be_nil
      end

      it "handles default values" do
        questions = [
          {
            number: 1,
            question: "What is your name?",
            type: "text",
            default: "Anonymous",
            required: false
          }
        ]

        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        responses = ui.collect_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("Anonymous")
      end

      it "displays context when provided" do
        questions = [
          {
            number: 1,
            question: "What is your name?",
            type: "text",
            required: true
          }
        ]

        context = {
          type: "user_registration",
          urgency: "high",
          description: "Please provide your information",
          agent_output: "Agent needs user information to continue"
        }

        # Mock Readline to return test input
        allow(Readline).to receive(:readline).and_return("John Doe")

        # Capture output
        expect { ui.collect_feedback(questions, context) }.to output(/Context:/).to_stdout
      end
    end

    describe "#validate_input_type" do
      it "validates email format" do
        expect(ui.validate_input_type("test@example.com", "email")[:valid]).to be true
        expect(ui.validate_input_type("invalid-email", "email")[:valid]).to be false
      end

      it "validates URL format" do
        expect(ui.validate_input_type("https://example.com", "url")[:valid]).to be true
        expect(ui.validate_input_type("invalid-url", "url")[:valid]).to be false
      end

      it "validates number format" do
        expect(ui.validate_input_type("123", "number")[:valid]).to be true
        expect(ui.validate_input_type("abc", "number")[:valid]).to be false
      end

      it "validates integer format" do
        expect(ui.validate_input_type("123", "integer")[:valid]).to be true
        expect(ui.validate_input_type("123.45", "integer")[:valid]).to be false
      end

      it "validates float format" do
        expect(ui.validate_input_type("123.45", "float")[:valid]).to be true
        expect(ui.validate_input_type("123", "float")[:valid]).to be true
        expect(ui.validate_input_type("abc", "float")[:valid]).to be false
      end

      it "validates boolean format" do
        expect(ui.validate_input_type("true", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("false", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("yes", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("no", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("y", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("n", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("1", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("0", "boolean")[:valid]).to be true
        expect(ui.validate_input_type("maybe", "boolean")[:valid]).to be false
      end

      it "validates file path" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.close

        expect(ui.validate_input_type(temp_file.path, "file")[:valid]).to be true
        expect(ui.validate_input_type("nonexistent.txt", "file")[:valid]).to be false

        temp_file.unlink
      end

      it "returns true for unknown types" do
        expect(ui.validate_input_type("anything", "unknown")[:valid]).to be true
      end
    end

    describe "#get_quick_feedback" do
      it "gets quick feedback for text questions" do
        # Mock Readline to return test input
        allow(Readline).to receive(:readline).and_return("Quick response")

        response = ui.get_quick_feedback("What is your name?", type: "text")

        expect(response).to eq("Quick response")
      end

      it "gets quick feedback for confirmation questions" do
        # Mock Readline to return confirmation
        allow(Readline).to receive(:readline).and_return("y")

        response = ui.get_quick_feedback("Do you want to continue?", type: "confirmation")

        expect(response).to be true
      end

      it "gets quick feedback for choice questions" do
        # Mock Readline to return choice selection
        allow(Readline).to receive(:readline).and_return("1")

        response = ui.get_quick_feedback("Choose an option:",
          type: "choice",
          options: ["Option A", "Option B"])

        expect(response).to eq("Option A")
      end
    end

    describe "#collect_batch_feedback" do
      it "collects batch feedback for multiple questions" do
        questions = [
          {
            question: "What is your name?",
            type: "text",
            required: true
          },
          {
            question: "What is your age?",
            type: "number",
            expected_input: "integer",
            required: true
          },
          {
            question: "Do you want to continue?",
            type: "confirmation",
            required: true
          }
        ]

        # Mock Readline to return test inputs
        allow(Readline).to receive(:readline).and_return("John Doe", "25", "y")

        responses = ui.collect_batch_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
        expect(responses["question_2"]).to eq("25")
        expect(responses["question_3"]).to be true
      end
    end

    describe "#get_user_preferences" do
      it "gets user preferences" do
        # Mock Readline to return preference selections
        allow(Readline).to receive(:readline).and_return("n", "y", "y", "n")

        preferences = ui.get_user_preferences

        expect(preferences).to be_a(Hash)
        expect(preferences[:auto_confirm_defaults]).to be false
        expect(preferences[:show_help_automatically]).to be true
        expect(preferences[:verbose_mode]).to be true
        expect(preferences[:file_browsing_enabled]).to be false
      end
    end

    describe "#apply_preferences" do
      it "applies user preferences" do
        preferences = {
          auto_confirm_defaults: true,
          show_help_automatically: false,
          verbose_mode: false,
          file_browsing_enabled: true
        }

        ui.apply_preferences(preferences)

        expect(ui.instance_variable_get(:@auto_confirm_defaults)).to be true
        expect(ui.instance_variable_get(:@show_help_automatically)).to be false
        expect(ui.instance_variable_get(:@verbose_mode)).to be false
        expect(ui.instance_variable_get(:@file_selection_enabled)).to be true
      end
    end

    describe "#show_help" do
      it "displays help information" do
        expect { ui.show_help }.to output(/Interactive Prompt Help/).to_stdout
        expect { ui.show_help }.to output(/Input Types/).to_stdout
        expect { ui.show_help }.to output(/Special Commands/).to_stdout
        expect { ui.show_help }.to output(/File Selection/).to_stdout
        expect { ui.show_help }.to output(/Validation/).to_stdout
        expect { ui.show_help }.to output(/Tips/).to_stdout
      end
    end

    describe "#display_question_summary" do
      it "displays question summary" do
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

        expect { ui.display_question_summary(questions) }.to output(/Question Summary/).to_stdout
        expect { ui.display_question_summary(questions) }.to output(/What is your name/).to_stdout
        expect { ui.display_question_summary(questions) }.to output(/What is your age/).to_stdout
      end
    end

    describe "#display_feedback_context" do
      it "displays feedback context" do
        context = {
          type: "user_registration",
          urgency: "high",
          description: "Please provide your information",
          agent_output: "Agent needs user information to continue"
        }

        expect { ui.display_feedback_context(context) }.to output(/Context:/).to_stdout
        expect { ui.display_feedback_context(context) }.to output(/Type: user_registration/).to_stdout
        expect { ui.display_feedback_context(context) }.to output(/Urgency: 🔴 High/).to_stdout
        expect { ui.display_feedback_context(context) }.to output(/Description: Please provide your information/).to_stdout
        expect { ui.display_feedback_context(context) }.to output(/Agent Output:/).to_stdout
      end
    end

    describe "#display_question_info" do
      it "displays question information for text questions" do
        expect { ui.display_question_info("text", "text", nil, nil, true) }.to output(/📝 Text/).to_stdout
        expect { ui.display_question_info("text", "text", nil, nil, true) }.to output(/Required: Yes/).to_stdout
      end

      it "displays question information for choice questions" do
        options = ["Option A", "Option B"]
        expect { ui.display_question_info("choice", "text", options, "Option A", true) }.to output(/🔘 Choice/).to_stdout
        expect { ui.display_question_info("choice", "text", options, "Option A", true) }.to output(/Options: Option A, Option B/).to_stdout
        expect { ui.display_question_info("choice", "text", options, "Option A", true) }.to output(/Default: Option A/).to_stdout
      end

      it "displays question information for email questions" do
        expect { ui.display_question_info("email", "email", nil, nil, true) }.to output(/📧 Email/).to_stdout
        expect { ui.display_question_info("email", "email", nil, nil, true) }.to output(/Expected: email/).to_stdout
      end
    end
  end
end
