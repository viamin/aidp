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
    allow(mock_prompt).to receive(:ask).and_return("default_response")
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

        # Mock the text response method directly to avoid TTY loops
        allow(ui).to receive(:get_text_response).and_return("John Doe")

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

        # Mock the choice response method directly to avoid TTY loops
        allow(ui).to receive(:get_choice_response).and_return("Option B")

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

        # Mock the confirmation response method directly to avoid TTY loops
        allow(ui).to receive(:get_confirmation_response).and_return(true)

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

        # Mock the email response method directly to avoid TTY loops
        allow(ui).to receive(:get_email_response).and_return("test@example.com")

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

        # Mock the number response method directly to avoid TTY loops
        allow(ui).to receive(:get_number_response).and_return(25)

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

        # Mock the get_url_response method directly to avoid TTY loops
        allow(ui).to receive(:get_url_response).and_return("https://example.com")

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

        # Mock the text response method to return nil for optional empty input
        allow(ui).to receive(:get_text_response).and_return(nil)

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

        # Mock the text response method to return the default value
        allow(ui).to receive(:get_text_response).and_return("Anonymous")

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

        # Mock TTY::Prompt to return test input
        allow(mock_prompt).to receive(:ask).and_return("John Doe")
        allow(mock_prompt).to receive(:keypress).and_return("")

        # Capture output
        output = capture_stdout do
          ui.collect_feedback(questions, context)
        end
        expect(output).to match(/Context:/)
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
        # Mock the text response method directly to avoid TTY loops
        allow(ui).to receive(:get_text_response).and_return("Quick response")

        response = ui.get_quick_feedback("What is your name?", type: "text")

        expect(response).to eq("Quick response")
      end

      it "gets quick feedback for confirmation questions" do
        # Mock the confirmation response method directly to avoid TTY loops
        allow(ui).to receive(:get_confirmation_response).and_return(true)

        response = ui.get_quick_feedback("Do you want to continue?", type: "confirmation")

        expect(response).to be true
      end

      it "gets quick feedback for choice questions" do
        # Mock the choice response method directly to avoid TTY loops
        allow(ui).to receive(:get_choice_response).and_return("Option A")

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

        # Mock the response methods directly to avoid TTY loops
        # get_quick_feedback calls get_text_response for both text and number questions
        allow(ui).to receive(:get_text_response).and_return("John Doe", "25")
        allow(ui).to receive(:get_confirmation_response).and_return(true)

        responses = ui.collect_batch_feedback(questions)

        expect(responses).to be_a(Hash)
        expect(responses["question_1"]).to eq("John Doe")
        expect(responses["question_2"]).to eq("25")
        expect(responses["question_3"]).to be true
      end
    end

    describe "#get_user_preferences" do
      it "gets user preferences" do
        # Mock get_confirmation to return the expected sequence of preferences
        allow(ui).to receive(:get_confirmation).and_return(false, true, true, false)

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
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/Interactive Prompt Help/)
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/Input Types/)
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/Special Commands/)
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/File Selection/)
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/Validation/)
        output = capture_stdout do
          ui.show_help
        end
        expect(output).to match(/Tips/)
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

        output = capture_stdout do
          ui.display_question_summary(questions)
        end
        expect(output).to match(/Question Summary/)
        output = capture_stdout do
          ui.display_question_summary(questions)
        end
        expect(output).to match(/What is your name/)
        output = capture_stdout do
          ui.display_question_summary(questions)
        end
        expect(output).to match(/What is your age/)
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

        output = capture_stdout do
          ui.display_feedback_context(context)
        end
        expect(output).to match(/Context:/)
        output = capture_stdout do
          ui.display_feedback_context(context)
        end
        expect(output).to match(/Type: user_registration/)
        output = capture_stdout do
          ui.display_feedback_context(context)
        end
        expect(output).to match(/Urgency: 🔴 High/)
        output = capture_stdout do
          ui.display_feedback_context(context)
        end
        expect(output).to match(/Description: Please provide your information/)
        output = capture_stdout do
          ui.display_feedback_context(context)
        end
        expect(output).to match(/Agent Output:/)
      end
    end

    describe "#display_question_info" do
      it "displays question information for text questions" do
        output = capture_stdout do
          ui.display_question_info("text", "text", nil, nil, true)
        end
        expect(output).to match(/📝 Text/)
        output = capture_stdout do
          ui.display_question_info("text", "text", nil, nil, true)
        end
        expect(output).to match(/Required: Yes/)
      end

      it "displays question information for choice questions" do
        options = ["Option A", "Option B"]
        output = capture_stdout do
          ui.display_question_info("choice", "text", options, "Option A", true)
        end
        expect(output).to match(/🔘 Choice/)
        output = capture_stdout do
          ui.display_question_info("choice", "text", options, "Option A", true)
        end
        expect(output).to match(/Options: Option A, Option B/)
        output = capture_stdout do
          ui.display_question_info("choice", "text", options, "Option A", true)
        end
        expect(output).to match(/Default: Option A/)
      end

      it "displays question information for email questions" do
        output = capture_stdout do
          ui.display_question_info("email", "email", nil, nil, true)
        end
        expect(output).to match(/📧 Email/)
        output = capture_stdout do
          ui.display_question_info("email", "email", nil, nil, true)
        end
        expect(output).to match(/Expected: email/)
      end
    end
  end
end
