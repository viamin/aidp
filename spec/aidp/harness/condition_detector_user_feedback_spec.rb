# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "user feedback detection" do
    describe "#needs_user_feedback?" do
      it "detects direct requests for input" do
        result = {output: "Please provide your email address"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects clarification requests" do
        result = {output: "Can you clarify what you mean by that?"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects choice/decision requests" do
        result = {output: "Which option would you prefer?"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects confirmation requests" do
        result = {output: "Is this correct?"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects file requests" do
        result = {output: "Please upload the configuration file"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects information requests" do
        result = {output: "What is your project name?"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "detects context patterns" do
        result = {output: "Waiting for user input to continue"}
        expect(detector.needs_user_feedback?(result)).to be true
      end

      it "returns false for non-feedback content" do
        result = {output: "Task completed successfully"}
        expect(detector.needs_user_feedback?(result)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.needs_user_feedback?(nil)).to be false
        expect(detector.needs_user_feedback?("string")).to be false
      end
    end

    describe "#extract_user_feedback_info" do
      it "extracts comprehensive feedback information" do
        result = {output: "Please provide your email address for verification"}
        info = detector.extract_user_feedback_info(result)

        expect(info).to be_a(Hash)
        expect(info[:detected_at]).to be_a(Time)
        expect(info[:feedback_type]).to eq("direct_requests")
        expect(info[:urgency]).to eq("medium")
        expect(info[:input_type]).to eq("email")
        expect(info[:questions]).to be_an(Array)
        expect(info[:context]).to be_an(Array)
      end

      it "detects high urgency feedback" do
        result = {output: "URGENT: Please provide input immediately"}
        info = detector.extract_user_feedback_info(result)

        expect(info[:urgency]).to eq("high")
      end

      it "detects file input type" do
        result = {output: "Please upload the configuration file"}
        info = detector.extract_user_feedback_info(result)

        expect(info[:input_type]).to eq("file")
      end

      it "detects URL input type" do
        result = {output: "What is the repository URL?"}
        info = detector.extract_user_feedback_info(result)

        expect(info[:input_type]).to eq("url")
      end

      it "detects boolean input type" do
        result = {output: "Should I proceed with this action?"}
        info = detector.extract_user_feedback_info(result)

        expect(info[:input_type]).to eq("boolean")
      end

      it "returns nil for non-feedback content" do
        result = {output: "Task completed successfully"}
        expect(detector.extract_user_feedback_info(result)).to be_nil
      end
    end

    describe "#detect_feedback_type" do
      it "detects direct requests" do
        text = "Please provide your input"
        expect(detector.send(:detect_feedback_type, text)).to eq("direct_requests")
      end

      it "detects clarification requests" do
        text = "Can you clarify what you mean?"
        expect(detector.send(:detect_feedback_type, text)).to eq("clarification")
      end

      it "detects choice requests" do
        text = "Which option would you prefer?"
        expect(detector.send(:detect_feedback_type, text)).to eq("choices")
      end

      it "detects confirmation requests" do
        text = "Is this correct?"
        expect(detector.send(:detect_feedback_type, text)).to eq("confirmation")
      end

      it "detects file requests" do
        text = "Please upload the file"
        expect(detector.send(:detect_feedback_type, text)).to eq("file_requests")
      end

      it "detects information requests" do
        text = "What is your name?"
        expect(detector.send(:detect_feedback_type, text)).to eq("information")
      end

      it "defaults to general for unknown patterns" do
        text = "Some other type of request"
        expect(detector.send(:detect_feedback_type, text)).to eq("general")
      end
    end

    describe "#detect_urgency" do
      it "detects high urgency" do
        text = "URGENT: Please respond immediately"
        expect(detector.send(:detect_urgency, text)).to eq("high")
      end

      it "detects medium urgency" do
        text = "Please provide your input"
        expect(detector.send(:detect_urgency, text)).to eq("medium")
      end

      it "detects low urgency" do
        text = "When you have time, please respond"
        expect(detector.send(:detect_urgency, text)).to eq("low")
      end
    end

    describe "#detect_input_type" do
      it "detects file input" do
        text = "Please upload the configuration file"
        expect(detector.send(:detect_input_type, text)).to eq("file")
      end

      it "detects email input" do
        text = "What is your email address?"
        expect(detector.send(:detect_input_type, text)).to eq("email")
      end

      it "detects URL input" do
        text = "What is the repository URL?"
        expect(detector.send(:detect_input_type, text)).to eq("url")
      end

      it "detects path input" do
        text = "What is the directory path?"
        expect(detector.send(:detect_input_type, text)).to eq("path")
      end

      it "detects number input" do
        text = "How many items do you want?"
        expect(detector.send(:detect_input_type, text)).to eq("number")
      end

      it "detects boolean input" do
        text = "Should I proceed? Yes or no?"
        expect(detector.send(:detect_input_type, text)).to eq("boolean")
      end

      it "defaults to text input" do
        text = "What is your preference?"
        expect(detector.send(:detect_input_type, text)).to eq("text")
      end
    end
  end

  describe "question extraction" do
    describe "#extract_questions" do
      it "extracts numbered questions" do
        result = {output: "1. What is your name?\n2. What is your email?"}
        questions = detector.extract_questions(result)

        expect(questions).to have(2).items
        expect(questions[0][:number]).to eq("1")
        expect(questions[0][:question]).to eq("What is your name?")
        expect(questions[0][:type]).to eq("information")
        expect(questions[1][:number]).to eq("2")
        expect(questions[1][:question]).to eq("What is your email?")
        expect(questions[1][:type]).to eq("information")
      end

      it "extracts bullet point questions" do
        result = {output: "- What is your preference?\n- Which option do you want?"}
        questions = detector.extract_questions(result)

        expect(questions).to have(2).items
        expect(questions[0][:question]).to eq("What is your preference?")
        expect(questions[1][:question]).to eq("Which option do you want?")
      end

      it "extracts lettered questions" do
        result = {output: "a) Should I proceed?\nb) Is this correct?"}
        questions = detector.extract_questions(result)

        expect(questions).to have(2).items
        expect(questions[0][:question]).to eq("Should I proceed?")
        expect(questions[1][:question]).to eq("Is this correct?")
      end

      it "extracts general questions" do
        result = {output: "What is your name? How old are you?"}
        questions = detector.extract_questions(result)

        expect(questions).to have(2).items
        expect(questions[0][:number]).to eq(1)
        expect(questions[0][:question]).to eq("What is your name?")
        expect(questions[1][:number]).to eq(2)
        expect(questions[1][:question]).to eq("How old are you?")
      end

      it "removes duplicates" do
        result = {output: "What is your name? What is your name?"}
        questions = detector.extract_questions(result)

        expect(questions).to have(1).item
      end

      it "skips very short questions" do
        result = {output: "What? How? Why?"}
        questions = detector.extract_questions(result)

        expect(questions).to be_empty
      end

      it "returns empty array for no questions" do
        result = {output: "Task completed successfully"}
        questions = detector.extract_questions(result)

        expect(questions).to be_empty
      end
    end

    describe "#detect_question_type" do
      it "detects information questions" do
        expect(detector.send(:detect_question_type, "What is your name?")).to eq("information")
        expect(detector.send(:detect_question_type, "What is your email?")).to eq("information")
      end

      it "detects choice questions" do
        expect(detector.send(:detect_question_type, "Which option would you prefer?")).to eq("choice")
        expect(detector.send(:detect_question_type, "Which do you want?")).to eq("choice")
      end

      it "detects permission questions" do
        expect(detector.send(:detect_question_type, "Should I proceed?")).to eq("permission")
        expect(detector.send(:detect_question_type, "Can I continue?")).to eq("permission")
      end

      it "detects confirmation questions" do
        expect(detector.send(:detect_question_type, "Is this correct?")).to eq("confirmation")
        expect(detector.send(:detect_question_type, "Does this look right?")).to eq("confirmation")
      end

      it "detects request questions" do
        expect(detector.send(:detect_question_type, "Can you help me?")).to eq("request")
        expect(detector.send(:detect_question_type, "Could you explain?")).to eq("request")
      end

      it "detects quantity questions" do
        expect(detector.send(:detect_question_type, "How many items?")).to eq("quantity")
        expect(detector.send(:detect_question_type, "How much does it cost?")).to eq("quantity")
      end

      it "detects time questions" do
        expect(detector.send(:detect_question_type, "When will it be ready?")).to eq("time")
      end

      it "detects location questions" do
        expect(detector.send(:detect_question_type, "Where is the file?")).to eq("location")
      end

      it "detects explanation questions" do
        expect(detector.send(:detect_question_type, "Why did this happen?")).to eq("explanation")
      end

      it "defaults to general for unknown questions" do
        expect(detector.send(:detect_question_type, "What do you think?")).to eq("general")
      end
    end
  end

  describe "user response validation" do
    describe "#validate_user_response" do
      it "validates email responses" do
        expect(detector.validate_user_response("test@example.com", "email")).to be true
        expect(detector.validate_user_response("invalid-email", "email")).to be false
      end

      it "validates URL responses" do
        expect(detector.validate_user_response("https://example.com", "url")).to be true
        expect(detector.validate_user_response("not-a-url", "url")).to be false
      end

      it "validates number responses" do
        expect(detector.validate_user_response("123", "number")).to be true
        expect(detector.validate_user_response("abc", "number")).to be false
      end

      it "validates boolean responses" do
        expect(detector.validate_user_response("yes", "boolean")).to be true
        expect(detector.validate_user_response("no", "boolean")).to be true
        expect(detector.validate_user_response("true", "boolean")).to be true
        expect(detector.validate_user_response("false", "boolean")).to be true
        expect(detector.validate_user_response("maybe", "boolean")).to be false
      end

      it "validates file responses" do
        expect(detector.validate_user_response("@file.txt", "file")).to be true
        expect(detector.validate_user_response("not-a-file", "file")).to be false
      end

      it "validates path responses" do
        expect(detector.validate_user_response("/tmp", "path")).to be true
        expect(detector.validate_user_response("not-a-path", "path")).to be false
      end

      it "validates text responses" do
        expect(detector.validate_user_response("some text", "text")).to be true
        expect(detector.validate_user_response("", "text")).to be false
        expect(detector.validate_user_response("   ", "text")).to be false
      end

      it "rejects nil or empty responses" do
        expect(detector.validate_user_response(nil, "text")).to be false
        expect(detector.validate_user_response("", "text")).to be false
      end
    end
  end

  describe "utility methods" do
    describe "#get_user_feedback_patterns" do
      it "returns all patterns for nil type" do
        patterns = detector.get_user_feedback_patterns(nil)
        expect(patterns).to be_an(Array)
        expect(patterns.length).to be > 0
      end

      it "returns specific patterns for known type" do
        patterns = detector.get_user_feedback_patterns("direct_requests")
        expect(patterns).to be_an(Array)
        expect(patterns.length).to be > 0
      end

      it "returns all patterns for unknown type" do
        patterns = detector.get_user_feedback_patterns("unknown_type")
        expect(patterns).to be_an(Array)
        expect(patterns.length).to be > 0
      end
    end

    describe "#contains_user_feedback?" do
      it "detects user feedback in text" do
        text = "Please provide your input"
        expect(detector.contains_user_feedback?(text)).to be true
      end

      it "detects specific feedback type" do
        text = "Please provide your input"
        expect(detector.contains_user_feedback?(text, "direct_requests")).to be true
        expect(detector.contains_user_feedback?(text, "clarification")).to be false
      end

      it "returns false for non-feedback text" do
        text = "Task completed successfully"
        expect(detector.contains_user_feedback?(text)).to be false
      end
    end
  end
end
