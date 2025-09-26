# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../../lib/aidp/harness/simple_user_interface"

RSpec.describe Aidp::Harness::SimpleUserInterface do
  let(:test_prompt) { TestPrompt.new }
  let(:ui) do
    described_class.new(prompt: test_prompt)
  end

  describe "#collect_feedback" do
    it "collects simple text responses" do
      questions = [
        {question: "What is your name?", type: "text", required: true},
        {question: "Comments?", type: "text", required: false, default: "None"}
      ]

      # Configure TestPrompt responses
      test_prompt = TestPrompt.new(responses: {ask: ["John Doe", "None"]})
      ui = described_class.new(prompt: test_prompt)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("John Doe")
      expect(responses["question_2"]).to eq("None")
    end

    it "handles choice questions" do
      questions = [
        {question: "Pick a color", type: "choice", options: ["Red", "Blue", "Green"]}
      ]

      test_prompt = TestPrompt.new(responses: {select: "Blue"})
      ui = described_class.new(prompt: test_prompt)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("Blue")
    end

    it "handles confirmation questions" do
      questions = [
        {question: "Do you agree", type: "confirmation", default: true}
      ]

      test_prompt = TestPrompt.new(responses: {yes?: true})
      ui = described_class.new(prompt: test_prompt)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq(true)
    end

    it "handles number questions" do
      questions = [
        {question: "Your age", type: "number", required: true}
      ]

      # Configure TestPrompt for number input
      test_prompt = TestPrompt.new(responses: {ask: "25"})
      ui = described_class.new(prompt: test_prompt)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq(25)
    end

    it "handles file questions with direct path" do
      questions = [
        {question: "Config file", type: "file", required: true}
      ]

      # Configure TestPrompt for file input
      test_prompt = TestPrompt.new(responses: {ask: "config.yml"})
      ui = described_class.new(prompt: test_prompt)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("config.yml")
    end

    it "handles file questions with @ selection" do
      questions = [
        {question: "Config file", type: "file", required: true}
      ]

      # Configure TestPrompt for file selection
      test_prompt = TestPrompt.new(responses: {ask: "@config", select: "config.yml"})
      ui = described_class.new(prompt: test_prompt)

      # Mock file system operations
      allow(Dir).to receive(:glob).with("**/*config*").and_return(["config.yml", "app_config.rb"])
      allow(File).to receive(:file?).and_return(true)

      responses = ui.collect_feedback(questions)

      expect(responses["question_1"]).to eq("config.yml")
    end

    it "shows context when provided" do
      questions = [{question: "Name?", type: "text"}]
      context = {description: "User registration"}

      # Configure TestPrompt for context display
      test_prompt = TestPrompt.new(responses: {ask: "Test"})
      ui = described_class.new(prompt: test_prompt)

      ui.collect_feedback(questions, context)

      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Agent needs feedback") }).to be true
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("User registration") }).to be true
    end
  end
end
