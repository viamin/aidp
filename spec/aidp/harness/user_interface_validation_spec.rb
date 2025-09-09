# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

  describe "input validation and error handling" do
    describe "#validate_input_type" do
      it "validates email input correctly" do
        result = ui.validate_input_type("test@example.com", "email")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates email input with errors" do
        result = ui.validate_input_type("invalid-email", "email")
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid email format")
        expect(result[:suggestions]).to include("Use format: user@domain.com")
      end

      it "validates URL input correctly" do
        result = ui.validate_input_type("https://example.com", "url")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates URL input with errors" do
        result = ui.validate_input_type("invalid-url", "url")
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid URL format")
        expect(result[:suggestions]).to include("Use format: https://example.com")
      end

      it "validates number input correctly" do
        result = ui.validate_input_type("123", "number")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates number input with range validation" do
        result = ui.validate_input_type("5", "number", { min: 1, max: 10 })
        expect(result[:valid]).to be true
      end

      it "validates number input with range errors" do
        result = ui.validate_input_type("15", "number", { min: 1, max: 10 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Number must be at most 10")
      end

      it "validates float input correctly" do
        result = ui.validate_input_type("3.14", "float")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates boolean input correctly" do
        result = ui.validate_input_type("yes", "boolean")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates boolean input with errors" do
        result = ui.validate_input_type("maybe", "boolean")
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid response")
        expect(result[:suggestions]).to include("Enter 'y' or 'yes' for Yes")
      end

      it "validates file path input correctly" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.close

        result = ui.validate_input_type(temp_file.path, "file")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil

        temp_file.unlink
      end

      it "validates file path input with errors" do
        result = ui.validate_input_type("nonexistent.txt", "file")
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("File does not exist: nonexistent.txt")
        expect(result[:suggestions]).to include("Check the file path for typos")
      end

      it "validates text input correctly" do
        result = ui.validate_input_type("Hello World", "text")
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates text input with length validation" do
        result = ui.validate_input_type("Hi", "text", { min_length: 5, max_length: 10 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Text must be at least 5 characters")
      end

      it "validates choice input correctly" do
        result = ui.validate_input_type("1", "choice", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil
      end

      it "validates choice input with errors" do
        result = ui.validate_input_type("5", "choice", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid selection number")
        expect(result[:suggestions]).to include("Enter a number between 1 and 2")
      end
    end

    describe "#validate_email" do
      it "validates valid email addresses" do
        valid_emails = [
          "test@example.com",
          "user.name@domain.co.uk",
          "user+tag@example.org",
          "user123@test-domain.com"
        ]

        valid_emails.each do |email|
          result = ui.validate_email(email)
          expect(result[:valid]).to be true, "Expected #{email} to be valid"
        end
      end

      it "validates invalid email addresses" do
        invalid_emails = [
          "invalid-email",
          "@example.com",
          "user@",
          "user@.com",
          "user..name@example.com"
        ]

        invalid_emails.each do |email|
          result = ui.validate_email(email)
          expect(result[:valid]).to be false, "Expected #{email} to be invalid"
          expect(result[:error_message]).to eq("Invalid email format")
        end
      end

      it "provides suggestions for common typos" do
        result = ui.validate_email("test@gmial.com")
        expect(result[:valid]).to be true
        expect(result[:suggestions]).to include("Did you mean gmail.com?")
      end

      it "warns about long email parts" do
        long_email = "a" * 65 + "@example.com"
        result = ui.validate_email(long_email)
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Local part is very long (65 characters)")
      end
    end

    describe "#validate_url" do
      it "validates valid URLs" do
        valid_urls = [
          "https://example.com",
          "http://localhost:3000",
          "https://www.example.com/path?query=value",
          "https://subdomain.example.com:8080/path"
        ]

        valid_urls.each do |url|
          result = ui.validate_url(url)
          expect(result[:valid]).to be true, "Expected #{url} to be valid"
        end
      end

      it "validates invalid URLs" do
        invalid_urls = [
          "invalid-url",
          "example.com",
          "ftp://example.com",
          "https://"
        ]

        invalid_urls.each do |url|
          result = ui.validate_url(url)
          expect(result[:valid]).to be false, "Expected #{url} to be invalid"
          expect(result[:error_message]).to eq("Invalid URL format")
        end
      end

      it "warns about HTTP vs HTTPS" do
        result = ui.validate_url("http://example.com")
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Consider using HTTPS for security")
      end

      it "suggests www prefix" do
        result = ui.validate_url("https://example.com")
        expect(result[:valid]).to be true
        expect(result[:suggestions]).to include("Consider using www.example.com")
      end
    end

    describe "#validate_number" do
      it "validates valid numbers" do
        valid_numbers = ["123", "-456", "0", "999999"]

        valid_numbers.each do |number|
          result = ui.validate_number(number)
          expect(result[:valid]).to be true, "Expected #{number} to be valid"
        end
      end

      it "validates invalid numbers" do
        invalid_numbers = ["abc", "12.34", "12a", ""]

        invalid_numbers.each do |number|
          result = ui.validate_number(number)
          expect(result[:valid]).to be false, "Expected #{number} to be invalid"
          expect(result[:error_message]).to eq("Invalid number format")
        end
      end

      it "validates number ranges" do
        result = ui.validate_number("5", { min: 1, max: 10 })
        expect(result[:valid]).to be true

        result = ui.validate_number("15", { min: 1, max: 10 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Number must be at most 10")
      end

      it "warns about very large numbers" do
        result = ui.validate_number("2000000")
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Very large number (2000000)")
      end
    end

    describe "#validate_float" do
      it "validates valid floats" do
        valid_floats = ["123", "123.45", "-456.78", "0.0", "999.999"]

        valid_floats.each do |float|
          result = ui.validate_float(float)
          expect(result[:valid]).to be true, "Expected #{float} to be valid"
        end
      end

      it "validates invalid floats" do
        invalid_floats = ["abc", "12a", "12.34.56", ""]

        invalid_floats.each do |float|
          result = ui.validate_float(float)
          expect(result[:valid]).to be false, "Expected #{float} to be invalid"
          expect(result[:error_message]).to eq("Invalid number format")
        end
      end

      it "validates float ranges" do
        result = ui.validate_float("5.5", { min: 1.0, max: 10.0 })
        expect(result[:valid]).to be true

        result = ui.validate_float("15.5", { min: 1.0, max: 10.0 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Number must be at most 10.0")
      end

      it "validates precision" do
        result = ui.validate_float("3.14159", { precision: 2 })
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Number has more decimal places than expected (5 > 2)")
      end
    end

    describe "#validate_boolean" do
      it "validates valid boolean responses" do
        valid_responses = ["y", "yes", "n", "no", "true", "false", "1", "0"]

        valid_responses.each do |response|
          result = ui.validate_boolean(response)
          expect(result[:valid]).to be true, "Expected #{response} to be valid"
        end
      end

      it "validates invalid boolean responses" do
        invalid_responses = ["maybe", "perhaps", "abc", "2"]

        invalid_responses.each do |response|
          result = ui.validate_boolean(response)
          expect(result[:valid]).to be false, "Expected #{response} to be invalid"
          expect(result[:error_message]).to eq("Invalid response")
        end
      end
    end

    describe "#validate_file_path" do
      it "validates existing files" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.close

        result = ui.validate_file_path(temp_file.path)
        expect(result[:valid]).to be true
        expect(result[:error_message]).to be_nil

        temp_file.unlink
      end

      it "validates nonexistent files" do
        result = ui.validate_file_path("nonexistent.txt")
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("File does not exist: nonexistent.txt")
        expect(result[:suggestions]).to include("Check the file path for typos")
      end

      it "validates file extensions" do
        # Create a temporary file for testing
        temp_file = Tempfile.new(["test", ".txt"])
        temp_file.close

        result = ui.validate_file_path(temp_file.path, { allowed_extensions: [".txt", ".md"] })
        expect(result[:valid]).to be true

        result = ui.validate_file_path(temp_file.path, { allowed_extensions: [".rb", ".js"] })
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Unexpected file extension: .txt")

        temp_file.unlink
      end

      it "warns about large files" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.write("x" * (11 * 1024 * 1024)) # 11MB
        temp_file.close

        result = ui.validate_file_path(temp_file.path)
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Large file size (11.0 MB)")

        temp_file.unlink
      end
    end

    describe "#validate_text" do
      it "validates text with length constraints" do
        result = ui.validate_text("Hello", { min_length: 3, max_length: 10 })
        expect(result[:valid]).to be true

        result = ui.validate_text("Hi", { min_length: 3, max_length: 10 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Text must be at least 3 characters")

        result = ui.validate_text("Hello World", { min_length: 3, max_length: 10 })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Text must be at most 10 characters")
      end

      it "validates text with patterns" do
        result = ui.validate_text("ABC123", { pattern: /\A[A-Z0-9]+\z/ })
        expect(result[:valid]).to be true

        result = ui.validate_text("abc123", { pattern: /\A[A-Z0-9]+\z/ })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Text does not match required pattern")
      end

      it "validates text with forbidden words" do
        result = ui.validate_text("Hello World", { forbidden_words: ["bad", "inappropriate"] })
        expect(result[:valid]).to be true

        result = ui.validate_text("This is bad", { forbidden_words: ["bad", "inappropriate"] })
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include("Text contains potentially inappropriate content")
      end
    end

    describe "#validate_choice" do
      it "validates numeric choices" do
        result = ui.validate_choice("1", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be true

        result = ui.validate_choice("2", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be true
      end

      it "validates text choices" do
        result = ui.validate_choice("Option A", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be true
      end

      it "validates invalid choices" do
        result = ui.validate_choice("5", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid selection number")

        result = ui.validate_choice("Option C", { choices: ["Option A", "Option B"] })
        expect(result[:valid]).to be false
        expect(result[:error_message]).to eq("Invalid choice")
      end
    end

    describe "#display_validation_error" do
      it "displays validation errors" do
        validation_result = {
          valid: false,
          error_message: "Invalid email format",
          suggestions: ["Use format: user@domain.com"],
          warnings: ["Local part is very long"]
        }

        expect { ui.display_validation_error(validation_result, "email") }.to output(/Validation Error/).to_stdout
        expect { ui.display_validation_error(validation_result, "email") }.to output(/Invalid email format/).to_stdout
        expect { ui.display_validation_error(validation_result, "email") }.to output(/Suggestions/).to_stdout
        expect { ui.display_validation_error(validation_result, "email") }.to output(/Warnings/).to_stdout
      end
    end

    describe "#display_validation_warnings" do
      it "displays warnings and handles user input" do
        validation_result = {
          valid: true,
          error_message: nil,
          suggestions: [],
          warnings: ["This is a warning"]
        }

        # Mock Readline to return "fix"
        allow(Readline).to receive(:readline).and_return("fix")

        result = ui.display_validation_warnings(validation_result)
        expect(result).to be true
      end

      it "returns false when no warnings" do
        validation_result = {
          valid: true,
          error_message: nil,
          suggestions: [],
          warnings: []
        }

        result = ui.display_validation_warnings(validation_result)
        expect(result).to be false
      end
    end

    describe "#handle_input_error" do
      it "handles input errors with retry options" do
        error = StandardError.new("Test error")
        question_data = { question: "Test question", type: "text" }

        # Mock Readline to return "1" (try again)
        allow(Readline).to receive(:readline).and_return("1")

        result = ui.handle_input_error(error, question_data, 0)
        expect(result).to eq(:retry)
      end

      it "handles maximum retries exceeded" do
        error = StandardError.new("Test error")
        question_data = { question: "Test question", type: "text" }

        result = ui.handle_input_error(error, question_data, 3)
        expect(result).to eq(:skip)
      end
    end

    describe "#show_question_help" do
      it "shows help for text questions" do
        question_data = { question: "What is your name?", type: "text" }

        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        expect { ui.show_question_help(question_data) }.to output(/Help for Text Question/).to_stdout
        expect { ui.show_question_help(question_data) }.to output(/Enter any text response/).to_stdout
      end

      it "shows help for choice questions" do
        question_data = { question: "Choose an option:", type: "choice" }

        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        expect { ui.show_question_help(question_data) }.to output(/Help for Choice Question/).to_stdout
        expect { ui.show_question_help(question_data) }.to output(/Select from the numbered options/).to_stdout
      end
    end
  end
end
