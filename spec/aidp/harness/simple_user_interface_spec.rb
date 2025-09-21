# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../../lib/aidp/harness/simple_user_interface"

RSpec.describe Aidp::Harness::SimpleUserInterface do
  let(:mock_prompt) { instance_double(TTY::Prompt) }
  let(:ui) do
    ui_instance = described_class.new
    ui_instance.instance_variable_set(:@prompt, mock_prompt)
    ui_instance
  end

  describe "#collect_feedback" do
    it "collects simple text responses" do
      questions = [
        {question: "What is your name?", type: "text", required: true},
        {question: "Comments?", type: "text", required: false, default: "None"}
      ]

      # Mock the prompt responses
      allow(mock_prompt).to receive(:ask).with("Response:", required: true).and_return("John Doe")
      allow(mock_prompt).to receive(:ask).with("Response:", required: false, default: "None").and_return("None")

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("John Doe")
      expect(responses["question_2"]).to eq("None")
    end

    it "handles choice questions" do
      questions = [
        {question: "Pick a color", type: "choice", options: ["Red", "Blue", "Green"]}
      ]

      allow(mock_prompt).to receive(:select).with("Choose:", ["Red", "Blue", "Green"], default: nil).and_return("Blue")

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("Blue")
    end

    it "handles confirmation questions" do
      questions = [
        {question: "Do you agree", type: "confirmation", default: true}
      ]

      allow(mock_prompt).to receive(:yes?).with("Do you agree?", default: true).and_return(true)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq(true)
    end

    it "handles number questions" do
      questions = [
        {question: "Your age", type: "number", required: true}
      ]

      # Mock the block configuration object
      config_double = double
      allow(config_double).to receive(:convert)
      allow(config_double).to receive(:validate)
      allow(mock_prompt).to receive(:ask).with("Number:", default: nil, required: true).and_yield(config_double).and_return(25)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq(25)
    end

    it "handles file questions with direct path" do
      questions = [
        {question: "Config file", type: "file", required: true}
      ]

      allow(mock_prompt).to receive(:ask).with("File path:", default: nil, required: true).and_return("config.yml")

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("config.yml")
    end

    it "handles file questions with @ selection" do
      questions = [
        {question: "Config file", type: "file", required: true}
      ]

      # Mock file selection
      allow(mock_prompt).to receive(:ask).with("File path:", default: nil, required: true).and_return("@config")
      allow(Dir).to receive(:glob).with("**/*config*").and_return(["config.yml", "app_config.rb"])
      allow(File).to receive(:file?).and_return(true)
      allow(mock_prompt).to receive(:select).with("Select file:", ["config.yml", "app_config.rb"], per_page: 15).and_return("config.yml")

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("config.yml")
    end

    it "shows context when provided" do
      questions = [{question: "Name?", type: "text"}]
      context = {description: "User registration"}

      allow(mock_prompt).to receive(:ask).and_return("Test")

      output = capture_stdout do
        ui.collect_feedback(questions, context)
      end

      expect(output).to include("Agent needs feedback")
      expect(output).to include("User registration")
    end
  end

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
